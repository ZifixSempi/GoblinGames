--[[----------------------------------------------------------------------------
  GoblinGames/Core/Init.lua

  Creates the addon namespace, the event dispatcher and the internal
  callback system. Every other file in the core gets the same namespace table
  through the "..." varargs WoW passes to each file:

      local ADDON_NAME, GG = ...

  Game modules are *separate addons* (GoblinGames_TicTacToe etc.), so they do
  not receive this private table. That's why we also publish it as the global
  `GoblinGames`. Modules should only use the functions documented in
  docs/MODULE_API.md.
------------------------------------------------------------------------------]]

local ADDON_NAME, GG = ...
_G.GoblinGames = GG

GG.name = ADDON_NAME

-- C_AddOns.GetAddOnMetadata exists on every current client; the plain global is
-- a fallback for anything older. "@project-version@" is replaced by the
-- BigWigs packager when a release is built; in a raw git checkout it stays as is.
local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
GG.version = GetMetadata(ADDON_NAME, "Version") or "dev"
if GG.version:find("@", 1, true) then GG.version = "dev" end

--[[ Network protocol version. Bump this when a message format changes in a way
     older clients can't understand. Clients only play with the same protocol. ]]
GG.PROTOCOL = 1

-- Which client are we running on? WOW_PROJECT_ID is a constant Blizzard
-- defines on every flavor; WOW_PROJECT_MAINLINE is Retail.
GG.isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
GG.isClassic = not GG.isRetail

-------------------------------------------------------------------------------
-- Printing
-------------------------------------------------------------------------------
local PREFIX = "|cff6fdc4fGoblin|r|cffd4af37Games|r: "

--- Print a message to the default chat frame (only the local player sees it).
function GG:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. table.concat(parts, " "))
end

--- Print only when debug mode is on (/gg debug).
function GG:Debug(...)
    if self.db and self.db.profile.debug then
        self:Print("|cff888888[debug]|r", ...)
    end
end

-------------------------------------------------------------------------------
-- Error safety net
--
-- WoW hides Lua errors from addons unless the player turns on the
-- "scriptErrors" setting, so a bug would just make a game silently stop.
-- Every call into a game module goes through GG:CallModule, which catches
-- errors, prints a short message in chat (once per error), and still hands
-- the full error to WoW's normal error handler.
-------------------------------------------------------------------------------
local reportedErrors = {}

local function Report(label, err)
    err = tostring(err)
    local firstLine = err:match("^[^\n]+") or err
    if not reportedErrors[firstLine] then
        reportedErrors[firstLine] = true
        GG:Print("|cffff5050" .. label .. " hit a bug:|r " .. firstLine)
        GG:Print("Please send that line to the addon author. Thanks!")
    end
    -- Also show it in the normal Lua error window, if the player has one.
    pcall(geterrorhandler(), err)
end

--- Call fn(...) safely. On error: report it and return nil.
function GG:Safe(label, fn, ...)
    local results = { xpcall(fn, function(e)
        return tostring(e) .. (debugstack and ("\n" .. debugstack(2, 8, 0)) or "")
    end, ...) }
    if results[1] then return unpack(results, 2) end
    Report(label, results[2])
    return nil
end

--- Call a game module's callback (def[method]) safely.
function GG:CallModule(def, method, ...)
    local fn = def and def[method]
    if not fn then return nil end
    local name = (def.catalog and def.catalog.name) or def.id or "A game"
    return self:Safe(name .. " (" .. method .. ")", fn, ...)
end

-------------------------------------------------------------------------------
-- Event dispatcher
--
-- WoW delivers game events (PLAYER_LOGIN, GROUP_ROSTER_UPDATE ...) to frames
-- that registered for them. We use one hidden frame for the whole core and let
-- any file add handlers with GG:RegisterEvent(event, func).
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function GG:RegisterEvent(event, handler)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(eventHandlers[event], handler)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        -- pcall keeps one broken handler from stopping the others; the error
        -- is still shown through the normal Lua error handler.
        local ok, err = pcall(list[i], event, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-------------------------------------------------------------------------------
-- Internal callbacks ("messages" between our own files and modules)
--
-- CallbackHandler gives us GG.RegisterCallback / GG.UnregisterCallback and a
-- registry whose :Fire(name, ...) notifies listeners. Names we fire:
--   SESSION_CREATED(session)      a lobby was created (host) or joined (guest)
--   SESSION_UPDATED(session)      invite list / players / status changed
--   SESSION_STARTED(session)      the game began
--   SESSION_ENDED(session, result)
--   SESSION_CLOSED(session)       the session is gone; tear down its UI
--   TURN_CHANGED(session)
--   INVITE_RECEIVED(invite)       someone invited us
--   INVITE_CLEARED(invite)
--   SETTINGS_CHANGED(key, value)
--   THEME_CHANGED()
-------------------------------------------------------------------------------
GG.callbacks = LibStub("CallbackHandler-1.0"):New(GG)

function GG:Fire(name, ...)
    self.callbacks:Fire(name, ...)
end

-------------------------------------------------------------------------------
-- Startup
--
-- ADDON_LOADED fires once per addon after its files and SavedVariables load.
-- PLAYER_LOGIN fires once when the character is fully in the world, which is
-- the earliest safe time to ask for things like the player's faction.
-------------------------------------------------------------------------------
GG.onLoad = {}     -- functions to run on our ADDON_LOADED (SavedVariables ready)
GG.onLogin = {}    -- functions to run on PLAYER_LOGIN

GG:RegisterEvent("ADDON_LOADED", function(_, addonName)
    if addonName ~= ADDON_NAME then return end
    for _, fn in ipairs(GG.onLoad) do fn() end
end)

GG:RegisterEvent("PLAYER_LOGIN", function()
    for _, fn in ipairs(GG.onLogin) do fn() end
    GG.loggedIn = true
end)
