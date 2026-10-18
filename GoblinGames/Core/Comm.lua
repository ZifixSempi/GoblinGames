--[[----------------------------------------------------------------------------
  GoblinGames/Core/Comm.lua

  Networking between players' clients.

  HOW ADDON MESSAGES WORK
  C_ChatInfo.SendAddonMessage(prefix, text, channel, target) sends invisible
  text to other copies of addons that registered the same prefix. Channels:
  PARTY, RAID, INSTANCE_CHAT, GUILD, WHISPER (target = player name).
  Limits: 255 bytes per message, and the server throttles how fast an addon
  may send. AceComm-3.0 handles both for us: it splits long messages and
  queues them through ChatThrottleLib.

  MESSAGE FORMAT (version 1)
      <protocol>^<op>^<sessionId>^<arg1>^<arg2>...
  Fields are separated by "^". A "^" or "~" inside a field is escaped as
  "~c" / "~t", so any text is safe. Every field arrives as a string; convert
  numbers with tonumber() on the receiving side.

  RETAIL (MIDNIGHT) CHAT LOCKDOWN
  During an active raid boss encounter or Mythic+ run, Retail blocks addon
  chat and addon messages (C_ChatInfo.InChatMessagingLockdown() returns true).
  We never try to get around this. Outgoing messages wait in a local queue and
  go out once the lockdown ends; games pause meanwhile (see Turns.lua).
------------------------------------------------------------------------------]]

local _, GG = ...

local Comm = {}
GG.Comm = Comm
LibStub("AceComm-3.0"):Embed(Comm)

Comm.PREFIX = "GoblinGames"   -- max 16 characters

local SEP = "^"

-------------------------------------------------------------------------------
-- Encoding
-------------------------------------------------------------------------------
local ESCAPE = { ["~"] = "~t", ["^"] = "~c" }
local UNESCAPE = { t = "~", c = "^" }

local function Escape(value)
    if value == nil then return "" end
    if value == true then return "1" end
    if value == false then return "0" end
    return (tostring(value):gsub("[~%^]", ESCAPE))
end

local function Unescape(text)
    return (text:gsub("~(.)", UNESCAPE))
end

function Comm.Encode(op, sessionId, ...)
    local parts = { tostring(GG.PROTOCOL), op, sessionId or "-" }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = Escape((select(i, ...)))
    end
    return table.concat(parts, SEP)
end

