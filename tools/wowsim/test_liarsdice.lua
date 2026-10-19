--[[ Simulated tests for Liar's Dice.
       lua5.1 tools/wowsim/test_liarsdice.lua        (SEED=n to vary randomness) ]]

package.path = "tools/wowsim/?.lua;" .. package.path
local Sim = require("sim")
Sim.verbose = os.getenv("VERBOSE") ~= nil

local ADDONS = { "GoblinGames", "GoblinGames_TicTacToe", "GoblinGames_LiarsDice" }
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

math.randomseed(tonumber(os.getenv("SEED") or "9"))

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
    local s = A.Lobby:CreateHosted("liarsdice")
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

local s = StartGame({ bob, eve })
local d = s.data
local T = A:GetGame("liarsdice")._test
local bs, es = B.Lobby.active, E.Lobby.active

print("\n== Bidding rules")
do
    check(T.BidOK(s, 15, nil, nil, 1, 2), "any opening bid is fine")
    check(not T.BidOK(s, 15, nil, nil, 3, 1), "no bids on ones while ones are wild")
    check(T.BidOK(s, 15, 3, 4, 3, 5), "same number, higher face: ok")
    check(T.BidOK(s, 15, 3, 4, 4, 2), "more dice, any face: ok")
    check(not T.BidOK(s, 15, 3, 4, 3, 4), "the same bid again: no")
    check(not T.BidOK(s, 15, 3, 4, 2, 6), "fewer dice: no")
    check(not T.BidOK(s, 15, 14, 6, 16, 2), "more dice than on the table: no")
    local q, f = T.MinBid(s, 15, 3, 6)
    check(q == 4 and f == 2, "after three 6s, the smallest bid is four 2s")
    check(T.Count(s, { 1, 1, 4, 5, 4 }, 4) == 4, "ones count as wild (two 4s + two 1s = 4)")
end

