--[[----------------------------------------------------------------------------
  GoblinGames_LiarsDice/LiarsDice.lua

  Liar's Dice for 2-6 players, in a smoky goblin tavern.

  RULES
    - Everyone has 5 dice (lobby option: 3 or 5) hidden under a cup. Each
      round, everyone's dice are rolled; you only see your own.
    - Take turns bidding on ALL the dice on the table: "there are at least
      four 5s". Each bid must be higher than the last: more dice, or the same
      number of dice with a higher face.
    - Ones are wild (lobby option, on by default): a 1 counts as every face,
      so nobody bids on 1s.
    - Instead of bidding, call "LIAR!" on the last bid. All dice are shown:
        * at least that many: the bid was true, the CALLER loses a die
        * fewer: the bidder was lying, the BIDDER loses a die
      The loser starts the next round. Lose your last die and you're out.
    - Last goblin with dice wins.

  WHERE THE DICE COME FROM
  Dice must stay secret, so they can't be rolled with /roll (everyone would
  see the result in chat). Instead the host's client rolls them and whispers
  each player only their own dice ("DICE"). That's the same casual-level
  trust as the card games: the host could peek, so play with people you
  trust. At a "Liar!" call, every die is shown to everyone ("REVEAL").

  Timeouts: the host makes the smallest legal bid for you (or calls Liar if
  no bid is possible). Leaving: your dice are removed and the round is
  re-rolled.
------------------------------------------------------------------------------]]

local GG = GoblinGames
local Util = GG.Util
local UI = GG.UI

local Game = {
    id = "liarsdice",
    compactHeader = true,
    hint = "Bid higher, or call LIAR! Ones are wild.",
    options = {
        { key = "dice", label = "Dice each", default = 5, values = {
            { value = 5, text = "5 dice" }, { value = 3, text = "3 dice (quick)" } } },
        { key = "wild", label = "Ones", default = 1, values = {
            { value = 1, text = "Ones are wild" }, { value = 0, text = "Ones are just ones" } } },
    },
}

local REVEAL_PAUSE = 6 -- seconds to look at everyone's dice after a call

local current

local function Wild(session) return tonumber(session.options and session.options.wild) ~= 0 end
local function MinFace(session) return Wild(session) and 2 or 1 end

--- Is (q, f) a legal bid after (cq, cf)? Shared by the host and the UI.
local function BidOK(session, total, cq, cf, q, f)
    if not q or not f or q < 1 or q > total then return false end
    if f < MinFace(session) or f > 6 then return false end
    if not cq or cq == 0 then return true end
    return q > cq or (q == cq and f > cf)
end

--- The smallest legal bid after (cq, cf), preferring `face` if given.
local function MinBid(session, total, cq, cf, face)
    local minF = MinFace(session)
    if not cq or cq == 0 then return 1, face or minF end
    if face and face > cf then return cq, face end
    if face then return cq + 1, face end
    if cf < 6 then return cq, cf + 1 end
    return cq + 1, minF
end

local function Count(session, dice, face)
    local n = 0
    for _, v in ipairs(dice) do
        if v == face or (v == 1 and Wild(session) and face ~= 1) then n = n + 1 end
    end
    return n
end

local function DiceString(list)
    local t = {}
    for i, v in ipairs(list) do t[i] = tostring(v) end
    return table.concat(t)
end

