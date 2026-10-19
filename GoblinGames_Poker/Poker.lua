--[[----------------------------------------------------------------------------
  GoblinGames_Poker/Poker.lua

  Texas Hold'em for 2-8 players, with chips. Built on the card engine.

  RULES (no-limit Texas Hold'em)
    - Everyone starts with the same stack of chips (lobby option).
    - Each hand, the two players after the dealer button post the small and
      big blinds (heads-up: the button is the small blind).
    - Everyone gets two face-down cards. Then four betting rounds:
        preflop -> flop (3 shared cards) -> turn (1 more) -> river (1 more).
      On your turn: Fold, Check (nothing to call), Call, Raise, or All-in.
      A raise must be at least the size of the last raise (or the big blind).
    - Last player who hasn't folded takes the pot. Otherwise, at the showdown
      the best five-card hand from your two cards plus the five shared ones
      wins. All-in players can only win what they matched (side pots).
    - Out of chips: you're out. The game ends when one player has all the
      chips, or after the hand limit (lobby option): then most chips wins.

  GOLD (optional, off unless the host turns on gold mode)
  The host can set a buy-in in gold. It's ledger-only: when the game ends,
  everyone who didn't win owes the winner(s) the buy-in, and players settle
  up themselves in the trade window. The addon never moves gold.

  HIDDEN INFORMATION
  Only the host shuffles. Each player is whispered only their own two cards
  ("HAND"). The board, bets and stacks are public ("TABLE" snapshots). At a
  showdown, the hands still in are revealed to everyone ("SHOW").
------------------------------------------------------------------------------]]

local GG = GoblinGames
local Util = GG.Util
local UI = GG.UI
local Cards = GG.Cards

local Game = {
    id = "poker",
    compactHeader = true,
    hint = "Check, call, raise or fold. Best five-card hand wins!",
    options = {
        { key = "chips", label = "Starting chips", default = 1000, values = {
            { value = 500, text = "500 (blinds 5/10)" }, { value = 1000, text = "1,000 (blinds 10/20)" },
            { value = 2000, text = "2,000 (blinds 10/20)" } } },
        { key = "hands", label = "Game length", default = 30, values = {
            { value = 0, text = "Until one player is left" }, { value = 15, text = "15 hands" },
            { value = 30, text = "30 hands" } } },
        { key = "stake", label = "Gold buy-in (ledger)", default = 0, gold = true, values = {
            { value = 0, text = "No buy-in" }, { value = 10, text = "10g" }, { value = 50, text = "50g" },
            { value = 100, text = "100g" }, { value = 500, text = "500g" }, { value = 1000, text = "1,000g" } } },
    },
}

local BETWEEN_HANDS = 6     -- seconds to look at the result
local RUNOUT_DELAY = 1.2    -- seconds between streets when everyone is all-in

local current

-------------------------------------------------------------------------------
-- Hand evaluation (every client: used for "You have: ..." and showdowns)
-------------------------------------------------------------------------------
local VALUE = { ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
    T = 10, J = 11, Q = 12, K = 13, A = 14 }
local RANK_OF = {}
for r, v in pairs(VALUE) do RANK_OF[v] = r end

local function StraightHigh(present)
    present[1] = present[14] -- the wheel: A-2-3-4-5
    for high = 14, 5, -1 do
        local ok = true
        for v = high, high - 4, -1 do
            if not present[v] then ok = false; break end
        end
        if ok then return high end
    end
    return nil
end

--- Score the best five-card hand among `cards` (5-7 cards). Returns a list
--- { category, tiebreakers... }; compare with Compare(). Categories:
--- 8 straight flush, 7 four of a kind, 6 full house, 5 flush, 4 straight,
--- 3 three of a kind, 2 two pair, 1 pair, 0 high card.
local function Evaluate(cards)
    local counts, bySuit, present = {}, {}, {}
    for _, c in ipairs(cards) do
        local v, s = VALUE[Cards.Rank(c)], Cards.Suit(c)
        counts[v] = (counts[v] or 0) + 1
        bySuit[s] = bySuit[s] or {}
        table.insert(bySuit[s], v)
        present[v] = true
    end
    -- Flush / straight flush.
    for _, list in pairs(bySuit) do
        if #list >= 5 then
            local p = {}
            for _, v in ipairs(list) do p[v] = true end
            local sf = StraightHigh(p)
            if sf then return { 8, sf } end
            table.sort(list, function(a, b) return a > b end)
            return { 5, list[1], list[2], list[3], list[4], list[5] }
        end
    end
    local quads, trips, pairs_, singles = {}, {}, {}, {}
    for v = 14, 2, -1 do
        local n = counts[v]
        if n == 4 then quads[#quads + 1] = v
        elseif n == 3 then trips[#trips + 1] = v
        elseif n == 2 then pairs_[#pairs_ + 1] = v
        elseif n == 1 then singles[#singles + 1] = v end
    end
    local function Kickers(exclude, n)
        local out = {}
        for v = 14, 2, -1 do
            if counts[v] and not exclude[v] then out[#out + 1] = v end
            if #out == n then break end
        end
        return out
    end
    if quads[1] then
        local k = Kickers({ [quads[1]] = true }, 1)
        return { 7, quads[1], k[1] or 0 }
    end
    if trips[1] and (trips[2] or pairs_[1]) then
        return { 6, trips[1], math.max(trips[2] or 0, pairs_[1] or 0) }
    end
    local st = StraightHigh(present)
    if st then return { 4, st } end
    if trips[1] then
        local k = Kickers({ [trips[1]] = true }, 2)
        return { 3, trips[1], k[1] or 0, k[2] or 0 }
    end
    if pairs_[2] then
        local k = Kickers({ [pairs_[1]] = true, [pairs_[2]] = true }, 1)
        return { 2, pairs_[1], pairs_[2], k[1] or 0 }
    end
    if pairs_[1] then
        local k = Kickers({ [pairs_[1]] = true }, 3)
        return { 1, pairs_[1], k[1] or 0, k[2] or 0, k[3] or 0 }
    end
    local k = Kickers({}, 5)
    return { 0, k[1] or 0, k[2] or 0, k[3] or 0, k[4] or 0, k[5] or 0 }
end

--- 1 if a beats b, -1 if b beats a, 0 for a tie.
local function Compare(a, b)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x > y then return 1 elseif x < y then return -1 end
    end
    return 0
end

local function Plural(v) return Cards.RankPlural(RANK_OF[v] or "?") end
local function Single(v) return Cards.RankName(RANK_OF[v] or "?") end

local function HandName(score)
    local c = score[1]
    if c == 8 then return score[2] == 14 and "Royal Flush!" or ("Straight Flush, " .. Single(score[2]) .. " high")
    elseif c == 7 then return "Four " .. Plural(score[2])
    elseif c == 6 then return "Full House, " .. Plural(score[2]) .. " over " .. Plural(score[3])
    elseif c == 5 then return "Flush, " .. Single(score[2]) .. " high"
    elseif c == 4 then return "Straight, " .. Single(score[2]) .. " high"
    elseif c == 3 then return "Three " .. Plural(score[2])
    elseif c == 2 then return "Two Pair, " .. Plural(score[2]) .. " and " .. Plural(score[3])
    elseif c == 1 then return "Pair of " .. Plural(score[2])
    else return Single(score[2]) .. " high" end
end

-------------------------------------------------------------------------------
-- Host: the dealer
--
-- Host-only: d.deck, d.hands[name] = {c1, c2}, d.runId (stale-timer guard)
-- d.seats[name] = { chips, bet (this street), contrib (this hand),
--                   state "" | "fold" | "allin" | "out", acted, last }
-- d.order = seating order; d.button; d.sb, d.bb (names this hand)
-------------------------------------------------------------------------------
local function Blinds(session)
    local start = tonumber(session.options and session.options.chips) or 1000
    if start <= 500 then return 5, 10 end
    return 10, 20
end

local function Snapshot(session)
    local d = session.data
    local seats = {}
    for _, p in ipairs(d.order) do
        local s = d.seats[p]
        seats[#seats + 1] = table.concat({ p, s.chips, s.bet, s.state, s.last or "" }, ",")
    end
    local pot = 0
    for _, p in ipairs(d.order) do pot = pot + d.seats[p].contrib end
    local _, bb = Blinds(session)
    local minTo = (d.currentBet > 0) and (d.currentBet + d.minRaise) or bb
    return d.handNo, d.maxHands, d.phase, table.concat(d.board), pot, d.currentBet, minTo,
        d.button or "", d.sb or "", d.bb or "", table.concat(seats, ";")
end

local function SendTable(session)
    session:Broadcast("TABLE", Snapshot(session))
end

-- The next seat after `from` (cyclic) that passes `test`.
local function NextSeat(d, from, test)
    local idx = Util.IndexOf(d.order, from) or 0
    for step = 1, #d.order do
        local p = d.order[(idx + step - 1) % #d.order + 1]
        if test(p) then return p end
    end
    return nil
end

local function InHand(d, p) local s = d.seats[p].state return s == "" or s == "allin" end
local function CanAct(d, p) return d.seats[p].state == "" end

local function CountInHand(d)
    local n = 0
    for _, p in ipairs(d.order) do if InHand(d, p) then n = n + 1 end end
    return n
end

local function CountCanAct(d)
    local n = 0
    for _, p in ipairs(d.order) do if CanAct(d, p) then n = n + 1 end end
    return n
end

local function Pay(d, p, amount)
    local s = d.seats[p]
    amount = math.min(amount, s.chips)
    s.chips = s.chips - amount
    s.bet = s.bet + amount
    s.contrib = s.contrib + amount
    if s.chips == 0 and s.state == "" then s.state = "allin" end
    return amount
end

local StartHand, NextStreet, Showdown, EndGame, AfterAction

function EndGame(session)
    local d = session.data
    local best, winners, everyone = -1, {}, {}
    for _, p in ipairs(d.order) do
        if session:IsActive(p) then
            everyone[#everyone + 1] = p
            local c = d.seats[p].chips
            if c > best then best, winners = c, { p } elseif c == best then winners[#winners + 1] = p end
        end
    end
    local tie = #winners > 1 and #winners == #everyone
    session:End({ winners = tie and {} or winners, draw = tie, reason = ("most chips: %d"):format(math.max(best, 0)) })
end

local function ScheduleNextHand(session)
    local d = session.data
    d.runId = (d.runId or 0) + 1
    local id = d.runId
    C_Timer.After(BETWEEN_HANDS, function()
        if session.status == "playing" and d.runId == id then StartHand(session) end
    end)
end

function StartHand(session)
    local d = session.data
    if session.status ~= "playing" then return end
    local alive = {}
    for _, p in ipairs(d.order) do
        local s = d.seats[p]
        s.bet, s.contrib, s.acted, s.last = 0, 0, false, nil
        if s.chips > 0 and session:IsActive(p) then s.state = ""; alive[#alive + 1] = p else s.state = "out" end
    end
    if #alive <= 1 or (d.maxHands > 0 and d.handNo >= d.maxHands) then
        SendTable(session)
        EndGame(session)
        return
    end
    d.handNo = d.handNo + 1
    d.phase = "preflop"
    d.board, d.hands = {}, {}
    d.deck = Cards.Shuffle(Cards.NewDeck())
    d.runId = (d.runId or 0) + 1

    local function Alive(p) return d.seats[p].state == "" end
    d.button = NextSeat(d, d.button or d.order[#d.order], Alive)
    if #alive == 2 then
        d.sb = d.button
        d.bb = NextSeat(d, d.sb, Alive)
    else
        d.sb = NextSeat(d, d.button, Alive)
        d.bb = NextSeat(d, d.sb, Alive)
    end
    local small, big = Blinds(session)
    Pay(d, d.sb, small); d.seats[d.sb].last = "SB"
    Pay(d, d.bb, big); d.seats[d.bb].last = "BB"
    d.currentBet = math.max(d.seats[d.sb].bet, d.seats[d.bb].bet)
    d.minRaise = big

    for _, p in ipairs(alive) do
        d.hands[p] = Cards.Draw(d.deck, 2)
        Cards.SendHand(session, p, d.hands[p])
    end
    session:Broadcast("EV", "HAND", d.handNo, d.button, d.sb, small, d.bb, big)
    SendTable(session)

    local first = NextSeat(d, d.bb, function(p) return CanAct(d, p) end)
    if not first or (CountCanAct(d) == 1 and d.seats[first].bet >= d.currentBet) then
        NextStreet(session)
    else
        GG.Turns:Advance(session, first)
    end
end

-- Move to the next street, or the showdown.
function NextStreet(session)
    local d = session.data
    for _, p in ipairs(d.order) do
        d.seats[p].bet, d.seats[p].acted = 0, false
        if d.seats[p].state == "" then d.seats[p].last = nil end
    end
    d.currentBet = 0
    local _, big = Blinds(session)
    d.minRaise = big

    if d.phase == "preflop" then
        d.phase = "flop"
        for _, c in ipairs(Cards.Draw(d.deck, 3)) do d.board[#d.board + 1] = c end
    elseif d.phase == "flop" then
        d.phase = "turn"
        d.board[#d.board + 1] = table.remove(d.deck)
    elseif d.phase == "turn" then
        d.phase = "river"
        d.board[#d.board + 1] = table.remove(d.deck)
    else
        Showdown(session)
        return
    end
    session:Broadcast("EV", "STREET", d.phase, table.concat(d.board))
    SendTable(session)

    if CountCanAct(d) >= 2 then
        local first = NextSeat(d, d.button, function(p) return CanAct(d, p) end)
        GG.Turns:Advance(session, first)
    else
        -- Everyone (or all but one) is all-in: deal the rest, slowly.
        local id = d.runId
        C_Timer.After(RUNOUT_DELAY, function()
            if session.status == "playing" and d.runId == id then NextStreet(session) end
        end)
    end
end

-- Give the pot(s) away. Side pots: each "layer" of contributions goes to the
-- best hand among the players who paid into that layer and didn't fold.
local function AwardPots(session, scores)
    local d = session.data
    local levels, seen = {}, {}
    for _, p in ipairs(d.order) do
        local c = d.seats[p].contrib
        if c > 0 and InHand(d, p) and not seen[c] then seen[c] = true; levels[#levels + 1] = c end
    end
    table.sort(levels)
    local prev, won = 0, {}
    for li, level in ipairs(levels) do
        local amount = 0
        for _, p in ipairs(d.order) do
            local c = d.seats[p].contrib
            -- The last layer also sweeps up anything folded players put in above it.
            local top = (li == #levels) and c or math.min(c, level)
            amount = amount + math.max(0, top - math.min(c, prev))
        end
        local best, winners = nil, {}
        for _, p in ipairs(d.order) do
            if InHand(d, p) and d.seats[p].contrib >= level then
                local sc = scores[p]
                local cmp = best and Compare(sc, best) or 1
                if cmp > 0 then best, winners = sc, { p } elseif cmp == 0 then winners[#winners + 1] = p end
            end
        end
        local share = math.floor(amount / #winners)
        local odd = amount - share * #winners
        for i, p in ipairs(winners) do
            local get = share + ((i == 1) and odd or 0)
            d.seats[p].chips = d.seats[p].chips + get
            won[p] = (won[p] or 0) + get
        end
        prev = level
    end
    return won
end

function Showdown(session)
    local d = session.data
    d.phase = "showdown"
    local scores = {}
    for _, p in ipairs(d.order) do
        if InHand(d, p) then
            local seven = { d.hands[p][1], d.hands[p][2] }
            for _, c in ipairs(d.board) do seven[#seven + 1] = c end
            scores[p] = Evaluate(seven)
            session:Broadcast("EV", "SHOW", p, table.concat(d.hands[p]), HandName(scores[p]))
        end
    end
    local won = AwardPots(session, scores)
    for _, p in ipairs(d.order) do d.seats[p].contrib = 0 end
    for _, p in ipairs(d.order) do
        if won[p] and won[p] > 0 then session:Broadcast("EV", "WIN", p, won[p], HandName(scores[p])) end
    end
    for _, p in ipairs(d.order) do d.seats[p].bet = 0 end
    SendTable(session)
    ScheduleNextHand(session)
end

local function WinUncontested(session)
    local d = session.data
    local winner
    for _, p in ipairs(d.order) do if InHand(d, p) then winner = p end end
    local pot = 0
    for _, p in ipairs(d.order) do pot = pot + d.seats[p].contrib; d.seats[p].bet = 0 end
    d.seats[winner].chips = d.seats[winner].chips + pot
    for _, p in ipairs(d.order) do d.seats[p].contrib = 0 end
    d.phase = "showdown"
    session:Broadcast("EV", "WIN", winner, pot, "")
    SendTable(session)
    ScheduleNextHand(session)
end

-- After someone acts (or folds by leaving): who's next?
function AfterAction(session, player)
    local d = session.data
    if CountInHand(d) == 1 then WinUncontested(session); return end
    local nxt = NextSeat(d, player, function(p)
        local s = d.seats[p]
        return s.state == "" and (not s.acted or s.bet < d.currentBet)
    end)
    -- One player left who can act, already matched: nothing to decide.
    if nxt and CountCanAct(d) == 1 and d.seats[nxt].bet >= d.currentBet then nxt = nil end
    if nxt then
        GG.Turns:Advance(session, nxt)
    else
        NextStreet(session)
    end
end

local function Act(session, player, action, amount)
    local d = session.data
    if session.status ~= "playing" or d.phase == "showdown" or GG.Turns:Current(session) ~= player then return false end
    local s = d.seats[player]
    if not s or s.state ~= "" then return false end
    local toCall = d.currentBet - s.bet
    local maxTo = s.bet + s.chips

    if action == "ALLIN" then
        if maxTo > d.currentBet then action, amount = "RAISE", maxTo else action = "CALL" end
    end

    if action == "FOLD" then
        s.state, s.last = "fold", "Fold"
        session:Broadcast("EV", "ACT", player, "FOLD", 0)
    elseif action == "CHECK" then
        if toCall > 0 then return false end
        s.last = "Check"
        session:Broadcast("EV", "ACT", player, "CHECK", 0)
    elseif action == "CALL" then
        if toCall <= 0 then
            s.last = "Check"
            session:Broadcast("EV", "ACT", player, "CHECK", 0)
        else
            local paid = Pay(d, player, toCall)
            s.last = s.state == "allin" and "All-in" or "Call"
            session:Broadcast("EV", "ACT", player, s.state == "allin" and "ALLIN" or "CALL", paid)
        end
    elseif action == "RAISE" then
        amount = math.floor(tonumber(amount) or 0)
        if amount > maxTo then amount = maxTo end
        if amount <= d.currentBet then return false end
        local allIn = amount == maxTo
        if amount < d.currentBet + d.minRaise and not allIn then return false end
        local raiseBy = amount - d.currentBet
        if raiseBy >= d.minRaise then d.minRaise = raiseBy end
        local opening = d.currentBet == 0
        d.currentBet = amount
        Pay(d, player, amount - s.bet)
        -- A raise means everyone else gets to act again.
        for _, p in ipairs(d.order) do if p ~= player then d.seats[p].acted = false end end
        s.last = s.state == "allin" and "All-in" or ((opening and "Bet " or "Raise ") .. amount)
        session:Broadcast("EV", "ACT", player, s.state == "allin" and "ALLIN" or (opening and "BET" or "RAISE"), amount)
    else
        return false
    end
    s.acted = true
    SendTable(session)
    AfterAction(session, player)
    return true
end

-- The practice dummy's (very readable) poker brain.
local function BotDecide(session, bot)
    local d = session.data
    local s = d.seats[bot]
    local hand = d.hands[bot]
    local toCall = d.currentBet - s.bet
    local strength -- 0 weak, 1 okay, 2 strong
    if #d.board == 0 then
        local a, b = VALUE[Cards.Rank(hand[1])], VALUE[Cards.Rank(hand[2])]
        if a == b and a >= 9 then strength = 2
        elseif a == b or (a >= 11 and b >= 11) or math.max(a, b) == 14 then strength = 1
        else strength = 0 end
    else
        local seven = { hand[1], hand[2] }
        for _, c in ipairs(d.board) do seven[#seven + 1] = c end
        local cat = Evaluate(seven)[1]
        strength = (cat >= 2 and 2) or (cat == 1 and 1) or 0
    end
    d.botRaised = d.botRaised or {}
    local key = d.handNo .. d.phase
    if strength == 2 and not d.botRaised[key] and math.random() < 0.8 then
        d.botRaised[key] = true
        local _, big = Blinds(session)
        return "RAISE", d.currentBet + math.max(d.minRaise, big * 2)
    end
    if toCall <= 0 then return "CHECK" end
    if strength >= 1 then return "CALL" end
    if toCall <= s.chips * 0.05 or math.random() < 0.15 then return "CALL" end
    return "FOLD"
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------
local view = {}
local seatFrames = {}
local Refresh

local function Me(s) local v = s.data.view return v and v.byName[s:Me()] end

local function SendAct(action, amount)
    local s = current
    if s and GG.Turns:IsMyTurn(s) then s:SendAction(action, amount or 0) end
end

local function SetRaise(to)
    local s = current
    local v = s and s.data.view
    local me = s and Me(s)
    if not v or not me then return end
    local maxTo = me.bet + me.chips
    to = math.floor(to)
    if to < v.minTo then to = v.minTo end
    if to > maxTo then to = maxTo end
    view.raiseTo = to
    Refresh()
end

local function Build()
    local area = UI:GetGameArea()

    -- Seats along the top (everyone but you).
    for i = 1, 7 do
        local f = CreateFrame("Frame", nil, area)
        f:SetSize(96, 90)
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
        f.name:SetWidth(58)
        f.name:SetJustifyH("LEFT")
        f.marker = UI.Text(f, "", { fancy = true, size = 12, justify = "RIGHT" })
        f.marker:SetPoint("TOPRIGHT", -6, -7)
        f.marker:SetTextColor(0.85, 0.6, 0.1)
        f.cards = {}
        for k = 1, 2 do
            local c = UI.PlayingCard(f, 28)
            c:SetClickable(false)
            c:SetPoint("TOPLEFT", 8 + (k - 1) * 22, -27)
            f.cards[k] = c
        end
        f.coin = UI.CoinIcon(f, 14, "Interface\\Icons\\INV_Misc_Coin_17")
        f.coin:SetPoint("BOTTOMLEFT", 6, 6)
        f.chips = UI.Text(f, "", { ink = true, font = "GameFontNormalSmall" })
        f.chips:SetPoint("LEFT", f.coin, "RIGHT", 2, 0)
        f.bet = UI.Text(f, "", { fancy = true, size = 13, justify = "CENTER" })
        f.bet:SetPoint("TOP", f, "BOTTOM", 0, -2)
        f.bet:SetTextColor(1, 0.85, 0.3)
        f.handName = UI.Text(f, "", { ink = true, font = "GameFontHighlightSmall", justify = "CENTER" })
        f.handName:SetPoint("BOTTOM", f, "BOTTOM", 0, 22)
        f.handName:SetWidth(88)
        seatFrames[i] = f
    end

    -- The table: board, pot, log.
    local t = UI.Card(area)
    t:SetPoint("TOPLEFT", 0, -110)
    t:SetPoint("RIGHT", area, "RIGHT", 0, 0)
    t:SetHeight(98)
    view.table = t
    view.handText = UI.Text(t, "", { ink = true, font = "GameFontNormalSmall" })
    view.handText:SetPoint("TOPLEFT", 14, -12)
    view.handText:SetTextColor(0.48, 0.38, 0.25)
    view.pot = UI.Text(t, "", { fancy = true, size = 22, ink = true })
    view.pot:SetPoint("TOPLEFT", 14, -30)
    view.street = UI.Text(t, "", { ink = true, font = "GameFontNormal" })
    view.street:SetPoint("TOPLEFT", 14, -60)
    view.board = {}
    for k = 1, 5 do
        local c = UI.PlayingCard(t, 50)
        c:SetClickable(false)
        c:SetPoint("TOPLEFT", 186 + (k - 1) * 54, -13)
        view.board[k] = c
    end
    view.log = UI.Text(t, "", { ink = true, font = "GameFontHighlightSmall", justify = "RIGHT" })
    view.log:SetPoint("TOPRIGHT", -14, -12)
    view.log:SetWidth(200)
    view.log:SetJustifyV("TOP")
    view.log:SetSpacing(2)

    -- You: your two cards, your stack, and the buttons.
    local me = CreateFrame("Frame", nil, area)
    me:SetPoint("TOPLEFT", 0, -216)
    me:SetPoint("BOTTOMRIGHT", 0, 0)
    view.me = me
    view.myCards = {}
    for k = 1, 2 do
        local c = UI.PlayingCard(me, 62)
        c:SetClickable(false)
        c:SetPoint("TOPLEFT", 4 + (k - 1) * 68, -8)
        view.myCards[k] = c
    end
    view.myGlow = me:CreateTexture(nil, "BACKGROUND")
    view.myGlow:SetTexture(UI.MEDIA .. "ButtonGlow")
    view.myGlow:SetPoint("TOPLEFT", -6, 0)
    view.myGlow:SetSize(150, 108)
    view.myGlow:SetBlendMode("ADD")
    view.myGlow:SetVertexColor(1, 0.75, 0.2)
    UI.AddPulse(view.myGlow, 0.3, 0.6)
    view.myInfo = UI.Text(me, "", { fancy = true, size = 15 })
    view.myInfo:SetPoint("TOPLEFT", 146, -10)
    view.myHand = UI.Text(me, "", { font = "GameFontHighlight" })
    view.myHand:SetPoint("TOPLEFT", 146, -32)
    view.myHand:SetTextColor(1, 0.92, 0.7)
    view.myHand:SetWidth(150)
    view.myHand:SetJustifyH("LEFT")

    -- Raise size row: [-] [Raise to 120] [+] [1/2 Pot] [Pot]
    local function Step(sign)
        local s = current
        local v = s and s.data.view
        if v then SetRaise((view.raiseTo or v.minTo) + sign * v.bb) end
    end
    view.minus = UI.Button(me, "-", 34, 30, function() GG:Safe("Poker", Step, -1) end, "wood")
    view.minus:SetPoint("TOPRIGHT", me, "TOPRIGHT", -264, -8)
    view.raiseLabel = UI.Text(me, "", { fancy = true, size = 15, justify = "CENTER" })
    view.raiseLabel:SetPoint("LEFT", view.minus, "RIGHT", 4, 0)
    view.raiseLabel:SetWidth(74)
    view.plus = UI.Button(me, "+", 34, 30, function() GG:Safe("Poker", Step, 1) end, "wood")
    view.plus:SetPoint("LEFT", view.raiseLabel, "RIGHT", 4, 0)
    view.halfPot = UI.Button(me, "1/2 Pot", 64, 30, function()
        local v = current and current.data.view
        if v then GG:Safe("Poker", SetRaise, v.currentBet + math.floor((v.pot + (v.currentBet - (Me(current).bet))) / 2)) end
    end, "wood")
    view.halfPot:SetPoint("LEFT", view.plus, "RIGHT", 6, 0)
    view.fullPot = UI.Button(me, "Pot", 56, 30, function()
        local v = current and current.data.view
        if v then GG:Safe("Poker", SetRaise, v.currentBet + v.pot + (v.currentBet - Me(current).bet)) end
    end, "wood")
    view.fullPot:SetPoint("LEFT", view.halfPot, "RIGHT", 6, 0)

    -- Action row: [Fold] [Check / Call 40] [Raise to 120] [All-in]
    view.fold = UI.Button(me, "Fold", 84, 38, function() GG:Safe("Poker", SendAct, "FOLD") end, "wood")
    view.call = UI.Button(me, "Check", 124, 38, function()
        local v = current and current.data.view
        local me_ = current and Me(current)
        if v and me_ then GG:Safe("Poker", SendAct, (v.currentBet > me_.bet) and "CALL" or "CHECK") end
    end, "primary")
    view.raise = UI.Button(me, "Raise", 130, 38, function() GG:Safe("Poker", SendAct, "RAISE", view.raiseTo) end, "accent")
    view.allin = UI.Button(me, "All-in", 84, 38, function() GG:Safe("Poker", SendAct, "ALLIN") end, "danger")
    view.allin:SetPoint("BOTTOMRIGHT", me, "BOTTOMRIGHT", -4, 8)
    view.raise:SetPoint("RIGHT", view.allin, "LEFT", -8, 0)
    view.call:SetPoint("RIGHT", view.raise, "LEFT", -8, 0)
    view.fold:SetPoint("RIGHT", view.call, "LEFT", -8, 0)

    view.stakeText = UI.Text(me, "", { font = "GameFontHighlightSmall" })
    view.stakeText:SetPoint("BOTTOMLEFT", 4, 8)
    view.stakeText:SetTextColor(1, 0.82, 0.4)
end

local function Name(p) return Util.IsMe(p) and "You" or Util.ShortName(p) end

local function LogLine(d, text)
    d.log[#d.log + 1] = text
    while #d.log > 5 do table.remove(d.log, 1) end
end

local STREET_NAME = { preflop = "Pre-flop", flop = "The Flop", turn = "The Turn", river = "The River", showdown = "Showdown" }

function Refresh()
    local s = current
    if not s or not view.table then return end
    local d = s.data
    local v = d.view
    if not v then return end
    local playing = s.status == "playing"
    local cur = GG.Turns:Current(s)
    local me = Me(s)

    -- Opponents.
    local others = {}
    local idx = Util.IndexOf(v.order, s:Me()) or 0
    for k = 1, #v.order do
        local p = v.order[(idx + k - 1) % #v.order + 1]
        if not Util.IsMe(p) then others[#others + 1] = p end
    end
    local n = #others
    local avail = view.table:GetWidth()
    if not avail or avail < 100 then avail = 704 end
    local x0 = (avail - (n * 100 - 4)) / 2
    for i, f in ipairs(seatFrames) do
        local p = others[i]
        local seat = p and v.byName[p]
        if seat then
            f:Show()
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", view.table, "TOPLEFT", x0 + (i - 1) * 100, 110)
            GG.Theme:SetCrest(f.crest, s:GetFaction(p))
            f.name:SetText(Util.ShortName(p))
            local marks = {}
            if v.button == p then marks[#marks + 1] = "D" end
            if v.sb == p then marks[#marks + 1] = "SB" end
            if v.bbPlayer == p then marks[#marks + 1] = "BB" end
            f.marker:SetText(table.concat(marks, " "))
            local shown = d.shown[p]
            for k, c in ipairs(f.cards) do
                if seat.state == "out" or seat.state == "fold" then
                    c:Hide()
                elseif shown then
                    c:SetCard(shown[k]); c:Show()
                else
                    c:SetBack(); c:Show()
                end
            end
            f.handName:SetText(shown and d.shownName[p] or "")
            f.chips:SetText(seat.chips)
            -- Under the seat: what they did last, and what they've put in.
            local word = seat.state == "out" and "Out" or ((seat.last or ""):match("^[%a%-]+") or "")
            f.bet:SetText(seat.bet > 0 and (word .. " " .. seat.bet) or word)
            local active = playing and cur == p and v.phase ~= "showdown"
            f.glow:SetShown(active)
            if active then f.glow.pulse:Play() end
            f:SetAlpha((seat.state == "fold" or seat.state == "out") and 0.55 or 1)
        else
            f:Hide()
        end
    end

    -- Table.
    view.handText:SetText(v.maxHands > 0 and ("Hand %d of %d   Blinds %d/%d"):format(v.handNo, v.maxHands, v.sbAmount, v.bb)
        or ("Hand %d   Blinds %d/%d"):format(v.handNo, v.sbAmount, v.bb))
    view.pot:SetText("Pot: " .. v.pot)
    view.street:SetText(STREET_NAME[v.phase] or "")
    for k, c in ipairs(view.board) do
        -- Cards still to come show face down.
        if v.board[k] then c:SetCard(v.board[k]); c:SetDim(false) else c:SetBack(); c:SetDim(true) end
        c:Show()
    end
    view.log:SetText(table.concat(d.log, "\n"))

    -- You.
    local myTurn = playing and cur == s:Me() and v.phase ~= "showdown"
    for k, c in ipairs(view.myCards) do
        if d.myCards[k] and me and me.state ~= "out" then c:SetCard(d.myCards[k]); c:Show() else c:Hide() end
        c:SetDim(me and me.state == "fold")
    end
    view.myGlow:SetShown(myTurn)
    if myTurn then view.myGlow.pulse:Play() end
    if me then
        local marks = {}
        if v.button == s:Me() then marks[#marks + 1] = "Dealer" end
        if v.sb == s:Me() then marks[#marks + 1] = "Small blind" end
        if v.bbPlayer == s:Me() then marks[#marks + 1] = "Big blind" end
        view.myInfo:SetText(UI.Gold("Chips: " .. me.chips) .. (me.bet > 0 and ("   Bet: " .. me.bet) or "")
            .. (#marks > 0 and ("\n|cffd9c79a" .. table.concat(marks, ", ") .. "|r") or ""))
        local text = ""
        if me.state == "fold" then text = "You folded."
        elseif me.state == "out" then text = "You're out of chips."
        elseif #d.myCards == 2 then
            if #v.board >= 3 then
                local seven = { d.myCards[1], d.myCards[2] }
                for _, c in ipairs(v.board) do seven[#seven + 1] = c end
                text = "You have: " .. HandName(Evaluate(seven))
            elseif Cards.Rank(d.myCards[1]) == Cards.Rank(d.myCards[2]) then
                text = "You have: Pocket " .. Cards.RankPlural(Cards.Rank(d.myCards[1]))
            end
        end
        view.myHand:SetText(text)
    end

    -- Buttons.
    local showButtons = myTurn and me and me.state == ""
    for _, b in ipairs({ view.fold, view.call, view.raise, view.allin, view.minus, view.plus, view.halfPot, view.fullPot }) do
        b:SetShown(showButtons and true or false)
    end
    view.raiseLabel:SetShown(showButtons and true or false)
    if showButtons then
        local toCall = v.currentBet - me.bet
        local maxTo = me.bet + me.chips
        if toCall > 0 then
            view.call:SetText(toCall >= me.chips and ("Call " .. me.chips) or ("Call " .. toCall))
        else
            view.call:SetText("Check")
        end
        if view.raiseFor ~= v.handNo .. v.phase .. v.currentBet then
            view.raiseFor = v.handNo .. v.phase .. v.currentBet
            view.raiseTo = math.min(v.minTo, maxTo)
        end
        local canRaise = maxTo > v.currentBet and maxTo > toCall + me.bet
        view.raiseTo = math.max(math.min(view.raiseTo or v.minTo, maxTo), math.min(v.minTo, maxTo))
        view.raise:SetEnabled(canRaise)
        view.raise:SetText((v.currentBet > 0 and "Raise to " or "Bet ") .. view.raiseTo)
        view.raiseLabel:SetText(UI.Gold(view.raiseTo))
        view.allin:SetText("All-in")
        UI:SetGameStatus(UI.Gold(toCall > 0 and ("Your turn! " .. toCall .. " to call.") or "Your turn! Check or bet."))
    else
        UI:SetGameStatus(nil)
    end

    local stake = GG.Lobby.Stake(s)
    view.stakeText:SetText(stake > 0 and ("Buy-in: " .. stake .. "g (ledger only: losers owe the winner)")
        or (s.isLocal and "Practice: just for fun" or "Playing for chips"))
end

-------------------------------------------------------------------------------
-- Module callbacks
-------------------------------------------------------------------------------
local function ParseTable(d, args)
    local v = { handNo = tonumber(args[1]) or 0, maxHands = tonumber(args[2]) or 0, phase = args[3] or "preflop",
        board = {}, pot = tonumber(args[5]) or 0, currentBet = tonumber(args[6]) or 0, minTo = tonumber(args[7]) or 0,
        button = args[8], sb = args[9], bb_ = args[10], order = {}, byName = {} }
    for c in (args[4] or ""):gmatch("..") do v.board[#v.board + 1] = c end
    for chunk in (args[11] or ""):gmatch("[^;]+") do
        local name, chips, bet, state, last = chunk:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)$")
        if name then
            local seat = { name = name, chips = tonumber(chips) or 0, bet = tonumber(bet) or 0, state = state,
                last = last ~= "" and last or nil }
            v.order[#v.order + 1] = name
            v.byName[name] = seat
        end
    end
    -- v.bb is the big blind AMOUNT (for the +/- buttons); v.bb_ the player.
    v.sbAmount, v.bb = d.blinds[1], d.blinds[2]
    v.bbPlayer = v.bb_
    d.view = v
end

function Game.OnSessionStart(session)
    current = session
    local d = session.data
    d.log, d.view, d.myCards, d.shown, d.shownName = {}, nil, {}, {}, {}
    d.blinds = { Blinds(session) }
    view.raiseTo, view.raiseFor = nil, nil
    if not view.table then Build() end
    view.table:Show(); view.me:Show()

    if session:IsHost() then
        local start = tonumber(session.options and session.options.chips) or 1000
        d.order = Util.Shuffle(Util.Copy(session.players))
        d.seats = {}
        for _, p in ipairs(d.order) do
            d.seats[p] = { chips = start, bet = 0, contrib = 0, state = "", acted = false }
        end
        d.handNo, d.maxHands = 0, tonumber(session.options and session.options.hands) or 0
        d.phase, d.board, d.currentBet, d.minRaise = "preflop", {}, 0, 0
        GG.Turns:Start(session, d.order)
        StartHand(session)
    end
    Refresh()
end

function Game.OnAction(session, sender, op, args)
    if op == "FOLD" or op == "CHECK" or op == "CALL" or op == "RAISE" or op == "ALLIN" then
        Act(session, sender, op, args[1])
    end
end

function Game.OnState(session, op, args)
    local d = session.data
    if op == "HAND" then
        d.myCards = Cards.Decode(args[1])
    elseif op == "TABLE" then
        ParseTable(d, args)
    elseif op == "EV" then
        local kind = args[1]
        if kind == "HAND" then
            d.log, d.shown, d.shownName = {}, {}, {}
            LogLine(d, ("|cff5a3412Hand %s.|r %s posts %s, %s posts %s."):format(args[2], Name(args[4]), args[5], Name(args[6]), args[7]))
        elseif kind == "ACT" then
            local who, what, amt = args[2], args[3], args[4]
            local text = ({ FOLD = "folds", CHECK = "checks", CALL = "calls " .. amt, BET = "bets " .. amt,
                RAISE = "raises to " .. amt, ALLIN = "is ALL-IN!" })[what] or what
            LogLine(d, Name(who) .. " " .. text)
        elseif kind == "STREET" then
            LogLine(d, "|cff5a3412" .. (STREET_NAME[args[2]] or args[2]) .. "|r")
        elseif kind == "SHOW" then
            local who, cards, name = args[2], args[3], args[4]
            local list = {}
            for c in (cards or ""):gmatch("..") do list[#list + 1] = c end
            d.shown[who], d.shownName[who] = list, name
        elseif kind == "WIN" then
            local who, amt, name = args[2], args[3], args[4]
            LogLine(d, ("|cff1f7a12%s %s %s|r%s"):format(Name(who), Util.IsMe(who) and "win" or "wins", amt,
                (name and name ~= "") and (" with " .. name) or ""))
            if Util.IsMe(who) and session == current then
                GG.Theme:PlaySound("click")
                UI:CoinShower(view.me)
            end
        end
    end
    if session == current then Refresh() end
end

function Game.OnSyncRequest(session, player)
    local d = session.data
    if d.hands and d.hands[player] then Cards.SendHand(session, player, d.hands[player]) end
    session:SendTo(player, "TABLE", Snapshot(session))
end

function Game.OnTurnTimeout(session, name)
    local d = session.data
    local s = d.seats[name]
    if not s or d.phase == "showdown" then return end
    Act(session, name, (d.currentBet - s.bet) > 0 and "FOLD" or "CHECK")
end

function Game.OnPlayerLeft(session, name)
    if Util.IsMe(name) then return false end -- the host is the dealer
    local d = session.data
    local s = d.seats[name]
    local wasTurn = GG.Turns:Current(session) == name
    if s then
        if s.state == "" or s.state == "allin" then s.state, s.last = "fold", "Left" end
    end
    local alive = 0
    for _, p in ipairs(d.order) do
        if session:IsActive(p) and (d.seats[p].chips > 0 or InHand(d, p)) then alive = alive + 1 end
    end
    if alive <= 1 then
        -- Award whatever's in the middle, then finish.
        if d.phase ~= "showdown" and CountInHand(d) == 1 then
            local winner
            for _, p in ipairs(d.order) do if InHand(d, p) then winner = p end end
            local pot = 0
            for _, p in ipairs(d.order) do pot = pot + d.seats[p].contrib; d.seats[p].contrib = 0 end
            d.seats[winner].chips = d.seats[winner].chips + pot
        end
        d.runId = (d.runId or 0) + 1
        SendTable(session)
        EndGame(session)
        return true
    end
    SendTable(session)
    if d.phase ~= "showdown" then
        if CountInHand(d) == 1 then
            WinUncontested(session)
        elseif wasTurn then
            AfterAction(session, name)
        end
    end
    return true
end

function Game.OnSessionEnd(session, result)
    -- Gold mode: everyone who didn't win owes the winner(s) the buy-in.
    local stake = GG.Lobby.Stake(session)
    if stake > 0 and not session.isLocal and result and #(result.winners or {}) > 0 then
        local share = math.floor(stake / #result.winners)
        for _, p in ipairs(session.players) do
            if not Util.IndexOf(result.winners, p) then
                for _, w in ipairs(result.winners) do GG.Ledger:Add("poker", p, w, share) end
            end
        end
    end
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
    local d = session.data
    if session.status ~= "playing" or GG.Turns:Current(session) ~= bot or d.phase == "showdown" then return end
    local action, amount = BotDecide(session, bot)
    if not Act(session, bot, action, amount) then
        Act(session, bot, (d.currentBet - d.seats[bot].bet) > 0 and "CALL" or "CHECK")
    end
end

Game._test = { Evaluate = Evaluate, Compare = Compare, HandName = HandName, Act = Act, StartHand = StartHand,
    AwardPots = AwardPots, Showdown = Showdown, SendAct = SendAct, SetRaise = SetRaise, view = view }

GG:RegisterGame(Game)
