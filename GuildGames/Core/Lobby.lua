--[[----------------------------------------------------------------------------
  GuildGames/Core/Lobby.lua

  Sessions: creating a game, inviting, accepting, starting, playing, ending.

  THE HOST IS THE REFEREE
  Whoever creates a game is its host. Every move goes to the host's client,
  which checks it against the rules and then tells everyone what happened:

      guest ── session:SendAction("MOVE", 5) ──▶ host  (def.OnAction checks it)
      host  ── session:Broadcast("SET", 5, 2) ─▶ all   (def.OnState applies it)

  Guests never change the game state on their own, so two clients can't
  disagree. Broadcasts carry a sequence number; a guest that notices a gap
  (missed message, loading screen) asks the host to resend the full state.

  INVITE FLOW
      host  INV  ──▶ guest      "want to play?"
      guest ACK  ──▶ host       "I have the addon"   (no ACK in 6s = no addon)
      guest ACC / DEC ──▶ host  accept or decline (with a reason)
      host  START ──▶ all       player list; the game begins
------------------------------------------------------------------------------]]

local _, GG = ...

local Util = GG.Util
local Comm = GG.Comm

local Lobby = {}
GG.Lobby = Lobby

Lobby.sessions = {}   -- sessionId -> session (only ours: hosting or joined)
Lobby.active = nil    -- the session we're currently in (one at a time)
Lobby.invites = {}    -- sessionId -> invite we've received and not answered

local NO_ADDON_TIMEOUT = 6     -- seconds to wait for ACK before "no addon"
local INVITE_TIMEOUT = 60      -- seconds before an unanswered invite expires
Lobby.OFFLINE_GRACE = 90       -- seconds a disconnected player has to come back

-------------------------------------------------------------------------------
-- Session object
-------------------------------------------------------------------------------
local Session = {}
Session.__index = Session
GG.SessionMeta = Session

local function NewSession(id, gameId, host)
    local s = setmetatable({}, Session)
    s.id = id
    s.gameId = gameId
    s.def = GG:GetGame(gameId)
    s.catalog = GG:GetCatalogEntry(gameId)
    s.host = host
    s.status = "lobby"          -- "lobby" | "playing" | "ended"
    s.players = {}              -- ordered full names (filled at start)
    s.factions = {}             -- name -> "Horde" | "Alliance" | "Neutral"
    s.invites = {}              -- (host only) name -> { status, reason }
    s.inviteOrder = {}          -- (host only) names in the order invited
    s.left = {}                 -- name -> reason, for players who dropped out
    s.offlineSince = {}         -- name -> GetTime() when they went offline
    s.seq = 0                   -- broadcast sequence number
    s.data = {}                 -- free space for the game module's state
    return s
end

function Session:IsHost() return Util.IsMe(self.host) end
function Session:Me() return Util.PlayerName() end

--- Faction of a player in this session (for "mixed" mode pieces).
function Session:GetFaction(name)
    return self.factions[name] or "Neutral"
end

--- 1-based seat number of a player, in the order of session.players.
function Session:SeatOf(name)
    return Util.IndexOf(self.players, name)
end

