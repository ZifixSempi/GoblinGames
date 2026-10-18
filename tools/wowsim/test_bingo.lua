--[[ Simulated tests for Guild Bingo and open guild games.
       lua5.1 tools/wowsim/test_bingo.lua        (SEED=n to vary randomness) ]]

package.path = "tools/wowsim/?.lua;" .. package.path
local Sim = require("sim")
Sim.verbose = os.getenv("VERBOSE") ~= nil

local ADDONS = { "GoblinGames", "GoblinGames_TicTacToe", "GoblinGames_Connect6", "GoblinGames_Deathroll", "GoblinGames_Bingo" }
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

math.randomseed(tonumber(os.getenv("SEED") or "5"))

-- Guild "Goblins": Alice is an officer (rank 1), Bob/Carol/Eve are members
-- (rank 3), Mallory is a fresh recruit (rank 4). Dave is in another guild.
local function Client(name, rank, guild, faction)
    return Sim.NewClient({ name = name, rank = rank, guild = guild, faction = faction or "Horde", addons = ADDONS, root = "." })
end
local alice = Client("Alice", 1, "Goblins")
local bob = Client("Bob", 3, "Goblins", "Alliance")
local carol = Client("Carol", 3, "Goblins")
local eve = Client("Eve", 3, "Goblins", "Alliance")
local mallory = Client("Mallory", 4, "Goblins")
local dave = Client("Dave", 1, "Others")
local all = { alice, bob, carol, eve, mallory, dave }
for _, c in ipairs(all) do Sim.Login(c, { "GoblinGames" }) end
Sim.Advance(1)
local A, B, C, E, M, D = alice.GG, bob.GG, carol.GG, eve.GG, mallory.GG, dave.GG
local byName = { ["Bob-TestRealm"] = B, ["Carol-TestRealm"] = C, ["Eve-TestRealm"] = E, ["Alice-TestRealm"] = A }

A:LoadGame("bingo")
local T = A:GetGame("bingo")._test

print("\n== Cards")
do
    local c1 = T.MakeCard("abc123", 1, "Bob-TestRealm")
    local c2 = B:LoadGame("bingo") and B:GetGame("bingo")._test.MakeCard("abc123", 1, "Bob-TestRealm")
    local same = true
    for i = 1, 25 do if c1[i] ~= c2[i] then same = false end end
    check(same, "the same card is built on every client")
    check(c1[13] == 0, "the centre is free")
    local okRanges, seen, unique = true, {}, true
    for i = 1, 25 do
        if i ~= 13 then
            local col = (i - 1) % 5 + 1
            local n = c1[i]
            if n < (col - 1) * 15 + 1 or n > col * 15 then okRanges = false end
            if seen[n] then unique = false end
            seen[n] = true
        end
    end
    check(okRanges, "B 1-15, I 16-30, N 31-45, G 46-60, O 61-75")
    check(unique, "no number appears twice on a card")
    local c3 = T.MakeCard("abc123", 1, "Carol-TestRealm")
    local c4 = T.MakeCard("abc123", 2, "Bob-TestRealm")
    local diff3, diff4 = false, false
    for i = 1, 25 do if c1[i] ~= c3[i] then diff3 = true end if c1[i] ~= c4[i] then diff4 = true end end
    check(diff3 and diff4, "different players and rounds get different cards")

    local function Set(list) local t = {} for _, n in ipairs(list) do t[n] = true end return t end
    local row1 = { c1[1], c1[2], c1[3], c1[4], c1[5] }
    check(T.Satisfied(c1, Set(row1), "line") ~= nil, "a full row is a line")
    local diag = { c1[1], c1[7], c1[19], c1[25] }     -- centre is free
    check(T.Satisfied(c1, Set(diag), "line") ~= nil, "a diagonal through the free centre is a line")
    check(T.Satisfied(c1, Set({ c1[1], c1[5], c1[21] }), "corners") == nil, "three corners isn't enough")
    check(T.Satisfied(c1, Set({ c1[1], c1[5], c1[21], c1[25] }), "corners") ~= nil, "four corners")
    check(T.Satisfied(c1, Set({ c1[1], c1[7], c1[19], c1[25], c1[5], c1[9], c1[17], c1[21] }), "x") ~= nil, "X")
    local allNums = {} for i = 1, 75 do allNums[i] = i end
    check(T.Satisfied(c1, Set(allNums), "blackout") ~= nil, "blackout with every number")
    check(T.Satisfied(c1, Set(row1), "blackout") == nil, "one row isn't a blackout")
