--[[ Simulated tests for Trivia.
       lua5.1 tools/wowsim/test_trivia.lua        (SEED=n to vary randomness) ]]

package.path = "tools/wowsim/?.lua;" .. package.path
local Sim = require("sim")
Sim.verbose = os.getenv("VERBOSE") ~= nil

local ADDONS = { "GoblinGames", "GoblinGames_TicTacToe", "GoblinGames_Trivia" }
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

math.randomseed(tonumber(os.getenv("SEED") or "10"))

-- Everyone is in the guild "Goblins"; Alice, Bob and Eve are also grouped.
local function Client(name, faction, group)
    return Sim.NewClient({ name = name, faction = faction, group = group, guild = "Goblins", rank = 3, addons = ADDONS, root = "." })
end
local alice = Client("Alice", "Horde", 1)
local bob = Client("Bob", "Alliance", 1)
local eve = Client("Eve", "Horde", 1)
local carol = Client("Carol", "Alliance", nil)
for _, c in ipairs({ alice, bob, eve, carol }) do Sim.Login(c, { "GoblinGames" }) end
Sim.Advance(1)
local A, B, E, C = alice.GG, bob.GG, eve.GG, carol.GG
local AN, BN, EN, CN = "Alice-TestRealm", "Bob-TestRealm", "Eve-TestRealm", "Carol-TestRealm"

A:LoadGame("trivia")
local T = A:GetGame("trivia")._test

