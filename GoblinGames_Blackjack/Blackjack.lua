--[[----------------------------------------------------------------------------
  GoblinGames_Blackjack/Blackjack.lua

  Blackjack for 2-8: the host is the dealer, everyone else plays against the
  house with chips. (In practice, the Training Dummy deals and you play.)

  RULES
    - Everyone starts with the same pile of chips (lobby option).
    - Each round: place a bet, get two cards face up. The dealer gets one
      card face up and one face down (the "hole" card).
    - On your turn: Hit (take a card), Stand (stop), or Double (double your
      bet, take exactly one more card; only on your first two cards).
      Go over 21 and you bust: you lose your bet.
    - Then the dealer turns over the hole card and draws until 17 or more
      (the dealer stands on every 17).
    - Beat the dealer without busting: you win your bet. Tie: push, you get
      it back. Blackjack (21 with your first two cards): paid 3 to 2.
    - After the last round (lobby option), the most chips wins.
    - Chips are just points. There's no gold in Blackjack.

  WHO HOLDS WHAT
  Players' cards are dealt face up, so they're public. The only secrets are
  the shuffled shoe and the dealer's hole card: they live only on the host's
  client until the hole card is revealed. Every change is sent to everyone as
  one "TABLE" snapshot, so a missed message is fixed by the next one.

  TURNS
  The core turn system is used for timers: the dealer "holds the turn" while
  bets are placed (if the clock runs out, the cards are dealt) and while the
  dealer plays. A player who runs out of time stands.
------------------------------------------------------------------------------]]

local GG = GoblinGames
local Util = GG.Util
local UI = GG.UI
local Cards = GG.Cards

local Game = {
    id = "blackjack",
    compactHeader = true,
    hint = "Bet, then Hit or Stand. Get closer to 21 than the dealer!",
    options = {
        { key = "rounds", label = "Rounds", default = 5, values = {
            { value = 3, text = "3 rounds" }, { value = 5, text = "5 rounds" }, { value = 10, text = "10 rounds" } } },
        { key = "chips", label = "Starting chips", default = 100, values = {
            { value = 100, text = "100 chips" }, { value = 500, text = "500 chips" } } },
    },
}

local DEALER_DELAY = 0.8   -- seconds between the dealer's cards
local RESULTS_PAUSE = 6    -- seconds to admire the results before the next deal
local SHOE_DECKS = 2
local RESHUFFLE_AT = 20    -- fewer cards than this left in the shoe: reshuffle

local current

-------------------------------------------------------------------------------
-- Shared helpers (every client)
-------------------------------------------------------------------------------

--- Best total of a hand, and whether it's "soft" (an Ace counted as 11).
local function HandValue(cards)
    local total, aces = 0, 0
    for _, c in ipairs(cards) do
        local r = Cards.Rank(c)
        if r == "A" then total = total + 1; aces = aces + 1
        elseif r == "T" or r == "J" or r == "Q" or r == "K" then total = total + 10
        elseif r ~= "?" then total = total + tonumber(r) end
    end
    if aces > 0 and total + 10 <= 21 then return total + 10, true end
    return total, false
end

local function IsBlackjack(cards)
    return #cards == 2 and HandValue(cards) == 21
end

local function BetChoices(session)
    local start = tonumber(session.options and session.options.chips) or 100
    return { start / 20, start / 10, start / 4, start / 2 }
end

local function Dealer(session)
    -- Practice: the Training Dummy deals. Otherwise the host does.
    if session.isLocal then
        for _, p in ipairs(session.players) do if Util.IsBot(p) then return p end end
    end
    return session.host
end

