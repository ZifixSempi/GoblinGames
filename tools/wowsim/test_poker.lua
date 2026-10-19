--[[ Simulated tests for Poker (Texas Hold'em).
       lua5.1 tools/wowsim/test_poker.lua        (SEED=n to vary randomness) ]]

package.path = "tools/wowsim/?.lua;" .. package.path
local Sim = require("sim")
Sim.verbose = os.getenv("VERBOSE") ~= nil

local ADDONS = { "GoblinGames", "GoblinGames_TicTacToe", "GoblinGames_Poker" }
local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1; print("  ok   " .. label)
    else failed = failed + 1; print("  FAIL " .. label) end
end
local function NoErrors(...)
    for _, c in ipairs({ ... }) do
        check(#c.errors == 0, c.name .. " had no Lua errors (" .. #c.errors .. ")")
        if #c.errors > 0 then print("       " .. tostring(c.errors[1])) end
        c.errors = {}
    end
end

math.randomseed(tonumber(os.getenv("SEED") or "6"))

local alice = Sim.NewClient({ name = "Alice", faction = "Horde", group = 1, addons = ADDONS, root = "." })
local bob = Sim.NewClient({ name = "Bob", faction = "Alliance", group = 1, addons = ADDONS, root = "." })
local eve = Sim.NewClient({ name = "Eve", faction = "Horde", group = 1, addons = ADDONS, root = "." })
for _, c in ipairs({ alice, bob, eve }) do Sim.Login(c, { "GoblinGames" }) end
Sim.Advance(1)
local A, B, E = alice.GG, bob.GG, eve.GG
for _, G in ipairs({ A, B, E }) do G.db.profile.turnTimer = 0 end
local AN, BN, EN = "Alice-TestRealm", "Bob-TestRealm", "Eve-TestRealm"
local byName = { [AN] = A, [BN] = B, [EN] = E }

local delivered = {}
Sim.dropFilter = function(from, to, text)
    delivered[#delivered + 1] = { to = to.name, text = text }
    return false
end

local function StartGame(guests, options)
    local s = A.Lobby:CreateHosted("poker")
    for k, v in pairs(options or {}) do A.Lobby:SetOption(s, k, v) end
    for _, g in ipairs(guests) do A.Lobby:Invite(s, g.name) end
    Sim.Advance(4)
    for _, g in ipairs(guests) do
        if g.GG.Lobby.invites[s.id] then g.GG.Lobby:AcceptInvite(s.id) end
    end
    Sim.Advance(1.5)
    if s.status == "lobby" then A.Lobby:Start(s); Sim.Advance(1) end
    return s
end

A:LoadGame("poker")
local T = A:GetGame("poker")._test

print("\n== Hand rankings")
do
    local Ev, Cmp, Nm = T.Evaluate, T.Compare, T.HandName
    local function H(str) local t = {} for c in str:gmatch("%S+") do t[#t + 1] = c end return Ev(t) end
    check(Nm(H("AS KS QS JS TS 2H 3D")) == "Royal Flush!", "royal flush")
    check(Nm(H("5S 4S 3S 2S AS KH KD")) == "Straight Flush, 5 high", "steel wheel (A-2-3-4-5 suited)")
    check(Nm(H("9C 9D 9H 9S 2C 3D 4H")) == "Four Nines", "four of a kind")
    check(Nm(H("KC KD KH 7S 7C 2D 3H")) == "Full House, Kings over Sevens", "full house")
    check(Nm(H("KC KD KH 7S 7C 7D 3H")) == "Full House, Kings over Sevens", "two sets of trips make a full house")
    check(H("2H 7H 9H JH KH AS AD")[1] == 5, "flush beats a pair")
    check(Nm(H("AC 2D 3H 4S 5C KD QH")) == "Straight, 5 high", "the wheel straight")
    check(Nm(H("6C 7D 8H 9S TC 2D 2H")) == "Straight, 10 high", "straight")
    check(Nm(H("QC QD QH 2S 5C 8D JH")) == "Three Queens", "three of a kind")
    check(Nm(H("JC JD 4H 4S AC 8D 2H")) == "Two Pair, Jacks and Fours", "two pair")
    check(Nm(H("TC TD 4H 6S AC 8D 2H")) == "Pair of Tens", "pair")
    check(Nm(H("AC TD 4H 6S 3C 8D 2H")) == "Ace high", "high card")
    check(Cmp(H("AS AD KC 7H 5D 3C 2S"), H("AH AC QD JH 9S 3D 2C")) == 1, "same pair: the King kicker wins")
    check(Cmp(H("AS AD KC 7H 5D 3C 2S"), H("AH AC KD 7C 5S 3H 2D")) == 0, "identical ranks: a split")
    check(Cmp(H("6C 7D 8H 9S TC 2D 2H"), H("AC 2D 3H 4S 5C KD QH")) == 1, "a 10-high straight beats the wheel")
    check(Cmp(H("JC JD 4H 4S AC 8D 2H"), H("JH JS 4C 4D KC 8S 2C")) == 1, "two pair: Ace kicker beats King kicker")
end

print("\n== Three players: the deal")
local s = StartGame({ bob, eve })
local d = s.data
local bs, es = B.Lobby.active, E.Lobby.active
do
    check(s.status == "playing" and #d.order == 3, "game started with three")
    check(d.handNo == 1 and d.phase == "preflop", "hand 1, pre-flop")
    check(d.sb ~= d.button and d.bb ~= d.sb and d.bb ~= d.button, "button, small blind and big blind are three different players")
    check(d.seats[d.sb].bet == 10 and d.seats[d.bb].bet == 20, "blinds 10/20 posted")
    check(d.seats[d.sb].chips == 990 and d.seats[d.bb].chips == 980, "and taken from their stacks")
    check(A.Turns:Current(s) == d.button, "three-handed, the button acts first pre-flop")
    local function same(a, b) return a[1] == b[1] and a[2] == b[2] end
    check(same(bs.data.myCards, d.hands[BN]) and same(es.data.myCards, d.hands[EN]), "each guest got their own two cards")
    check(bs.data.hands == nil and bs.data.deck == nil, "Bob's client has nobody else's cards and no deck")
    local leak = false
    for _, m in ipairs(delivered) do
        if m.text:find("HAND", 1, true) and m.text:find("%^P%^") then
            local owner = m.to .. "-TestRealm"
            for c in m.text:gmatch("[A2-9TJQK][SHDC]") do
                if c ~= d.hands[owner][1] and c ~= d.hands[owner][2] then leak = true end
            end
        end
    end
    check(not leak, "private card messages only carried the receiver's own cards")
    check(bs.data.view.pot == 30 and bs.data.view.currentBet == 20, "Bob sees a pot of 30 and 20 to match")
    NoErrors(alice, bob, eve)
end

local function Cur() return A.Turns:Current(s) end
local function Act(action, amount) return T.Act(s, Cur(), action, amount) end

print("\n== Betting")
do
    check(not T.Act(s, d.sb, "CALL"), "can't act out of turn")
    check(not Act("CHECK"), "can't check when there's a bet to call")
    check(not Act("RAISE", 30), "a raise must be at least the big blind more (to 40)")
    local raiser = Cur()
    check(Act("RAISE", 60), "button raises to 60")
    Sim.Advance(0.3)
    check(d.currentBet == 60 and d.seats[raiser].chips == 940, "60 is the bet to match")
    check(bs.data.view.currentBet == 60, "everyone sees the raise")
    check(Act("CALL"), "small blind calls")
    check(Act("CALL"), "big blind calls")
    Sim.Advance(0.3)
    check(d.phase == "flop" and #d.board == 3, "everyone matched: the flop is dealt")
    check(#bs.data.view.board == 3 and bs.data.view.pot == 180, "Bob sees the flop and a pot of 180")
    check(Cur() == d.sb, "after the flop, the first player after the button acts first")
    check(Act("CHECK") and Act("CHECK") and Act("CHECK"), "check, check, check")
    Sim.Advance(0.3)
    check(d.phase == "turn" and #d.board == 4, "the turn")
    -- Bet and two folds: uncontested.
    local bettor = Cur()
    local before = d.seats[bettor].chips
    check(Act("RAISE", 100), "a bet of 100")
    check(Act("FOLD") and Act("FOLD"), "two folds")
    Sim.Advance(0.5)
    check(d.phase == "showdown" and d.seats[bettor].chips == before + 180, "the bettor took the 180 pot without a showdown")
    Sim.Advance(5)
    check(bs.data.view.phase == "showdown", "everyone sees the hand is over (" .. tostring(bs.data.view.phase) .. " " .. tostring(bs.data.view.handNo) .. " host " .. d.phase .. ")")
    local total = 0
    for _, p in ipairs(d.order) do total = total + d.seats[p].chips end
    check(total == 3000, "no chips were lost or invented (" .. total .. ")")
    NoErrors(alice, bob, eve)
end

print("\n== Showdown and side pots")
do
    -- Rig: Alice all-in short (100), Bob and Eve deeper.
    d.runId = (d.runId or 0) + 1 -- stop the scheduled next hand
    local function Seat(chips, contrib, state) return { chips = chips, bet = 0, contrib = contrib, state = state or "", acted = true } end
    d.seats[AN] = Seat(0, 100, "allin")
    d.seats[BN] = Seat(500, 300)
    d.seats[EN] = Seat(500, 300)
    d.hands = { [AN] = { "AS", "AD" }, [BN] = { "KS", "KD" }, [EN] = { "2C", "7H" } }
    d.board = { "AH", "KH", "3C", "8S", "9D" }
    local scores = {}
    for p, h in pairs(d.hands) do
        local seven = { h[1], h[2] }
        for _, c in ipairs(d.board) do seven[#seven + 1] = c end
        scores[p] = T.Evaluate(seven)
    end
    local won = T.AwardPots(s, scores)
    check(won[AN] == 300, "Alice's three Aces win the main pot (100 from each = 300)")
    check(won[BN] == 400, "Bob's Kings win the side pot (the other 200 each = 400)")
    check(not won[EN], "Eve wins nothing")

    -- A folded player's chips still go in the pot.
    d.seats[AN] = Seat(0, 50, "fold")
    d.seats[BN] = Seat(0, 200)
    d.seats[EN] = Seat(0, 200)
    d.hands[EN] = { "AC", "KC" }
    scores[EN] = T.Evaluate({ "AC", "KC", "AH", "KH", "3C", "8S", "9D" })
    won = T.AwardPots(s, scores)
    check(won[BN] == 450 and not won[EN], "Bob's three Kings win everything, including the folded 50")

    -- A tie splits the pot.
    d.seats[AN] = Seat(0, 0, "fold")
    d.seats[BN] = Seat(0, 100)
    d.seats[EN] = Seat(0, 100)
    d.board = { "AH", "KH", "QC", "JS", "TD" }
    scores[BN] = T.Evaluate({ "2C", "3C", "AH", "KH", "QC", "JS", "TD" })
    scores[EN] = T.Evaluate({ "4C", "5C", "AH", "KH", "QC", "JS", "TD" })
    won = T.AwardPots(s, scores)
    check(won[BN] == 100 and won[EN] == 100, "both play the board's straight: split")
    NoErrors(alice, bob, eve)
end

print("\n== All-in, run-out and the reveal")
do
    A.Lobby:Close(s); B.Lobby:Close(bs); E.Lobby:Close(es)
    Sim.Advance(1)
    s = StartGame({ bob })
    d = s.data
    bs = B.Lobby.active
    check(#d.order == 2 and d.sb == d.button, "heads-up: the button is the small blind")
    check(Cur() == d.sb, "and acts first pre-flop")
    check(Act("ALLIN"), "small blind shoves all-in")
    check(Act("CALL"), "big blind calls")
    Sim.Advance(0.3)
    check(d.phase ~= "showdown" or #d.board == 5, "running out the board...")
    Sim.Advance(6)
    check(#d.board == 5, "all five shared cards came out")
    local sv = bs.data
    check(sv.shown[AN] and sv.shown[BN] and #sv.shown[AN] == 2, "at the showdown, both hands were revealed to everyone")
    check(sv.shownName[AN] ~= nil, "with the name of each hand")
    Sim.Advance(8)
    check(s.status == "ended" or d.handNo == 2, "either someone won everything, or the next hand started")
    if s.status ~= "ended" then
        local total = d.seats[AN].chips + d.seats[BN].chips + d.seats[AN].contrib + d.seats[BN].contrib
        check(total == 2000, "chips add up after a split (" .. total .. ")")
    else
        check(s.result.winners[1] ~= nil, "a winner")
    end
    NoErrors(alice, bob)
end

print("\n== Timeouts and leaving")
do
    A.Lobby:Close(s); B.Lobby:Close(B.Lobby.active)
    Sim.Advance(1)
    s = StartGame({ bob, eve })
    d = s.data
    local G = A:GetGame("poker")
    local first = Cur()
    G.OnTurnTimeout(s, first)
    Sim.Advance(0.3)
    check(d.seats[first].state == "fold", "out of time with a bet to call: fold")
    -- Get to the flop, then time out with nothing to call.
    while d.phase == "preflop" and s.status == "playing" do Act("CALL"); Sim.Advance(0.2) end
    local p = Cur()
    if d.phase == "flop" then
        G.OnTurnTimeout(s, p)
        Sim.Advance(0.3)
        check(d.seats[p].state == "" and d.seats[p].last == "Check", "out of time with nothing to call: check")
    else
        check(true, "(hand ended before the flop)")
    end
    -- Eve leaves mid-hand.
    E.Lobby:Leave()
    Sim.Advance(1)
    check(s.status == "playing", "Eve left; Alice and Bob play on")
    check(d.seats[EN].state == "fold" or d.seats[EN].state == "out", "Eve's hand is folded")
    NoErrors(alice, bob, eve)
end

print("\n== A whole game with a gold buy-in")
do
    A.Lobby:Close(s); B.Lobby:Close(B.Lobby.active)
    if E.Lobby.active then E.Lobby:Close(E.Lobby.active) end
    Sim.Advance(1)
    for _, G in ipairs({ A, B }) do G.db.profile.goldMode = true; G.db.global.ledger = {} end
    s = StartGame({ bob }, { stake = 50, hands = 15, chips = 500 })
    d = s.data
    check(s.options.stake == 50 and B.Lobby.active and B.Lobby.active.options.stake == 50, "the buy-in travelled with the invite")
    check(d.seats[AN].chips + d.seats[BN].chips + d.seats[AN].contrib + d.seats[BN].contrib == 1000, "500 chips each (blinds 5/10)")
    local guard, broken = 0, nil
    while s.status == "playing" and guard < 600 do
        guard = guard + 1
        local cur = Cur()
        if d.phase ~= "showdown" and cur then
            local r = math.random()
            local seat = d.seats[cur]
            if seat.state ~= "" then
                -- nothing to do
            elseif r < 0.1 then T.Act(s, cur, "FOLD")
            elseif r < 0.2 then T.Act(s, cur, "RAISE", d.currentBet + math.max(d.minRaise, 10) * 2)
            elseif r < 0.23 then T.Act(s, cur, "ALLIN")
            else T.Act(s, cur, "CALL") end
        end
        Sim.Advance(0.5)
        local total = 0
        for _, p in ipairs(d.order) do total = total + d.seats[p].chips + d.seats[p].contrib end
        if total ~= 1000 then broken = (broken or 0) + 1 end
    end
    check(not broken, "chips + pot always added up to 1,000")
    check(s.status == "ended", "the game finished (" .. guard .. " steps, " .. d.handNo .. " hands)")
    check(d.handNo <= 15, "no more than the 15-hand limit")
    Sim.Advance(30)
    local winners = s.result.winners or {}
    if #winners == 1 then
        local loser = winners[1] == AN and BN or AN
        local la, lb = A.db.global.ledger, B.db.global.ledger
        check(#la == 1 and #lb == 1, "both ledgers have one entry")
        check(la[1] and la[1].from == loser and la[1].to == winners[1] and la[1].gold == 50, "the loser owes the winner the 50g buy-in")
    else
        check(#A.db.global.ledger == 0, "a draw: nobody owes anything")
    end
    NoErrors(alice, bob)
    for _, G in ipairs({ A, B }) do G.db.profile.goldMode = false end
    A.Lobby:Close(s); B.Lobby:Close(B.Lobby.active)
    Sim.Advance(1)
end

print("\n== Practice against the Training Dummy")
do
    local sent = bob.sent
    local p = B.Lobby:StartPractice("poker")
    check(p and p.isLocal, "practice started")
    local BT = B:GetGame("poker")._test
    local pd = p.data
    check(pd.seats[BN] and #pd.order == 2, "you and the dummy")
    local guard = 0
    while p.status == "playing" and guard < 900 do
        guard = guard + 1
        local v = pd.view
        if v and B.Turns:IsMyTurn(p) and v.phase ~= "showdown" then
            local me = v.byName[BN]
            local r = math.random()
            if r < 0.15 then BT.SendAct("RAISE", v.minTo)
            elseif r < 0.2 then BT.SendAct("ALLIN")
            elseif v.currentBet > me.bet then BT.SendAct("CALL")
            else BT.SendAct("CHECK") end
        end
        Sim.Advance(1)
    end
    check(p.status == "ended", "practice game finished (" .. guard .. " steps, " .. pd.handNo .. " hands)")
    check(bob.sent == sent, "practice sends nothing over the network")
    NoErrors(bob)
end

Sim.dropFilter = nil
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