--- Is this player still in the game (hasn't left, forfeited or timed out)?
function Session:IsActive(name)
    return Util.IndexOf(self.players, name) ~= nil and not self.left[name]
end

--- Players still in the game.
function Session:ActivePlayers()
    local list = {}
    for _, p in ipairs(self.players) do
        if not self.left[p] then list[#list + 1] = p end
    end
    return list
end

--- Everyone except me.
function Session:Others()
    local list = {}
    for _, p in ipairs(self.players) do
        if not Util.IsMe(p) then list[#list + 1] = p end
    end
    return list
end

-- Convert values to the strings they'd arrive as over the network, so local
-- (host / practice) delivery behaves exactly like remote delivery.
local function ToArgs(...)
    local args = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v == nil then v = "" elseif v == true then v = "1" elseif v == false then v = "0" end
        args[i] = tostring(v)
    end
    return args
end

-- Deliver a host->players state message to our own client.
local function DeliverState(session, op, args, isPrivate)
    if op:sub(1, 1) == "_" then
        local coreHandler = Lobby.coreStateOps[op]
        if coreHandler then coreHandler(session, args) end
    elseif session.def and session.def.OnState then
        session.def.OnState(session, op, args, isPrivate)
    end
end

--- Send a raw message to every other player in the session.
function Session:SendToAll(prio, op, ...)
    if self.isLocal then return end
    if self.channel and self.channel ~= "WHISPER" then
        Comm:Send(self.channel, nil, prio, op, self.id, ...)
    else
        for _, p in ipairs(self.players) do
            if not Util.IsMe(p) and not self.left[p] then
                Comm:Whisper(p, prio, op, self.id, ...)
            end
        end
    end
end

--- (Players) Ask the host to make a move. On the host this runs locally.
function Session:SendAction(op, ...)
    if self.status ~= "playing" then return end
    if self:IsHost() then
        if self.def.OnAction then self.def.OnAction(self, self:Me(), op, ToArgs(...)) end
    else
        Comm:SendToPlayer(self.host, "ALERT", "A", self.id, op, ...)
    end
end

--- (Host, practice games only) Make a move on behalf of a bot player.
function Session:ActAs(name, op, ...)
    if not self:IsHost() or not Util.IsBot(name) then return end
    if self.def.OnAction then self.def.OnAction(self, name, op, ToArgs(...)) end
end

--- (Host) Tell every player about a state change, including ourselves.
--- Arrives at each client's def.OnState(session, op, args).
function Session:Broadcast(op, ...)
    if not self:IsHost() then return end
    self.seq = self.seq + 1
    self:SendToAll("ALERT", "S", self.seq, op, ...)
    DeliverState(self, op, ToArgs(...), false)
end

--- (Host) Send something to ONE player only, by whisper (hidden cards, dice).
--- Arrives at def.OnState(session, op, args, true).
function Session:SendTo(name, op, ...)
    if not self:IsHost() then return end
    if Util.IsMe(name) then
        DeliverState(self, op, ToArgs(...), true)
    elseif not Util.IsBot(name) and not self.isLocal then
        Comm:Whisper(name, "ALERT", "P", self.id, op, ...)
    end
end

--- (Host) Finish the game.
-- @param result { winners = {names}, draw = bool, reason = "text" }
function Session:End(result)
    if not self:IsHost() or self.status ~= "playing" then return end
    result = result or {}
    self:Broadcast("_END", Comm.EncodeList(result.winners or {}), result.draw and "1" or "0", result.reason or "")
end

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function Fire(event, session) GG:Fire(event, session) end

local function CountAccepted(session)
    local n = 0
    for _, info in pairs(session.invites) do
        if info.status == "accepted" then n = n + 1 end
    end
    return n
end
Lobby.CountAccepted = CountAccepted

--- Is the player free to join a new game?
function Lobby:IsBusy()
    return self.active ~= nil and self.active.status ~= "ended"
end

local function IsTrustedInviter(name)
    local mode = GG.db.profile.acceptFrom
    if mode == "anyone" then return true end
    if mode == "nobody" then return false end
    return Util.IsInMyGroup(name) or Util.IsGuildMember(name) or Util.IsFriend(name)
end

-------------------------------------------------------------------------------
-- Hosting
-------------------------------------------------------------------------------

--- Create a new game lobby that we host. Returns session or nil, error.
function Lobby:CreateHosted(gameId)
    if self:IsBusy() then return nil, "Finish or leave your current game first." end
    local def, err = GG:LoadGame(gameId)
    if not def then return nil, err end
    if self.active then self:Close(self.active) end

    local me = Util.PlayerName()
    local s = NewSession(Util.RandomId(), gameId, me)
    s.factions[me] = GG.Theme:GetPlayerFaction()
    self.sessions[s.id] = s
    self.active = s
    Fire("SESSION_CREATED", s)
    return s
end

--- Invite a player to the lobby we host.
function Lobby:Invite(session, name)
    name = Util.FullName(name)
    if not name or not session:IsHost() or session.status ~= "lobby" then return false end
    if Util.IsMe(name) then return false, "You can't invite yourself." end
    local existing = session.invites[name]
    if existing and existing.status ~= "declined" and existing.status ~= "noaddon" then
        return false, Util.ShortName(name) .. " is already invited."
    end
    if CountAccepted(session) + 1 >= session.catalog.max then
        return false, "The game is full."
    end

    if not existing then table.insert(session.inviteOrder, name) end
    session.invites[name] = { status = "sent" }
    Comm:SendToPlayer(name, "ALERT", "INV", session.id, session.gameId, GG.Theme:GetPlayerFaction())
    Fire("SESSION_UPDATED", session)

    -- No ACK in time: they don't have the addon (or are offline / out of reach).
    C_Timer.After(NO_ADDON_TIMEOUT, function()
        local info = session.invites[name]
        if info and info.status == "sent" and session.status == "lobby" then
            info.status = "noaddon"
            Fire("SESSION_UPDATED", session)
        end
    end)
    return true
end

--- Can the host start now?
function Lobby:CanStart(session)
    return session:IsHost() and session.status == "lobby"
        and CountAccepted(session) + 1 >= session.catalog.min
end

--- Start the game with everyone who accepted.
function Lobby:Start(session)
    if not self:CanStart(session) then return false end

    local players = { session.host }
    for _, name in ipairs(session.inviteOrder) do
        local info = session.invites[name]
        if info.status == "accepted" then
            players[#players + 1] = name
        elseif info.status == "sent" or info.status == "pending" then
            Comm:SendToPlayer(name, "NORMAL", "CANCEL", session.id, "started")
        end
    end
    session.players = players

    -- Use the group channel if everyone is in our group, otherwise whispers.
    local channel = Util.GroupChannel()
    if channel then
        for i = 2, #players do
            if not Util.IsInMyGroup(players[i]) then channel = nil; break end
        end
    end
    session.channel = channel or "WHISPER"

    local roster = {}
    for i, p in ipairs(players) do roster[i] = p .. ":" .. session:GetFaction(p) end
    session:SendToAll("ALERT", "START", Comm.EncodeList(roster), session.channel)

    self:Begin(session)
    return true
end

--- Practice against a bot. Nothing is sent over the network.
function Lobby:StartPractice(gameId)
    if self:IsBusy() then return nil, "Finish or leave your current game first." end
    local def, err = GG:LoadGame(gameId)
    if not def then return nil, err end
    if not def.BotAction then return nil, def.catalog.name .. " has no practice mode yet." end
    if self.active then self:Close(self.active) end

    local me = Util.PlayerName()
    local myFaction = GG.Theme:GetPlayerFaction()
    local bot = "Training Dummy" .. Util.BOT_SUFFIX
    local s = NewSession(Util.RandomId(), gameId, me)
    s.isLocal = true
    s.players = { me, bot }
    s.factions[me] = myFaction
    -- Give the dummy the other side, so both crests show up.
    s.factions[bot] = (myFaction == "Horde") and "Alliance" or "Horde"
    self.sessions[s.id] = s
    self.active = s
    Fire("SESSION_CREATED", s)
    self:Begin(s)
    return s
end

--- Host a fresh game with the same players.
function Lobby:Rematch(old)
    if not old:IsHost() then return nil, "Only the host can start a rematch." end
    if old.isLocal then return self:StartPractice(old.gameId) end
    local others = {}
    for _, p in ipairs(old.players) do
        if not Util.IsMe(p) then others[#others + 1] = p end
    end
    local s, err = self:CreateHosted(old.gameId)
    if not s then return nil, err end
    for _, p in ipairs(others) do self:Invite(s, p) end
    return s
end

-------------------------------------------------------------------------------
-- Both sides
-------------------------------------------------------------------------------

function Lobby:Begin(session)
    session.status = "playing"
    session.seq = 0
    Fire("SESSION_STARTED", session)
    session.def.OnSessionStart(session)
end

--- Leave the current lobby or forfeit the current game.
function Lobby:Leave(session)
    session = session or self.active
    if not session then return end

    if session.status == "lobby" then
        if session:IsHost() then
            for name, info in pairs(session.invites) do
                if info.status ~= "declined" and info.status ~= "noaddon" then
                    Comm:SendToPlayer(name, "NORMAL", "CANCEL", session.id, "cancelled")
                end
            end
        else
            Comm:SendToPlayer(session.host, "NORMAL", "DEC", session.id, "left")
        end
        self:Close(session)

    elseif session.status == "playing" then
        if session:IsHost() then
            self:HandlePlayerLeft(session, session:Me(), "forfeit")
        else
            Comm:SendToPlayer(session.host, "ALERT", "LEAVE", session.id, "forfeit")
            if not session.isLocal then
                GG.Stats:Record(session.gameId, "loss", session:Others())
            end
            GG:Print("You forfeited " .. session.catalog.name .. ".")
            self:Close(session)
        end

    else -- ended
        self:Close(session)
    end
end

--- Remove a session from this client and tear down its UI.
function Lobby:Close(session)
    if not session then return end
    self.sessions[session.id] = nil
    if self.active == session then self.active = nil end
    session.closed = true
    if session.def and session.def.OnSessionClosed then session.def.OnSessionClosed(session) end
    Fire("SESSION_CLOSED", session)
end

--- (Host) A player forfeited, timed out or disconnected.
function Lobby:HandlePlayerLeft(session, name, reason)
    if not session:IsHost() or session.status ~= "playing" or session.left[name] then return end
    -- Tell everyone (including the player who left, if they're still around).
    session:Broadcast("_LEFT", name, reason or "left")

    -- Let the module decide if it can carry on (e.g. 5-player games).
    if session.def.OnPlayerLeft and session.def.OnPlayerLeft(session, name, reason) then
        return
    end

    local remaining = session:ActivePlayers()
    if Util.IsMe(name) and #remaining > 1 then
        -- The host is the referee; without them the game can't continue.
        session:End({ winners = {}, reason = "the host left" })
    elseif #remaining <= 1 then
        session:End({ winners = remaining, reason = Util.ShortName(name) .. " " .. (reason or "left") })
    elseif GG.Turns:Current(session) == name then
        GG.Turns:Advance(session)
    end
end

-------------------------------------------------------------------------------
-- Answering invites
-------------------------------------------------------------------------------

local function ClearInvite(sessionId)
    local invite = Lobby.invites[sessionId]
    if invite then
        Lobby.invites[sessionId] = nil
        GG:Fire("INVITE_CLEARED", invite)
    end
end

function Lobby:AcceptInvite(sessionId)
    local invite = self.invites[sessionId]
    if not invite then return end
    ClearInvite(sessionId)

    if self:IsBusy() then
        Comm:SendToPlayer(invite.host, "NORMAL", "DEC", sessionId, "busy")
        GG:Print("Leave your current game before joining another.")
        return
    end
    local def, err = GG:LoadGame(invite.gameId)
    if not def then
        Comm:SendToPlayer(invite.host, "NORMAL", "DEC", sessionId, "nogame")
        GG:Print(err)
        return
    end
    if self.active then self:Close(self.active) end

    local s = NewSession(sessionId, invite.gameId, invite.host)
    s.factions[invite.host] = invite.hostFaction
    self.sessions[s.id] = s
    self.active = s
    Comm:SendToPlayer(invite.host, "ALERT", "ACC", sessionId, GG.Theme:GetPlayerFaction())
    Fire("SESSION_CREATED", s)

    -- We can only be in one game: turn down anything else that's pending.
    for otherId in pairs(self.invites) do self:DeclineInvite(otherId, "busy") end
end

function Lobby:DeclineInvite(sessionId, reason)
    local invite = self.invites[sessionId]
    if not invite then return end
    ClearInvite(sessionId)
    Comm:SendToPlayer(invite.host, "NORMAL", "DEC", sessionId, reason or "declined")
end

-------------------------------------------------------------------------------
-- Network handlers (core ops)
-------------------------------------------------------------------------------

-- Someone invites us.
Comm:RegisterOp("INV", function(sender, sid, args, _, protocol)
    -- ACK first: it only means "GuildGames is installed here".
    Comm:SendToPlayer(sender, "ALERT", "ACK", sid)
    local function Decline(reason) Comm:SendToPlayer(sender, "NORMAL", "DEC", sid, reason) end

    local gameId, hostFaction = args[1], args[2]
    if protocol ~= GG.PROTOCOL then return Decline("version") end
    if Lobby.invites[sid] or Lobby.sessions[sid] then return end
    if not IsTrustedInviter(sender) then return Decline("notaccepting") end
    if Lobby:IsBusy() then return Decline("busy") end
    if not GG:IsGameInstalled(gameId) then return Decline("nogame") end

    local invite = {
        id = sid, gameId = gameId, host = sender,
        hostFaction = GG.Theme:Sanitize(hostFaction),
        expires = GetTime() + INVITE_TIMEOUT,
    }
    Lobby.invites[sid] = invite
    GG.Theme:PlaySound("invite")
    GG:Print(Util.ShortName(sender) .. " invites you to " .. GG:GetCatalogEntry(gameId).name .. ".")
    GG:Fire("INVITE_RECEIVED", invite)

    C_Timer.After(INVITE_TIMEOUT, function()
        if Lobby.invites[sid] == invite then Lobby:DeclineInvite(sid, "timeout") end
    end)
end)

local function HostedSession(sid)
    local s = Lobby.sessions[sid]
    if s and s:IsHost() then return s end
end

Comm:RegisterOp("ACK", function(sender, sid)
    local s = HostedSession(sid)
    local info = s and s.invites[sender]
    if info and (info.status == "sent" or info.status == "noaddon") then
        info.status = "pending"
        Fire("SESSION_UPDATED", s)
    end
end)

Comm:RegisterOp("ACC", function(sender, sid, args)
    local s = HostedSession(sid)
    local info = s and s.invites[sender]
    if not info or s.status ~= "lobby" then
        -- Too late (game started or lobby gone): let them know.
        Comm:SendToPlayer(sender, "NORMAL", "CANCEL", sid, "closed")
        return
    end
    if CountAccepted(s) + 1 >= s.catalog.max then
        Comm:SendToPlayer(sender, "NORMAL", "CANCEL", sid, "full")
        return
    end
    info.status = "accepted"
    s.factions[sender] = GG.Theme:Sanitize(args[1])
    Fire("SESSION_UPDATED", s)
    -- Full table (e.g. 2-player games): start right away.
    if CountAccepted(s) + 1 >= s.catalog.max then
        C_Timer.After(0.5, function()
            if s.status == "lobby" and Lobby:CanStart(s) then Lobby:Start(s) end
        end)
    end
end)

local DECLINE_TEXT = {
    declined = "declined", busy = "is busy in another game", nogame = "doesn't have this game installed",
    notaccepting = "isn't accepting invites from you", timeout = "didn't answer",
    version = "has a different GuildGames version", left = "left the lobby",
}

Comm:RegisterOp("DEC", function(sender, sid, args)
    local s = HostedSession(sid)
    local info = s and s.invites[sender]
    if not info then return end
    info.status = "declined"
    info.reason = args[1]
    if s.status == "lobby" then
        GG:Print(Util.ShortName(sender) .. " " .. (DECLINE_TEXT[args[1]] or "declined") .. ".")
    end
    Fire("SESSION_UPDATED", s)
end)

Comm:RegisterOp("CANCEL", function(sender, sid, args)
    if Lobby.invites[sid] and Lobby.invites[sid].host == sender then
        ClearInvite(sid)
        return
    end
    local s = Lobby.sessions[sid]
    if s and s.host == sender and s.status == "lobby" then
        local why = args[1] == "full" and "the game is full" or (args[1] == "started" and "it started without you") or "the host closed the lobby"
        GG:Print("Left " .. s.catalog.name .. ": " .. why .. ".")
        Lobby:Close(s)
    end
end)

Comm:RegisterOp("START", function(sender, sid, args)
    local s = Lobby.sessions[sid]
    if not s or s.host ~= sender or s.status ~= "lobby" then return end
    local players, inGame = {}, false
    for _, entry in ipairs(Comm.DecodeList(args[1])) do
        local name, faction = entry:match("^(.+):(%a+)$")
        if name then
            players[#players + 1] = name
            s.factions[name] = GG.Theme:Sanitize(faction)
            if Util.IsMe(name) then inGame = true end
        end
    end
    if not inGame then return end -- a START on the group channel for another game
    s.players = players
    s.channel = args[2]
    Lobby:Begin(s)
end)

-- A move from a player, to the host.
Comm:RegisterOp("A", function(sender, sid, args)
    local s = HostedSession(sid)
    if not s or s.status ~= "playing" or not s:IsActive(sender) then return end
    s.offlineSince[sender] = nil
    local op = table.remove(args, 1)
    if s.def.OnAction then s.def.OnAction(s, sender, op, args) end
end)

-- A state change from the host, to everyone.
Comm:RegisterOp("S", function(sender, sid, args)
    local s = Lobby.sessions[sid]
    if not s or s.host ~= sender or s.status == "lobby" then return end
    s.offlineSince[sender] = nil
    local seq = tonumber(table.remove(args, 1)) or 0
    local op = table.remove(args, 1)
    if seq <= s.seq then return end -- duplicate
    if seq > s.seq + 1 then
        -- We missed something: ask for a full resend instead of guessing.
        if not s.syncRequested then
            s.syncRequested = true
            Comm:SendToPlayer(s.host, "ALERT", "SYNC", s.id)
        end
        return
    end
    s.seq = seq
    DeliverState(s, op, args, false)
end)

-- A private message from the host, to us only.
Comm:RegisterOp("P", function(sender, sid, args)
    local s = Lobby.sessions[sid]
    if not s or s.host ~= sender then return end
    local op = table.remove(args, 1)
    DeliverState(s, op, args, true)
end)

Comm:RegisterOp("LEAVE", function(sender, sid, args)
    local s = HostedSession(sid)
    if s then Lobby:HandlePlayerLeft(s, sender, args[1] or "left") end
end)

-- A player asks for the full game state (missed messages, loading screen).
Comm:RegisterOp("SYNC", function(sender, sid)
    local s = HostedSession(sid)
    if not s or s.status == "lobby" or not s:IsActive(sender) then return end
    s.offlineSince[sender] = nil
    if s.def.OnSyncRequest then s.def.OnSyncRequest(s, sender) end
    GG.Turns:SendTo(s, sender)
    s:SendTo(sender, "_SEQ", s.seq)
end)

-------------------------------------------------------------------------------
-- Core state ops (host -> everyone, delivered in order with module ops)
-------------------------------------------------------------------------------
Lobby.coreStateOps = {}

Lobby.coreStateOps["_SEQ"] = function(s, args)
    s.seq = tonumber(args[1]) or s.seq
    s.syncRequested = nil
end

local LEFT_TEXT = { forfeit = "forfeited", timeout = "ran out of time", offline = "disconnected", left = "left" }

Lobby.coreStateOps["_LEFT"] = function(s, args)
    local name, reason = args[1], args[2]
    if s.left[name] then return end
    s.left[name] = reason
    if Util.IsMe(name) and not s:IsHost() then
        GG:Print("You're out of this game: you " .. (LEFT_TEXT[reason] or reason) .. ".")
    else
        GG:Print(Util.ShortName(name) .. " " .. (LEFT_TEXT[reason] or reason) .. ".")
    end
    Fire("SESSION_UPDATED", s)
end

Lobby.coreStateOps["_END"] = function(s, args)
    if s.status == "ended" then return end
    s.status = "ended"
    local winners = Comm.DecodeList(args[1])
    local result = { winners = winners, draw = args[2] == "1", reason = args[3] ~= "" and args[3] or nil }
    s.result = result

    local me = Util.PlayerName()
    local outcome
    if result.draw then
        outcome = "draw"
    elseif Util.IndexOf(winners, me) then
        outcome = "win"
    elseif #winners == 0 then
        outcome = nil -- abandoned: no stats
    else
        outcome = "loss"
    end
    result.outcome = outcome

    if outcome and not s.isLocal then
        GG.Stats:Record(s.gameId, outcome, s:Others())
    end

    if outcome == "win" then
        GG.Theme:PlaySound("victory")
        GG:Print("You won " .. s.catalog.name .. "!")
    elseif outcome == "loss" then
        GG.Theme:PlaySound("defeat")
        local names = {}
        for i, w in ipairs(winners) do names[i] = Util.ShortName(w) end
        GG:Print(table.concat(names, ", ") .. " won " .. s.catalog.name .. ".")
    elseif outcome == "draw" then
        GG:Print(s.catalog.name .. " ended in a draw.")
    else
        GG:Print(s.catalog.name .. " ended" .. (result.reason and (": " .. result.reason) or "") .. ".")
    end

    if s.def.OnSessionEnd then s.def.OnSessionEnd(s, result) end
    GG:Fire("SESSION_ENDED", s, result)
end

-------------------------------------------------------------------------------
-- Presence: noticing players who disconnect
--
-- There's no "player disconnected" event for arbitrary players, so we watch
-- the system messages the game prints anyway:
--   ERR_FRIEND_OFFLINE_S         "%s has gone offline."  (group, guild, friends)
--   ERR_CHAT_PLAYER_NOT_FOUND_S  "No player named '%s' is currently playing."
-- Blizzard's global strings are localized, so we turn them into patterns
-- instead of matching English text.
-------------------------------------------------------------------------------
local function ToPattern(fmt)
    if not fmt then return nil end
    fmt = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. fmt:gsub("%%%%s", "(.+)") .. "$"
end

local offlinePatterns

local function MatchPlayer(session, shortName)
    for _, p in ipairs(session.players) do
        if Ambiguate(p, "none") == shortName or p:match("^[^-]+") == shortName then return p end
    end
end

GG:RegisterEvent("CHAT_MSG_SYSTEM", function(_, text)
    local s = Lobby.active
    if not s or s.status ~= "playing" or s.isLocal then return end
    offlinePatterns = offlinePatterns or { ToPattern(ERR_FRIEND_OFFLINE_S), ToPattern(ERR_CHAT_PLAYER_NOT_FOUND_S) }
    for _, pattern in ipairs(offlinePatterns) do
        local who = text:match(pattern)
        if who then
            who = who:gsub("|H.-|h%[?(.-)%]?|h", "%1") -- strip player links
            local player = MatchPlayer(s, who)
            if player and not s.offlineSince[player] then
                s.offlineSince[player] = GetTime()
                GG:Print(Util.ShortName(player) .. " went offline. Waiting " .. Lobby.OFFLINE_GRACE .. "s for them to come back.")
                Fire("SESSION_UPDATED", s)
            end
            return
        end
    end
end)

-- Group members: the client tells us directly when someone reconnects.
GG:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    local s = Lobby.active
    if not s or s.status ~= "playing" then return end
    for player in pairs(s.offlineSince) do
        local short = Ambiguate(player, "none")
        if (UnitInParty(short) or UnitInRaid(short)) and UnitIsConnected(short) then
            s.offlineSince[player] = nil
            Fire("SESSION_UPDATED", s)
        end
    end
end)

-- After any loading screen, guests ask the host for a fresh copy of the game,
-- in case messages were missed while the screen was up.
GG:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    local s = Lobby.active
    if s and s.status == "playing" and not s:IsHost() and not s.isLocal then
        s.syncRequested = true
        Comm:SendToPlayer(s.host, "ALERT", "SYNC", s.id)
    end
end)
