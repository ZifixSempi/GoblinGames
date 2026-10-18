--[[ Simulated tests for Connect 6 (vertical rack): run from the repo root with
       lua5.1 tools/wowsim/test_connect6.lua        (SEED=n to vary randomness) ]]

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
local bob = Sim.NewClient({ name = "Bob", faction = "Alliance", group = 1, addons = ADDONS, root = "." })
Sim.Login(alice, { "GoblinGames" })
Sim.Login(bob, { "GoblinGames" })
Sim.Advance(1)
local A, B = alice.GG, bob.GG

A:LoadGame("connect6")
local T = A:GetGame("connect6")._test
local COLS, ROWS, Idx = T.COLS, T.ROWS, T.Idx

local function Board(pieces)  -- pieces: { {col,row,seat}, ... }
    local b = {}
    for i = 1, COLS * ROWS do b[i] = 0 end
    for _, p in ipairs(pieces) do b[Idx(p[1], p[2])] = p[3] or 1 end
    return b
end

print("\n== Rules")
do
    check(COLS == 9 and ROWS == 8, "rack is 9 columns x 8 rows")
    local empty = Board({})
    check(T.LandingRow(empty, 3) == ROWS, "a checker falls to the bottom row")
    local stack = Board({ { 3, 8 }, { 3, 7 } })
    check(T.LandingRow(stack, 3) == 6, "checkers stack on top of each other")
    local full = {}
    for r = 1, ROWS do full[#full + 1] = { 5, r, (r % 2) + 1 } end
    check(T.LandingRow(Board(full), 5) == nil, "a full column takes no more")
    local five = Board({ { 1, 8 }, { 2, 8 }, { 3, 8 }, { 4, 8 }, { 5, 8 } })
    check(T.WinningLine(five, 5, 8) == nil, "five in a row is not a win")
    local six = Board({ { 2, 8 }, { 3, 8 }, { 4, 8 }, { 5, 8 }, { 6, 8 }, { 7, 8 } })
    check(T.WinningLine(six, 4, 8) ~= nil, "six across wins")
    local vert = Board({ { 9, 3 }, { 9, 4 }, { 9, 5 }, { 9, 6 }, { 9, 7 }, { 9, 8 } })
    check(T.WinningLine(vert, 9, 3) ~= nil, "six up-and-down wins")
    local diag = Board({ { 1, 8 }, { 2, 7 }, { 3, 6 }, { 4, 5 }, { 5, 4 }, { 6, 3 } })
    check(T.WinningLine(diag, 3, 6) ~= nil, "six diagonally wins")
    local broken = Board({ { 1, 8 }, { 2, 8 }, { 3, 8, 2 }, { 4, 8 }, { 5, 8 }, { 6, 8 }, { 7, 8 } })
    check(T.WinningLine(broken, 7, 8) == nil, "an enemy checker breaks the line")
    -- Bot: take a win, and block one.
    local canWin = Board({ { 1, 8, 2 }, { 2, 8, 2 }, { 3, 8, 2 }, { 4, 8, 2 }, { 5, 8, 2 }, { 1, 7 }, { 2, 7 } })
    check(T.BestColumn(canWin, 2) == 6, "bot drops the winning checker")
    local mustBlock = Board({ { 2, 8 }, { 3, 8 }, { 4, 8 }, { 5, 8 }, { 6, 8 }, { 9, 8, 2 } })
    local blocked = T.BestColumn(mustBlock, 2)
    check(blocked == 1 or blocked == 7, "bot blocks a five (picked column " .. tostring(blocked) .. ")")
end

print("\n== Networked game")
local s
do
    s = A.Lobby:CreateHosted("connect6")
    A.Lobby:Invite(s, "Bob")
    Sim.Advance(1)
    B.Lobby:AcceptInvite(s.id)
    Sim.Advance(2)
    check(s.status == "playing" and B.Lobby.active and B.Lobby.active.status == "playing", "game started on both clients")
    check(bob.loaded.GoblinGames_Connect6, "Bob loaded Connect 6 on demand")
    NoErrors(alice, bob)
end

local function Who(name) return name == "Alice-TestRealm" and A or B end
local function Drop(col)
    local cur = A.Turns:Current(s)
    Who(cur).Lobby.active:SendAction("DROP", col)
    Sim.Advance(0.4)
    return cur
end

local first, second
print("\n== One checker per turn, gravity, rejected moves")
do
    first = Drop(5)
    second = A.Turns:Current(s)
    check(second ~= first, "turn passes after one checker")
    check(s.data.board[Idx(5, ROWS)] ~= 0, "the checker landed on the bottom row")
    Who(first).Lobby.active:SendAction("DROP", 1)
    Sim.Advance(0.4)
    check(s.data.board[Idx(1, ROWS)] == 0, "out-of-turn drop rejected")
    Who(second).Lobby.active:SendAction("DROP", 0)
    Who(second).Lobby.active:SendAction("DROP", 10)
    Who(second).Lobby.active:SendAction("DROP", 2.5)
    Sim.Advance(0.4)
    check(A.Turns:Current(s) == second, "invalid columns rejected (still their turn)")
    Drop(5)
    check(s.data.board[Idx(5, ROWS - 1)] ~= 0, "second checker in the same column stacks on top")
    local bs = B.Lobby.active
    local same = true
    for i = 1, COLS * ROWS do if bs.data.board[i] ~= s.data.board[i] then same = false end end
    check(same, "racks identical on both clients")
    check(bs.data.lastMove == s.data.lastMove, "last move known on both clients (for the glow)")
    NoErrors(alice, bob)
end

print("\n== Resync after a dropped message")
do
    local dropped = false
    Sim.dropFilter = function(_, to, text)
        if not dropped and to == bob and text:find("%^S%^") then dropped = true; return true end
    end
    Drop(1)               -- first player (dropped for Bob)
    Sim.dropFilter = nil
    Drop(9)               -- second player: Bob notices the gap and resyncs
    Sim.Advance(2)
    local bs = B.Lobby.active
    local same = true
    for i = 1, COLS * ROWS do if bs.data.board[i] ~= s.data.board[i] then same = false end end
    check(dropped, "a message was dropped")
    check(same, "Bob's rack restored from the snapshot")
    check(bs.seq == s.seq, "sequence numbers back in step")
    NoErrors(alice, bob)
end

print("\n== Six in a row wins")
do
    -- First player has 5 (bottom) and 1 (bottom). Second has 5 (row 7) and 9.
    -- First builds the bottom row: 2, 3, 4, 6 -> 1..6 = six.
    -- Second plays column 8 each time, stacking harmlessly.
    Drop(2); Drop(8)
    Drop(3); Drop(8)
    Drop(4); Drop(8)
    Drop(6)
    local bs = B.Lobby.active
    check(s.status == "ended" and bs.status == "ended", "game over on both clients")
    check(s.result.winners[1] == first and bs.result.winners[1] == first, "the right player won")
    check(bs.data.winLine and #bs.data.winLine >= 6, "winning line found for the glow")
    check((first == "Alice-TestRealm" and A or B).Stats:Get("connect6").wins == 1, "win recorded")
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
    while p.status == "playing" and guard < 200 do
        guard = guard + 1
        if A.Turns:IsMyTurn(p) then
            for _ = 1, 30 do
                local col = math.random(1, COLS)
                if T.LandingRow(p.data.board, col) then p:SendAction("DROP", col); break end
            end
        end
        Sim.Advance(0.5)
    end
    check(p.status == "ended", "practice game finished (" .. guard .. " steps)")
    check(p.result.outcome == "loss" or p.result.outcome == "draw", "the bot doesn't lose to random drops (" .. tostring(p.result.outcome) .. ")")
    check(alice.sent == sentBefore, "practice sends nothing over the network")
    NoErrors(alice)
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
