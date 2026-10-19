--[[ Simulated tests for Blackjack.
       lua5.1 tools/wowsim/test_blackjack.lua        (SEED=n to vary randomness) ]]

package.path = "tools/wowsim/?.lua;" .. package.path
local Sim = require("sim")
Sim.verbose = os.getenv("VERBOSE") ~= nil

local ADDONS = { "GoblinGames", "GoblinGames_TicTacToe", "GoblinGames_Blackjack" }
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

math.randomseed(tonumber(os.getenv("SEED") or "4"))

local alice = Sim.NewClient({ name = "Alice", faction = "Horde", group = 1, addons = ADDONS, root = "." })
local bob = Sim.NewClient({ name = "Bob", faction = "Alliance", group = 1, addons = ADDONS, root = "." })
local eve = Sim.NewClient({ name = "Eve", faction = "Horde", group = 1, addons = ADDONS, root = "." })
for _, c in ipairs({ alice, bob, eve }) do Sim.Login(c, { "GoblinGames" }) end
Sim.Advance(1)
local A, B, E = alice.GG, bob.GG, eve.GG
for _, G in ipairs({ A, B, E }) do G.db.profile.turnTimer = 0 end
local AN, BN, EN = "Alice-TestRealm", "Bob-TestRealm", "Eve-TestRealm"