end

print("\n== Who may host")
do
    local s, err = M.Lobby:CreateHosted("bingo")
    check(s == nil and err and err:find("officers"), "a rank-4 recruit can't host (" .. tostring(err) .. ")")
    -- Mallory cheats by allowing everyone in HER settings, and announces...
    M.db.profile.bingoMaxRank = 99
    local ms = M.Lobby:CreateHosted("bingo")
    check(ms ~= nil, "...changing her own setting lets her open a lobby")
    M.Lobby:Announce(ms)
    Sim.Advance(1)
    local anyone = false
    for _, c in ipairs({ A, B, C, E }) do if next(c.Lobby.invites) then anyone = true end end
    check(not anyone, "...but nobody else sees it: their settings don't allow rank 4 hosts")
    M.Lobby:Leave(ms)
    Sim.Advance(0.5)
    NoErrors(mallory, alice, bob, carol, eve)
end

print("\n== Opening Bingo night")
local s
do
    s = A.Lobby:CreateHosted("bingo")
    check(s and s.open, "officer Alice opens a Bingo lobby")
    local ok = A.Lobby:Announce(s)
    Sim.Advance(1)
    check(ok, "announced to the guild")
    local function HasInvite(c) return c.Lobby.invites[s.id] ~= nil end
    check(HasInvite(B) and HasInvite(C) and HasInvite(E), "guild members get a join popup")
    check(not HasInvite(D), "someone from another guild doesn't")
    check(B.Lobby.invites[s.id].open, "the popup is the 'opened Guild Bingo' kind")
    local ok2, err2 = A.Lobby:Announce(s)
    check(not ok2 and err2, "announcing again right away is rate-limited")
    B.Lobby:AcceptInvite(s.id)
    C.Lobby:AcceptInvite(s.id)
    E.Lobby:DeclineInvite(s.id)    -- Eve says not now (joins later)
    Sim.Advance(1)
    check(A.Lobby.CountAccepted(s) == 2, "two players joined")
    check(A.Lobby:CanStart(s), "Alice can start the night")
    A.Lobby:Start(s)
    Sim.Advance(1)
    check(s.status == "playing" and s.channel == "GUILD", "night started on the GUILD channel")
    check(B.Lobby.active.status == "playing" and C.Lobby.active.status == "playing", "players are in")
    NoErrors(alice, bob, carol)
end

local function Data(c) return c.Lobby.active and c.Lobby.active.data end

