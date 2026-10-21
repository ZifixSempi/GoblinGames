--[[----------------------------------------------------------------------------
  GoblinGames_Bingo/Bingo.lua

  Guild Bingo: officer-hosted prize nights.

  HOW A BINGO NIGHT WORKS
    1. An officer (ranks chosen in Settings) clicks "Play with friends" on
       Guild Bingo and presses "Announce to guild!". Everyone in the guild with
       Goblin Games gets a popup to join. Latecomers can join any time.
    2. The host (the "caller") doesn't play. They pick a pattern and start a
       round. Numbers are called automatically (or one at a time by hand).
    3. Cards mark themselves. When your card has the pattern, the BINGO!
       button lights up. Press it, and the host's client checks your card.
    4. Each win goes into the winner log (round, pattern, winner, time), so
       officers can hand out prizes later (Stats tab). Optionally the win is
       posted in guild chat.

  PATTERNS: any line (row, column or diagonal), four corners, X (both
  diagonals), blackout (every square).

  FAIR CARDS WITHOUT SENDING CARDS
  Every card is built from a seed of (game id, round, player name) with a
  small deterministic random generator (below). Every client can therefore
  rebuild any card exactly, so the host verifies a "BINGO!" against the real
  card and the numbers it actually called. Nobody can claim a card they
  don't have.

  Numbers: B 1-15, I 16-30, N 31-45, G 46-60, O 61-75; the centre is free.
------------------------------------------------------------------------------]]

local GG = GoblinGames
local Util = GG.Util
local UI = GG.UI

local Game = {
    id = "bingo",
    compactHeader = true,
    lateJoin = true,          -- the core lets new players join mid-night
    hint = "Your card marks itself. When it lights up, hit BINGO!",
}

local LETTERS = { "B", "I", "N", "G", "O" }
local COLUMN_COLORS = {
    { 0.25, 0.50, 1.00 }, { 0.92, 0.25, 0.20 }, { 0.62, 0.38, 0.92 },
    { 0.30, 0.78, 0.30 }, { 1.00, 0.60, 0.15 },
}
local PATTERNS = {
    { value = "line", text = "Any line" },
    { value = "corners", text = "Four corners" },
    { value = "x", text = "X marks the spot" },
    { value = "blackout", text = "Blackout" },
}
local PATTERN_NAME = {}
for _, p in ipairs(PATTERNS) do PATTERN_NAME[p.value] = p.text end
local SPEEDS = {
    { value = 0, text = "By hand" }, { value = 5, text = "Every 5s" },
    { value = 8, text = "Every 8s" }, { value = 12, text = "Every 12s" },
}
local PRACTICE_SPEED = 2

-------------------------------------------------------------------------------
-- Cards (pure functions)
-------------------------------------------------------------------------------
local MOD = 2147483647  -- 2^31 - 1

--- A number from a string, the same on every client.
local function Hash(text)
    local h = 5381
    for i = 1, #text do h = (h * 33 + text:byte(i)) % MOD end
    if h == 0 then h = 1 end
    return h
end

--- A tiny seeded random generator (Park-Miller). rand(n) -> 1..n.
--- math.random can't be used here: it's seeded differently on every client.
local function Seeded(seed)
    local state = seed
    return function(n)
        state = (state * 48271) % MOD
        return state % n + 1
    end
end

