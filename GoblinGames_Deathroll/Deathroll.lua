--[[----------------------------------------------------------------------------
  GoblinGames_Deathroll/Deathroll.lua

  Deathroll, the goblin classic.

  RULES
    - The first player rolls 1-1000 (or the start value the host picked).
    - Each next player rolls from 1 up to the PREVIOUS result.
    - Whoever rolls a 1 loses. Everyone else wins.
    - Running out of time, leaving or disconnecting also counts as rolling a 1.

  FAIR DICE (see Core/Dice.lua)
  Rolls are real /rolls made by the server. The host's client watches the
  server's "X rolls N (1-M)" messages and accepts a roll only if it was the
  right player's turn and the right range. That's why everyone should be in
  the same GROUP: then the host sees every roll for itself ("verified").
  If the host can't see a roll (not grouped), the roller's own addon reports
  it after a short wait and it's shown with a "?" as unverified.

  GOLD (optional, see Core/Ledger.lua)
  With gold mode on, the host can set a stake before inviting. The loser then
  owes the stake to every winner, in the ledger only. Players trade the gold
  themselves. Practice games never have stakes.

  Practice: you and the Training Dummy roll locally (math.random), so nothing
  is announced to your party.
------------------------------------------------------------------------------]]

local GG = GoblinGames
local Util = GG.Util
local UI = GG.UI

local Game = {
    id = "deathroll",
    hint = "Press ROLL! Roll a 1 and you're out.",
    compactHeader = true,
    options = {
        { key = "start", label = "Start rolling at", default = 1000, values = {
            { value = 100, text = "100" }, { value = 1000, text = "1000" },
            { value = 10000, text = "10,000" }, { value = 100000, text = "100,000" } } },
        { key = "stake", label = "Gold stake (ledger)", default = 0, gold = true, values = {
            { value = 0, text = "No stake" }, { value = 10, text = "10g" }, { value = 50, text = "50g" },
            { value = 100, text = "100g" }, { value = 500, text = "500g" }, { value = 1000, text = "1,000g" },
            { value = 5000, text = "5,000g" } } },
    },
}

local REPORT_WAIT = 2.5     -- seconds the host waits to see a roll itself
local HISTORY_KEEP = 30     -- rolls kept in the log (and in sync snapshots)

local current

-------------------------------------------------------------------------------
-- Host: accepting rolls
-------------------------------------------------------------------------------

