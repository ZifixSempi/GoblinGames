--[[----------------------------------------------------------------------------
  tools/wowsim/sim.lua  (developer tool, not shipped in the addon zip)

  A tiny fake World of Warcraft for testing GoblinGames logic outside the game.
  It runs several "clients" side by side in one Lua 5.1 process. Each client
  gets its own global environment, loads the real addon files, and exchanges
  addon messages with the others through a fake server.

  Frames are mocked loosely: any method you call on a frame works and does
  nothing, except the handful the logic depends on (scripts, events, show/hide,
  text). It tests rules and networking, not how things look.

  Run:  lua5.1 tools/wowsim/test_tictactoe.lua   (from the repo root)
------------------------------------------------------------------------------]]

local Sim = {}
Sim.now = 1000
Sim.clients = {}
Sim.timers = {}
Sim.inflight = {}      -- messages "on the wire"
Sim.dropFilter = nil   -- function(fromClient, toClient, text) -> true to drop
Sim.log = {}

local REALM = "TestRealm"

-------------------------------------------------------------------------------
-- Fake frames
-------------------------------------------------------------------------------
local FrameMethods = {}
FrameMethods.__index = function(self, key)
    local m = rawget(FrameMethods, key)
    if m then return m end
    -- Unknown WoW method (CamelCase): a no-op. Lowercase keys are our own
    -- fields, which are simply nil until set.
    if type(key) == "string" and key:match("^%u") then return function() end end
    return nil
end

local function NewObject(client, kind)
    return setmetatable({ _client = client, _kind = kind, _scripts = {}, _events = {}, _shown = true, _text = "" }, FrameMethods)
end

function FrameMethods:SetScript(name, fn) self._scripts[name] = fn end
function FrameMethods:GetScript(name) return self._scripts[name] end
function FrameMethods:HookScript(name, fn)
    local old = self._scripts[name]
    self._scripts[name] = function(...) if old then old(...) end fn(...) end
end
function FrameMethods:RegisterEvent(e) self._events[e] = true end
function FrameMethods:UnregisterEvent(e) self._events[e] = nil end
function FrameMethods:UnregisterAllEvents() self._events = {} end
function FrameMethods:IsEventRegistered(e) return self._events[e] == true end
function FrameMethods:Show()
    local was = self._shown
    self._shown = true
    if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
end
function FrameMethods:Hide()
    local was = self._shown
    self._shown = false
    if was and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function FrameMethods:SetShown(v) if v then self:Show() else self:Hide() end end
function FrameMethods:IsShown() return self._shown end
function FrameMethods:IsVisible() return self._shown end
function FrameMethods:SetText(t) self._text = t or "" end
function FrameMethods:GetText() return self._text end
function FrameMethods:GetWidth() return 140 end
function FrameMethods:GetHeight() return 140 end
function FrameMethods:GetCenter() return 500, 500 end
function FrameMethods:GetEffectiveScale() return 1 end
function FrameMethods:GetChecked() return self._checked end
function FrameMethods:SetChecked(v) self._checked = v end
function FrameMethods:GetName() return self._name end
function FrameMethods:GetParent() return self._parent end
function FrameMethods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function FrameMethods:CreateTexture() return NewObject(self._client, "Texture") end
function FrameMethods:CreateFontString() return NewObject(self._client, "FontString") end
function FrameMethods:GetHighlightTexture()
    self._hl = self._hl or NewObject(self._client, "Texture")
    return self._hl
end
function FrameMethods:CreateAnimationGroup() return NewObject(self._client, "AnimationGroup") end
function FrameMethods:CreateAnimation(kind) return NewObject(self._client, kind) end
function FrameMethods:IsEnabled() return true end
function FrameMethods:GetFrameLevel() return self._level or 1 end
function FrameMethods:SetFrameLevel(l) self._level = l end
function FrameMethods:Click(button)
    if self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton") end
end