function Comm.Decode(message)
    local fields = {}
    -- Split on "^". Escaped "^" became "~c", so a plain split is safe.
    for field in (message .. SEP):gmatch("(.-)%" .. SEP) do
        fields[#fields + 1] = Unescape(field)
    end
    local protocol = tonumber(fields[1])
    local op, sessionId = fields[2], fields[3]
    local args = {}
    for i = 4, #fields do args[#args + 1] = fields[i] end
    return protocol, op, sessionId, args
end

--- Helpers for packing a list into ONE field, e.g. "a,b,c".
--- Only for simple tokens (names, numbers); commas inside items are not allowed.
function Comm.EncodeList(list)
    return table.concat(list, ",")
end

function Comm.DecodeList(text)
    local list = {}
    if not text or text == "" then return list end
    for item in (text .. ","):gmatch("(.-),") do list[#list + 1] = item end
    return list
end

-------------------------------------------------------------------------------
-- Lockdown handling (Retail)
-------------------------------------------------------------------------------

--- True while Blizzard blocks addon messages (Retail encounters / M+).
function GG:IsCommLocked()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown() or false
end

local heldMessages = {}
local lockTicker

local function FlushHeld()
    if GG:IsCommLocked() then return end
    if lockTicker then lockTicker:Cancel(); lockTicker = nil end
    local queue = heldMessages
    heldMessages = {}
    for _, m in ipairs(queue) do
        Comm:SendCommMessage(Comm.PREFIX, m.text, m.channel, m.target, m.prio)
    end
    GG:Fire("COMM_LOCK_CHANGED", false)
end

-------------------------------------------------------------------------------
-- Sending
-------------------------------------------------------------------------------

--- Low-level send. Prefer the session helpers (session:Broadcast etc.).
-- @param channel "PARTY" | "RAID" | "INSTANCE_CHAT" | "GUILD" | "WHISPER"
-- @param target  player name for WHISPER, otherwise nil
-- @param prio    ChatThrottleLib priority: "ALERT" (fast), "NORMAL", "BULK"
function Comm:Send(channel, target, prio, op, sessionId, ...)
    local text = Comm.Encode(op, sessionId, ...)
    if channel == "WHISPER" and target then
        -- A whisper to ourselves would just bounce back; nothing to do.
        if GG.Util.IsMe(target) or GG.Util.IsBot(target) then return end
    end
    GG:Debug("send", channel, target or "", text)
    if GG:IsCommLocked() then
        heldMessages[#heldMessages + 1] = { text = text, channel = channel, target = target, prio = prio or "NORMAL" }
        if not lockTicker then
            GG:Fire("COMM_LOCK_CHANGED", true)
            lockTicker = C_Timer.NewTicker(1, FlushHeld)
        end
        return
    end
    self:SendCommMessage(self.PREFIX, text, channel, target, prio or "NORMAL")
end

--- Send to one player. Uses the group channel when they're in our group so
--- it also works across factions on Retail; otherwise a whisper.
--- NOTE: when using the group channel every group member's addon receives it,
--- so the message carries the target name and others ignore it. Never use this
--- for secret information; use Comm:Whisper for that.
function Comm:SendToPlayer(name, prio, op, sessionId, ...)
    local group = GG.Util.GroupChannel()
    if group and GG.Util.IsInMyGroup(name) then
        self:Send(group, nil, prio, "@" .. op, sessionId, name, ...)
    else
        self:Send("WHISPER", name, prio, op, sessionId, ...)
    end
end

--- Private message: always a whisper, so only that player receives it.
function Comm:Whisper(name, prio, op, sessionId, ...)
    self:Send("WHISPER", name, prio, op, sessionId, ...)
end

-------------------------------------------------------------------------------
-- Receiving
-------------------------------------------------------------------------------
local handlers = {}
local warnedNewer = {}

--- Register the handler for a core op. Handler signature:
---   handler(sender, sessionId, args, channel)
function Comm:RegisterOp(op, handler)
    handlers[op] = handler
end

function Comm:OnCommReceived(prefix, message, channel, sender)
    if prefix ~= self.PREFIX then return end
    sender = GG.Util.FullName(sender)
    -- On PARTY/RAID/GUILD we also receive our own messages; ignore them.
    if GG.Util.IsMe(sender) then return end

    local protocol, op, sessionId, args = Comm.Decode(message)
    if not protocol or not op then return end
    GG:Debug("recv", channel, sender, message)

    if protocol ~= GG.PROTOCOL then
        if protocol > GG.PROTOCOL and not warnedNewer[sender] then
            warnedNewer[sender] = true
            GG:Print(GG.Util.ShortName(sender) .. " has a newer GoblinGames. Update yours to play with them.")
        end
        -- Still answer pings and decline invites so the other side isn't left waiting.
        if op ~= "PING" and op ~= "INV" and op ~= "@INV" then return end
    end

    -- "@OP" messages were sent on a group channel for one specific player.
    if op:sub(1, 1) == "@" then
        local target = table.remove(args, 1)
        if not GG.Util.IsMe(GG.Util.FullName(target)) then return end
        op = op:sub(2)
    end

    local handler = handlers[op]
    if handler then
        handler(sender, sessionId, args, channel, protocol)
    end
end

table.insert(GG.onLoad, function()
    -- Registers the prefix with C_ChatInfo.RegisterAddonMessagePrefix under the hood.
    Comm:RegisterComm(Comm.PREFIX, "OnCommReceived")
end)

-------------------------------------------------------------------------------
-- Version check: /gg who
-------------------------------------------------------------------------------
local whoResults

Comm:RegisterOp("PING", function(sender, _, _, channel)
    -- Reply privately so a guild-wide ping doesn't make everyone answer on GUILD.
    Comm:Whisper(sender, "BULK", "PONG", nil, GG.version, GG.PROTOCOL)
end)

Comm:RegisterOp("PONG", function(sender, _, args)
    if whoResults then whoResults[sender] = args[1] or "?" end
end)

--- Ask everyone in the group (and guild) which version they run.
function Comm:WhoHasAddon(callback)
    whoResults = {}
    local group = GG.Util.GroupChannel()
    if group then self:Send(group, nil, "BULK", "PING", nil) end
    if IsInGuild() then self:Send("GUILD", nil, "BULK", "PING", nil) end
    C_Timer.After(4, function()
        local results = whoResults
        whoResults = nil
        callback(results)
    end)
end