--- The card for a player in a round: 25 numbers, row by row; 0 = free centre.
local function MakeCard(sessionId, round, name)
    local rand = Seeded(Hash(sessionId .. ":" .. round .. ":" .. name))
    local cells = {}
    for col = 1, 5 do
        local pool = {}
        for n = (col - 1) * 15 + 1, col * 15 do pool[#pool + 1] = n end
        for i = #pool, 2, -1 do
            local j = rand(i)
            pool[i], pool[j] = pool[j], pool[i]
        end
        for row = 1, 5 do cells[(row - 1) * 5 + col] = pool[row] end
    end
    cells[13] = 0
    return cells
end

local function Letter(n) return LETTERS[math.floor((n - 1) / 15) + 1] end
local function ColumnOf(n) return math.floor((n - 1) / 15) + 1 end

-- Cell index lists for each pattern ("line" is any one of twelve lines).
local LINES = {}
for r = 1, 5 do local l = {} for c = 1, 5 do l[#l + 1] = (r - 1) * 5 + c end LINES[#LINES + 1] = l end
for c = 1, 5 do local l = {} for r = 1, 5 do l[#l + 1] = (r - 1) * 5 + c end LINES[#LINES + 1] = l end
LINES[#LINES + 1] = { 1, 7, 13, 19, 25 }
LINES[#LINES + 1] = { 5, 9, 13, 17, 21 }
local SHAPES = {
    corners = { { 1, 5, 21, 25 } },
    x = { { 1, 7, 13, 19, 25, 5, 9, 17, 21 } },
    blackout = { (function() local t = {} for i = 1, 25 do t[i] = i end return t end)() },
    line = LINES,
}

local function IsMarked(cells, i, calledSet)
    return cells[i] == 0 or calledSet[cells[i]] == true
end

--- Does the card show the pattern? Returns the satisfied cell list or nil.
local function Satisfied(cells, calledSet, pattern)
    for _, shape in ipairs(SHAPES[pattern] or {}) do
        local ok = true
        for _, i in ipairs(shape) do
            if not IsMarked(cells, i, calledSet) then ok = false; break end
        end
        if ok then return shape end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Who plays
-------------------------------------------------------------------------------
local current

--- The caller (host) doesn't get a card, except in practice.
local function HasCard(session, name)
    return session.isLocal or name ~= session.host
end

local function CardPlayers(session)
    local list = {}
    for _, p in ipairs(session.players) do
        if HasCard(session, p) and not session.left[p] then list[#list + 1] = p end
    end
    return list
end

-------------------------------------------------------------------------------
-- Host: the caller
-------------------------------------------------------------------------------
local Refresh

local function NewBag()
    local bag = {}
    for n = 1, 75 do bag[n] = n end
    return Util.Shuffle(bag)
end

local function CallNext(session)
    local d = session.data
    if not session:IsHost() or not d.roundActive then return end
    local n = table.remove(d.bag)
    if not n then
        session:Broadcast("NOWIN")
        return
    end
    session:Broadcast("CALL", n)
    d.nextCallAt = GetTime() + (d.speed > 0 and d.speed or 0)
end

local function StartRound(session)
    local d = session.data
    if not session:IsHost() or d.roundActive or session.status ~= "playing" then return end
    d.bag = NewBag()
    d.paused = false
    session:Broadcast("ROUND", d.round + 1, d.pattern)
    d.nextCallAt = GetTime() + 2  -- a moment to look at your new card
end

local function Announce(text)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send and not GG:IsCommLocked() then pcall(send, text, "GUILD") end
end

local function Win(session, name)
    local d = session.data
    d.roundActive = false
    session:Broadcast("WIN", name, d.round, d.pattern)
    if session.isLocal then return end
    -- Winner log, kept by the host for handing out prizes.
    local guild = GetGuildInfo("player")
    table.insert(GG.db.global.bingoLog, {
        t = time(), guild = guild, host = session.host, round = d.round,
        pattern = d.pattern, winner = name, prizeGiven = false,
    })
    GG:Fire("BINGO_LOG_CHANGED")
    if GG.db.profile.announceBingo then
        Announce(("[Goblin Games] BINGO! %s wins round %d (%s)!"):format(
            Util.ShortName(name), d.round, PATTERN_NAME[d.pattern] or d.pattern))
    end
end

-- One ticker drives automatic calling on the host.
local ticker
local function EnsureTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.5, function()
        local s = current
        if not s or not s:IsHost() or s.status ~= "playing" then return end
        local d = s.data
        if d.roundActive and not d.paused and d.speed > 0 and GetTime() >= (d.nextCallAt or 0) then
            GG:Safe("Guild Bingo", CallNext, s)
        end
    end)
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------
local CELL, GAP = 52, 4
local view = {}          -- all our frames
local cellFrames = {}

local function MakeBall(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.ball = f:CreateTexture(nil, "ARTWORK", nil, 0)
    f.ball:SetTexture(UI.MEDIA .. "Ball")
    f.ball:SetAllPoints()
    f.face = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.face:SetTexture(UI.MEDIA .. "BallFace")
    f.face:SetAllPoints()
    f.text = UI.Text(f, "", { fancy = true, size = math.floor(size * 0.30), justify = "CENTER", ink = true })
    f.text:SetPoint("CENTER", 0, -size * 0.04)
    f.letter = UI.Text(f, "", { fancy = true, size = math.max(9, math.floor(size * 0.16)), justify = "CENTER", ink = true })
    f.letter:SetPoint("BOTTOM", f.text, "TOP", 0, -2)
    function f:SetNumber(n)
        if not n then
            self.ball:SetVertexColor(0.6, 0.6, 0.6)
            self.text:SetText("")
            self.letter:SetText("")
            return
        end
        local c = COLUMN_COLORS[ColumnOf(n)]
        self.ball:SetVertexColor(c[1], c[2], c[3])
        self.text:SetText(n)
        self.letter:SetText(Letter(n))
    end
    function f:SetLetter(letter, col)
        local c = COLUMN_COLORS[col]
        self.ball:SetVertexColor(c[1], c[2], c[3])
        self.text:SetText(letter)
        self.letter:SetText("")
    end
    return f
end

local function OnBingoClick()
    local s = current
    if not s or s.status ~= "playing" then return end
    local d = s.data
    if not d.roundActive or not d.canClaim or d.claimed then
        view.bingo.bounce:Play()
        return
    end
    d.claimed = true
    s:SendAction("BINGO", d.round)
    Refresh()
end

local function Build()
    local area = UI:GetGameArea()

    ---------------------------------------------------------------- card
    view.cardPanel = UI.Card(area)
    view.cardPanel:SetPoint("TOPLEFT", 0, 0)
    view.cardPanel:SetPoint("BOTTOMLEFT", 0, 0)
    view.cardPanel:SetWidth(330)

    local gridW = 5 * CELL + 4 * GAP
    local x0 = (330 - gridW) / 2
    view.headers = {}
    for col = 1, 5 do
        local b = MakeBall(view.cardPanel, 44)
        b:SetPoint("TOPLEFT", x0 + (col - 1) * (CELL + GAP) + (CELL - 44) / 2, -14)
        b:SetLetter(LETTERS[col], col)
        view.headers[col] = b
    end
    for i = 1, 25 do
        local row, col = math.floor((i - 1) / 5), (i - 1) % 5
        local f = CreateFrame("Frame", nil, view.cardPanel)
        f:SetSize(CELL, CELL)
        f:SetPoint("TOPLEFT", x0 + col * (CELL + GAP), -66 - row * (CELL + GAP))
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetTexture(UI.MEDIA .. "BingoCell")
        f.bg:SetAllPoints()
        f.num = UI.Text(f, "", { fancy = true, size = 20, ink = true, justify = "CENTER" })
        f.num:SetPoint("CENTER", 0, -1)
        -- The "daub": a chip in your faction colour, with your crest.
        f.daub = f:CreateTexture(nil, "ARTWORK", nil, 0)
        f.daub:SetTexture(UI.MEDIA .. "Chip")
        f.daub:SetSize(CELL - 8, CELL - 8)
        f.daub:SetPoint("CENTER")
        f.daub:SetAlpha(0.8)
        f.crest = f:CreateTexture(nil, "ARTWORK", nil, 1)
        f.crest:SetSize(CELL * 0.42, CELL * 0.42)
        f.crest:SetPoint("CENTER")
        f.crest:SetAlpha(0.85)
        UI.AddPopIn(f.daub)
        f.glow = f:CreateTexture(nil, "OVERLAY")
        f.glow:SetTexture(UI.MEDIA .. "ButtonGlow")
        f.glow:SetPoint("TOPLEFT", -5, 5)
        f.glow:SetPoint("BOTTOMRIGHT", 5, -5)
        f.glow:SetBlendMode("ADD")
        f.glow:SetVertexColor(1, 0.85, 0.3)
        UI.AddPulse(f.glow, 0.3, 0.45)
        f.free = f:CreateTexture(nil, "ARTWORK", nil, 2)
        f.free:SetTexture(UI.MEDIA .. "Emblem")
        f.free:SetSize(CELL - 10, CELL - 10)
        f.free:SetPoint("CENTER", 0, 4)
        f.freeText = UI.Text(f, "FREE", { fancy = true, size = 11, ink = true, justify = "CENTER" })
        f.freeText:SetPoint("BOTTOM", 0, 3)
        cellFrames[i] = f
    end

    ---------------------------------------------------------------- caller's desk (host)
    view.desk = UI.Card(area)
    view.desk:SetPoint("TOPLEFT", 0, 0)
    view.desk:SetPoint("BOTTOMLEFT", 0, 0)
    view.desk:SetWidth(330)
    local deskTitle = UI.Text(view.desk, "Caller's desk", { fancy = true, size = 22, ink = true })
    deskTitle:SetPoint("TOPLEFT", 16, -14)
    view.patternCycle = UI.CycleButton(view.desk, "Pattern", PATTERNS,
        function() return current and current.data.pattern end,
        function(v) if current and not current.data.roundActive then current.data.pattern = v; Refresh() end end, 170, 110)
    view.patternCycle:SetPoint("TOPLEFT", 18, -52)
    view.speedCycle = UI.CycleButton(view.desk, "Calling", SPEEDS,
        function() return current and current.data.speed end,
        function(v)
            if current then
                current.data.speed = v
                current.data.nextCallAt = GetTime() + v
                Refresh()
            end
        end, 170, 110)
    view.speedCycle:SetPoint("TOPLEFT", 18, -88)

    view.startButton = UI.Button(view.desk, "Start round!", 180, 40, function()
        GG:Safe("Guild Bingo", StartRound, current)
    end, "primary")
    view.startButton:SetPoint("TOP", 0, -132)
    view.callButton = UI.Button(view.desk, "Call next number", 180, 34, function()
        GG:Safe("Guild Bingo", CallNext, current)
    end, "primary")
    view.callButton:SetPoint("TOP", view.startButton, "BOTTOM", 0, -6)
    view.pauseButton = UI.Button(view.desk, "Pause", 120, 28, function()
        if current then current.data.paused = not current.data.paused; Refresh() end
    end, "wood")
    view.pauseButton:SetPoint("TOP", view.callButton, "BOTTOM", 0, -6)
    view.announceButton = UI.Button(view.desk, "Announce again", 150, 28, function()
        if not current then return end
        local ok, err = GG.Lobby:Announce(current)
        UI:Say(ok and "Announced! Latecomers get a popup to join." or (err or "Can't announce right now."), true)
    end, "wood")
    view.announceButton:SetPoint("BOTTOMLEFT", 16, 44)
    view.announceButton.tooltip = "Sends the join popup to the guild again, for latecomers."
    view.chatCheck = UI.Checkbox(view.desk, "Post winners in guild chat",
        function() return GG.db.profile.announceBingo end,
        function(v) GG:SetSetting("announceBingo", v) end)
    view.chatCheck:SetPoint("BOTTOMLEFT", 16, 14)

    ---------------------------------------------------------------- right side (everyone)
    view.info = UI.Card(area)
    view.info:SetPoint("TOPLEFT", view.cardPanel, "TOPRIGHT", 12, 0)
    view.info:SetPoint("BOTTOMRIGHT", 0, 0)

    view.roundText = UI.Text(view.info, "", { fancy = true, size = 18, ink = true })
    view.roundText:SetPoint("TOPLEFT", 16, -14)
    view.patternText = UI.Text(view.info, "", { ink = true })
    view.patternText:SetPoint("TOPLEFT", view.roundText, "BOTTOMLEFT", 0, -4)

    -- Mini 5x5 showing the pattern.
    view.mini = {}
    for i = 1, 25 do
        local t = view.info:CreateTexture(nil, "ARTWORK")
        t:SetSize(9, 9)
        t:SetPoint("TOPRIGHT", view.info, "TOPRIGHT", -18 - (5 - ((i - 1) % 5 + 1)) * 11, -14 - math.floor((i - 1) / 5) * 11)
        view.mini[i] = t
    end

    view.bigBall = MakeBall(view.info, 104)
    view.bigBall:SetPoint("TOPLEFT", 22, -66)
    UI.AddPopIn(view.bigBall)
    view.calledText = UI.Text(view.info, "", { ink = true, font = "GameFontHighlightSmall" })
    view.calledText:SetPoint("TOPLEFT", view.bigBall, "TOPRIGHT", 14, -6)
    view.recent = {}
    for i = 1, 5 do
        local b = MakeBall(view.info, 34)
        b:SetPoint("TOPLEFT", view.bigBall, "TOPRIGHT", 12 + (i - 1) * 38, -30)
        view.recent[i] = b
    end

    -- Players: the BINGO! button.
    view.bingo = UI.Button(view.info, "BINGO!", 230, 58, function() GG:Safe("Guild Bingo", OnBingoClick) end, "primary")
    view.bingo:SetPoint("TOP", view.info, "TOP", 0, -186)
    UI.AddPulse(view.bingo.label, 0.5, 0.35)
    view.bingoGlow = view.bingo:CreateTexture(nil, "OVERLAY")
    view.bingoGlow:SetTexture(UI.MEDIA .. "ButtonGlow")
    view.bingoGlow:SetPoint("TOPLEFT", -14, 12)
    view.bingoGlow:SetPoint("BOTTOMRIGHT", 14, -12)
    view.bingoGlow:SetBlendMode("ADD")
    view.bingoGlow:SetVertexColor(1, 0.85, 0.3)
    UI.AddPulse(view.bingoGlow, 0.2, 0.4)

    -- Host: every number, 15 per row, lit when called.
    view.board = {}
    for n = 1, 75 do
        local col, row = (n - 1) % 15, math.floor((n - 1) / 15)
        local fs = UI.Text(view.info, tostring(n), { font = "GameFontHighlightSmall", justify = "CENTER" })
        fs:SetWidth(22)
        fs:SetPoint("TOPLEFT", 14 + col * 22, -186 - row * 16)
        view.board[n] = fs
    end

    view.status = UI.Text(view.info, "", { ink = true, justify = "CENTER" })
    view.status:SetPoint("TOP", view.info, "TOP", 0, -258)
    view.status:SetWidth(330)

    view.winners = UI.Text(view.info, "", { ink = true, font = "GameFontHighlightSmall" })
    view.winners:SetPoint("BOTTOMLEFT", 16, 14)
    view.winners:SetWidth(330)

    -- Practice: a "next round" button next to Quit.
    view.nextButton = UI.Button(UI:GetGameArea(), "Next round!", 140, 36, function()
        GG:Safe("Guild Bingo", StartRound, current)
    end, "primary")
    view.nextButton:SetPoint("BOTTOMRIGHT", UI.frame.actions, "BOTTOMRIGHT", -118, 0)
end

function Refresh()
    local s = current
    if not s or not view.cardPanel then return end
    local d = s.data
    local me = s:Me()
    local isCaller = s:IsHost() and not s.isLocal
    local mine = d.card

    view.cardPanel:SetShown(not isCaller)
    view.desk:SetShown(isCaller)
    view.info:ClearAllPoints()
    view.info:SetPoint("TOPLEFT", isCaller and view.desk or view.cardPanel, "TOPRIGHT", 12, 0)
    view.info:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Card.
    local winShape = mine and d.roundActive and Satisfied(mine, d.calledSet, d.pattern)
    local glowing = {}
    for _, i in ipairs(winShape or {}) do glowing[i] = true end
    local myFaction = s:GetFaction(me)
    local fc = ({ Horde = { 0.86, 0.20, 0.14 }, Alliance = { 0.24, 0.46, 1.00 } })[myFaction] or { 0.38, 0.76, 0.26 }
    for i, f in ipairs(cellFrames) do
        local n = mine and mine[i]
        local isFree = (i == 13)
        f.free:SetShown(isFree)
        f.freeText:SetShown(isFree)
        f.num:SetText((n and n > 0) and n or "")
        local marked = mine and n and n > 0 and d.calledSet[n]
        f.daub:SetVertexColor(fc[1], fc[2], fc[3])
        GG.Theme:SetCrest(f.crest, myFaction)
        if marked then
            if not f.daub:IsShown() then f.daub:Show(); f.daub.popIn:Play() end
            f.crest:Show()
        else
            f.daub:Hide()
            f.crest:Hide()
        end
        f.glow:SetShown(glowing[i] == true)
        if glowing[i] then f.glow.pulse:Play() end
    end

    -- Round / pattern.
    if d.round == 0 then
        view.roundText:SetText("Waiting for round 1")
    else
        view.roundText:SetText("Round " .. d.round)
    end
    view.patternText:SetText("Pattern: " .. (PATTERN_NAME[d.pattern] or "?"))
    local shape = {}
    if d.pattern == "line" then
        for c = 1, 5 do shape[10 + c] = true end -- show one example line
    else
        for _, i in ipairs(SHAPES[d.pattern][1]) do shape[i] = true end
    end
    for i, t in ipairs(view.mini) do
        if shape[i] or i == 13 then t:SetColorTexture(0.70, 0.25, 0.15, 1) else t:SetColorTexture(0.45, 0.35, 0.22, 0.35) end
    end

    -- Balls.
    local last = d.called[#d.called]
    view.bigBall:SetNumber(last)
    for i, b in ipairs(view.recent) do
        local n = d.called[#d.called - i]
        b:SetShown(n ~= nil)
        if n then b:SetNumber(n) end
    end
    view.calledText:SetText(#d.called .. " of 75 called" .. (#d.called > 1 and ". Before that:" or ""))

    -- BINGO button (players) vs number board (caller).
    local playing = s.status == "playing"
    view.bingo:SetShown(not isCaller and playing)
    view.bingoGlow:Hide()
    if not isCaller then
        if d.canClaim and d.roundActive and not d.claimed then
            view.bingo:SetEnabled(true)
            view.bingo:SetText("BINGO!")
            view.bingoGlow:Show(); view.bingoGlow.pulse:Play()
            view.bingo.label.pulse:Play()
        else
            view.bingo:SetEnabled(false)
            view.bingo:SetText(d.claimed and "Checking..." or "BINGO!")
            view.bingo.label.pulse:Stop()
        end
    end
    for n, fs in ipairs(view.board) do
        fs:SetShown(isCaller)
        if d.calledSet[n] then
            local c = COLUMN_COLORS[ColumnOf(n)]
            fs:SetTextColor(c[1] * 0.8, c[2] * 0.8, c[3] * 0.8)
        else
            fs:SetTextColor(0.62, 0.55, 0.45)
        end
    end

    -- Status line.
    local status
    if s.status == "ended" then
        status = "Bingo night is over. Thanks for playing!"
    elseif d.roundActive then
        if isCaller then
            status = d.paused and UI.InkRed("Paused.") or (d.speed > 0 and "Calling automatically..." or "Call numbers with the button.")
        elseif d.canClaim and not d.claimed then
            status = UI.InkGreen("You've got it! Press BINGO!")
        else
            status = "Your card marks itself. Fingers crossed!"
        end
    elseif d.lastWinner then
        status = UI.InkGreen(Util.ShortName(d.lastWinner) .. " won round " .. d.round .. "!") ..
            (isCaller and "  Start the next round when ready." or "  Next round soon...")
    elseif d.round > 0 then
        status = "Nobody won that round. Next round soon..."
    else
        status = isCaller and "Pick a pattern and press Start round!" or "Waiting for the caller to start..."
    end
    view.status:SetText(status)
    view.status:ClearAllPoints()
    view.status:SetPoint("TOP", view.info, "TOP", 0, isCaller and -272 or -258)

    -- Winners tonight.
    local lines = {}
    for i = #d.winners, math.max(1, #d.winners - 2), -1 do
        local w = d.winners[i]
        lines[#lines + 1] = ("Round %d: %s (%s)"):format(w.round, Util.ShortName(w.name), PATTERN_NAME[w.pattern] or w.pattern)
    end
    view.winners:SetText(#lines > 0 and ("Winners tonight:\n" .. table.concat(lines, "\n")) or
        (UI.InkGrey(#CardPlayers(s) .. " players tonight")))

    -- Caller's desk.
    if isCaller then
        local active = d.roundActive
        view.patternCycle.button:SetEnabled(not active)
        view.startButton:SetShown(not active and playing)
        view.callButton:SetShown(active and d.speed == 0)
        view.pauseButton:SetShown(active and d.speed > 0)
        view.pauseButton:SetText(d.paused and "Resume" or "Pause")
        view.patternCycle:Refresh()
        view.speedCycle:Refresh()
    end
    view.nextButton:SetShown(s.isLocal and playing and not d.roundActive and d.round > 0)

    -- The goblin narrates.
    if isCaller then
        UI:Say(d.roundActive and ("Round " .. d.round .. ": " .. #d.called .. " numbers called. " .. #CardPlayers(s) .. " players.")
            or "You're the caller! Pick a pattern, then Start round. Wins land in the winner log (Stats tab).")
    elseif d.canClaim and d.roundActive and not d.claimed then
        UI:Say("BINGO! Hit the button before someone else does!")
    end
end

-------------------------------------------------------------------------------
-- Module callbacks
-------------------------------------------------------------------------------
local function ResetRound(session, round, pattern)
    local d = session.data
    d.round = round
    d.pattern = pattern
    d.called, d.calledSet = {}, {}
    d.roundActive = true
    d.canClaim, d.claimed = false, false
    d.lastWinner = nil
    d.card = HasCard(session, session:Me()) and MakeCard(session.id, round, session:Me()) or nil
end

function Game.OnSessionStart(session)
    current = session
    local d = session.data
    d.round = 0
    d.pattern = "line"
    d.speed = session.isLocal and PRACTICE_SPEED or 8
    d.called, d.calledSet = {}, {}
    d.roundActive = false
    d.winners = {}
    d.card = nil
    if not view.cardPanel then Build() end
    for _, f in ipairs({ view.cardPanel, view.desk, view.info }) do f:Show() end
    EnsureTicker()
    Refresh()
    if session.isLocal then
        C_Timer.After(1, function() GG:Safe("Guild Bingo", StartRound, session) end)
    end
end

-- Host: a player calls BINGO. Check their real card against the real calls.
function Game.OnAction(session, sender, op, args)
    if op ~= "BINGO" or session.status ~= "playing" then return end
    local d = session.data
    if not d.roundActive or tonumber(args[1]) ~= d.round or not HasCard(session, sender) then
        session:SendTo(sender, "NOPE", d.round)
        return
    end
    local card = MakeCard(session.id, d.round, sender)
    if Satisfied(card, d.calledSet, d.pattern) then
        Win(session, sender)
    else
        session:SendTo(sender, "NOPE", d.round)
    end
end

function Game.OnState(session, op, args, isPrivate)
    local d = session.data
    if op == "ROUND" then
        ResetRound(session, tonumber(args[1]) or (d.round + 1), args[2] or "line")
        if HasCard(session, session:Me()) then GG.Theme:PlaySound("turn") end
    elseif op == "CALL" then
        local n = tonumber(args[1])
        if n and not d.calledSet[n] then
            d.called[#d.called + 1] = n
            d.calledSet[n] = true
            if session == current and view.bigBall then view.bigBall.popIn:Play() end
            if d.card and not d.canClaim and Satisfied(d.card, d.calledSet, d.pattern) then
                d.canClaim = true
                GG.Theme:PlaySound("turn")
            end
            -- Practice: the dummy shouts BINGO after a little "reaction time".
            if session.isLocal and session:IsHost() then Game.BotCheck(session) end
        end
    elseif op == "WIN" then
        local name, round, pattern = args[1], tonumber(args[2]), args[3]
        d.roundActive = false
        d.lastWinner = name
        d.winners[#d.winners + 1] = { name = name, round = round, pattern = pattern }
        if Util.IsMe(name) then
            GG.Theme:PlaySound("victory")
            UI:CoinShower(UI.frame)
            GG:Print("BINGO! You won round " .. round .. "!")
            if not session.isLocal then GG.Stats:Record("bingo", "win", {}) end
        else
            GG:Print(Util.ShortName(name) .. " got BINGO in round " .. round .. ".")
        end
    elseif op == "NOWIN" then
        d.roundActive = false
        d.lastWinner = nil
    elseif op == "NOPE" then
        d.claimed = false
        d.canClaim = d.card and Satisfied(d.card, d.calledSet, d.pattern) ~= nil
        GG:Print("The caller says that's not a Bingo (yet)!")
    elseif op == "SNAP" then
        local round, pattern = tonumber(args[1]) or 0, args[2] or "line"
        if round > 0 then ResetRound(session, round, pattern) else d.round, d.pattern = 0, pattern end
        d.roundActive = args[3] == "1"
        for n in (args[4] or ""):gmatch("%d+") do
            n = tonumber(n)
            d.called[#d.called + 1] = n
            d.calledSet[n] = true
        end
        d.lastWinner = (args[5] ~= "" and args[5]) or nil
        d.winners = {}
        for name, r, p in (args[6] or ""):gmatch("([^:;]+):(%d+):(%a+)") do
            d.winners[#d.winners + 1] = { name = name, round = tonumber(r), pattern = p }
        end
        d.canClaim = d.card ~= nil and d.roundActive and Satisfied(d.card, d.calledSet, d.pattern) ~= nil
    end
    if session == current then Refresh() end
end

-- Host: the full state for a latecomer or someone who missed messages.
function Game.OnSyncRequest(session, player)
    local d = session.data
    local wins = {}
    for _, w in ipairs(d.winners) do wins[#wins + 1] = w.name .. ":" .. w.round .. ":" .. w.pattern end
    session:SendTo(player, "SNAP", d.round, d.pattern, d.roundActive and "1" or "0",
        table.concat(d.called, ","), d.lastWinner or "", table.concat(wins, ";"))
end

-- Players can come and go; only the caller leaving ends the night.
function Game.OnPlayerLeft(session, name)
    if name == session.host then
        session:End({ winners = {}, reason = "the caller ended Bingo night" })
    end
    return true
end

function Game.QuitLabel(session)
    if session.isLocal then return "Quit" end
    return session:IsHost() and "End night" or "Leave"
end

function Game.OnSessionEnd(session)
    if session == current then Refresh() end
end

function Game.OnSessionClosed(session)
    if session == current then
        current = nil
        for _, f in ipairs({ view.cardPanel, view.desk, view.info, view.nextButton }) do if f then f:Hide() end end
    end
end

-------------------------------------------------------------------------------
-- Practice: you play a card, the Training Dummy plays one too, and a robot
-- caller calls a number every few seconds. The dummy is a bit slow on the
-- buzzer, so you have a chance.
-------------------------------------------------------------------------------
function Game.BotCheck(session)
    local d = session.data
    for _, p in ipairs(session.players) do
        if Util.IsBot(p) and d.roundActive and not d.botPending then
            local card = MakeCard(session.id, d.round, p)
            if Satisfied(card, d.calledSet, d.pattern) then
                d.botPending = true
                local round = d.round
                C_Timer.After(1.5 + math.random() * 2.5, function()
                    d.botPending = false
                    if session.status == "playing" and d.roundActive and d.round == round then
                        session:ActAs(p, "BINGO", round)
                    end
                end)
            end
        end
    end
end
Game.BotAction = function() end  -- Bingo has no turns; marks the game as practice-able

Game._test = { MakeCard = MakeCard, Satisfied = Satisfied, Hash = Hash, StartRound = StartRound,
    CallNext = CallNext, ClickBingo = OnBingoClick, SHAPES = SHAPES }

GG:RegisterGame(Game)