local delivered = {}
Sim.dropFilter = function(from, to, text)
    delivered[#delivered + 1] = { to = to.name, text = text }
    return false
end

local function StartGame(guests, options)
    local s = A.Lobby:CreateHosted("blackjack")
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

local T = nil

print("\n== Hand values")
do
    A:LoadGame("blackjack")
    T = A:GetGame("blackjack")._test
    local V = T.HandValue
    check(V({ "TS", "7H" }) == 17, "10 + 7 = 17")
    local v, soft = V({ "AS", "6H" })
    check(v == 17 and soft, "Ace + 6 = soft 17")
    check(V({ "AS", "6H", "TC" }) == 17, "Ace + 6 + 10: the Ace drops to 1 (17)")
    check(V({ "AS", "AH", "9C" }) == 21, "Ace + Ace + 9 = 21")
    check(V({ "KS", "QH", "2C" }) == 22, "K + Q + 2 = 22 (bust)")
    check(T.IsBlackjack({ "AS", "KH" }) and not T.IsBlackjack({ "7S", "7H", "7C" }), "Blackjack is 21 with two cards only")
end

print("\n== The deal: host is the dealer")
local s = StartGame({ bob, eve })
local d = s.data
local bs, es = B.Lobby.active, E.Lobby.active
do
    check(s.status == "playing", "game started")
    check(T.Dealer(s) == AN, "the host deals")
    check(d.seats[AN] == nil and d.seats[BN] and d.seats[EN], "the dealer has no seat; Bob and Eve do")
    check(d.phase == "bet" and d.round == 1 and A.Turns:Current(s) == AN, "round 1: bets, the dealer holds the turn")
    check(bs.data.view and bs.data.view.byName[BN].chips == 100, "Bob sees his 100 chips")
    check(not T.Bet(s, AN, 10), "the dealer can't bet")

    B:GetGame("blackjack")._test.DoBet(10)
    Sim.Advance(0.5)
    check(d.seats[BN].bet == 10 and d.phase == "bet", "Bob bet 10; still waiting on Eve")
    E:GetGame("blackjack")._test.DoBet(25)
    Sim.Advance(1.5)
    check(d.phase == "play", "everyone bet, so the cards were dealt")
    check(#d.seats[BN].cards == 2 and #d.seats[EN].cards == 2 and #d.dealerCards == 2, "two cards each, two for the dealer")
    local v = bs.data.view
    check(v.dealer[2] == "??" and v.dealer[1] == d.dealerCards[1], "Bob sees the dealer's up card, not the hole card")
    local leaked = false
    for _, m in ipairs(delivered) do
        if (m.to == "Bob" or m.to == "Eve") and m.text:find("TABLE", 1, true) and m.text:find(d.hole, 1, true)
            and not m.text:find(d.dealerCards[1] .. "??", 1, true) then
            -- The hole card's code could appear legitimately as a player's card; only flag a dealer field.
            local field = m.text:match("TABLE.-%^.-%^.-%^.-%^([^%^]*)")
            if field and field:find(d.hole, 1, true) then leaked = true end
        end
    end
    check(not leaked, "the hole card was never sent before the reveal")
    NoErrors(alice, bob, eve)
end

-- Rig a round: known hands for Bob and Eve, a known dealer hand and shoe.
local function Rig(bobCards, eveCards, dealerCards, shoe)
    d.phase = "play"
    d.seats[BN].cards, d.seats[BN].state, d.seats[BN].bet = bobCards, "", 10
    d.seats[EN].cards, d.seats[EN].state, d.seats[EN].bet = eveCards, "", 10
    d.seats[BN].chips, d.seats[EN].chips = 100, 100
    d.dealerCards, d.hole, d.revealed = dealerCards, dealerCards[2], false
    d.shoe = shoe
    s.turn.current = BN
end

print("\n== Hit, stand, bust and the dealer")
do
    -- shoe pops from the end: Bob gets the 5, then the dealer draws the K.
    Rig({ "TS", "6H" }, { "9C", "9D" }, { "7S", "9H" }, { "KC", "5D" })
    check(not T.Hit(s, EN, nil), "Eve can't hit on Bob's turn")
    check(T.Hit(s, BN), "Bob hits")
    Sim.Advance(0.3)
    check(#d.seats[BN].cards == 3 and T.HandValue(d.seats[BN].cards) == 21, "he drew the 5: 21")
    check(d.seats[BN].state == "stand" and A.Turns:Current(s) == EN, "21 stands automatically; Eve's turn")
    E:GetGame("blackjack")._test.DoStand()
    Sim.Advance(0.3)
    check(d.phase == "dealer" and d.revealed, "everyone's done: the dealer reveals")
    Sim.Advance(0.3)
    check(bs.data.view.dealer[2] == "9H", "now Bob sees the hole card")
    Sim.Advance(3)
    check(#d.dealerCards == 3 and T.HandValue(d.dealerCards) == 26, "dealer had 16, had to draw: the King busts them")
    check(d.phase == "results", "the round was settled")
    check(d.seats[BN].chips == 110 and d.seats[EN].chips == 110, "dealer bust: Bob and Eve each win 10")
    local bv = bs.data.view.byName[BN]
    check(bv.res == "W" and bv.delta == 10, "Bob's table shows WIN +10")
    NoErrors(alice, bob, eve)
end

print("\n== Payouts")
local function Play(bobCards, eveCards, dealerCards, shoe, bobBet)
    Rig(bobCards, eveCards, dealerCards, shoe or { "2C", "2D", "2H", "2S" })
    d.seats[BN].bet = bobBet or 10
    if T.IsBlackjack(bobCards) then d.seats[BN].state = "bj" end
    if T.IsBlackjack(eveCards) then d.seats[EN].state = "bj" end
    if d.seats[BN].state == "" then T.Stand(s, BN) else s.turn.current = EN end
    if d.seats[EN].state == "" then T.Stand(s, EN) end
    if d.phase == "play" then A:GetGame("blackjack")._test.Settle(s) end
    Sim.Advance(4)
end
do
    Play({ "AS", "KH" }, { "TC", "8D" }, { "TS", "9H" }, nil, 10)
    check(d.seats[BN].res == "B" and d.seats[BN].chips == 115, "Blackjack pays 3 to 2 (10 bet wins 15)")
    check(d.seats[EN].res == "L" and d.seats[EN].chips == 90, "18 against the dealer's 19 loses")

    Play({ "TS", "8H" }, { "AC", "QD" }, { "AD", "KS" })
    check(d.seats[BN].res == "L", "dealer Blackjack beats a plain 18")
    check(d.seats[EN].res == "P" and d.seats[EN].chips == 100, "Blackjack against dealer Blackjack: push")

    Play({ "TS", "8H" }, { "9C", "8D" }, { "TD", "8S" })
    check(d.seats[BN].res == "P" and d.seats[BN].chips == 100, "18 v 18: push")
    check(d.seats[EN].res == "L", "17 v 18: lose")
    NoErrors(alice, bob, eve)
end

print("\n== Double")
do
    Rig({ "5S", "6H" }, { "9C", "9D" }, { "TS", "7H" }, { "TC" })
    check(T.Double(s, BN), "Bob doubles on 11")
    Sim.Advance(0.3)
    check(d.seats[BN].bet == 20 and #d.seats[BN].cards == 3 and d.seats[BN].state == "dbl", "bet doubled, one card, done")
    check(A.Turns:Current(s) == EN, "Eve's turn")
    T.Stand(s, EN)
    Sim.Advance(4)
    check(d.seats[BN].res == "W" and d.seats[BN].chips == 120, "21 beats 17: a doubled bet wins 20")

    Rig({ "5S", "6H", "2C" }, { "9C", "9D" }, { "TS", "7H" }, {})
    check(not T.Double(s, BN), "can't double on three cards")
    d.seats[BN].cards = { "5S", "6H" }
    d.seats[BN].chips = 15
    check(not T.Double(s, BN), "can't double without the chips to cover it")
    NoErrors(alice, bob, eve)
end

print("\n== Timeouts, rounds and the end")
do
    A.Lobby:Close(s); B.Lobby:Close(bs); E.Lobby:Close(es)
    Sim.Advance(1)
    s = StartGame({ bob, eve }, { rounds = 3 })
    d = s.data
    bs, es = B.Lobby.active, E.Lobby.active
    check(d.rounds == 3, "a 3-round game")
    local G = A:GetGame("blackjack")
    -- The dealer's clock runs out during bets: deal anyway, smallest bets.
    G.OnTurnTimeout(s, AN)
    Sim.Advance(0.5)
    check(d.phase ~= "bet" and d.seats[BN].bet == 5 and d.seats[EN].bet == 5, "out of time: dealt with the smallest bet (5)")
    -- Players' clocks run out: they stand.
    local guard = 0
    while s.status == "playing" and guard < 200 do
        guard = guard + 1
        local cur = A.Turns:Current(s)
        if d.phase == "bet" then G.OnTurnTimeout(s, AN)
        elseif d.phase == "play" and cur ~= AN then G.OnTurnTimeout(s, cur) end
        Sim.Advance(1)
    end
    check(s.status == "ended", "three rounds later, the game is over (" .. guard .. " steps)")
    check(d.round == 3, "it ended after round 3")
    local b, e = d.seats[BN].chips, d.seats[EN].chips
    local r = s.result or {}
    check(r.outcome == nil, "the dealer records no win or loss")
    Sim.Advance(30)
    local br = (B.Lobby.active and B.Lobby.active.result) or {}
    if b > e then check(br.outcome == "win", "Bob had more chips and won")
    elseif e > b then check(br.outcome == "loss", "Eve had more chips: Bob lost")
    else check(br.outcome == "draw", "equal chips: a draw") end
    NoErrors(alice, bob, eve)
    A.Lobby:Close(s); B.Lobby:Close(B.Lobby.active); E.Lobby:Close(E.Lobby.active)
    Sim.Advance(1)
end

print("\n== Leaving and going broke")
do
    s = StartGame({ bob, eve })
    d = s.data
    bs = B.Lobby.active
    d.seats[BN].chips = 5
    B:GetGame("blackjack")._test.DoBet(5)
    Sim.Advance(0.5)
    E.Lobby:Leave()
    Sim.Advance(2)
    check(s.status == "playing" and d.seats[EN].state == "out", "Eve left; Bob plays on")
    check(d.phase == "play", "Eve leaving completed the bets, so the cards were dealt")
    -- Make Bob lose everything.
    Rig({ "TS", "6H" }, { "2C", "3C" }, { "TD", "9S" }, { "KC" })
    d.seats[EN].state = "out"
    d.seats[BN].chips, d.seats[BN].bet = 5, 5
    T.Hit(s, BN) -- 26: bust
    Sim.Advance(8)
    check(d.seats[BN].chips == 0, "Bob busted his last 5 chips")
    check(s.status == "ended", "nobody has chips left: the game ends")
    NoErrors(alice, bob, eve)
    A.Lobby:Close(s); if B.Lobby.active then B.Lobby:Close(B.Lobby.active) end
    if E.Lobby.active then E.Lobby:Close(E.Lobby.active) end
    Sim.Advance(1)
end

print("\n== Practice: the Training Dummy deals")
do
    local sent = bob.sent
    local p = B.Lobby:StartPractice("blackjack")
    check(p and p.isLocal, "practice started")
    local BT = B:GetGame("blackjack")._test
    local pd = p.data
    check(BT.Dealer(p) ~= BN and pd.seats[BN] and pd.seats[BT.Dealer(p)] == nil, "the dummy deals, you play")
    local guard = 0
    while p.status == "playing" and guard < 300 do
        guard = guard + 1
        local v = pd.view
        if v and v.phase == "bet" and v.byName[BN].bet == 0 then
            BT.DoBet(10)
        elseif v and v.phase == "play" and B.Turns:IsMyTurn(p) then
            if BT.HandValue(v.byName[BN].cards) < 17 then BT.DoHit() else BT.DoStand() end
        end
        Sim.Advance(1)
    end
    check(p.status == "ended", "five practice rounds played (" .. guard .. " steps)")
    check(bob.sent == sent, "practice sends nothing over the network")
    check(p.result and p.result.outcome == "win", "alone at the table, you 'win' by finishing")
    NoErrors(bob)
end

Sim.dropFilter = nil
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