print("\n== The roll is secret")
do
    check(s.status == "playing" and d.round == 1, "round 1")
    check(d.counts[AN] == 5 and d.counts[BN] == 5 and d.counts[EN] == 5, "5 dice each")
    local function same(a, b)
        if #a ~= #b then return false end
        for i = 1, #a do if a[i] ~= b[i] then return false end end
        return true
    end
    check(same(bs.data.myDice, d.dice[BN]) and same(es.data.myDice, d.dice[EN]), "each guest got exactly their own dice")
    check(bs.data.dice == nil, "Bob's client has nobody else's dice")
    local diceMsgs = 0
    for _, m in ipairs(delivered) do
        if m.text:find("DICE", 1, true) then
            diceMsgs = diceMsgs + 1
            check(m.text:find("%^P%^") ~= nil, "dice travel only as private whispers (to " .. m.to .. ")")
        end
    end
    check(diceMsgs == 2, "one dice message per guest")
    check(bs.data.counts[EN] == 5 and #bs.data.order == 3, "Bob sees how many dice everyone has")
    NoErrors(alice, bob, eve)
end

local function Cur() return A.Turns:Current(s) end
local function Rig(dice)
    d.dice = { [AN] = dice[1], [BN] = dice[2], [EN] = dice[3] }
    d.counts = { [AN] = #dice[1], [BN] = #dice[2], [EN] = #dice[3] }
    d.bid, d.phase = nil, "bid"
    d.order = { AN, BN, EN }
    d.runId = (d.runId or 0) + 1
    s.turn.current = AN
end

print("\n== Bids and LIAR!")
do
    Rig({ { 1, 3, 3, 5, 6 }, { 3, 4, 4, 2, 6 }, { 1, 1, 2, 5, 6 } })
    check(not T.CallLiar(s, AN), "nothing to call before the first bid")
    check(T.Bid(s, AN, 3, 3), "Alice bids three 3s")
    Sim.Advance(0.5)
    check(Cur() == BN, "Bob's turn")
    check(bs.data.bid and bs.data.bid.q == 3 and bs.data.bid.f == 3 and bs.data.bid.by == AN, "Bob sees the bid")
    check(not T.Bid(s, BN, 2, 6), "Bob can't go lower")
    -- Bob bids from his own window.
    local BT = B:GetGame("liarsdice")._test
    BT.PickFace(4)
    check(BT.view.q == 3 and BT.view.f == 4, "picking 4s sets the picker to three 4s (the smallest legal bid)")
    BT.StepQty(2)
    BT.SendBid()
    Sim.Advance(0.5)
    check(d.bid.q == 5 and d.bid.f == 4 and Cur() == EN, "Bob bid five 4s")
    -- Eve calls. There are: Alice 1 (wild) ; Bob 4,4 ; Eve 1,1 (wild) = 5 fours. True!
    check(T.CallLiar(s, EN), "Eve calls LIAR!")
    Sim.Advance(0.5)
    check(d.counts[EN] == 4 and d.counts[BN] == 5, "there were exactly five (ones wild): Eve, the caller, loses a die")
    check(bs.data.revealed[AN] and #bs.data.revealed[AN] == 5, "everyone's dice were shown to everyone")
    check(d.phase == "reveal", "a pause to look at the dice")
    Sim.Advance(7)
    check(d.round >= 2 and d.phase == "bid" and Cur() == EN, "next round: the loser (Eve) starts")
    check(#es.data.myDice == 4, "Eve now has 4 dice")
    NoErrors(alice, bob, eve)

    Rig({ { 2, 2, 3 }, { 5, 5 }, { 6 } })
    T.Bid(s, AN, 4, 5)
    T.CallLiar(s, BN)
    Sim.Advance(0.5)
    check(d.counts[AN] == 2, "only two 5s: the bidder lied and loses a die")
    NoErrors(alice, bob, eve)
end

print("\n== Out of dice, and winning")
do
    Rig({ { 2 }, { 5 }, { 6 } })
    T.Bid(s, AN, 2, 6)
    T.CallLiar(s, BN)
    Sim.Advance(0.5)
    check(d.counts[AN] == 0, "Alice lied with her last die: she's out")
    Sim.Advance(7)
    check(s.status == "playing" and Cur() ~= AN, "the game goes on without her")
    Rig({ {}, { 5 }, { 6 } })
    d.counts[AN] = 0
    s.turn.current = BN
    T.Bid(s, BN, 1, 5)
    T.CallLiar(s, EN)
    Sim.Advance(0.5)
    check(d.counts[EN] == 0, "a true bid: Eve called and lost her last die")
    Sim.Advance(7)
    check(s.status == "ended" and s.result.winners[1] == BN, "Bob is the last goblin with dice")
    Sim.Advance(5)
    check(bs.result and bs.result.outcome == "win", "Bob won")
    NoErrors(alice, bob, eve)
end

print("\n== Options, timeouts and leaving")
do
    A.Lobby:Close(s); B.Lobby:Close(bs); E.Lobby:Close(es)
    Sim.Advance(1)
    s = StartGame({ bob, eve }, { dice = 3, wild = 0 })
    d = s.data
    bs, es = B.Lobby.active, E.Lobby.active
    check(d.counts[AN] == 3 and #bs.data.myDice == 3, "a quick game: 3 dice each")
    check(T.BidOK(s, 9, nil, nil, 2, 1), "ones aren't wild: you can bid on them")
    check(T.Count(s, { 1, 1, 4 }, 4) == 1, "and they only count as ones")
    local G = A:GetGame("liarsdice")
    local first = Cur()
    G.OnTurnTimeout(s, first)
    Sim.Advance(0.5)
    check(d.bid and d.bid.q == 1 and d.bid.f == 1 and d.bid.by == first, "out of time: the smallest bid (one 1) was made for you")
    local round = d.round
    E.Lobby:Leave()
    Sim.Advance(1)
    check(s.status == "playing" and d.counts[EN] == 0, "Eve left; her dice are gone")
    check(d.round == round and d.bid == nil and #d.dice[AN] == 3, "the round was rolled again")
    NoErrors(alice, bob, eve)
end

print("\n== Whole games with the auto-player")
do
    A.Lobby:Close(s); B.Lobby:Close(B.Lobby.active)
    if E.Lobby.active then E.Lobby:Close(E.Lobby.active) end
    Sim.Advance(1)
    s = StartGame({ bob, eve })
    d = s.data
    local guard = 0
    while s.status == "playing" and guard < 400 do
        guard = guard + 1
        if d.phase == "bid" then T.AutoTurn(s, Cur(), true) end
        Sim.Advance(1)
    end
    check(s.status == "ended", "the game finished (" .. guard .. " steps, " .. d.round .. " rounds)")
    local alive = 0
    for _, c in pairs(d.counts) do if c > 0 then alive = alive + 1 end end
    check(alive == 1, "exactly one player has dice left")
    NoErrors(alice, bob, eve)
    A.Lobby:Close(s); B.Lobby:Close(B.Lobby.active); E.Lobby:Close(E.Lobby.active)
    Sim.Advance(1)
end

print("\n== Practice against the Training Dummy")
do
    local sent = bob.sent
    local p = B.Lobby:StartPractice("liarsdice")
    check(p and p.isLocal, "practice started")
    local BT = B:GetGame("liarsdice")._test
    local pd = p.data
    local guard = 0
    while p.status == "playing" and guard < 600 do
        guard = guard + 1
        if B.Turns:IsMyTurn(p) and pd.phase == "bid" then
            if pd.bid and math.random() < 0.35 then BT.SendLiar()
            else
                BT.PickFace(math.random(2, 6))
                BT.SendBid()
            end
        end
        Sim.Advance(1)
    end
    check(p.status == "ended", "practice game finished (" .. guard .. " steps, " .. pd.round .. " rounds)")
    check(bob.sent == sent, "practice sends nothing over the network")
    NoErrors(bob)
end

Sim.dropFilter = nil
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