-------------------------------------------------------------------------------
-- Timers and the clock
-------------------------------------------------------------------------------
local function AddTimer(client, delay, fn, repeating)
    local t = { client = client, at = Sim.now + delay, fn = fn, every = repeating and delay or nil }
    t.Cancel = function(self) self.cancelled = true end
    t.IsCancelled = function(self) return self.cancelled end
    table.insert(Sim.timers, t)
    return t
end

local function RunClient(client, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        client.errors[#client.errors + 1] = err
        print(("  [%s] LUA ERROR: %s"):format(client.name, tostring(err)))
    end
end

--- Advance simulated time, delivering messages and firing timers/OnUpdates.
function Sim.Advance(seconds, step)
    step = step or 0.05
    local target = Sim.now + seconds
    while Sim.now < target - 1e-9 do
        Sim.now = math.min(target, Sim.now + step)
        -- Deliver messages sent in earlier steps (one step of "latency").
        local wire = Sim.inflight
        Sim.inflight = {}
        for _, m in ipairs(wire) do
            if m.system then
                Sim.FireEvent(m.to, "CHAT_MSG_SYSTEM", m.text)
            else
                Sim.FireEvent(m.to, "CHAT_MSG_ADDON", m.prefix, m.text, m.channel, m.sender, m.to.name)
            end
        end
        -- Timers.
        local due = {}
        for _, t in ipairs(Sim.timers) do
            if not t.cancelled and t.at <= Sim.now then due[#due + 1] = t end
        end
        for _, t in ipairs(due) do
            if t.every then t.at = t.at + t.every else t.cancelled = true end
            RunClient(t.client, t.fn, t)
        end
        local live = {}
        for _, t in ipairs(Sim.timers) do if not t.cancelled then live[#live + 1] = t end end
        Sim.timers = live
        -- OnUpdate scripts (ChatThrottleLib drains its queue here).
        for _, c in ipairs(Sim.clients) do
            for _, f in ipairs(c.frames) do
                local fn = f._scripts.OnUpdate
                if fn then RunClient(c, fn, f, step) end
            end
        end
    end
end

function Sim.FireEvent(client, event, ...)
    for _, f in ipairs(client.frames) do
        if f._events[event] and f._scripts.OnEvent then
            RunClient(client, f._scripts.OnEvent, f, event, ...)
        end
    end
end

-------------------------------------------------------------------------------
-- The fake server: routes addon messages between clients
-------------------------------------------------------------------------------
local function FindClient(name)
    local short = name:match("^[^-]+")
    for _, c in ipairs(Sim.clients) do
        if c.name == short then return c end
    end
end

local function Route(from, prefix, text, channel, target)
    if not from.registeredPrefixes[prefix] then return 2 end
    local recipients = {}
    if channel == "WHISPER" then
        local c = target and FindClient(target)
        if c and c.online then recipients[1] = c end
    elseif channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT" then
        for _, c in ipairs(Sim.clients) do
            if c.online and c.group == from.group and from.group then recipients[#recipients + 1] = c end
        end
    elseif channel == "GUILD" then
        for _, c in ipairs(Sim.clients) do
            if c.online and c.guild == from.guild and from.guild then recipients[#recipients + 1] = c end
        end
    end
    for _, to in ipairs(recipients) do
        if to.registeredPrefixes[prefix] then
            if not (Sim.dropFilter and Sim.dropFilter(from, to, text)) then
                table.insert(Sim.inflight, { to = to, prefix = prefix, text = text, channel = channel, sender = from.name .. "-" .. REALM })
            end
        end
    end
    from.sent = from.sent + 1
    return 0
end

-------------------------------------------------------------------------------
-- A client: one player's game, with its own globals
-------------------------------------------------------------------------------
local function BuildEnv(client)
    local env = {}
    env._G = env
    -- Plain Lua.
    for _, k in ipairs({ "ipairs", "pairs", "next", "select", "type", "tostring", "tonumber", "unpack",
        "pcall", "error", "assert", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal",
        "loadstring", "print" }) do env[k] = _G[k] end
    -- WoW's xpcall forwards extra arguments (like Lua 5.2); Lua 5.1's doesn't.
    env.xpcall = function(f, handler, ...)
        local n, args = select("#", ...), { ... }
        return xpcall(function() return f(unpack(args, 1, n)) end, handler)
    end
    env.math, env.table, env.coroutine = math, table, coroutine
    env.string = setmetatable({}, { __index = string })
    env.string.trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    -- WoW adds string.trim; make ("x"):trim() work by patching the shared string metatable.
    string.trim = env.string.trim
    env.strtrim = env.string.trim
    env.strsub, env.strfind, env.strlen, env.strmatch = string.sub, string.find, string.len, string.match
    env.format, env.gsub = string.format, string.gsub
    env.tinsert, env.tremove, env.tconcat = table.insert, table.remove, table.concat
    env.strlenutf8 = string.len
    env.GetLocale = function() return "enUS" end
    env.GetCurrentRegion = function() return 1 end
    env.GetCurrentRegionName = function() return "US" end
    env.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    env.UnitRace = function() return "Orc", "Orc", 2 end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    table.wipe = env.wipe -- WoW adds table.wipe; ChatThrottleLib uses it
    env.floor, env.max, env.min = math.floor, math.max, math.min
    env.geterrorhandler = function() return function(err) error(err, 0) end end
    env.securecallfunction = function(fn, ...) return fn(...) end
    env.debugstack = function() return "" end
    env.hooksecurefunc = function(tbl, name, hook)
        if type(tbl) == "string" then tbl, name, hook = env, tbl, name end
        local orig = tbl[name] or function() end
        tbl[name] = function(...)
            local r = { orig(...) }
            hook(...)
            return unpack(r)
        end
    end

    -- Time, frames, timers.
    env.GetTime = function() return Sim.now end
    env.time = function() return math.floor(Sim.now) end
    env.date = os.date
    env.debugprofilestop = function() return Sim.now * 1000 end
    env.GetFramerate = function() return 60 end
    env.CreateFrame = function(kind, name, parent)
        local f = NewObject(client, kind)
        f._name, f._parent = name, parent
        client.frames[#client.frames + 1] = f
        if name then env[name] = f end
        return f
    end
    env.UIParent = env.CreateFrame("Frame", "UIParent")
    env.Minimap = env.CreateFrame("Frame", "Minimap")
    env.GameTooltip = env.CreateFrame("GameTooltip", "GameTooltip")
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg)
        client.chat[#client.chat + 1] = msg
        if Sim.verbose then print(("  [%s chat] %s"):format(client.name, (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))) end
    end }
    env.UISpecialFrames = {}
    env.SlashCmdList = {}
    env.BackdropTemplateMixin = {}
    env.C_Timer = {
        After = function(d, fn) AddTimer(client, d, fn, false) end,
        NewTimer = function(d, fn) return AddTimer(client, d, fn, false) end,
        NewTicker = function(d, fn) return AddTimer(client, d, fn, true) end,
    }
    env.GetCursorPosition = function() return 0, 0 end

    -- Constants.
    env.WOW_PROJECT_ID, env.WOW_PROJECT_MAINLINE = 1, 1
    env.LE_PARTY_CATEGORY_HOME, env.LE_PARTY_CATEGORY_INSTANCE = 1, 2
    env.ERR_FRIEND_OFFLINE_S = "%s has gone offline."
    env.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
    env.RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
    -- /roll: the server rolls and tells the roller, their group, and anyone
    -- standing nearby (we model "nearby" as everyone in client.nearby).
    env.RandomRoll = function(min, max)
        min, max = tonumber(min), tonumber(max)
        local roll = Sim.forcedRoll or math.random(min, max)
        Sim.forcedRoll = nil
        client.rolls = (client.rolls or 0) + 1
        local text = ("%s rolls %d (%d-%d)"):format(client.name, roll, min, max)
        for _, c in ipairs(Sim.clients) do
            if c == client or (c.online and client.group and c.group == client.group) or (client.nearby and client.nearby[c]) then
                table.insert(Sim.inflight, { system = true, to = c, text = text })
            end
        end
    end
    env.SOUNDKIT = { READY_CHECK = 8960, IG_PLAYER_INVITE = 880, IG_QUEST_LIST_COMPLETE = 878 }
    env.Enum = { SendAddonMessageResult = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3,
        InvalidChatType = 4, NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9 } }

    -- Sound.
    env.PlaySound = function(id) client.sounds[#client.sounds + 1] = id; return true end

    -- Player and group.
    env.UnitName = function(unit)
        if unit == "player" then return client.name end
        local other = client.units[unit]
        if other then return other.name end
    end
    env.UnitNameUnmodified = function(u) return env.UnitName(u) end
    env.UnitFullName = function(unit) return env.UnitName(unit), REALM end
    env.UnitExists = function(unit) return unit == "player" or client.units[unit] ~= nil end
    env.UnitIsPlayer = env.UnitExists
    env.UnitIsConnected = function(unit)
        local c = client.units[unit] or FindClient(unit)
        return c and c.online
    end
    env.UnitFactionGroup = function(unit) return client.faction end
    env.GetRealmName = function() return REALM end
    env.GetNormalizedRealmName = function() return REALM end
    env.Ambiguate = function(name, mode)
        local short, realm = name:match("^([^-]+)-(.+)$")
        if short and realm == REALM then return short end
        return name
    end
    local function GroupMates()
        local list = {}
        for _, c in ipairs(Sim.clients) do
            if c ~= client and client.group and c.group == client.group then list[#list + 1] = c end
        end
        return list
    end
    env.IsInGroup = function(cat)
        if cat == 2 then return false end
        return #GroupMates() > 0
    end
    env.IsInRaid = function() return false end
    env.GetNumGroupMembers = function() return #GroupMates() + (#GroupMates() > 0 and 1 or 0) end
    env.GetNumSubgroupMembers = function()
        client.units = {}
        for i, c in ipairs(GroupMates()) do client.units["party" .. i] = c end
        return #GroupMates()
    end
    env.UnitInParty = function(name)
        for _, c in ipairs(GroupMates()) do if c.name == name then return true end end
        return false
    end
    env.UnitInRaid = function() return nil end
    env.IsInGuild = function() return client.guild ~= nil end
    env.GetNumGuildMembers = function() return 0 end
    env.GetGuildRosterInfo = function() return nil end
    env.C_FriendList = { GetFriendInfo = function() return nil end }

    -- Addon messages.
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(p) client.registeredPrefixes[p] = true; return true end,
        IsAddonMessagePrefixRegistered = function(p) return client.registeredPrefixes[p] == true end,
        SendAddonMessage = function(prefix, text, channel, target)
            assert(#text <= 255, "addon message longer than 255 bytes")
            assert(not (client.lockdown), "sent an addon message during chat lockdown")
            return Route(client, prefix, text, channel, target)
        end,
        SendAddonMessageLogged = function() return 0 end,
        SendChatMessage = function(text, channel)
            client.chatSent[#client.chatSent + 1] = { text = text, channel = channel }
        end,
        InChatMessagingLockdown = function() return client.lockdown == true end,
    }
    env.SendChatMessage = env.C_ChatInfo.SendChatMessage
    env.BNSendGameData = function() end

    -- Addon loading.
    env.C_AddOns = {
        GetAddOnMetadata = function(addon, key) return key == "Version" and "sim" or nil end,
        DoesAddOnExist = function(addon) return client.addonFiles[addon] ~= nil end,
        IsAddOnLoaded = function(addon) return client.loaded[addon] == true end,
        LoadAddOn = function(addon)
            if not client.addonFiles[addon] then return false, "MISSING" end
            if client.loaded[addon] then return true end
            Sim.LoadAddon(client, addon)
            return true
        end,
        GetAddOnInfo = function(addon)
            return addon, addon, "", true, client.addonFiles[addon] and "DEMAND_LOADED" or "MISSING"
        end,
    }
    env.Settings = nil
    env.InterfaceOptions_AddCategory = function() end

    -- Strict mode: reading an unknown global is almost always a typo here.
    setmetatable(env, { __index = function(_, k)
        if Sim.allowNil[k] then return nil end
        error("simulator: unknown global '" .. tostring(k) .. "'", 2)
    end })
    return env
end

-- Globals the addon checks for existence (nil is a valid answer).
Sim.allowNil = {
    Settings = true, InterfaceOptionsFrame = true, SettingsPanel = true, C_Texture = true,
    GetAddOnMetadata = true, LoadAddOn = true, IsAddOnLoaded = true, GetAddOnInfo = true,
    C_BattleNet = true, ChatThrottleLib = true, LibStub = true, GoblinGames = true,
    GoblinGamesDB = true, AceComm = true, C_GameRules = true, RegionalUniqueNamesEnabled = true,
    RegisterAddonMessagePrefix = true, issecretvalue = true, CallbackHandler = true, LoadSavedVariablesFirst = true,
}

-- Which files each addon loads, in .toc order (libraries expanded from XML).
function Sim.ReadToc(root, addon)
    local files = {}
    for line in io.lines(root .. "/" .. addon .. "/" .. addon .. ".toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then
            local path = line:gsub("\\", "/")
            if path:match("%.xml$") then
                Sim.ExpandXml(root .. "/" .. addon, path, files)
            else
                files[#files + 1] = root .. "/" .. addon .. "/" .. path
            end
        end
    end
    return files
end

function Sim.ExpandXml(base, xmlPath, out)
    local dir = xmlPath:match("^(.*)/[^/]+$") or ""
    local fh = assert(io.open(base .. "/" .. xmlPath))
    local xml = fh:read("*a"):gsub("<!%-%-.-%-%->", "")
    fh:close()
    for tag, file in xml:gmatch("<(%a+)%s+file=\"([^\"]+)\"") do
        file = file:gsub("\\", "/")
        local rel = (dir ~= "" and (dir .. "/") or "") .. file
        if tag == "Include" then
            Sim.ExpandXml(base, rel, out)
        elseif tag == "Script" then
            out[#out + 1] = base .. "/" .. rel
        end
    end
end

function Sim.LoadAddon(client, addon)
    local ns = {}
    for _, path in ipairs(client.addonFiles[addon]) do
        local chunk = assert(loadfile(path))
        setfenv(chunk, client.env)
        local ok, err = pcall(chunk, addon, ns)
        if not ok then error(("loading %s: %s"):format(path, tostring(err)), 0) end
    end
    client.loaded[addon] = true
    Sim.FireEvent(client, "ADDON_LOADED", addon)
end

--- Create a client. opts = { name, faction, group, guild, addons = {list}, root }
function Sim.NewClient(opts)
    local client = {
        name = opts.name, faction = opts.faction or "Horde", group = opts.group, guild = opts.guild,
        online = true, frames = {}, units = {}, chat = {}, chatSent = {}, sounds = {}, errors = {},
        registeredPrefixes = {}, loaded = {}, addonFiles = {}, sent = 0,
    }
    client.env = BuildEnv(client)
    for _, addon in ipairs(opts.addons) do
        client.addonFiles[addon] = Sim.ReadToc(opts.root, addon)
    end
    Sim.clients[#Sim.clients + 1] = client
    return client
end

--- Log in: load non-LoD addons and fire the login events.
function Sim.Login(client, mainAddons)
    for _, addon in ipairs(mainAddons) do Sim.LoadAddon(client, addon) end
    Sim.FireEvent(client, "PLAYER_LOGIN")
    Sim.FireEvent(client, "PLAYER_ENTERING_WORLD", true, false)
    client.GG = client.env.GoblinGames
end

function Sim.Chat(client, pattern)
    for _, line in ipairs(client.chat) do
        if line:find(pattern) then return true end
    end
    return false
end

return Sim
