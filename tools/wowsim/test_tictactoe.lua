--[[ Simulated tests for Milestone 1: run from the repo root with
       lua5.1 tools/wowsim/test_tictactoe.lua
     Exits with an error if any check fails. ]]

package.path = "tools/wowsim/?.lua;" .. package.path
local Sim = require("sim")
Sim.verbose = os.getenv("VERBOSE") ~= nil

local ROOT = "."
local ADDONS = { "GoblinGames", "GoblinGames_TicTacToe" }
local passed, failed = 0, 0

local function check(cond, label)
    if cond then
        passed = passed + 1
        print("  ok   " .. label)
    else
        failed = failed + 1
        print("  FAIL " .. label)
    end
end

local function NoErrors(...)
    for _, c in ipairs({ ... }) do
        check(#c.errors == 0, c.name .. " had no Lua errors (" .. #c.errors .. ")")
        c.errors = {}
    end
end

math.randomseed(42)

-- Alice (Horde) and Bob (Alliance) are in a party together. Carol has no addon.
local alice = Sim.NewClient({ name = "Alice", faction = "Horde", group = 1, guild = "G", addons = ADDONS, root = ROOT })
local bob = Sim.NewClient({ name = "Bob", faction = "Alliance", group = 1, guild = "G", addons = ADDONS, root = ROOT })
local carol = Sim.NewClient({ name = "Carol", faction = "Horde", group = 1, addons = {}, root = ROOT })
Sim.Login(alice, { "GoblinGames" })
Sim.Login(bob, { "GoblinGames" })
Sim.Advance(1)

local A, B = alice.GG, bob.GG

print("\n== Message encoding")
do
    local text = A.Comm.Encode("X", "sid", "a^b", "c~d", 5, true, nil, "")
    local proto, op, sid, args = A.Comm.Decode(text)
    check(proto == 1 and op == "X" and sid == "sid", "header round-trips")
    check(args[1] == "a^b" and args[2] == "c~d" and args[3] == "5" and args[4] == "1" and args[5] == "" and args[6] == "",
        "fields with ^ and ~ round-trip")
end

print("\n== Version check")
do
    local got
    A.Comm:WhoHasAddon(function(r) got = r end)
    Sim.Advance(5)
    check(got and got["Bob-TestRealm"] == "sim", "/gg who finds Bob")
end

print("\n== Invite, no-addon detection, accept, auto-start")
local s
do
    s = A.Lobby:CreateHosted("tictactoe")
    check(s ~= nil and s:IsHost(), "Alice hosts a lobby")
    check(alice.loaded.GoblinGames_TicTacToe, "Tic-Tac-Toe module loaded on demand")
    check(not bob.loaded.GoblinGames_TicTacToe, "...but not yet on Bob")

    A.Lobby:Invite(s, "Carol")
    A.Lobby:Invite(s, "Bob")
    Sim.Advance(1)
    check(B.Lobby.invites[s.id] ~= nil, "Bob received the invite")
    check(s.invites["Bob-TestRealm"].status == "pending", "Alice saw Bob's ACK (addon installed)")
    Sim.Advance(6)
    check(s.invites["Carol-TestRealm"].status == "noaddon", "Carol flagged as no addon")

    B.Lobby:AcceptInvite(s.id)
    check(bob.loaded.GoblinGames_TicTacToe, "Bob loaded the module when accepting")
    Sim.Advance(2)
    local bs = B.Lobby.active
    check(s.status == "playing", "Alice's game started automatically (2 of 2)")
    check(bs and bs.id == s.id and bs.status == "playing", "Bob's game started")
    check(bs and #bs.players == 2 and bs.players[1] == "Alice-TestRealm", "Bob has the same player list")
    check(bs and bs:GetFaction("Alice-TestRealm") == "Horde" and bs:GetFaction("Bob-TestRealm") == "Alliance",
        "factions known on both sides (mixed mode)")
    check(s.channel == "PARTY", "group channel chosen because everyone is grouped")
    NoErrors(alice, bob)
end

-- Play moves: whoever's turn it is picks the lowest free cell from a script.
local function PlayGame(script, maxMoves)
    local moves = 0
    while s.status == "playing" and moves < (maxMoves or 20) do
        local cur = A.Turns:Current(s)
        local who = (cur == "Alice-TestRealm") and A or B
        local sess = who.Lobby.active
        local cell = table.remove(script, 1)
        if not cell then break end
        sess:SendAction("MOVE", cell)
        Sim.Advance(0.5)
        moves = moves + 1
    end
end

print("\n== Rules: illegal moves are ignored")
do
    local bs = B.Lobby.active
    local cur = A.Turns:Current(s)
    local waiting = (cur == "Alice-TestRealm") and B or A
    waiting.Lobby.active:SendAction("MOVE", 1) -- not their turn
    Sim.Advance(0.5)
    check(s.data.board[1] == 0, "move out of turn rejected")
    local mover = (cur == "Alice-TestRealm") and A or B
    mover.Lobby.active:SendAction("MOVE", 5)
    Sim.Advance(0.5)
    check(s.data.board[5] ~= 0 and bs.data.board[5] == s.data.board[5], "legal move applied on both boards")
    local next = (cur == "Alice-TestRealm") and B or A
    next.Lobby.active:SendAction("MOVE", 5)
    Sim.Advance(0.5)
    check(A.Turns:Current(s) ~= cur, "taking an occupied cell is rejected (still their turn)")
    check(B.Turns:Current(bs) == A.Turns:Current(s), "both clients agree whose turn it is")
end

print("\n== Win detection and stats")
do
    -- Board so far: centre taken by first mover (X). Script: second mover 1, X 9? Make X win on the diagonal 1-5-9 or 3-5-7.
    -- Current mover = second player. Moves: O:1, X:3, O:2, X:7  -> X wins 3-5-7.
    PlayGame({ 1, 3, 2, 7 })
    local bs = B.Lobby.active
    check(s.status == "ended" and bs.status == "ended", "game ended on both clients")
    local winner = s.result.winners[1]
    check(winner ~= nil and bs.result.winners[1] == winner, "same winner on both clients")
    local aliceWon = winner == "Alice-TestRealm"
    local aStats, bStats = A.Stats:Get("tictactoe"), B.Stats:Get("tictactoe")
    check(aStats.wins == (aliceWon and 1 or 0) and aStats.losses == (aliceWon and 0 or 1), "Alice's stats recorded")
    check(bStats.wins == (aliceWon and 0 or 1) and bStats.losses == (aliceWon and 1 or 0), "Bob's stats recorded")
    check(aStats.opponents["Bob-TestRealm"] ~= nil, "per-opponent record kept")
    NoErrors(alice, bob)
end

print("\n== Rematch, then a draw")
do
    A.Lobby:Rematch(s)
    s = A.Lobby.active
    Sim.Advance(1)
    check(B.Lobby.invites[s.id] ~= nil, "Bob got the rematch invite even though his old game is open")
    B.Lobby:AcceptInvite(s.id)
    Sim.Advance(2)
    check(s.status == "playing", "rematch started")
    -- X:5 O:1 X:9 O:... a known draw sequence: 5,1,9,... ; use 1,2,3,5,4,6,8,7,9 style draw:
    -- X1 O2 X3 O5 X4 O6 X8 O7 X9 -> check: X has 1,3,4,8,9 no line; O has 2,5,6,7 no line. Draw.
    PlayGame({ 1, 2, 3, 5, 4, 6, 8, 7, 9 })
    check(s.status == "ended" and s.result.draw, "draw detected")
    check(B.Lobby.active.result.draw, "Bob sees the draw")
    check(A.Stats:Get("tictactoe").draws == 1, "draw counted")
    NoErrors(alice, bob)
end

print("\n== Missed message -> resync")
do
    A.Lobby:Rematch(s)
    s = A.Lobby.active
    Sim.Advance(1)
    B.Lobby:AcceptInvite(s.id)
    Sim.Advance(2)
    local bs = B.Lobby.active
    -- Drop the next state message to Bob.
    local dropped = false
    Sim.dropFilter = function(from, to, text)
        if not dropped and to == bob and text:find("%^S%^") then dropped = true; return true end
    end
    local cur = A.Turns:Current(s)
    local mover = (cur == "Alice-TestRealm") and A or B
    mover.Lobby.active:SendAction("MOVE", 1)
    Sim.Advance(0.5)
    Sim.dropFilter = nil
    check(dropped, "a message to Bob was dropped")
    local mover2 = (A.Turns:Current(s) == "Alice-TestRealm") and A or B
    mover2.Lobby.active:SendAction("MOVE", 2)
    Sim.Advance(1)
    check(bs.data.board[1] == s.data.board[1] and bs.data.board[2] == s.data.board[2], "Bob resynced the full board")
    check(bs.seq == s.seq, "sequence numbers match again")
    NoErrors(alice, bob)
end

print("\n== Forfeit")
do
    local bs = B.Lobby.active
    B.Lobby:Leave(bs)
    Sim.Advance(1)
    check(s.status == "ended" and s.result.winners[1] == "Alice-TestRealm", "Bob forfeits, Alice wins")
    check(B.Lobby.active == nil, "Bob's session closed")
    check(B.Stats:Get("tictactoe").losses >= 1, "forfeit counted as a loss for Bob")
    NoErrors(alice, bob)
end

print("\n== Turn timer runs out")
do
    A.db.profile.turnTimer = 30
    A.Lobby:Rematch(s)
    s = A.Lobby.active
    Sim.Advance(1)
    B.Lobby:AcceptInvite(s.id)
    Sim.Advance(2)
    local staller = A.Turns:Current(s)
    local remaining = A.Turns:Remaining(s)
    check(remaining and remaining > 25 and remaining <= 30, "a 30s clock is running")
    Sim.Advance(remaining - 1)
    check(s.status == "playing", "still playing 1s before the deadline")
    Sim.Advance(2)
    check(s.status == "ended", "game ends when the clock runs out")
    check(s.result.winners[1] ~= staller, "the player who stalled loses")
    NoErrors(alice, bob)
end

print("\n== Chat lockdown (Retail encounter) pauses everything")
do
    A.Lobby:Rematch(s)
    s = A.Lobby.active
    Sim.Advance(1)
    B.Lobby:AcceptInvite(s.id)
    Sim.Advance(2)
    local remaining = A.Turns:Remaining(s)
    alice.lockdown, bob.lockdown = true, true
    local cur = A.Turns:Current(s)
    local mover = (cur == "Alice-TestRealm") and A or B
    mover.Lobby.active:SendAction("MOVE", 5)
    Sim.Advance(40)
    check(s.status == "playing", "no timeout during lockdown")
    check(math.abs(A.Turns:Remaining(s) - remaining) < 1 or mover == A, "clock frozen during lockdown")
    alice.lockdown, bob.lockdown = false, false
    Sim.Advance(2)
    check(s.data.board[5] ~= 0, "move held during lockdown went through afterwards")
    check(B.Lobby.active.data.board[5] == s.data.board[5], "...and reached Bob")
    NoErrors(alice, bob)
    A.Lobby:Leave(s)
    Sim.Advance(1)
end

print("\n== Disconnect")
do
    A.db.profile.turnTimer = 0 -- so only the disconnect rule can end this game
    A.Lobby:Close(A.Lobby.active)
    if B.Lobby.active then B.Lobby:Close(B.Lobby.active) end
    s = A.Lobby:CreateHosted("tictactoe")
    A.Lobby:Invite(s, "Bob")
    Sim.Advance(1)
    B.Lobby:AcceptInvite(s.id)
    Sim.Advance(2)
    bob.online = false
    Sim.FireEvent(alice, "CHAT_MSG_SYSTEM", "Bob has gone offline.")
    check(s.offlineSince["Bob-TestRealm"] ~= nil, "Alice noticed Bob went offline")
    Sim.Advance(95)
    check(s.status == "ended" and s.result.winners[1] == "Alice-TestRealm", "Bob removed after the grace period")
    bob.online = true
    NoErrors(alice, bob)
end

print("\n== Practice mode (solo)")
do
    A.Lobby:Close(A.Lobby.active)
    local p = A.Lobby:StartPractice("tictactoe")
    check(p and p.isLocal, "practice session created")
    local sentBefore = alice.sent
    local guard = 0
    while p.status == "playing" and guard < 20 do
        guard = guard + 1
        if A.Turns:IsMyTurn(p) then
            for i = 1, 9 do if p.data.board[i] == 0 then p:SendAction("MOVE", i); break end end
        end
        Sim.Advance(1.5)
    end
    check(p.status == "ended", "practice game finished")
    check(alice.sent == sentBefore, "practice sends nothing over the network")
    local before = A.Stats:Get("tictactoe")
    check(true, "practice result: " .. tostring(p.result.outcome))
    NoErrors(alice)
end

print("\n== Declines and filters")
do
    A.Lobby:Close(A.Lobby.active)
    if B.Lobby.active then B.Lobby:Close(B.Lobby.active) end
    s = A.Lobby:CreateHosted("tictactoe")
    A.Lobby:Invite(s, "Bob")
    Sim.Advance(1)
    B.Lobby:DeclineInvite(s.id, "declined")
    Sim.Advance(1)
    check(s.invites["Bob-TestRealm"].status == "declined", "decline reaches the host")
    B.db.profile.acceptFrom = "nobody"
    A.Lobby:Invite(s, "Bob")
    Sim.Advance(1)
    check(s.invites["Bob-TestRealm"].status == "declined" and s.invites["Bob-TestRealm"].reason == "notaccepting",
        "invites auto-declined when Bob accepts from nobody")
    check(B.Lobby.invites[s.id] == nil, "Bob never saw a popup")
    B.db.profile.acceptFrom = "known"
    NoErrors(alice, bob)
end

print("\n== Slash commands and UI smoke test")
do
    A.Lobby:Close(A.Lobby.active)
    for _, cmd in ipairs({ "", "help", "stats", "settings", "practice ttt", "leave", "who", "debug", "debug" }) do
        alice.env.SlashCmdList.GOBLINGAMES(cmd)
        Sim.Advance(0.2)
    end
    Sim.Advance(5)
    alice.env.GoblinGames.UI:ShowPanel("games")
    alice.env.GoblinGames.UI:ShowPanel("lobby")
    alice.env.GoblinGames.UI:ShowPanel("game")
    for _, id in ipairs({ "general", "tictactoe", "connect6", "deathroll", "bingo", "gofish", "crazyeights", "blackjack", "poker", "liarsdice", "trivia" }) do
        alice.env.GoblinGames.UI:ShowRules(id)
    end
    alice.env.SlashCmdList.GOBLINGAMES("rules ttt")
    alice.env.SlashCmdList.GOBLINGAMES("rules")
    check(alice.env.GoblinGames.RULES.tictactoe and select(2, alice.env.GoblinGames:RulesText("gofish")):find("Go Fish") ~= nil, "rules exist for the games")
    alice.env.GoblinGames:SetSetting("theme", "Alliance")
    check(alice.env.GoblinGames.Theme:GetThemeFaction() == "Alliance", "theme can be forced")
    NoErrors(alice, bob)
end

print("\n== Saved data survives a migration run")
do
    local raw = alice.env.GoblinGamesDB
    check(raw.global.schemaVersion == alice.env.GoblinGames.SCHEMA_VERSION, "schemaVersion stored")
    check(raw.char and next(raw.char) ~= nil, "per-character stats saved")
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