local function SplitCards(text)
    local list = {}
    for c in (text or ""):gmatch("..") do list[#list + 1] = c end
    return list
end

-------------------------------------------------------------------------------
-- Host: the table
--
-- Host-only: d.shoe = {cards}, d.hole = the dealer's face-down card
-- d.seats[name] = { chips, bet, cards = {}, state, res, delta }
--   state: "" (still to act) | "stand" | "bust" | "bj" | "dbl" | "out"
--   res:   "W" win | "B" blackjack | "P" push | "L" loss (after the round)
-------------------------------------------------------------------------------
local function Players(session)
    local list, dealer = {}, Dealer(session)
    for _, p in ipairs(session.players) do
        if p ~= dealer then list[#list + 1] = p end
    end
    return list
end

local function InHand(session, p)
    local seat = session.data.seats[p]
    return seat and seat.state ~= "out" and session:IsActive(p)
end

local function Snapshot(session)
    local d = session.data
    local dealerCards = {}
    for i, c in ipairs(d.dealerCards) do
        dealerCards[i] = (i == 2 and not d.revealed) and "??" or c
    end
    local seats = {}
    for _, p in ipairs(Players(session)) do
        local s = d.seats[p]
        seats[#seats + 1] = table.concat({ p, s.chips, s.bet, table.concat(s.cards),
            s.state, s.res or "", s.delta or 0 }, ",")
    end
    return d.round, d.rounds, d.phase, table.concat(dealerCards), table.concat(seats, ";")
end

local function SendTable(session)
    session:Broadcast("TABLE", Snapshot(session))
end

local function DrawCard(session)
    local d = session.data
    if #d.shoe < 1 then
        d.shoe = Cards.Shuffle(Cards.NewDeck(SHOE_DECKS))
        session:Broadcast("EV", "SHUFFLE")
    end
    return table.remove(d.shoe)
end

local StartRound, Deal, NextPlayer, DealerPlay, Settle, EndGame

function EndGame(session)
    local d = session.data
    local best, winners = -1, {}
    local everyone = {}
    for _, p in ipairs(Players(session)) do
        if session:IsActive(p) then
            everyone[#everyone + 1] = p
            local chips = d.seats[p].chips
            if chips > best then best, winners = chips, { p } elseif chips == best then winners[#winners + 1] = p end
        end
    end
    local tie = #winners > 1 and #winners == #everyone
    session:End({ winners = tie and {} or winners, draw = tie,
        reason = ("most chips: %d"):format(math.max(best, 0)) })
end

function StartRound(session)
    local d = session.data
    if session.status ~= "playing" then return end
    local anyone = false
    for _, p in ipairs(Players(session)) do
        local s = d.seats[p]
        s.bet, s.cards, s.res, s.delta = 0, {}, nil, 0
        if s.chips <= 0 or not session:IsActive(p) then s.state = "out" else s.state = ""; anyone = true end
    end
    if not anyone or d.round >= d.rounds then
        SendTable(session)
        EndGame(session)
        return
    end
    d.round = d.round + 1
    d.phase = "bet"
    d.dealerCards, d.hole, d.revealed = {}, nil, false
    if #d.shoe < RESHUFFLE_AT then
        d.shoe = Cards.Shuffle(Cards.NewDeck(SHOE_DECKS))
        session:Broadcast("EV", "SHUFFLE")
    end
    session:Broadcast("EV", "ROUND", d.round)
    SendTable(session)
    GG.Turns:Advance(session, Dealer(session)) -- the dealer holds the turn while bets go in
end

local function AllBet(session)
    for _, p in ipairs(Players(session)) do
        if InHand(session, p) and session.data.seats[p].bet <= 0 then return false end
    end
    return true
end

local function Bet(session, player, amount)
    local d = session.data
    if session.status ~= "playing" or d.phase ~= "bet" or not InHand(session, player) then return false end
    local seat = d.seats[player]
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    -- Short on chips? Then it's all-in.
    if amount > seat.chips then amount = seat.chips end
    seat.bet = amount
    session:Broadcast("EV", "BET", player, amount)
    SendTable(session)
    if AllBet(session) then
        local round = d.round
        C_Timer.After(0.6, function()
            if session.status == "playing" and d.phase == "bet" and d.round == round then Deal(session) end
        end)
    end
    return true
end

function Deal(session)
    local d = session.data
    if session.status ~= "playing" or d.phase ~= "bet" then return false end
    local minBet = BetChoices(session)[1]
    -- Anyone who didn't bet in time gets the smallest bet.
    for _, p in ipairs(Players(session)) do
        local seat = d.seats[p]
        if InHand(session, p) and seat.bet <= 0 then seat.bet = math.min(minBet, seat.chips) end
    end
    -- Two each, the dealer last; the dealer's second card is the hole card.
    for round = 1, 2 do
        for _, p in ipairs(Players(session)) do
            if InHand(session, p) then table.insert(d.seats[p].cards, DrawCard(session)) end
        end
        table.insert(d.dealerCards, DrawCard(session))
    end
    d.hole = d.dealerCards[2]
    for _, p in ipairs(Players(session)) do
        if InHand(session, p) and IsBlackjack(d.seats[p].cards) then
            d.seats[p].state = "bj"
            session:Broadcast("EV", "BJ", p)
        end
    end
    d.phase = "play"
    SendTable(session)
    NextPlayer(session)
    return true
end

-- Whose turn is next? The first player still to act, or the dealer.
function NextPlayer(session)
    local d = session.data
    for _, p in ipairs(Players(session)) do
        if InHand(session, p) and d.seats[p].state == "" then
            GG.Turns:Advance(session, p)
            return
        end
    end
    DealerPlay(session)
end

local function Hit(session, player)
    local d = session.data
    local seat = d.seats[player]
    if d.phase ~= "play" or GG.Turns:Current(session) ~= player or not seat or seat.state ~= "" then return false end
    local card = DrawCard(session)
    table.insert(seat.cards, card)
    local total = HandValue(seat.cards)
    session:Broadcast("EV", "HIT", player, card, total)
    if total > 21 then
        seat.state = "bust"
        session:Broadcast("EV", "BUST", player)
    elseif total == 21 then
        seat.state = "stand" -- 21: nothing better to do
    end
    SendTable(session)
    if seat.state ~= "" then NextPlayer(session) else GG.Turns:ResetTimer(session) end
    return true
end

local function Stand(session, player)
    local d = session.data
    local seat = d.seats[player]
    if d.phase ~= "play" or GG.Turns:Current(session) ~= player or not seat or seat.state ~= "" then return false end
    seat.state = "stand"
    session:Broadcast("EV", "STAND", player, HandValue(seat.cards))
    SendTable(session)
    NextPlayer(session)
    return true
end

local function CanDouble(seat)
    return seat and seat.state == "" and #seat.cards == 2 and seat.chips >= seat.bet * 2
end

local function Double(session, player)
    local d = session.data
    local seat = d.seats[player]
    if d.phase ~= "play" or GG.Turns:Current(session) ~= player or not CanDouble(seat) then return false end
    seat.bet = seat.bet * 2
    local card = DrawCard(session)
    table.insert(seat.cards, card)
    local total = HandValue(seat.cards)
    session:Broadcast("EV", "DOUBLE", player, card, total)
    if total > 21 then
        seat.state = "bust"
        session:Broadcast("EV", "BUST", player)
    else
        seat.state = "dbl"
    end
    SendTable(session)
    NextPlayer(session)
    return true
end

-- The dealer turns over the hole card and draws to 17, one card at a time.
function DealerPlay(session)
    local d = session.data
    d.phase = "dealer"
    d.revealed = true
    session:Broadcast("EV", "REVEAL", d.hole or "", HandValue(d.dealerCards))
    SendTable(session)
    GG.Turns:Advance(session, Dealer(session))

    -- If every player busted, the dealer doesn't need to draw.
    local needed = false
    for _, p in ipairs(Players(session)) do
        if InHand(session, p) and d.seats[p].state ~= "bust" and d.seats[p].state ~= "bj" then needed = true end
    end
    local round = d.round
    local function Step()
        if session.status ~= "playing" or d.round ~= round or d.phase ~= "dealer" then return end
        if needed and HandValue(d.dealerCards) < 17 then
            local card = DrawCard(session)
            table.insert(d.dealerCards, card)
            session:Broadcast("EV", "DHIT", card, HandValue(d.dealerCards))
            SendTable(session)
            C_Timer.After(DEALER_DELAY, Step)
        else
            Settle(session)
        end
    end
    C_Timer.After(DEALER_DELAY, Step)
end

function Settle(session)
    local d = session.data
    local dv = HandValue(d.dealerCards)
    local dealerBJ = IsBlackjack(d.dealerCards)
    for _, p in ipairs(Players(session)) do
        local seat = d.seats[p]
        if InHand(session, p) and #seat.cards > 0 then
            local pv = HandValue(seat.cards)
            local res
            if seat.state == "bust" then res = "L"
            elseif seat.state == "bj" then res = dealerBJ and "P" or "B"
            elseif dealerBJ then res = "L"
            elseif dv > 21 or pv > dv then res = "W"
            elseif pv < dv then res = "L"
            else res = "P" end
            local delta = (res == "W" and seat.bet) or (res == "B" and math.floor(seat.bet * 1.5))
                or (res == "L" and -seat.bet) or 0
            seat.res, seat.delta = res, delta
            seat.chips = seat.chips + delta
        end
    end
    d.phase = "results"
    session:Broadcast("EV", "SETTLE", dv)
    SendTable(session)
    -- Each settle gets a number, so only the latest one starts the next round.
    d.settles = (d.settles or 0) + 1
    local id = d.settles
    C_Timer.After(RESULTS_PAUSE, function()
        if session.status == "playing" and d.settles == id and d.phase == "results" then StartRound(session) end
    end)
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------
local view = {}
local seatFrames = {}
local Refresh

local RES_TEXT = { W = "|cff1f7a12WIN|r", B = "|cffd4af37BLACKJACK!|r", P = "|cff5a3412PUSH|r", L = "|cffa51d12LOSE|r" }
local STATE_TEXT = { stand = "Stands", bust = "|cffa51d12BUST!|r", bj = "|cffb8860bBlackjack!|r", dbl = "Doubled", out = "|cff7a6a55Out|r" }

local function MySeat(s)
    local v = s.data.view
    return v and v.byName[s:Me()]
end

local function DoBet(amount)
    local s = current
    if s then s:SendAction("BET", amount) end
end
local function DoHit() if current then current:SendAction("HIT") end end
local function DoStand() if current then current:SendAction("STAND") end end
local function DoDouble() if current then current:SendAction("DOUBLE") end end
local function DoDeal() if current then current:SendAction("DEAL") end end

-- A small hand of cards (face up, overlapping).
local function CardRow(parent, count, width)
    local row = { cards = {} }
    for i = 1, count do
        local c = UI.PlayingCard(parent, width)
        c:SetClickable(false)
        c:Hide()
        row.cards[i] = c
    end
    function row:Set(list, anchor, x, y, maxWidth)
        local n = #list
        local w = width
        local step = (n > 1) and math.min(w + 4, ((maxWidth or 200) - w) / (n - 1)) or 0
        for i, c in ipairs(self.cards) do
            local code = list[i]
            if code then
                if code == "??" then c:SetBack() else c:SetCard(code) end
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", anchor, "TOPLEFT", x + (i - 1) * step, y)
                c:SetFrameLevel(anchor:GetFrameLevel() + i + 2)
                c:Show()
            else
                c:Hide()
            end
        end
    end
    return row
end

local function Build()
    local area = UI:GetGameArea()

    -- The dealer, across the top.
    local dealer = UI.Card(area)
    dealer:SetPoint("TOPLEFT", 0, 0)
    dealer:SetPoint("RIGHT", area, "RIGHT", 0, 0)
    dealer:SetHeight(104)
    view.dealer = dealer
    view.dealerCrest = dealer:CreateTexture(nil, "ARTWORK")
    view.dealerCrest:SetSize(24, 24)
    view.dealerCrest:SetPoint("TOPLEFT", 14, -12)
    view.dealerName = UI.Text(dealer, "", { fancy = true, size = 16, ink = true })
    view.dealerName:SetPoint("LEFT", view.dealerCrest, "RIGHT", 6, 0)
    view.dealerTotal = UI.Text(dealer, "", { fancy = true, size = 22, ink = true })
    view.dealerTotal:SetPoint("TOPLEFT", 14, -44)
    view.round = UI.Text(dealer, "", { ink = true, font = "GameFontNormalSmall" })
    view.round:SetPoint("TOPLEFT", 14, -76)
    view.round:SetTextColor(0.48, 0.38, 0.25)
    view.dealerRow = CardRow(dealer, 10, 54)
    view.news = UI.Text(dealer, "", { ink = true, font = "GameFontHighlightSmall", justify = "RIGHT" })
    view.news:SetPoint("TOPRIGHT", -14, -12)
    view.news:SetWidth(230)
    view.news:SetJustifyV("TOP")
    view.news:SetSpacing(2)

    -- The players' seats.
    for i = 1, 7 do
        local f = CreateFrame("Frame", nil, area)
        f:SetSize(96, 146)
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
        f.crest:SetSize(16, 16)
        f.crest:SetPoint("TOPLEFT", 7, -7)
        f.name = UI.Text(f, "", { ink = true, font = "GameFontNormalSmall" })
        f.name:SetPoint("LEFT", f.crest, "RIGHT", 3, 0)
        f.name:SetWidth(66)
        f.name:SetJustifyH("LEFT")
        f.row = CardRow(f, 8, 34)
        f.total = UI.Text(f, "", { fancy = true, size = 18, ink = true, justify = "CENTER" })
        f.total:SetPoint("TOP", 0, -80)
        f.state = UI.Text(f, "", { fancy = true, size = 12, ink = true, justify = "CENTER" })
        f.state:SetPoint("TOP", f.total, "BOTTOM", 0, -1)
        f.coin = UI.CoinIcon(f, 16, "Interface\\Icons\\INV_Misc_Coin_02")
        f.coin:SetPoint("BOTTOMLEFT", 6, 6)
        f.chips = UI.Text(f, "", { ink = true, font = "GameFontNormalSmall" })
        f.chips:SetPoint("LEFT", f.coin, "RIGHT", 2, 0)
        f.bet = UI.Text(f, "", { ink = true, font = "GameFontNormalSmall", justify = "RIGHT" })
        f.bet:SetPoint("BOTTOMRIGHT", -7, 8)
        seatFrames[i] = f
    end

    -- Your controls, along the bottom.
    local bar = CreateFrame("Frame", nil, area)
    bar:SetPoint("BOTTOMLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", 0, 0)
    bar:SetHeight(44)
    view.bar = bar
    view.prompt = UI.Text(bar, "", { fancy = true, size = 16 })
    view.prompt:SetPoint("LEFT", 4, 0)
    view.betButtons = {}
    for i = 1, 4 do
        local b = UI.Button(bar, "", 74, 36, function(self) GG:Safe("Blackjack", DoBet, self.amount) end, "wood")
        b:SetPoint("RIGHT", bar, "RIGHT", -(4 - i) * 80 - 4, 0)
        view.betButtons[i] = b
    end
    view.hit = UI.Button(bar, "Hit", 110, 38, function() GG:Safe("Blackjack", DoHit) end, "primary")
    view.stand = UI.Button(bar, "Stand", 110, 38, function() GG:Safe("Blackjack", DoStand) end, "wood")
    view.double = UI.Button(bar, "Double", 110, 38, function() GG:Safe("Blackjack", DoDouble) end, "accent")
    view.double:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    view.stand:SetPoint("RIGHT", view.double, "LEFT", -8, 0)
    view.hit:SetPoint("RIGHT", view.stand, "LEFT", -8, 0)
    view.double.tooltip = "Double your bet and take exactly one more card."
    view.deal = UI.Button(bar, "Deal now!", 140, 38, function() GG:Safe("Blackjack", DoDeal) end, "primary")
    view.deal:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    view.deal.tooltip = "Deal the cards. Anyone who hasn't bet gets the smallest bet."
end

local function Name(p) return Util.IsMe(p) and "You" or Util.ShortName(p) end

local function LogLine(d, text)
    d.log[#d.log + 1] = text
    while #d.log > 4 do table.remove(d.log, 1) end
end

function Refresh()
    local s = current
    if not s or not view.dealer then return end
    local d = s.data
    local v = d.view
    if not v then return end
    local playing = s.status == "playing"
    local cur = GG.Turns:Current(s)
    local dealerName = Dealer(s)

    -- Dealer.
    GG.Theme:SetCrest(view.dealerCrest, s:GetFaction(dealerName))
    view.dealerName:SetText("Dealer: " .. Name(dealerName))
    view.dealerRow:Set(v.dealer, view.dealer, 150, -14, 300)
    if #v.dealer == 0 then
        view.dealerTotal:SetText("")
    elseif v.dealer[2] == "??" then
        view.dealerTotal:SetText("Shows " .. HandValue({ v.dealer[1] }))
    else
        local t = HandValue(v.dealer)
        view.dealerTotal:SetText(t > 21 and "|cffa51d12BUST!|r" or tostring(t))
    end
    view.round:SetText(("Round %d of %d"):format(math.max(v.round, 1), v.rounds))
    view.news:SetText(table.concat(d.log, "\n"))

    -- Seats, centred.
    local n = #v.seats
    local width = 96 + 4
    local total = n * width - 4
    local avail = view.dealer:GetWidth()
    if not avail or avail < 100 then avail = 704 end
    local x0 = (avail - total) / 2
    for i, f in ipairs(seatFrames) do
        local seat = v.seats[i]
        if seat then
            f:Show()
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", view.dealer, "BOTTOMLEFT", x0 + (i - 1) * width, -8)
            GG.Theme:SetCrest(f.crest, s:GetFaction(seat.name))
            f.name:SetText(Util.IsMe(seat.name) and "|cff1f7a12You|r" or Util.ShortName(seat.name))
            f.row:Set(seat.cards, f, 8, -28, 80)
            if #seat.cards > 0 then
                local t = HandValue(seat.cards)
                f.total:SetText(tostring(t))
            else
                f.total:SetText("")
            end
            local stateText
            if seat.res and seat.res ~= "" and v.phase == "results" then
                local sign = seat.delta > 0 and "+" or ""
                stateText = RES_TEXT[seat.res] .. (seat.delta ~= 0 and (" " .. sign .. seat.delta) or "")
            elseif v.phase == "bet" and seat.state ~= "out" then
                stateText = seat.bet > 0 and "|cff1f7a12Bet in!|r" or "|cff7a6a55Betting...|r"
            else
                stateText = STATE_TEXT[seat.state] or ""
            end
            f.state:SetText(stateText)
            f.chips:SetText(seat.chips)
            f.bet:SetText(seat.bet > 0 and ("Bet " .. seat.bet) or "")
            local active = playing and v.phase == "play" and cur == seat.name
            f.glow:SetShown(active)
            if active then f.glow.pulse:Play() end
            f:SetAlpha(seat.state == "out" and 0.5 or 1)
        else
            f:Hide()
        end
    end

    -- Controls.
    local mine = MySeat(s)
    for _, b in ipairs(view.betButtons) do b:Hide() end
    view.hit:Hide(); view.stand:Hide(); view.double:Hide(); view.deal:Hide()
    local prompt = ""
    if not playing then
        prompt = ""
    elseif s:IsHost() and Util.IsMe(dealerName) then
        -- The host is the dealer: mostly watching, but can hurry the deal.
        if v.phase == "bet" then
            prompt = "You're the dealer. Waiting for bets..."
            view.deal:Show()
        elseif v.phase == "play" then
            prompt = cur and ("Waiting on " .. Util.ShortName(cur) .. "...") or ""
        elseif v.phase == "dealer" then
            prompt = "Dealer's turn: drawing to 17."
        else
            prompt = "Next round coming up..."
        end
    elseif mine then
        if mine.state == "out" then
            prompt = "You're out of chips. Watch the rest!"
        elseif v.phase == "bet" then
            if mine.bet > 0 then
                prompt = "Bet placed: " .. mine.bet .. ". Change it?"
            else
                prompt = "Place your bet!"
            end
            for i, amount in ipairs(BetChoices(s)) do
                local b = view.betButtons[i]
                b.amount = amount
                b:SetText(tostring(amount))
                b:SetEnabled(mine.chips >= amount or (i == 1 and mine.chips > 0))
                b:Show()
            end
        elseif v.phase == "play" and cur == s:Me() then
            prompt = "Your total: " .. HandValue(mine.cards)
            view.hit:Show(); view.stand:Show(); view.double:Show()
            view.double:SetEnabled(CanDouble(mine))
        elseif v.phase == "play" then
            prompt = cur and ("Waiting on " .. Util.ShortName(cur) .. "...") or ""
        elseif v.phase == "dealer" then
            prompt = "Dealer's turn..."
        elseif v.phase == "results" and mine.res then
            prompt = (mine.res == "L" and "Lost " .. (-mine.delta)) or (mine.res == "P" and "Push: bet returned")
                or ("Won " .. mine.delta .. "!")
        end
    end
    view.prompt:SetText(UI.Gold(prompt))

    if playing and v.phase == "play" and cur == s:Me() then
        UI:SetGameStatus(UI.Gold("Your turn! Hit or Stand?"))
    elseif playing and v.phase == "bet" and mine and mine.state ~= "out" and mine.bet <= 0 then
        UI:SetGameStatus(UI.Gold("Place your bet!"))
    else
        UI:SetGameStatus(nil)
    end
end

-------------------------------------------------------------------------------
-- Module callbacks
-------------------------------------------------------------------------------
local function ParseTable(d, args)
    local v = { round = tonumber(args[1]) or 0, rounds = tonumber(args[2]) or 0, phase = args[3] or "bet",
        dealer = SplitCards(args[4]), seats = {}, byName = {} }
    for chunk in (args[5] or ""):gmatch("[^;]+") do
        local name, chips, bet, cards, state, res, delta = chunk:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)$")
        if name then
            local seat = { name = name, chips = tonumber(chips) or 0, bet = tonumber(bet) or 0,
                cards = SplitCards(cards), state = state, res = res ~= "" and res or nil, delta = tonumber(delta) or 0 }
            v.seats[#v.seats + 1] = seat
            v.byName[name] = seat
        end
    end
    d.view = v
end

function Game.IsPlaying(session, name)
    return name ~= Dealer(session)
end

function Game.OnSessionStart(session)
    current = session
    local d = session.data
    d.log, d.view = {}, nil
    if not view.dealer then Build() end
    view.dealer:Show(); view.bar:Show()

    if session:IsHost() then
        local start = tonumber(session.options and session.options.chips) or 100
        d.seats = {}
        for _, p in ipairs(Players(session)) do
            d.seats[p] = { chips = start, bet = 0, cards = {}, state = "" }
        end
        d.round, d.rounds = 0, tonumber(session.options and session.options.rounds) or 5
        d.phase, d.dealerCards, d.revealed = "bet", {}, false
        d.shoe = Cards.Shuffle(Cards.NewDeck(SHOE_DECKS))
        local order = { Dealer(session) }
        for _, p in ipairs(Players(session)) do order[#order + 1] = p end
        GG.Turns:Start(session, order)
        StartRound(session)
    end
    Refresh()
end

function Game.OnAction(session, sender, op, args)
    if op == "BET" then
        Bet(session, sender, args[1])
    elseif op == "HIT" then
        Hit(session, sender)
    elseif op == "STAND" then
        Stand(session, sender)
    elseif op == "DOUBLE" then
        Double(session, sender)
    elseif op == "DEAL" then
        if sender == Dealer(session) then Deal(session) end
    end
end

local function CardName(code) return Cards.IsValid(code) and Cards.Name(code) or "a card" end

function Game.OnState(session, op, args)
    local d = session.data
    if op == "TABLE" then
        ParseTable(d, args)
    elseif op == "EV" then
        local kind = args[1]
        if kind == "ROUND" then
            d.log = {}
            LogLine(d, ("|cff5a3412Round %s: place your bets!|r"):format(args[2] or "?"))
        elseif kind == "BET" then
            LogLine(d, ("%s bet %s."):format(Name(args[2]), args[3]))
        elseif kind == "BJ" then
            LogLine(d, ("|cffb8860b%s got Blackjack!|r"):format(Name(args[2])))
        elseif kind == "HIT" then
            LogLine(d, ("%s hit: %s (%s)"):format(Name(args[2]), CardName(args[3]), args[4]))
        elseif kind == "DOUBLE" then
            LogLine(d, ("%s doubled: %s (%s)"):format(Name(args[2]), CardName(args[3]), args[4]))
        elseif kind == "BUST" then
            LogLine(d, ("|cffa51d12%s bust!|r"):format(Name(args[2])))
            if Util.IsMe(args[2]) then GG.Theme:PlaySound("defeat") end
        elseif kind == "STAND" then
            LogLine(d, ("%s stood on %s."):format(Name(args[2]), args[3]))
        elseif kind == "REVEAL" then
            LogLine(d, ("Dealer turns over %s: %s"):format(CardName(args[2]), args[3]))
        elseif kind == "DHIT" then
            LogLine(d, ("Dealer draws %s: %s"):format(CardName(args[2]), args[3]))
        elseif kind == "SETTLE" then
            local dv = tonumber(args[2]) or 0
            LogLine(d, dv > 21 and "|cff1f7a12Dealer busts!|r" or ("Dealer stands on " .. dv .. "."))
        elseif kind == "SHUFFLE" then
            LogLine(d, "The dealer shuffles the shoe.")
        end
    end
    if session == current then Refresh() end
    if op == "TABLE" and session == current and d.view and d.view.phase == "results" then
        local mine = MySeat(session)
        if mine and (mine.res == "W" or mine.res == "B") and d.celebrated ~= d.view.round then
            d.celebrated = d.view.round
            GG.Theme:PlaySound("click")
            UI:CoinShower(view.bar)
        end
    end
end

function Game.OnSyncRequest(session, player)
    session:SendTo(player, "TABLE", Snapshot(session))
end

function Game.OnTurnTimeout(session, name)
    local d = session.data
    if name == Dealer(session) then
        if d.phase == "bet" then Deal(session) end
    elseif d.phase == "play" then
        Stand(session, name)
    end
end

function Game.OnPlayerLeft(session, name)
    if Util.IsMe(name) then return false end -- the host-dealer left: core ends it
    local d = session.data
    if d.seats[name] then d.seats[name].state = "out" end
    local anyone = false
    for _, p in ipairs(Players(session)) do if InHand(session, p) then anyone = true end end
    if not anyone then
        local left = {}
        for _, p in ipairs(Players(session)) do
            if session:IsActive(p) then left[#left + 1] = p end
        end
        if #left == 0 then
            session:End({ winners = {}, reason = "everyone left the table" })
        else
            EndGame(session)
        end
        return true
    end
    SendTable(session)
    if d.phase == "play" and GG.Turns:Current(session) == name then
        NextPlayer(session)
    elseif d.phase == "bet" and AllBet(session) then
        Deal(session)
    end
    return true
end

function Game.OnSessionEnd(session)
    if session == current then Refresh() end
end

function Game.OnSessionClosed(session)
    if session == current then
        current = nil
        if view.dealer then view.dealer:Hide(); view.bar:Hide() end
        for _, f in ipairs(seatFrames) do f:Hide() end
        UI:SetGameStatus(nil)
    end
end

GG.RegisterCallback(Game, "TURN_CHANGED", function(_, session)
    if session == current then Refresh() end
end)

-- Practice: the Training Dummy is the dealer, and the dealing is automatic,
-- so there's nothing for it to decide.
function Game.BotAction(session, bot)
end

Game._test = { HandValue = HandValue, IsBlackjack = IsBlackjack, Bet = Bet, Deal = Deal, Hit = Hit,
    Stand = Stand, Double = Double, Settle = Settle, StartRound = StartRound, Dealer = Dealer,
    DoBet = DoBet, DoHit = DoHit, DoStand = DoStand, view = view }

GG:RegisterGame(Game)
