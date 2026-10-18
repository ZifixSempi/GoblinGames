--[[ Simulated tests for Connect 6: run from the repo root with
       lua5.1 tools/wowsim/test_connect6.lua ]]

package.path = "tools/wowsim/?.lua;" .. package.path
local Sim = require("sim")
Sim.verbose = os.getenv("VERBOSE") ~= nil

local ADDONS = { "GoblinGames", "GoblinGames_TicTacToe", "GoblinGames_Connect6" }
local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1; print("  ok   " .. label)
    else failed = failed + 1; print("  FAIL " .. label) end
end
local function NoErrors(...)
    for _, c in ipairs({ ... }) do
        check(#c.errors == 0, c.name .. " had no Lua errors (" .. #c.errors .. ")")
        c.errors = {}
    end
end

math.randomseed(tonumber(os.getenv("SEED") or "7"))

local alice = Sim.NewClient({ name = "Alice", faction = "Horde", group = 1, addons = ADDONS, root = "." })
local bob = Sim.NewClient({ name = "Bob", faction = "Horde", group = 1, addons = ADDONS, root = "." })
Sim.Login(alice, { "GoblinGames" })
Sim.Login(bob, { "GoblinGames" })
Sim.Advance(1)
local A, B = alice.GG, bob.GG

-- Load the module on Alice to reach its pure rule helpers.
A:LoadGame("connect6")
local T = A:GetGame("connect6")._test
local N, Idx = T.N, T.Idx

print("\n== Rules")
do
    local function Board(stones)
        local b = {}
        for i = 1, N * N do b[i] = 0 end
        for _, s in ipairs(stones) do b[Idx(s[1], s[2])] = s[3] or 1 end
        return b
    end
    local row5 = Board({ { 3, 5 }, { 4, 5 }, { 5, 5 }, { 6, 5 }, { 7, 5 } })
    check(T.WinningLine(row5, 7, 5) == nil, "five in a row is not a win")
    local row6 = Board({ { 3, 5 }, { 4, 5 }, { 5, 5 }, { 6, 5 }, { 7, 5 }, { 8, 5 } })
    local line = T.WinningLine(row6, 5, 5)
    check(line and #line == 6, "six in a row wins, from a middle stone too")
    local row7 = Board({ { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 }, { 5, 1 }, { 6, 1 }, { 7, 1 } })
    check(T.WinningLine(row7, 7, 1) ~= nil, "seven in a row also wins")
    local diag = Board({ { 10, 10 }, { 11, 9 }, { 12, 8 }, { 13, 7 }, { 14, 6 }, { 15, 5 } })
    check(T.WinningLine(diag, 12, 8) ~= nil, "rising diagonal wins")
    local mixed = Board({ { 3, 5 }, { 4, 5 }, { 5, 5, 2 }, { 6, 5 }, { 7, 5 }, { 8, 5 }, { 9, 5 } })
    check(T.WinningLine(mixed, 7, 5) == nil, "an enemy stone breaks the line")
    -- The bot must block an open four of the opponent (seat 1) when it's seat 2.
    local threat = Board({ { 5, 10 }, { 6, 10 }, { 7, 10 }, { 8, 10 } })
    local block = T.BestCell(threat, 2)
    local bx, by = T.XY(block)
    check(by == 10 and (bx == 4 or bx == 9 or bx == 3 or bx == 10), "bot blocks an open four (picked " .. bx .. "," .. by .. ")")
    -- And it takes a win when it has five.
    local five = Board({ { 5, 3, 2 }, { 6, 3, 2 }, { 7, 3, 2 }, { 8, 3, 2 }, { 9, 3, 2 }, { 10, 12 }, { 11, 12 } })
    local win = T.BestCell(five, 2)
    local wx, wy = T.XY(win)
    check(wy == 3 and (wx == 4 or wx == 10), "bot completes its own six")
end

print("\n== Start a networked game")
local s
do
    s = A.Lobby:CreateHosted("connect6")
    A.Lobby:Invite(s, "Bob")
    Sim.Advance(1)
    B.Lobby:AcceptInvite(s.id)
    Sim.Advance(2)
    check(s.status == "playing" and B.Lobby.active and B.Lobby.active.status == "playing", "game started on both clients")
    check(bob.loaded.GoblinGames_Connect6, "Bob loaded Connect 6 on demand")
    check(s.data.stonesLeft == 1 and B.Lobby.active.data.stonesLeft == 1, "first move is a single stone")
    NoErrors(alice, bob)
end

local function Who(name) return name == "Alice-TestRealm" and A or B end
local function Place(x, y)
    local cur = A.Turns:Current(s)
    Who(cur).Lobby.active:SendAction("PLACE", x, y)
    Sim.Advance(0.4)
    return cur
end

print("\n== Turn structure: 1 stone, then 2 per turn")
local first, second
do
    first = Place(10, 10)
    second = A.Turns:Current(s)
    check(second ~= first, "turn passes after the opening stone")
    check(s.data.stonesLeft == 2, "next player gets 2 stones")
    -- Out of turn: the first player tries to play.
    Who(first).Lobby.active:SendAction("PLACE", 1, 1)
    Sim.Advance(0.4)
    check(s.data.board[Idx(1, 1)] == 0, "out-of-turn stone rejected")
    -- Occupied and off-board.
    Who(second).Lobby.active:SendAction("PLACE", 10, 10)
    Who(second).Lobby.active:SendAction("PLACE", 20, 3)
    Who(second).Lobby.active:SendAction("PLACE", 0, 3)
    Sim.Advance(0.4)
    check(s.data.stonesLeft == 2 and s.data.count == 1, "occupied and off-board stones rejected")
    Place(1, 19)
    check(A.Turns:Current(s) == second and s.data.stonesLeft == 1, "still your turn after the first of two stones")
    Place(3, 19)
    check(A.Turns:Current(s) == first and s.data.stonesLeft == 2, "turn passes after two stones")
    local bs = B.Lobby.active
    check(#bs.data.lastStones == 2, "last turn's two stones remembered (for the glow)")
    local same = true
    for i = 1, N * N do if bs.data.board[i] ~= s.data.board[i] then same = false end end
    check(same, "boards identical on both clients")
    NoErrors(alice, bob)
end

print("\n== Resync after a dropped message (snapshot is > 255 bytes)")
do
    local dropped = false
    Sim.dropFilter = function(_, to, text)
        if not dropped and to == bob and text:find("%^S%^") then dropped = true; return true end
    end
    Place(11, 10)                 -- first player, stone 1 of 2 (dropped for Bob)
    Sim.dropFilter = nil
    Place(12, 10)                 -- stone 2: Bob sees a gap and asks for SYNC
    Sim.Advance(2)
    local bs = B.Lobby.active
    local same = true
    for i = 1, N * N do if bs.data.board[i] ~= s.data.board[i] then same = false end end
    check(dropped, "a message was dropped")
    check(same, "Bob's board restored from the snapshot")
    check(bs.data.stonesLeft == s.data.stonesLeft, "stones-left restored")
    check(bs.seq == s.seq, "sequence numbers back in step")
    NoErrors(alice, bob)
end

print("\n== Six in a row wins")
do
    -- The first player builds row y=10 from x=10 (has 10,11,12 already).
    -- The second player scatters stones along the bottom edge.
    Place(1, 17); Place(5, 17)            -- second player
    Place(13, 10); Place(14, 10)          -- first player: 10..14 = five
    Place(9, 17); Place(13, 17)           -- second player ignores it
    Place(15, 10)                         -- first player: six!
    local bs = B.Lobby.active
    check(s.status == "ended" and bs.status == "ended", "game over on both clients")
    check(s.result.winners[1] == first and bs.result.winners[1] == first, "the right player won")
    check(bs.data.winLine and #bs.data.winLine >= 6, "winning line found for the glow")
    local winnerStats = (first == "Alice-TestRealm" and A or B).Stats:Get("connect6")
    check(winnerStats.wins == 1, "win recorded")
    NoErrors(alice, bob)
end

print("\n== Practice vs. the bot (solo)")
do
    A.Lobby:Close(A.Lobby.active)
    if B.Lobby.active then B.Lobby:Close(B.Lobby.active) end
    local p = A.Lobby:StartPractice("connect6")
    check(p and p.isLocal, "practice game started")
    local sentBefore = alice.sent
    local guard = 0
    while p.status == "playing" and guard < 400 do
        guard = guard + 1
        if A.Turns:IsMyTurn(p) and p.data.stonesLeft > 0 then
            -- Alice plays randomly near the centre.
            for _ = 1, 50 do
                local x, y = math.random(4, 16), math.random(4, 16)
                if p.data.board[Idx(x, y)] == 0 then p:SendAction("PLACE", x, y); break end
            end
        end
        Sim.Advance(0.5)
    end
    check(p.status == "ended", "practice game finished (" .. guard .. " steps)")
    check(p.result.outcome == "loss", "the bot beats a random player")
    check(alice.sent == sentBefore, "practice sends nothing over the network")
    NoErrors(alice)
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