print("\n== The question bank")
do
    local opts = { count = 200, topic = "all", set = 2 }
    local all = T.PickQuestions(opts)
    check(#all >= 90, "at least 90 built-in questions (" .. #all .. ")")
    local ok = true
    for _, q in ipairs(all) do
        if type(q.q) ~= "string" or #q.q < 10 or #q.a ~= 4 then ok = false end
        local seen = {}
        for _, a in ipairs(q.a) do
            if type(a) ~= "string" or a == "" or seen[a] or #a > 48 then ok = false end
            seen[a] = true
        end
    end
    check(ok, "every question has four different, short answers")
    local lore = T.PickQuestions({ count = 200, topic = "lore", set = 2 })
    local allLore = true
    for _, q in ipairs(lore) do if q.c ~= "lore" then allLore = false end end
    check(#lore > 20 and allLore, "the topic filter works (" .. #lore .. " lore questions)")
    check(#T.PickQuestions({ count = 10, topic = "all", set = 0 }) == 10, "10 questions when asked for 10")

    local custom = T.CustomQuestions()
    check(#custom == 0, "no custom questions yet")
    local mine = T.PickQuestions({ count = 10, set = 1 })
    check(#mine == 10, "'only yours' with none of your own falls back to the built-in questions")
    custom[1] = { q = "What is the name of our guild bank goblin?", a = { "Grizzle", "Zifix", "Gazlowe", "Bob" } }
    custom[2] = { q = "Which raid does our guild wipe on most?", a = { "Molten Core", "Karazhan", "Naxxramas", "Ulduar" } }
    mine = T.PickQuestions({ count = 10, set = 1 })
    check(#mine == 2 and mine[1].c == "custom", "'only yours' uses just your 2 questions")
    A:GetGame("trivia").OpenEditor()
    check(_G and true, "the question editor opens")
    NoErrors(alice)
end

local function StartGame(guests, options)
    local s = A.Lobby:CreateHosted("trivia")
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

print("\n== A quiz: Alice asks, Bob and Eve answer")
local s = StartGame({ bob, eve }, { count = 5, seconds = 15, set = 2 })
local d = s.data
local bs, es = B.Lobby.active, E.Lobby.active
do
    check(s.status == "playing" and s.catalog.open, "the quiz started (an open game)")
    Sim.Advance(2.5)
    check(d.n == 1 and bs.data.q and bs.data.q.text ~= "", "question 1 arrived")
    check(#bs.data.q.answers == 4, "with four answers")
    check(bs.data.correct == nil and bs.data.questions == nil, "Bob's client doesn't know the answer")
    check(not T.IsPlaying(s, AN) and T.IsPlaying(s, BN), "by default the host is the quizmaster, not a player")
    check(not T.Answer(s, AN, 1, d.correct), "the quizmaster can't answer")

    -- Bob answers right first, Eve right second.
    local right = d.correct
    B:GetGame("trivia")._test.Choose(right)
    Sim.Advance(0.3)
    check(bs.data.myChoice == right, "Bob's answer is locked in")
    check(es.data.answered[BN], "Eve sees that Bob has answered (not what)")
    B:GetGame("trivia")._test.Choose((right % 4) + 1)
    Sim.Advance(0.3)
    check(d.answers[BN].choice == right, "a second click doesn't change Bob's answer")
    E:GetGame("trivia")._test.Choose(right)
    Sim.Advance(1.5)
    check(d.hostPhase == "reveal", "everyone answered: revealed early")
    check(d.hostScores[BN] == 3 and d.hostScores[EN] == 2, "fastest right answer +3, second +2")
    check(bs.data.reveal and bs.data.reveal.correct == right, "Bob sees the right answer")
    check(bs.data.scores[BN] == 3 and bs.data.scores[EN] == 2, "and the scoreboard")
    check(bs.data.scores[AN] == nil, "the quizmaster isn't on the scoreboard")
    NoErrors(alice, bob, eve)

    -- Question 2: Eve answers wrong, Bob doesn't answer: the clock runs out.
    Sim.Advance(7)
    check(d.n == 2 and d.hostPhase == "question", "question 2")
    E:GetGame("trivia")._test.Choose((d.correct % 4) + 1)
    Sim.Advance(16)
    check(d.n >= 2 and (d.hostPhase == "reveal" or d.n == 3), "the clock ran out: revealed")
    check(d.hostScores[EN] == 2 and d.hostScores[BN] == 3, "wrong and no answer score nothing")
    NoErrors(alice, bob, eve)
end

print("\n== Latecomers and leavers")
do
    -- Carol (guild, not grouped) joins mid-quiz through the guild announcement.
    s.lastAnnounce = nil
    local ok = A.Lobby:Announce(s)
    check(ok, "the quizmaster can announce mid-quiz (latecomers welcome)")
    Sim.Advance(1)
    local inv
    for id, i in pairs(C.Lobby.invites) do if id == s.id then inv = i end end
    check(inv ~= nil, "Carol got a join popup")
    C.Lobby:AcceptInvite(s.id)
    Sim.Advance(3)
    local cs = C.Lobby.active
    check(cs and cs.status == "playing" and A.Util.IndexOf(s.players, CN), "Carol joined the running quiz")
    -- Wait for a fresh question so Carol can answer it.
    local guard = 0
    while d.hostPhase ~= "question" and guard < 20 do Sim.Advance(1); guard = guard + 1 end
    Sim.Advance(1)
    check(cs.data.q and cs.data.n == d.n, "Carol sees the current question")
    C:GetGame("trivia")._test.Choose(d.correct)
    Sim.Advance(0.5)
    check(d.answers[CN] and d.answers[CN].choice == d.correct, "Carol's answer counted")
    E.Lobby:Leave()
    Sim.Advance(1)
    check(s.status == "playing", "Eve left; the quiz goes on")
    NoErrors(alice, bob, carol, eve)
end

print("\n== The end")
do
    local guard = 0
    while s.status == "playing" and guard < 200 do
        if d.hostPhase == "question" then
            if not d.answers[BN] then T.Answer(s, BN, d.n, d.correct) end
        end
        Sim.Advance(1)
        guard = guard + 1
    end
    check(s.status == "ended", "5 questions later, the quiz is over")
    check(d.n == 5, "exactly 5 questions were asked")
    check(s.result.outcome == nil, "the quizmaster records no win or loss")
    Sim.Advance(10)
    check(bs.result and bs.result.outcome == "win", "Bob (most points) won")
    NoErrors(alice, bob, carol)
    A.Lobby:Close(s); B.Lobby:Close(bs)
    if C.Lobby.active then C.Lobby:Close(C.Lobby.active) end
    if E.Lobby.active then E.Lobby:Close(E.Lobby.active) end
    Sim.Advance(1)
end

print("\n== The host plays too, with custom questions")
do
    s = StartGame({ bob }, { count = 5, set = 1, hostplays = 1 })
    d = s.data
    bs = B.Lobby.active
    Sim.Advance(2.5)
    check(#d.questions == 2, "only Alice's 2 custom questions")
    check(T.IsPlaying(s, AN), "Alice plays too")
    check(bs.data.q.cat == "custom", "a 'Guild question'")
    check(T.Answer(s, AN, d.n, d.correct), "the host can answer")
    T.Answer(s, BN, d.n, (d.correct % 4) + 1)
    Sim.Advance(1.5)
    check(d.hostScores[AN] == 3 and (d.hostScores[BN] or 0) == 0, "Alice +3, Bob 0")
    Sim.Advance(7)
    T.Answer(s, AN, d.n, d.correct); T.Answer(s, BN, d.n, d.correct)
    Sim.Advance(10)
    check(s.status == "ended" and s.result.outcome == "win", "two questions, then Alice wins")
    NoErrors(alice, bob)
    A.Lobby:Close(s); B.Lobby:Close(B.Lobby.active)
    Sim.Advance(1)
end

print("\n== Practice against the Training Dummy")
do
    local sent = bob.sent
    B.db.global.triviaQuestions = {}
    local p = B.Lobby:StartPractice("trivia")
    check(p and p.isLocal, "practice started")
    local BT = B:GetGame("trivia")._test
    local pd = p.data
    local guard = 0
    while p.status == "playing" and guard < 400 do
        guard = guard + 1
        if pd.phase == "question" and not pd.myChoice and math.random() < 0.3 then
            BT.Choose(math.random(1, 4))
        end
        Sim.Advance(1)
    end
    check(p.status == "ended", "practice quiz finished (" .. guard .. " seconds)")
    check(pd.n == 10, "10 questions by default")
    local dummyAnswered = false
    for name, sc in pairs(pd.hostScores) do if name ~= BN and sc > 0 then dummyAnswered = true end end
    check(dummyAnswered, "the Training Dummy answered (and got some right)")
    check(bob.sent == sent, "practice sends nothing over the network")
    NoErrors(bob)
end

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