local function ParseDice(text)
    local list = {}
    for ch in (text or ""):gmatch("%d") do list[#list + 1] = tonumber(ch) end
    return list
end

-------------------------------------------------------------------------------
-- Host
--
-- Host-only: d.dice[name] = {faces}   (whispered to each owner)
-- Everyone:  d.counts[name] (dice left), d.bid = { q, f, by }, d.round,
--            d.phase "bid" | "reveal", d.revealed[name] = {faces}
-------------------------------------------------------------------------------
local function Alive(session)
    local d = session.data
    local list = {}
    for _, p in ipairs(d.order) do
        if session:IsActive(p) and (d.counts[p] or 0) > 0 then list[#list + 1] = p end
    end
    return list
end

local function TotalDice(d)
    local n = 0
    for _, c in pairs(d.counts) do n = n + c end
    return n
end

local function Snapshot(session)
    local d = session.data
    local seats = {}
    for _, p in ipairs(d.order) do seats[#seats + 1] = p .. ":" .. (d.counts[p] or 0) end
    local b = d.bid or {}
    return d.round, d.phase, b.q or 0, b.f or 0, b.by or "", table.concat(seats, ";")
end

local function SendTable(session)
    session:Broadcast("TABLE", Snapshot(session))
end

local function NextAlive(session, from)
    local d = session.data
    local idx = Util.IndexOf(d.order, from) or 0
    for step = 1, #d.order do
        local p = d.order[(idx + step - 1) % #d.order + 1]
        if session:IsActive(p) and (d.counts[p] or 0) > 0 then return p end
    end
end

local StartRound

local function EndIfOver(session)
    local alive = Alive(session)
    if #alive <= 1 then
        session:End({ winners = alive, reason = "last goblin with dice" })
        return true
    end
    return false
end

function StartRound(session, starter)
    local d = session.data
    if session.status ~= "playing" or EndIfOver(session) then return end
    d.round = d.round + 1
    d.phase = "bid"
    d.bid = nil
    d.dice = {}
    for _, p in ipairs(Alive(session)) do
        local list = {}
        for i = 1, d.counts[p] do list[i] = math.random(1, 6) end
        table.sort(list)
        d.dice[p] = list
        session:SendTo(p, "DICE", d.round, DiceString(list))
    end
    if not (starter and session:IsActive(starter) and (d.counts[starter] or 0) > 0) then
        starter = NextAlive(session, starter or d.order[#d.order])
    end
    session:Broadcast("EV", "ROUND", d.round, starter)
    SendTable(session)
    GG.Turns:Advance(session, starter)
end

local function Bid(session, player, q, f)
    local d = session.data
    if session.status ~= "playing" or d.phase ~= "bid" or GG.Turns:Current(session) ~= player then return false end
    q, f = tonumber(q), tonumber(f)
    local cur = d.bid or {}
    if not BidOK(session, TotalDice(d), cur.q, cur.f, q, f) then return false end
    d.bid = { q = q, f = f, by = player }
    session:Broadcast("EV", "BID", player, q, f)
    SendTable(session)
    GG.Turns:Advance(session, NextAlive(session, player))
    return true
end

local function CallLiar(session, caller)
    local d = session.data
    if session.status ~= "playing" or d.phase ~= "bid" or GG.Turns:Current(session) ~= caller then return false end
    local bid = d.bid
    if not bid then return false end -- nothing to call yet

    -- Show everyone's dice, then count.
    local all, shown = {}, {}
    for _, p in ipairs(Alive(session)) do
        shown[#shown + 1] = p .. ":" .. DiceString(d.dice[p] or {})
        for _, v in ipairs(d.dice[p] or {}) do all[#all + 1] = v end
    end
    local count = Count(session, all, bid.f)
    local loser = (count >= bid.q) and caller or bid.by
    d.counts[loser] = d.counts[loser] - 1
    d.phase = "reveal"
    session:Broadcast("REVEAL", d.round, table.concat(shown, ";"))
    session:Broadcast("EV", "LIAR", caller, bid.by, bid.q, bid.f, count, loser)
    if d.counts[loser] == 0 then session:Broadcast("EV", "OUT", loser) end
    SendTable(session)
    GG.Turns:Advance(session, caller) -- the clock waits while everyone looks

    d.runId = (d.runId or 0) + 1
    local id = d.runId
    C_Timer.After(REVEAL_PAUSE, function()
        if session.status == "playing" and d.runId == id then StartRound(session, loser) end
    end)
    return true
end

-- Timeouts and the dummy. `smart` = think about the odds first.
local function AutoTurn(session, player, smart)
    local d = session.data
    if d.phase ~= "bid" then return end
    local total = TotalDice(d)
    local mine = d.dice[player] or {}
    local cur = d.bid
    -- Which face do I have most of (wild ones included)?
    local bestFace, bestN = MinFace(session), -1
    for f = MinFace(session), 6 do
        local n = Count(session, mine, f)
        if n > bestN then bestFace, bestN = f, n end
    end
    if smart and cur then
        -- Expected number of the bid face: mine, plus what the others probably have.
        local p = (Wild(session) and cur.f ~= 1) and (1 / 3) or (1 / 6)
        local expected = Count(session, mine, cur.f) + (total - #mine) * p
        if cur.q > expected + 0.75 then
            CallLiar(session, player)
            return
        end
    end
    local q, f = MinBid(session, total, cur and cur.q, cur and cur.f, smart and bestFace or nil)
    if smart and not cur then q = math.max(1, bestN + math.floor((total - #mine) / 6)) end
    if not Bid(session, player, q, f) then
        local q2, f2 = MinBid(session, total, cur and cur.q, cur and cur.f)
        if not Bid(session, player, q2, f2) then CallLiar(session, player) end
    end
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------
local view = {}
local seatFrames = {}
local Refresh

local function SendBid()
    local s = current
    if s and GG.Turns:IsMyTurn(s) and view.q and view.f then s:SendAction("BID", view.q, view.f) end
end
local function SendLiar()
    local s = current
    if s and GG.Turns:IsMyTurn(s) then s:SendAction("LIAR") end
end

-- Keep the bid picker on a legal bid.
local function FixPicker(s)
    local d = s.data
    local total = 0
    for _, c in pairs(d.counts) do total = total + c end
    local cq, cf = d.bid and d.bid.q, d.bid and d.bid.f
    if not view.q or not view.f or not BidOK(s, total, cq, cf, view.q, view.f) then
        view.q, view.f = MinBid(s, total, cq, cf, view.f)
        if not BidOK(s, total, cq, cf, view.q, view.f) then view.q, view.f = MinBid(s, total, cq, cf) end
    end
end

local function PickFace(face)
    local s = current
    if not s then return end
    view.f = face
    local d = s.data
    local total = 0
    for _, c in pairs(d.counts) do total = total + c end
    -- Jump to the smallest legal bid of that face; +/- adjust from there.
    local cq, cf = d.bid and d.bid.q, d.bid and d.bid.f
    view.q = (MinBid(s, total, cq, cf, face))
    Refresh()
end

local function StepQty(delta)
    local s = current
    if not s then return end
    view.q = math.max(1, (view.q or 1) + delta)
    Refresh()
end

local function Build()
    local area = UI:GetGameArea()

    -- Opponents' cups along the top.
    for i = 1, 5 do
        local f = CreateFrame("Frame", nil, area)
        f:SetSize(134, 84)
        f.parts = UI.NineSlice(f, UI.MEDIA .. "Parchment", 128, 24, 14)
        f.glow = f:CreateTexture(nil, "OVERLAY")
        f.glow:SetTexture(UI.MEDIA .. "ButtonGlow")
        f.glow:SetPoint("TOPLEFT", -10, 8)
        f.glow:SetPoint("BOTTOMRIGHT", 10, -8)
        f.glow:SetBlendMode("ADD")
        f.glow:SetVertexColor(1, 0.75, 0.2)
        f.glow:Hide()
        UI.AddPulse(f.glow, 0.3, 0.6)
        f.crest = f:CreateTexture(nil, "ARTWORK")
        f.crest:SetSize(18, 18)
        f.crest:SetPoint("TOPLEFT", 8, -8)
        f.name = UI.Text(f, "", { ink = true, font = "GameFontNormalSmall" })
        f.name:SetPoint("LEFT", f.crest, "RIGHT", 4, 0)
        f.name:SetWidth(96)
        f.name:SetJustifyH("LEFT")
        f.dice = {}
        for k = 1, 5 do
            local die = UI.Die(f, 22)
            die:SetPoint("TOPLEFT", 8 + (k - 1) * 24, -32)
            f.dice[k] = die
        end
        f.bid = UI.Text(f, "", { fancy = true, size = 13, ink = true })
        f.bid:SetPoint("BOTTOMLEFT", 8, 8)
        seatFrames[i] = f
    end

    -- The table: the bid on the line.
    local t = UI.Card(area)
    t:SetPoint("TOPLEFT", 0, -94)
    t:SetPoint("RIGHT", area, "RIGHT", 0, 0)
    t:SetHeight(110)
    view.table = t
    view.round = UI.Text(t, "", { ink = true, font = "GameFontNormalSmall" })
    view.round:SetPoint("TOPLEFT", 14, -12)
    view.round:SetTextColor(0.48, 0.38, 0.25)
    view.bidLabel = UI.Text(t, "", { ink = true, font = "GameFontNormal" })
    view.bidLabel:SetPoint("TOPLEFT", 14, -30)
    view.bidQty = UI.Text(t, "", { fancy = true, size = 34, ink = true })
    view.bidQty:SetPoint("TOPLEFT", 14, -50)
    view.bidDie = UI.Die(t, 42)
    view.bidDie:SetPoint("LEFT", view.bidQty, "RIGHT", 8, 0)
    view.wildNote = UI.Text(t, "", { ink = true, font = "GameFontHighlightSmall" })
    view.wildNote:SetPoint("TOPLEFT", 14, -96)
    view.wildNote:SetTextColor(0.48, 0.38, 0.25)
    view.totalText = UI.Text(t, "", { ink = true, font = "GameFontNormalSmall" })
    view.totalText:SetPoint("TOPLEFT", 170, -12)
    view.liarRibbon = UI.Ribbon(t, "LIAR!", 200, 52, "danger")
    view.liarRibbon:SetPoint("CENTER", t, "CENTER", 30, 0)
    view.liarRibbon:Hide()
    UI.AddPopIn(view.liarRibbon)
    view.log = UI.Text(t, "", { ink = true, font = "GameFontHighlightSmall", justify = "RIGHT" })
    view.log:SetPoint("TOPRIGHT", -14, -12)
    view.log:SetWidth(250)
    view.log:SetJustifyV("TOP")
    view.log:SetSpacing(2)

    -- You: your dice, and the bid picker.
    local me = CreateFrame("Frame", nil, area)
    me:SetPoint("TOPLEFT", 0, -212)
    me:SetPoint("BOTTOMRIGHT", 0, 0)
    view.me = me
    view.myTitle = UI.Text(me, "Your dice", { fancy = true, size = 15 })
    view.myTitle:SetPoint("TOPLEFT", 4, -4)
    view.myDice = {}
    for k = 1, 5 do
        local die = UI.Die(me, 48)
        die:SetPoint("TOPLEFT", 4 + (k - 1) * 54, -26)
        view.myDice[k] = die
    end
    view.myNote = UI.Text(me, "", { font = "GameFontHighlightSmall" })
    view.myNote:SetPoint("TOPLEFT", 4, -82)
    view.myNote:SetTextColor(1, 0.9, 0.7)
    view.myNote:SetWidth(280)
    view.myNote:SetJustifyH("LEFT")

    -- Picker: [-] qty [+]  x  [2][3][4][5][6]
    view.minus = UI.Button(me, "-", 32, 30, function() GG:Safe("Liar's Dice", StepQty, -1) end, "wood")
    view.minus:SetPoint("TOPLEFT", me, "TOPLEFT", 300, -18)
    view.qty = UI.Text(me, "", { fancy = true, size = 26, justify = "CENTER" })
    view.qty:SetPoint("LEFT", view.minus, "RIGHT", 2, 0)
    view.qty:SetWidth(40)
    view.plus = UI.Button(me, "+", 32, 30, function() GG:Safe("Liar's Dice", StepQty, 1) end, "wood")
    view.plus:SetPoint("LEFT", view.qty, "RIGHT", 2, 0)
    view.times = UI.Text(me, "x", { fancy = true, size = 18 })
    view.times:SetPoint("LEFT", view.plus, "RIGHT", 8, 0)
    view.faces = {}
    for face = 1, 6 do
        local b = CreateFrame("Button", nil, me)
        b:SetSize(38, 38)
        b.die = UI.Die(b, 34)
        b.die:SetPoint("CENTER")
        b.die:SetFace(face)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture(UI.MEDIA .. "ButtonGlow")
        hl:SetAllPoints()
        hl:SetBlendMode("ADD")
        b:SetScript("OnClick", function() GG:Safe("Liar's Dice", PickFace, face) end)
        view.faces[face] = b
    end
    view.bidButton = UI.Button(me, "Bid!", 150, 40, function() GG:Safe("Liar's Dice", SendBid) end, "primary")
    view.bidButton:SetPoint("BOTTOMRIGHT", me, "BOTTOMRIGHT", -170, 10)
    view.liarButton = UI.Button(me, "LIAR!", 150, 40, function() GG:Safe("Liar's Dice", SendLiar) end, "danger")
    view.liarButton:SetPoint("BOTTOMRIGHT", me, "BOTTOMRIGHT", -4, 10)
    view.liarButton.tooltip = "Call the last bid a lie. Everyone's dice are shown."
end

local function Name(p) return Util.IsMe(p) and "You" or Util.ShortName(p) end
local FACE_PLURAL = { "ones", "twos", "threes", "fours", "fives", "sixes" }

local function LogLine(d, text)
    d.log[#d.log + 1] = text
    while #d.log > 5 do table.remove(d.log, 1) end
end

function Refresh()
    local s = current
    if not s or not view.table then return end
    local d = s.data
    local playing = s.status == "playing"
    local cur = GG.Turns:Current(s)
    local myTurn = playing and d.phase == "bid" and cur == s:Me()
    local total = 0
    for _, c in pairs(d.counts) do total = total + c end
    local bid = d.bid
    local revealing = d.phase == "reveal" and d.revealed

    -- Opponents.
    local others = {}
    local order = d.order or s.players
    local idx = Util.IndexOf(order, s:Me()) or 0
    for k = 1, #order do
        local p = order[(idx + k - 1) % #order + 1]
        if not Util.IsMe(p) then others[#others + 1] = p end
    end
    local avail = view.table:GetWidth()
    if not avail or avail < 100 then avail = 704 end
    local n = #others
    local x0 = (avail - (n * 140 - 6)) / 2
    for i, f in ipairs(seatFrames) do
        local p = others[i]
        if p then
            f:Show()
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", view.table, "TOPLEFT", x0 + (i - 1) * 140, 94)
            GG.Theme:SetCrest(f.crest, s:GetFaction(p))
            local count = d.counts[p] or 0
            f.name:SetText(Util.ShortName(p) .. ((count == 0) and " |cffa51d12(out)|r" or ""))
            local shown = revealing and d.revealed[p]
            for k, die in ipairs(f.dice) do
                if k <= (shown and #shown or count) then
                    die:SetFace(shown and shown[k] or 0)
                    die:SetGlow(shown and bid and (shown[k] == bid.f or (shown[k] == 1 and d.wild and bid.f ~= 1)))
                else
                    die:SetFace(nil)
                end
            end
            f.bid:SetText(d.lastBid[p] or "")
            local active = playing and d.phase == "bid" and cur == p
            f.glow:SetShown(active)
            if active then f.glow.pulse:Play() end
            f:SetAlpha(count == 0 and 0.5 or 1)
        else
            f:Hide()
        end
    end

    -- The bid on the table.
    view.round:SetText(("Round %d"):format(math.max(1, d.round or 1)))
    view.totalText:SetText(("Dice on the table: %d"):format(total))
    if bid then
        view.bidLabel:SetText(Name(bid.by) .. (Util.IsMe(bid.by) and " bid:" or " bids:"))
        view.bidQty:SetText(bid.q .. " x")
        view.bidDie:SetFace(bid.f)
    else
        view.bidLabel:SetText(cur and (Name(cur) .. (Util.IsMe(cur) and " open the bidding." or " opens the bidding.")) or "")
        view.bidQty:SetText("")
        view.bidDie:SetFace(nil)
    end
    view.wildNote:SetText(d.wild and "Ones are wild: they count as any face." or "Ones are just ones.")
    view.liarRibbon:SetShown(revealing and true or false)
    view.log:SetText(table.concat(d.log, "\n"))

    -- Your dice.
    local mine = (revealing and d.revealed[s:Me()]) or d.myDice
    local myCount = d.counts[s:Me()] or 0
    for k, die in ipairs(view.myDice) do
        if k <= myCount or (revealing and mine[k]) then
            die:SetFace(mine[k] or 0)
            die:SetGlow(bid and mine[k] and (mine[k] == bid.f or (mine[k] == 1 and d.wild and bid.f ~= 1)))
        else
            die:SetFace(nil)
        end
    end
    if myCount == 0 then
        view.myNote:SetText("You're out of dice. Enjoy the show!")
    elseif bid then
        local have = 0
        for _, v in ipairs(d.myDice) do
            if v == bid.f or (v == 1 and d.wild and bid.f ~= 1) then have = have + 1 end
        end
        view.myNote:SetText(("You have %d of the %d %s bid on (glowing)."):format(have, bid.q, FACE_PLURAL[bid.f]))
    else
        view.myNote:SetText("Only you can see these.")
    end

    -- Picker.
    local show = myTurn
    for _, w in ipairs({ view.minus, view.qty, view.plus, view.times, view.bidButton, view.liarButton }) do
        w:SetShown(show and true or false)
    end
    for face, b in ipairs(view.faces) do
        b:ClearAllPoints()
        b:SetShown(show and face >= (d.wild and 2 or 1))
    end
    if show then
        FixPicker(s)
        local x = 0
        for face = (d.wild and 2 or 1), 6 do
            local b = view.faces[face]
            b:SetPoint("LEFT", view.times, "RIGHT", 6 + x * 40, 0)
            b.die:SetGlow(face == view.f)
            x = x + 1
        end
        view.qty:SetText(UI.Gold(view.q))
        local ok = BidOK(s, total, bid and bid.q, bid and bid.f, view.q, view.f)
        view.bidButton:SetEnabled(ok)
        view.bidButton:SetText(ok and ("Bid " .. view.q .. " " .. FACE_PLURAL[view.f]) or "Can't bid that")
        view.liarButton:SetEnabled(bid ~= nil)
        UI:SetGameStatus(UI.Gold(bid and "Your turn! Raise the bid, or call LIAR!" or "Your turn! Open the bidding."))
    else
        UI:SetGameStatus(nil)
    end
end

-------------------------------------------------------------------------------
-- Module callbacks
-------------------------------------------------------------------------------
function Game.OnSessionStart(session)
    current = session
    local d = session.data
    d.log, d.myDice, d.counts, d.lastBid, d.revealed = {}, {}, {}, {}, {}
    d.round, d.phase, d.bid = 0, "bid", nil
    d.wild = Wild(session)
    view.q, view.f = nil, nil
    if not view.table then Build() end
    view.table:Show(); view.me:Show()

    if session:IsHost() then
        local per = tonumber(session.options and session.options.dice) or 5
        d.order = Util.Shuffle(Util.Copy(session.players))
        for _, p in ipairs(d.order) do d.counts[p] = per end
        GG.Turns:Start(session, d.order)
        StartRound(session, d.order[1])
    end
    Refresh()
end

function Game.OnAction(session, sender, op, args)
    if op == "BID" then
        Bid(session, sender, args[1], args[2])
    elseif op == "LIAR" then
        CallLiar(session, sender)
    end
end

function Game.OnState(session, op, args)
    local d = session.data
    if op == "DICE" then
        d.myDice = ParseDice(args[2])
    elseif op == "TABLE" then
        d.round, d.phase = tonumber(args[1]) or 0, args[2]
        local q, f = tonumber(args[3]) or 0, tonumber(args[4]) or 0
        d.bid = (q > 0) and { q = q, f = f, by = args[5] } or nil
        if not session:IsHost() then
            d.order, d.counts = {}, {}
            for name, c in (args[6] or ""):gmatch("([^:;]+):(%d+)") do
                d.order[#d.order + 1] = name
                d.counts[name] = tonumber(c)
            end
        end
    elseif op == "REVEAL" then
        d.revealed = {}
        for name, dice in (args[2] or ""):gmatch("([^:;]+):(%d*)") do d.revealed[name] = ParseDice(dice) end
    elseif op == "EV" then
        local kind = args[1]
        if kind == "ROUND" then
            d.lastBid, d.revealed = {}, {}
            if session == current then view.q, view.f = nil, nil end
            LogLine(d, ("|cff5a3412Round %s: cups down! %s %s first.|r"):format(args[2], Name(args[3]), Util.IsMe(args[3]) and "go" or "goes"))
        elseif kind == "BID" then
            local who, q, f = args[2], tonumber(args[3]), tonumber(args[4])
            d.lastBid[who] = ("Bid %d %s"):format(q, FACE_PLURAL[f] or "?")
            LogLine(d, ("%s %s %d %s."):format(Name(who), Util.IsMe(who) and "bid" or "bids", q, FACE_PLURAL[f] or "?"))
        elseif kind == "LIAR" then
            local caller, bidder, q, f, count, loser = args[2], args[3], tonumber(args[4]), tonumber(args[5]), tonumber(args[6]), args[7]
            d.lastBid[caller] = "LIAR!"
            LogLine(d, ("|cffa51d12%s called LIAR on %s!|r"):format(Name(caller), Name(bidder)))
            LogLine(d, ("There %s %d %s. %s %s a die!"):format(count == 1 and "was" or "were", count, FACE_PLURAL[f] or "?",
                Name(loser), Util.IsMe(loser) and "lose" or "loses"))
            if Util.IsMe(loser) then GG.Theme:PlaySound("defeat") end
            if session == current and view.liarRibbon then view.liarRibbon:Show(); view.liarRibbon.popIn:Play() end
        elseif kind == "OUT" then
            LogLine(d, ("|cffa51d12%s %s out of dice!|r"):format(Name(args[2]), Util.IsMe(args[2]) and "are" or "is"))
        elseif kind == "LEFT" then
            LogLine(d, ("%s left; the dice are rolled again."):format(Name(args[2])))
        end
    end
    if session == current then Refresh() end
end

function Game.OnSyncRequest(session, player)
    local d = session.data
    if d.dice and d.dice[player] then session:SendTo(player, "DICE", d.round, DiceString(d.dice[player])) end
    session:SendTo(player, "TABLE", Snapshot(session))
end

function Game.OnTurnTimeout(session, name)
    local d = session.data
    if d.phase == "bid" then AutoTurn(session, name, false) end
end

function Game.OnPlayerLeft(session, name)
    if Util.IsMe(name) then return false end
    local d = session.data
    d.counts[name] = 0
    session:Broadcast("EV", "LEFT", name)
    if EndIfOver(session) then return true end
    if d.phase == "bid" then
        -- Re-roll, starting with whoever was up (or the next player).
        local starter = GG.Turns:Current(session)
        if starter == name then starter = NextAlive(session, name) end
        d.round = d.round - 1 -- it's the same round, rolled again
        StartRound(session, starter)
    else
        SendTable(session)
    end
    return true
end

function Game.OnSessionEnd(session)
    if session == current then Refresh() end
end

function Game.OnSessionClosed(session)
    if session == current then
        current = nil
        if view.table then view.table:Hide(); view.me:Hide() end
        for _, f in ipairs(seatFrames) do f:Hide() end
        UI:SetGameStatus(nil)
    end
end

GG.RegisterCallback(Game, "TURN_CHANGED", function(_, session)
    if session == current then Refresh() end
end)

function Game.BotAction(session, bot)
    if session.status ~= "playing" or GG.Turns:Current(session) ~= bot then return end
    AutoTurn(session, bot, true)
end

Game._test = { BidOK = BidOK, MinBid = MinBid, Count = Count, Bid = Bid, CallLiar = CallLiar, AutoTurn = AutoTurn,
    PickFace = PickFace, StepQty = StepQty, SendBid = SendBid, SendLiar = SendLiar, view = view }

GG:RegisterGame(Game)