--- Accept a roll for the current turn (host only). Ignores anything that
--- isn't the current player rolling 1..current max, and anything after the
--- first accepted roll of a turn (no re-rolls).
local function Accept(session, name, roll, min, max, verified)
    local d = session.data
    if not session:IsHost() or session.status ~= "playing" then return end
    if GG.Turns:Current(session) ~= name then return end
    if min ~= 1 or max ~= d.max or not roll or roll < 1 or roll > max then return end
    local turnNo = session.turn and session.turn.number
    if d.acceptedTurn == turnNo then return end
    d.acceptedTurn = turnNo

    session:Broadcast("ROLL", name, roll, max, verified and "1" or "0")

    if roll == 1 then
        local winners = {}
        for _, p in ipairs(session:ActivePlayers()) do
            if p ~= name then winners[#winners + 1] = p end
        end
        session:End({ winners = winners, reason = Util.ShortName(name) .. " rolled a 1" })
    else
        GG.Turns:Advance(session)
    end
end

-- Someone in the game can't roll any more (timeout, left, offline): that
-- counts as rolling a 1.
local function Eliminate(session, name, why)
    if session.status ~= "playing" then return end
    session:Broadcast("OUT", name)
    local winners = {}
    for _, p in ipairs(session.players) do
        if p ~= name then winners[#winners + 1] = p end
    end
    session:End({ winners = winners, reason = Util.ShortName(name) .. " " .. why })
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------
local rollCard, sideCard, bigNumber, numberLabel, stakeText, rollButton, slashHint
local skull, dice, playerList, logList, deathRibbon
local tumble -- { untilTime, from, to }

local function DangerColor(value, start)
    -- Green at the start, through yellow, to red near 1.
    local t = 1 - math.log(math.max(value, 1)) / math.log(math.max(start, 2))
    t = math.max(0, math.min(1, t))
    if t < 0.5 then return 0.35 + t * 1.3, 0.85, 0.25 end
    return 1, 0.85 - (t - 0.5) * 1.5, 0.15
end

local Refresh

local function OnRollClick()
    local s = current
    if not s or s.status ~= "playing" or not GG.Turns:IsMyTurn(s) then return end
    local d = s.data
    if d.rollPendingUntil and GetTime() < d.rollPendingUntil then return end
    d.rollPendingUntil = GetTime() + 3
    dice.shake:Play()
    if s.isLocal then
        -- Practice: roll locally so nothing is announced to your group.
        Accept(s, s:Me(), math.random(1, d.max), 1, d.max, true)
    else
        GG.Dice:Roll(1, d.max)
    end
    Refresh()
end

local function Build()
    local area = UI:GetGameArea()

    -- Left: the roll card.
    rollCard = UI.Card(area)
    rollCard:SetPoint("TOPLEFT", 0, 0)
    rollCard:SetPoint("BOTTOMLEFT", 0, 0)
    rollCard:SetWidth(370)

    local title = UI.Text(rollCard, "Deathroll", { fancy = true, size = 26, ink = true })
    title:SetPoint("TOPLEFT", 18, -14)

    dice = rollCard:CreateTexture(nil, "ARTWORK")
    dice:SetTexture("Interface\\Icons\\INV_Misc_Dice_01")
    dice:SetSize(40, 40)
    dice:SetPoint("TOPRIGHT", -18, -14)
    local g = dice:CreateAnimationGroup()
    for n, deg in ipairs({ 25, -50, 40, -15 }) do
        local r = g:CreateAnimation("Rotation")
        r:SetDegrees(deg)
        r:SetDuration(0.07)
        r:SetOrder(n)
    end
    dice.shake = g

    numberLabel = UI.Text(rollCard, "", { ink = true, justify = "CENTER" })
    numberLabel:SetPoint("TOP", 0, -64)

    bigNumber = UI.Text(rollCard, "1000", { fancy = true, size = 64, justify = "CENTER" })
    bigNumber:SetPoint("TOP", numberLabel, "BOTTOM", 0, -6)
    bigNumber:SetShadowColor(0, 0, 0, 0.9)
    bigNumber:SetShadowOffset(2, -3)

    skull = rollCard:CreateTexture(nil, "OVERLAY")
    skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    skull:SetSize(90, 90)
    skull:SetPoint("CENTER", bigNumber, "CENTER", 0, 0)
    UI.AddPopIn(skull)
    skull:Hide()

    stakeText = UI.Text(rollCard, "", { ink = true, justify = "CENTER", font = "GameFontHighlightSmall" })
    stakeText:SetPoint("TOP", bigNumber, "BOTTOM", 0, -10)

    rollButton = UI.Button(rollCard, "ROLL!", 250, 54, function() GG:Safe("Deathroll", OnRollClick) end, "primary")
    rollButton:SetPoint("BOTTOM", 0, 44)
    UI.AddPulse(rollButton.label, 0.55, 0.5)

    slashHint = UI.Text(rollCard, "", { ink = true, justify = "CENTER", font = "GameFontHighlightSmall" })
    slashHint:SetPoint("TOP", rollButton, "BOTTOM", 0, -6)
    slashHint:SetTextColor(0.48, 0.38, 0.25)

    deathRibbon = UI.Ribbon(rollCard, "DEATH!", 320, 70, "danger")
    deathRibbon:SetPoint("CENTER", bigNumber, "CENTER", 0, -6)
    UI.AddPopIn(deathRibbon)
    deathRibbon:Hide()

    -- The number "tumbles" through random values before landing.
    rollCard:SetScript("OnUpdate", function()
        if not tumble then return end
        if GetTime() < tumble.untilTime then
            bigNumber:SetText(math.random(1, math.max(1, tumble.from)))
        else
            tumble = nil
            Refresh()
        end
    end)

    -- Right: players and the roll log.
    sideCard = UI.Card(area)
    sideCard:SetPoint("TOPLEFT", rollCard, "TOPRIGHT", 12, 0)
    sideCard:SetPoint("BOTTOMRIGHT", 0, 0)

    local pTitle = UI.Text(sideCard, "Players", { fancy = true, size = 17, ink = true })
    pTitle:SetPoint("TOPLEFT", 16, -12)
    playerList = UI.ScrollList(sideCard, 24,
        function(parent)
            local row = CreateFrame("Frame", nil, parent)
            row.glow = row:CreateTexture(nil, "BACKGROUND")
            row.glow:SetTexture(UI.MEDIA .. "ButtonGlow")
            row.glow:SetAllPoints()
            row.glow:SetBlendMode("ADD")
            row.glow:SetVertexColor(1, 0.75, 0.2)
            row.crest = row:CreateTexture(nil, "ARTWORK")
            row.crest:SetSize(20, 20)
            row.crest:SetPoint("LEFT", 2, 0)
            row.name = UI.Text(row, "", { ink = true })
            row.name:SetPoint("LEFT", row.crest, "RIGHT", 6, 0)
            row.state = UI.Text(row, "", { ink = true, font = "GameFontHighlightSmall" })
            row.state:SetPoint("RIGHT", -6, 0)
            return row
        end,
        function(row, item)
            GG.Theme:SetCrest(row.crest, item.faction)
            row.name:SetText(item.name)
            row.state:SetText(item.state)
            row.glow:SetShown(item.active)
        end)
    playerList:SetPoint("TOPLEFT", pTitle, "BOTTOMLEFT", -2, -4)
    playerList:SetPoint("RIGHT", sideCard, "RIGHT", -34, 0)
    playerList:SetHeight(120)

    local lTitle = UI.Text(sideCard, "Rolls", { fancy = true, size = 17, ink = true })
    lTitle:SetPoint("TOPLEFT", playerList, "BOTTOMLEFT", 2, -8)
    logList = UI.ScrollList(sideCard, 20,
        function(parent)
            local row = CreateFrame("Frame", nil, parent)
            row.text = UI.Text(row, "", { ink = true, font = "GameFontHighlightSmall" })
            row.text:SetPoint("LEFT", 2, 0)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(14, 14)
            row.icon:SetPoint("RIGHT", -6, 0)
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                if not self.tip then return end
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return row
        end,
        function(row, item)
            row.text:SetText(item.text)
            row.icon:SetTexture(item.icon)
            row.icon:SetShown(item.icon ~= nil)
            row.tip = item.tip
        end)
    logList:SetPoint("TOPLEFT", lTitle, "BOTTOMLEFT", -2, -4)
    logList:SetPoint("BOTTOMRIGHT", -34, 14)
end

function Refresh()
    local s = current
    if not s or not rollCard then return end
    local d = s.data
    local start = d.start
    local myTurn = GG.Turns:IsMyTurn(s)
    local cur = GG.Turns:Current(s)

    -- Big number.
    if not tumble then
        bigNumber:SetText(d.loser and "1" or tostring(d.max))
        bigNumber:SetTextColor(DangerColor(d.loser and 1 or d.max, start))
    end
    numberLabel:SetText(d.loser and "Rolled a 1:" or (#d.history == 0 and "First roll goes from 1 to" or "Next roll goes from 1 to"))
    local dead = d.loser ~= nil and not tumble
    skull:SetShown(dead)
    if dead and not skull.shownFor then skull.shownFor = true; skull.popIn:Play() end
    deathRibbon:SetShown(dead)
    if dead and not deathRibbon.shownFor then deathRibbon.shownFor = true; deathRibbon.popIn:Play() end

    -- Stake.
    local stake = GG.Lobby.Stake(s)
    if stake > 0 then
        stakeText:SetText("|cffa51d12Stake: " .. stake .. "g|r   (the loser owes each winner, ledger only)")
    else
        stakeText:SetText(s.isLocal and "Practice round: just for fun" or "No stake: playing for glory")
    end

    -- Roll button.
    local pending = d.rollPendingUntil and GetTime() < d.rollPendingUntil
    if s.status ~= "playing" then
        rollButton:Hide()
        slashHint:SetText("")
    else
        rollButton:Show()
        rollButton:SetEnabled(myTurn and not pending)
        if myTurn then
            rollButton:SetText(pending and "Rolling..." or ("ROLL 1-" .. d.max .. "!"))
            rollButton.label.pulse:Play()
            slashHint:SetText(s.isLocal and "" or ("(or type /roll " .. d.max .. ")"))
        else
            rollButton.label.pulse:Stop()
            rollButton:SetText(cur and ("Waiting on " .. Util.ShortName(cur)) or "Waiting...")
            slashHint:SetText("")
        end
    end

    -- Players.
    local items = {}
    for _, p in ipairs(s.players) do
        local state
        if p == d.loser then state = UI.InkRed("DEAD")
        elseif s.status == "ended" then state = UI.InkGreen("Survived!")
        elseif p == cur then state = UI.InkGreen(Util.IsMe(p) and "Your roll!" or "Rolling...")
        elseif s.left[p] then state = UI.InkGrey("Out")
        else state = UI.InkGrey("Waiting") end
        items[#items + 1] = {
            name = Util.ShortName(p) .. (Util.IsMe(p) and " (you)" or ""),
            faction = s:GetFaction(p),
            state = state,
            active = s.status == "playing" and p == cur,
        }
    end
    playerList:SetItems(items)

    -- Roll log, newest first.
    local log = {}
    for i = #d.history, 1, -1 do
        local h = d.history[i]
        local text = Util.ShortName(h.name) .. " rolled " .. (h.roll == 1 and UI.InkRed("1") or tostring(h.roll)) .. UI.InkGrey(" (1-" .. h.max .. ")")
        local icon, tip
        if not s.isLocal then
            if h.verified then
                icon, tip = UI.ICON_READY, "Verified: the host saw this /roll from the server."
            else
                icon, tip = UI.ICON_WAIT, "Unverified: the host couldn't see this roll (are you all in the same group?)."
            end
        end
        log[#log + 1] = { text = text, icon = icon, tip = tip }
    end
    if #log == 0 then log[1] = { text = UI.InkGrey("No rolls yet. Somebody's gotta go first!") } end
    logList:SetItems(log)

    if s.status == "playing" and myTurn then
        UI:SetGameStatus(UI.Gold("Your roll! 1-" .. d.max))
    else
        UI:SetGameStatus(nil)
    end
end

-------------------------------------------------------------------------------
-- Module callbacks
-------------------------------------------------------------------------------
local function EncodeHistory(history)
    local parts = {}
    for i = math.max(1, #history - HISTORY_KEEP + 1), #history do
        local h = history[i]
        parts[#parts + 1] = h.name .. ":" .. h.roll .. ":" .. h.max .. ":" .. (h.verified and 1 or 0)
    end
    return table.concat(parts, ";")
end

local function DecodeHistory(text)
    local history = {}
    for name, roll, max, v in (text or ""):gmatch("([^:;]+):(%d+):(%d+):(%d)") do
        history[#history + 1] = { name = name, roll = tonumber(roll), max = tonumber(max), verified = v == "1" }
    end
    return history
end

function Game.OnSessionStart(session)
    current = session
    local d = session.data
    d.start = tonumber(session.options and session.options.start) or 1000
    d.max = d.start
    d.history = {}
    d.loser = nil
    d.acceptedTurn = nil
    d.rollPendingUntil = nil
    tumble = nil
    if not rollCard then Build() end
    skull.shownFor, deathRibbon.shownFor = nil, nil
    rollCard:Show()
    sideCard:Show()
    Refresh()

    if session:IsHost() then
        GG.Turns:Start(session, Util.Shuffle(Util.Copy(session.players)))
    end
end

-- Host: a player's addon reports the roll it saw for itself. Used only if
-- the host can't see that roll directly within a couple of seconds.
function Game.OnAction(session, sender, op, args)
    if op ~= "REPORT" or session.status ~= "playing" then return end
    if GG.Turns:Current(session) ~= sender then return end
    local roll, min, max = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local turnNo = session.turn and session.turn.number
    C_Timer.After(REPORT_WAIT, function()
        if session.turn and session.turn.number == turnNo and session.data.acceptedTurn ~= turnNo then
            Accept(session, sender, roll, min, max, false)
        end
    end)
end

function Game.OnState(session, op, args)
    local d = session.data
    if op == "ROLL" then
        local name, roll, max, verified = args[1], tonumber(args[2]), tonumber(args[3]), args[4] == "1"
        if not roll then return end
        d.history[#d.history + 1] = { name = name, roll = roll, max = max, verified = verified }
        tumble = { untilTime = GetTime() + 0.7, from = max }
        d.rollPendingUntil = nil
        if roll == 1 then d.loser = name else d.max = roll end
        if session == current then dice.shake:Play() end
    elseif op == "OUT" then
        d.loser = args[1]
    elseif op == "SNAP" then
        d.start = tonumber(args[1]) or d.start
        d.max = tonumber(args[2]) or d.max
        d.history = DecodeHistory(args[3])
        tumble = nil
    end
    if session == current then Refresh() end
end

function Game.OnSyncRequest(session, player)
    local d = session.data
    session:SendTo(player, "SNAP", d.start, d.max, EncodeHistory(d.history))
end

-- Out of time = rolled a 1.
function Game.OnTurnTimeout(session, name)
    Eliminate(session, name, "ran out of time")
end

-- Leaving or disconnecting mid-game = rolled a 1. Returning true tells the
-- core we've handled it.
function Game.OnPlayerLeft(session, name, reason)
    Eliminate(session, name, reason == "offline" and "disconnected" or "left")
    return true
end

function Game.OnSessionEnd(session, result)
    local d = session.data
    -- Gold mode: the loser owes the stake to each winner (ledger only).
    local stake = GG.Lobby.Stake(session)
    if stake > 0 and not session.isLocal and d.loser then
        for _, winner in ipairs(result.winners or {}) do
            GG.Ledger:Add("deathroll", d.loser, winner, stake)
        end
    end
    if session == current then Refresh() end
end

function Game.OnSessionClosed(session)
    if session == current then
        current = nil
        tumble = nil
        if rollCard then rollCard:Hide(); sideCard:Hide() end
    end
end

-- Real /rolls from the server (Core/Dice.lua).
GG.RegisterCallback(Game, "DICE_ROLLED", function(_, name, roll, min, max)
    local s = current
    if not s or s.status ~= "playing" or s.isLocal then return end
    if s:IsHost() then
        GG:Safe("Deathroll", Accept, s, name, roll, min, max, true)
    elseif Util.IsMe(name) and GG.Turns:Current(s) == name then
        s:SendAction("REPORT", roll, min, max)
    end
end)

GG.RegisterCallback(Game, "TURN_CHANGED", function(_, session)
    if session == current then Refresh() end
end)

-- Practice: the Training Dummy rolls (locally, after the core's short pause).
function Game.BotAction(session, bot)
    local d = session.data
    if session.status ~= "playing" or GG.Turns:Current(session) ~= bot then return end
    Accept(session, bot, math.random(1, d.max), 1, d.max, true)
end

Game._test = { Accept = Accept, ClickRoll = OnRollClick }

GG:RegisterGame(Game)
