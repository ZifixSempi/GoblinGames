--[[ Simulated tests for Deathroll, the dice helper and the gold ledger.
       lua5.1 tools/wowsim/test_deathroll.lua        (SEED=n to vary randomness) ]]

package.path = "tools/wowsim/?.lua;" .. package.path
local Sim = require("sim")
Sim.verbose = os.getenv("VERBOSE") ~= nil

local ADDONS = { "GoblinGames", "GoblinGames_TicTacToe", "GoblinGames_Connect6", "GoblinGames_Deathroll" }
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

math.randomseed(tonumber(os.getenv("SEED") or "3"))

-- Alice, Bob, Eve grouped. Carol + Dave are guildmates, NOT grouped.
local alice = Sim.NewClient({ name = "Alice", faction = "Horde", group = 1, guild = "G", addons = ADDONS, root = "." })
local bob = Sim.NewClient({ name = "Bob", faction = "Alliance", group = 1, guild = "G", addons = ADDONS, root = "." })
local eve = Sim.NewClient({ name = "Eve", faction = "Horde", group = 1, guild = "G", addons = ADDONS, root = "." })
local carol = Sim.NewClient({ name = "Carol", faction = "Horde", guild = "G", addons = ADDONS, root = "." })
local dave = Sim.NewClient({ name = "Dave", faction = "Horde", guild = "G", addons = ADDONS, root = "." })
for _, c in ipairs({ alice, bob, eve, carol, dave }) do Sim.Login(c, { "GoblinGames" }) end
Sim.Advance(1)
local A, B, E, C, D = alice.GG, bob.GG, eve.GG, carol.GG, dave.GG
local byName = { ["Alice-TestRealm"] = A, ["Bob-TestRealm"] = B, ["Eve-TestRealm"] = E, ["Carol-TestRealm"] = C, ["Dave-TestRealm"] = D }
-- Carol and Dave accept invites from anyone (they aren't grouped; guild roster is empty in the sim).
C.db.profile.acceptFrom = "anyone"; D.db.profile.acceptFrom = "anyone"

print("\n== Dice helper")
do
    local n, r, lo, hi = A.Dice.Parse("Bob rolls 523 (1-1000)")
    check(n == "Bob-TestRealm" and r == 523 and lo == 1 and hi == 1000, "parses a roll message")
    local n2 = A.Dice.Parse("Zug-Stormrage rolls 7 (1-100)")
    check(n2 == "Zug-Stormrage", "keeps other realms")
    check(A.Dice.Parse("Bob has gone offline.") == nil, "ignores other system messages")
    local seen
    local listener = {}
    A.RegisterCallback(listener, "DICE_ROLLED", function(_, name, roll) seen = { name, roll } end)
    Sim.forcedRoll = 42
    B.Dice:Roll(1, 100)
    Sim.Advance(0.2)
    check(seen and seen[1] == "Bob-TestRealm" and seen[2] == 42, "Alice sees Bob's /roll from the server (same group)")
    A.UnregisterCallback(listener, "DICE_ROLLED")
    NoErrors(alice, bob)
end

local function StartGame(host, hostClient, guests, options)
    local s = host.Lobby:CreateHosted("deathroll")
    for k, v in pairs(options or {}) do host.Lobby:SetOption(s, k, v) end
    for _, g in ipairs(guests) do host.Lobby:Invite(s, g.name) end
    Sim.Advance(1)
    for _, g in ipairs(guests) do
        if g.GG.Lobby.invites[s.id] then g.GG.Lobby:AcceptInvite(s.id) end
    end
    Sim.Advance(1.5)
    if s.status == "lobby" then host.Lobby:Start(s); Sim.Advance(1) end
    return s
end

local function RollFor(s, value)
    local cur = s.host and byName[A.Turns:Current(s)] and A.Turns:Current(s)
    cur = (byName[s.host] or A).Turns:Current(s)
    local client = byName[cur]
    Sim.forcedRoll = value
    client.Dice:Roll(1, s.data.max)
    Sim.Advance(0.3)
    return cur
end

print("\n== Two players in a group")
local s
do
    s = StartGame(A, alice, { bob })
    check(s.status == "playing", "game started")
    check(s.data.max == 1000, "starts at 1000")
    local first = RollFor(s, 640)
    local bs = B.Lobby.active
    check(s.data.max == 640 and bs.data.max == 640, "roll accepted: next roll is 1-640 on both clients")
    check(bs.data.history[1] and bs.data.history[1].verified, "the roll is marked verified (host saw it)")
    check(A.Turns:Current(s) ~= first, "turn passed")
    -- The waiting player rolls out of turn: ignored.
    local waiting = byName[first]
    Sim.forcedRoll = 5
    waiting.Dice:Roll(1, 640)
    Sim.Advance(0.3)
    check(s.data.max == 640, "out-of-turn roll ignored")
    -- The current player rolls the wrong range: ignored.
    local cur = A.Turns:Current(s)
    Sim.forcedRoll = 50
    byName[cur].Dice:Roll(1, 100)
    Sim.Advance(0.3)
    check(s.data.max == 640 and A.Turns:Current(s) == cur, "wrong range (1-100 instead of 1-640) ignored")
    -- Rolls twice quickly: only the first counts.
    Sim.forcedRoll = 300
    byName[cur].Dice:Roll(1, 640)
    Sim.forcedRoll = 2
    byName[cur].Dice:Roll(1, 640)
    Sim.Advance(0.3)
    check(s.data.max == 300 and #s.data.history == 2, "a second roll in the same turn is ignored")
    -- Next player rolls a 1: dead.
    local loser = RollFor(s, 1)
    check(s.status == "ended" and bs.status == "ended", "rolling a 1 ends the game")
    check(s.data.loser == loser and bs.data.loser == loser, "both clients know who died")
    check(s.result.winners[1] ~= loser and #s.result.winners == 1, "the other player wins")
    local loserStats = byName[loser].Stats:Get("deathroll")
    check(loserStats.losses == 1, "loss recorded for " .. loser)
    NoErrors(alice, bob)
end

print("\n== Not grouped: rolls are reported and shown as unverified")
do
    local cs = StartGame(C, carol, { dave })
    check(cs.status == "playing" and cs.channel == "WHISPER", "game started over whispers")
    local cur = C.Turns:Current(cs)
    local client = byName[cur]
    Sim.forcedRoll = 777
    client.Dice:Roll(1, 1000)
    Sim.Advance(0.5)
    if cur == "Dave-TestRealm" then
        check(cs.data.max == 1000, "Carol can't see Dave's roll right away")
        Sim.Advance(3)
    end
    check(cs.data.max == 777, "roll accepted after the report")
    local entry = cs.data.history[1]
    check(entry and entry.verified == (cur == "Carol-TestRealm"), "Dave's rolls are unverified, the host's own are verified")
    -- Finish: next player rolls a 1.
    local nxt = C.Turns:Current(cs)
    Sim.forcedRoll = 1
    byName[nxt].Dice:Roll(1, 777)
    Sim.Advance(4)
    check(cs.status == "ended", "game ends")
    NoErrors(carol, dave)
    C.Lobby:Close(cs)
    if D.Lobby.active then D.Lobby:Close(D.Lobby.active) end
end

print("\n== Gold stakes (ledger only)")
do
    A.Lobby:Close(A.Lobby.active); if B.Lobby.active then B.Lobby:Close(B.Lobby.active) end
    local before = #B.db.global.ledger
    -- Alice turns gold mode on and sets a stake; Bob has gold mode off.
    A:SetSetting("goldMode", true)
    check(Sim.Chat(alice, "Terms of Use"), "switching gold mode on shows the Terms of Use reminder")
    local st = A.Lobby:CreateHosted("deathroll")
    check(st.options.start == 1000 and st.options.stake == 0, "default options: start 1000, no stake")
    A.Lobby:SetOption(st, "stake", 100)
    A.Lobby:SetOption(st, "start", 100)
    A.Lobby:Invite(st, "Bob")
    Sim.Advance(1)
    check(st.invites["Bob-TestRealm"].status == "declined" and st.invites["Bob-TestRealm"].reason == "nogold",
        "Bob (gold mode off) auto-declines a staked game")
    check(A.Lobby:SetOption(st, "stake", 500) == false, "options are locked once invites went out")
    B:SetSetting("goldMode", true)
    A.Lobby:Invite(st, "Bob")
    Sim.Advance(1)
    check(B.Lobby.invites[st.id] and B.Lobby.invites[st.id].options.stake == 100, "Bob's invite shows the 100g stake")
    B.Lobby:AcceptInvite(st.id)
    Sim.Advance(1)
    check(st.status == "lobby", "Deathroll (up to 40 players) waits for the host to press Start")
    A.Lobby:Start(st)
    Sim.Advance(1)
    check(st.status == "playing" and st.data.max == 100, "staked game started at 100")
    check(B.Lobby.active.options.stake == 100, "Bob's client knows the stake")
    -- Play until someone rolls a 1.
    local guard = 0
    while st.status == "playing" and guard < 20 do
        guard = guard + 1
        RollFor(st, st.data.max <= 3 and 1 or math.random(2, st.data.max))
        Sim.Advance(3)
    end
    check(st.status == "ended", "staked game finished")
    local loser = st.data.loser
    local winner = st.result.winners[1]
    local aEntry = A.db.global.ledger[#A.db.global.ledger]
    local bEntry = B.db.global.ledger[#B.db.global.ledger]
    check(#B.db.global.ledger == before + 1, "Bob's ledger has one new entry")
    check(aEntry and aEntry.from == loser and aEntry.to == winner and aEntry.gold == 100, "Alice's ledger: loser owes winner 100g")
    check(bEntry and bEntry.from == loser and bEntry.gold == 100, "Bob's ledger matches")
    local open = A.Ledger:Open()
    A.Ledger:Settle(open[1].index)
    check(#A.Ledger:Open() == #open - 1, "marking an entry paid settles it")
    NoErrors(alice, bob)
end

print("\n== Three players, and running out of time")
do
    A.Lobby:Close(A.Lobby.active); if B.Lobby.active then B.Lobby:Close(B.Lobby.active) end
    A:SetSetting("goldMode", false)
    A.db.profile.turnTimer = 30
    local s3 = StartGame(A, alice, { bob, eve })
    check(s3.status == "playing" and #s3.players == 3, "three-player game started")
    local seen = {}
    for _ = 1, 3 do
        local cur = RollFor(s3, math.max(2, math.floor(s3.data.max * 0.8)))
        seen[cur] = true
        Sim.Advance(0.5)
    end
    check(seen["Alice-TestRealm"] and seen["Bob-TestRealm"] and seen["Eve-TestRealm"], "everyone took a turn")
    local staller = A.Turns:Current(s3)
    Sim.Advance(32)
    check(s3.status == "ended" and s3.data.loser == staller, "running out of time counts as rolling a 1")
    check(#s3.result.winners == 2, "the other two win")
    NoErrors(alice, bob, eve)
    A.db.profile.turnTimer = 60
end

print("\n== Practice vs. the Training Dummy")
do
    A.Lobby:Close(A.Lobby.active)
    for _, c in ipairs({ B, E }) do if c.Lobby.active then c.Lobby:Close(c.Lobby.active) end end
    local rollsBefore = alice.rolls or 0
    local sentBefore = alice.sent
    local p = A.Lobby:StartPractice("deathroll")
    local T = A:GetGame("deathroll")._test
    check(p and p.options.stake == 0, "practice never has a stake")
    local guard = 0
    while p.status == "playing" and guard < 60 do
        guard = guard + 1
        if A.Turns:IsMyTurn(p) then
            p.data.rollPendingUntil = nil
            T.ClickRoll()
        end
        Sim.Advance(1.2)
    end
    check(p.status == "ended" and p.data.loser ~= nil, "practice game finished (" .. guard .. " steps)")
    check((alice.rolls or 0) == rollsBefore, "practice never calls /roll (no spam to the party)")
    check(alice.sent == sentBefore, "practice sends no addon messages")
    NoErrors(alice)
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
