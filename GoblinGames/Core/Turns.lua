--[[----------------------------------------------------------------------------
  GoblinGames/Core/Turns.lua

  Whose turn it is, turn timers, and what happens when someone stalls.

  The host owns the turn order. When it changes, the host broadcasts a core
  "_TURN" message (current player + seconds left), and every client starts its
  own countdown from that. Only the host acts when a timer runs out.

  Timers PAUSE (on every client) while:
    - Retail's chat lockdown is active (raid boss / Mythic+), since nobody
      could send a move anyway;
  and a player who disconnects gets Lobby.OFFLINE_GRACE seconds to return
  before they're removed from the game.

  Module usage (host side):
      GG.Turns:Start(session, orderList)      -- first player in the list goes first
      GG.Turns:Advance(session)               -- next active player
      GG.Turns:Advance(session, name)         -- jump to a specific player
  Anyone:
      GG.Turns:Current(session)  GG.Turns:IsMyTurn(session)  GG.Turns:Remaining(session)
------------------------------------------------------------------------------]]

local _, GG = ...

local Util = GG.Util

local Turns = {}
GG.Turns = Turns

local BOT_DELAY = 0.9 -- seconds before a practice bot moves, so it feels natural

local function TimerLength(session)
    if session.isLocal then return 0 end
    if session.def.turnTimer ~= nil then return session.def.turnTimer end
    return GG.db.profile.turnTimer or 0
end

-- Send the current turn to everyone (or to one player after a SYNC).
local function BroadcastTurn(session)
    local t = session.turn
    session:Broadcast("_TURN", t.current, t.length, t.number)
end

function Turns:Start(session, order)
    if not session:IsHost() then return end
    session.turn = {
        order = Util.Copy(order),
        current = order[1],
        length = TimerLength(session),
        number = 1,
    }
    BroadcastTurn(session)
end

function Turns:Advance(session, nextPlayer)
    if not session:IsHost() or not session.turn or session.status ~= "playing" then return end
    local t = session.turn
    if not nextPlayer then
        local idx = Util.IndexOf(t.order, t.current) or 0
        for step = 1, #t.order do
            local candidate = t.order[(idx + step - 1) % #t.order + 1]
            if session:IsActive(candidate) then nextPlayer = candidate; break end
        end
    end
    if not nextPlayer then return end
    t.current = nextPlayer
    t.number = t.number + 1
    BroadcastTurn(session)
end

--- Restart the current player's clock without changing turns (e.g. Connect 6
--- placing a second stone, or a module that wants a fresh timer).
function Turns:ResetTimer(session)
    if session:IsHost() and session.turn then BroadcastTurn(session) end
end

--- (Host) Re-send the turn state privately to one player (used by SYNC).
function Turns:SendTo(session, name)
    local t = session.turn
    if t then session:SendTo(name, "_TURN", t.current, Turns:Remaining(session) or t.length, t.number) end
end

function Turns:Current(session)
    return session and session.turn and session.turn.current
end

function Turns:IsMyTurn(session)
    return session ~= nil and session.status == "playing" and Util.IsMe(self:Current(session) or "")
end

--- Seconds left on the clock, or nil when there's no timer.
function Turns:Remaining(session)
    local t = session and session.turn
    if not t or not t.deadline then return nil end
    return math.max(0, t.deadline - GetTime())
end

-------------------------------------------------------------------------------
-- Applying "_TURN" on every client (host included)
-------------------------------------------------------------------------------
GG.Lobby.coreStateOps["_TURN"] = function(session, args)
    local current, seconds, number = args[1], tonumber(args[2]) or 0, tonumber(args[3]) or 1
    session.turn = session.turn or { order = Util.Copy(session.players) }
    local t = session.turn
    t.current = current
    t.number = number
    t.length = t.length or seconds
    t.deadline = (seconds > 0) and (GetTime() + seconds) or nil
    t.timedOut = nil

    if Util.IsMe(current) and not session.isLocal then GG.Theme:PlaySound("turn") end
    GG:Fire("TURN_CHANGED", session)

    -- Practice games: let the bot take its turn after a short pause.
    if session.isLocal and Util.IsBot(current) and session.def.BotAction then
        local turnNumber = number
        C_Timer.After(BOT_DELAY, function()
            if session.status == "playing" and session.turn.number == turnNumber then
                session.def.BotAction(session, current)
            end
        end)
    end
end

-------------------------------------------------------------------------------
-- The clock: one ticker for the whole addon
-------------------------------------------------------------------------------
local TICK = 0.25

local function OnTick()
    local session = GG.Lobby.active
    if not session or session.status ~= "playing" or session.isLocal then return end
    local t = session.turn

    -- Freeze the clock during Retail's chat lockdown.
    if t and t.deadline and GG:IsCommLocked() then
        t.deadline = t.deadline + TICK
        return
    end

    local now = GetTime()

    if session:IsHost() then
        -- Disconnected players get a grace period, then they're out.
        for name, since in pairs(session.offlineSince) do
            if session:IsActive(name) and now - since > GG.Lobby.OFFLINE_GRACE then
                session.offlineSince[name] = nil
                GG.Lobby:HandlePlayerLeft(session, name, "offline")
                return
            end
        end
        -- While the current player is offline, their clock waits for them.
        if t and t.deadline and session.offlineSince[t.current] then
            t.deadline = t.deadline + TICK
        elseif t and t.deadline and now > t.deadline and not t.timedOut then
            t.timedOut = true
            local who = t.current
            if session.def.OnTurnTimeout then
                session.def.OnTurnTimeout(session, who)
            else
                GG.Lobby:HandlePlayerLeft(session, who, "timeout")
            end
        end
    else
        -- Guests: if the host (the referee) vanishes for too long, give up.
        local since = session.offlineSince[session.host]
        if since and now - since > GG.Lobby.OFFLINE_GRACE then
            GG:Print("The host didn't come back, so the game was abandoned.")
            session.status = "ended"
            session.result = { winners = {}, reason = "host disconnected" }
            if session.def.OnSessionEnd then session.def.OnSessionEnd(session, session.result) end
            GG:Fire("SESSION_ENDED", session, session.result)
        end
    end
end

table.insert(GG.onLogin, function()
    C_Timer.NewTicker(TICK, OnTick)
end)