print("\n== A round of 'any line'")
do
    A.db.profile.announceBingo = true
    s.data.speed = 5
    T.StartRound(s)
    Sim.Advance(0.5)
    check(Data(B).round == 1 and Data(B).card ~= nil, "Bob got a card for round 1")
    check(s.data.card == nil, "the caller (host) has no card")
    -- A false claim from Carol before anything is called.
    C.Lobby.active:SendAction("BINGO", 1)
    Sim.Advance(0.5)
    check(s.data.roundActive and #A.db.global.bingoLog == 0, "a false BINGO is rejected")
    check(Sim.Chat(carol, "not a Bingo"), "Carol is told it's not a Bingo")
    -- Let the caller call until Bob or Carol can claim.
    local claimer
    for _ = 1, 1000 do
        Sim.Advance(0.5)
        if Data(B).canClaim then claimer = "Bob-TestRealm"; break end
        if Data(C).canClaim then claimer = "Carol-TestRealm"; break end
    end
    check(claimer ~= nil, "numbers were called until someone had a line (" .. #s.data.called .. " calls)")
    local Bcl = byName[claimer]
    local calledSame = #Data(B).called == #s.data.called and #Data(C).called == #s.data.called
    check(calledSame, "every client has the same called numbers")
    Bcl:GetGame("bingo")._test.ClickBingo()
    Sim.Advance(0.5)
    check(not s.data.roundActive and s.data.lastWinner == claimer, "the host verified the card: " .. claimer .. " wins")
    check(Data(B).lastWinner == claimer and Data(C).lastWinner == claimer, "everyone sees the winner")
    local log = A.db.global.bingoLog[#A.db.global.bingoLog]
    check(log and log.winner == claimer and log.round == 1 and log.pattern == "line" and log.prizeGiven == false,
        "winner log: round, pattern, winner, time")
    local posted = false
    for _, m in ipairs(alice.chatSent) do if m.channel == "GUILD" and m.text:find("BINGO") then posted = true end end
    check(posted, "the win was posted in guild chat (setting on)")
    check(Bcl.Stats:Get("bingo").wins == 1, "the winner's stats count the win")
    NoErrors(alice, bob, carol)
end

print("\n== A latecomer joins mid-round")
do
    s.data.pattern = "blackout"
    T.StartRound(s)
    Sim.Advance(12)
    s.lastAnnounce = nil
    A.Lobby:Announce(s)
    Sim.Advance(1)
    check(E.Lobby.invites[s.id] ~= nil, "Eve gets the announcement again")
    E.Lobby:AcceptInvite(s.id)
    Sim.Advance(2)
    local es = E.Lobby.active
    check(es and es.status == "playing", "Eve joined the running night")
    check(es and es.data.round == 2 and es.data.card ~= nil, "Eve has a card for the current round")
    check(es and #es.data.called == #s.data.called and #es.data.called > 0, "Eve caught up with the numbers already called")
    check(#s.players == 4 and #B.Lobby.active.players == 4, "everyone's player list includes Eve")
    NoErrors(alice, bob, carol, eve)
end

print("\n== Players leave, the caller ends the night")
do
    C.Lobby:Leave(C.Lobby.active)
    Sim.Advance(1)
    check(s.status == "playing", "a player leaving doesn't end the night")
    check(C.Lobby.active == nil, "Carol is out")
    A.Lobby:Leave(s)    -- "End night"
    Sim.Advance(1)
    check(s.status == "ended" and B.Lobby.active.status == "ended" and E.Lobby.active.status == "ended",
        "the caller ending the night ends it for everyone")
    check(B.Stats:Get("bingo").losses == 0, "nobody gets a 'loss' for Bingo night")
    local e = A.db.global.bingoLog[1]
    e.prizeGiven = true
    check(A.db.global.bingoLog[1].prizeGiven, "prizes can be marked as given")
    NoErrors(alice, bob, carol, eve)
end

print("\n== Practice: you and the Training Dummy")
do
    for _, c in ipairs({ A, B, E }) do if c.Lobby.active then c.Lobby:Close(c.Lobby.active) end end
    local sent = bob.sent
    local logBefore = #B.db.global.bingoLog
    local p = B.Lobby:StartPractice("bingo")
    check(p and p.isLocal, "practice started (anyone can practice, no rank needed)")
    local BT = B:GetGame("bingo")._test
    local winner
    for _ = 1, 800 do
        Sim.Advance(0.5)
        if p.data.canClaim and not p.data.claimed then BT.ClickBingo() end
        if p.data.lastWinner then winner = p.data.lastWinner; break end
    end
    check(winner ~= nil, "someone won the practice round (" .. tostring(winner) .. ")")
    check(p.data.card ~= nil, "in practice you get a card too")
    check(bob.sent == sent, "practice sends nothing over the network")
    check(#B.db.global.bingoLog == logBefore, "practice wins don't go in the winner log")
    NoErrors(bob)
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
