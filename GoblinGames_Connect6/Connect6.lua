--[[----------------------------------------------------------------------------
  GoblinGames_Connect6/Connect6.lua

  Connect 6 (Connect6 / "Liuziqi"), played on the lines of a 19x19 board.

  RULES
    - The first player places ONE stone. After that, every turn is TWO stones.
    - Six or more of your stones in a row (across, down or diagonal) wins.
    - A full board with no winner is a draw.
  The one-then-two opening keeps it fair: each player is always one stone
  ahead of or level with the other after their turn.

  HOW IT FOLLOWS THE MODULE PATTERN (see docs/MODULE_API.md)
    - Each stone is one action: session:SendAction("PLACE", x, y).
    - The host checks it, then Broadcasts "SET" (the stone) and, when the
      player has used up their stones, "NEXT" + GG.Turns:Advance().
    - Every client applies SET / NEXT in OnState, so all boards stay identical.
    - "SNAP" is the whole game (sent when a player missed messages).

  PIECES: stones take the colour of their owner's faction (Horde red,
  Alliance blue, goblin green for neutral), with a gold rim for the first seat
  and silver for the second, so two players of the same faction still differ.
------------------------------------------------------------------------------]]

local GG = GoblinGames
local Util = GG.Util
local UI = GG.UI

local N = 19            -- board size (lines)
local NEED = 6          -- stones in a row to win

local Game = {
    id = "connect6",
    hint = "Click where the lines cross. Six in a row wins!",
    compactHeader = true,   -- ask the core for the big-board layout
}

local DIRS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }

-------------------------------------------------------------------------------
-- Rules (pure functions)
-------------------------------------------------------------------------------
local function Idx(x, y) return (y - 1) * N + x end
local function XY(i) return (i - 1) % N + 1, math.floor((i - 1) / N) + 1 end
local function OnBoard(x, y) return x >= 1 and x <= N and y >= 1 and y <= N end

local function EmptyBoard()
    local b = {}
    for i = 1, N * N do b[i] = 0 end
    return b
end

--- The winning line through (x, y) if that stone completes six or more, else nil.
local function WinningLine(board, x, y)
    local seat = board[Idx(x, y)]
    if seat == 0 then return nil end
    for _, d in ipairs(DIRS) do
        local line = { Idx(x, y) }
        for sign = -1, 1, 2 do
            local cx, cy = x + d[1] * sign, y + d[2] * sign
            while OnBoard(cx, cy) and board[Idx(cx, cy)] == seat do
                line[#line + 1] = Idx(cx, cy)
                cx, cy = cx + d[1] * sign, cy + d[2] * sign
            end
        end
        if #line >= NEED then return line end
    end
    return nil
end

local function BoardToString(board) return table.concat(board) end
local function BoardFromString(text)
    local b = EmptyBoard()
    for i = 1, N * N do b[i] = tonumber(text:sub(i, i)) or 0 end
    return b
end

local function ListToString(list) return table.concat(list, ",") end
local function ListFromString(text)
    local list = {}
    for v in (text or ""):gmatch("%d+") do list[#list + 1] = tonumber(v) end
    return list
end

-------------------------------------------------------------------------------
-- Board UI
-------------------------------------------------------------------------------
local SPACING = 18                     -- pixels between lines
local MARGIN = 16                      -- wood border around the grid
local BOARD_PX = (N - 1) * SPACING + 2 * MARGIN

local FACTION_STONE = {
    Horde    = { 0.85, 0.22, 0.16 },
    Alliance = { 0.28, 0.50, 1.00 },
    Neutral  = { 0.40, 0.78, 0.28 },
}
local RIM = { { 1.00, 0.80, 0.25 }, { 0.80, 0.84, 0.92 } }

local boardFrame, cells, side
local current

local function StoneColor(session, seat)
    local faction = session:GetFaction(session.players[seat])
    local c = FACTION_STONE[faction] or FACTION_STONE.Neutral
    -- Same faction on both sides: darken the second player's stones.
    local other = session:GetFaction(session.players[seat == 1 and 2 or 1])
    if seat == 2 and other == faction then
        return { c[1] * 0.55, c[2] * 0.55, c[3] * 0.55 }
    end
    return c
end

local function OnCellClick(cell)
    local s = current
    if not s or s.status ~= "playing" then return end
    if not GG.Turns:IsMyTurn(s) or s.data.board[cell.index] ~= 0 or s.data.stonesLeft <= 0 then
        cell.shake:Play()
        return
    end
    local x, y = XY(cell.index)
    s:SendAction("PLACE", x, y)
end

local function BuildBoard()
    local area = UI:GetGameArea()
    boardFrame = CreateFrame("Frame", nil, area)
    boardFrame:SetSize(BOARD_PX, BOARD_PX)
    boardFrame:SetPoint("TOPLEFT", 4, -2)

    -- Wood, tiled, with a dark edge.
    local wood = boardFrame:CreateTexture(nil, "BACKGROUND")
    wood:SetTexture(UI.MEDIA .. "BoardWood", "REPEAT", "REPEAT")
    wood:SetHorizTile(true)
    wood:SetVertTile(true)
    wood:SetAllPoints()
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                            { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = boardFrame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.18, 0.10, 0.04, 1)
        t:SetPoint(edge[1]); t:SetPoint(edge[2])
        if edge[3] then t:SetHeight(3) else t:SetWidth(3) end
    end

    -- Grid lines.
    local span = (N - 1) * SPACING
    for i = 0, N - 1 do
        local h = boardFrame:CreateTexture(nil, "BORDER", nil, 1)
        h:SetColorTexture(0.22, 0.13, 0.05, 0.85)
        h:SetSize(span + 1, 1)
        h:SetPoint("TOPLEFT", MARGIN, -(MARGIN + i * SPACING))
        local v = boardFrame:CreateTexture(nil, "BORDER", nil, 1)
        v:SetColorTexture(0.22, 0.13, 0.05, 0.85)
        v:SetSize(1, span + 1)
        v:SetPoint("TOPLEFT", MARGIN + i * SPACING, -MARGIN)
    end
    -- Star points, like a Go board, to help count.
    for _, sx in ipairs({ 4, 10, 16 }) do
        for _, sy in ipairs({ 4, 10, 16 }) do
            local dot = boardFrame:CreateTexture(nil, "BORDER", nil, 2)
            dot:SetTexture(UI.MEDIA .. "Stone")
            dot:SetVertexColor(0.2, 0.12, 0.05)
            dot:SetSize(6, 6)
            dot:SetPoint("CENTER", boardFrame, "TOPLEFT", MARGIN + (sx - 1) * SPACING, -(MARGIN + (sy - 1) * SPACING))
        end
    end

    -- One button per intersection.
    cells = {}
    for i = 1, N * N do
        local x, y = XY(i)
        local cell = CreateFrame("Button", nil, boardFrame)
        cell:SetSize(SPACING, SPACING)
        cell:SetPoint("CENTER", boardFrame, "TOPLEFT", MARGIN + (x - 1) * SPACING, -(MARGIN + (y - 1) * SPACING))
        cell.index = i

        cell.stone = cell:CreateTexture(nil, "ARTWORK")
        cell.stone:SetTexture(UI.MEDIA .. "Stone")
        cell.stone:SetSize(SPACING - 1, SPACING - 1)
        cell.stone:SetPoint("CENTER")
        cell.stone:Hide()
        UI.AddPopIn(cell.stone)

        cell.rim = cell:CreateTexture(nil, "ARTWORK", nil, 1)
        cell.rim:SetTexture(UI.MEDIA .. "StoneRim")
        cell.rim:SetAllPoints(cell.stone)
        cell.rim:Hide()

        -- Marks the stones placed in the latest turn, and the winning line.
        cell.mark = cell:CreateTexture(nil, "OVERLAY")
        cell.mark:SetTexture(UI.MEDIA .. "ButtonGlow")
        cell.mark:SetPoint("CENTER")
        cell.mark:SetSize(SPACING + 10, SPACING + 10)
        cell.mark:SetBlendMode("ADD")
        cell.mark:Hide()
        UI.AddPulse(cell.mark, 0.25, 0.5)

        -- Ghost stone under the mouse when it's your turn.
        cell.ghost = cell:CreateTexture(nil, "HIGHLIGHT")
        cell.ghost:SetTexture(UI.MEDIA .. "Stone")
        cell.ghost:SetSize(SPACING - 1, SPACING - 1)
        cell.ghost:SetPoint("CENTER")

        local shake = cell:CreateAnimationGroup()
        for n, dx in ipairs({ 3, -6, 5, -2 }) do
            local t = shake:CreateAnimation("Translation")
            t:SetOffset(dx, 0)
            t:SetDuration(0.04)
            t:SetOrder(n)
        end
        cell.shake = shake

        cell:SetScript("OnClick", OnCellClick)
        cells[i] = cell
    end

    -- Side card: players, stones left this turn, rules.
    side = UI.Card(area)
    side:SetPoint("TOPLEFT", boardFrame, "TOPRIGHT", 14, 0)
    side:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
    local title = UI.Text(side, "Connect 6", { fancy = true, size = 22, ink = true })
    title:SetPoint("TOPLEFT", 16, -14)

    side.rows = {}
    for seat = 1, 2 do
        local row = CreateFrame("Frame", nil, side)
        row:SetSize(280, 40)
        row:SetPoint("TOPLEFT", 14, -46 - (seat - 1) * 44)
        row.stone = row:CreateTexture(nil, "ARTWORK")
        row.stone:SetTexture(UI.MEDIA .. "Stone")
        row.stone:SetSize(26, 26)
        row.stone:SetPoint("LEFT", 2, 0)
        row.rim = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.rim:SetTexture(UI.MEDIA .. "StoneRim")
        row.rim:SetAllPoints(row.stone)
        row.crest = row:CreateTexture(nil, "ARTWORK")
        row.crest:SetSize(22, 22)
        row.crest:SetPoint("LEFT", row.stone, "RIGHT", 6, 0)
        row.name = UI.Text(row, "", { ink = true })
        row.name:SetPoint("TOPLEFT", row.crest, "TOPRIGHT", 6, 2)
        row.sub = UI.Text(row, "", { ink = true, font = "GameFontHighlightSmall" })
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
        row.arrow = row:CreateTexture(nil, "OVERLAY")
        row.arrow:SetTexture(UI.MEDIA .. "ButtonGlow")
        row.arrow:SetPoint("TOPLEFT", -8, 6)
        row.arrow:SetPoint("BOTTOMRIGHT", 8, -6)
        row.arrow:SetBlendMode("ADD")
        row.arrow:SetVertexColor(1, 0.75, 0.2)
        UI.AddPulse(row.arrow, 0.3, 0.6)
        side.rows[seat] = row
    end

    side.pips = {}
    local pipLabel = UI.Text(side, "Stones this turn:", { ink = true })
    pipLabel:SetPoint("TOPLEFT", 18, -150)
    side.pipLabel = pipLabel
    for i = 1, 2 do
        local pip = side:CreateTexture(nil, "ARTWORK")
        pip:SetTexture(UI.MEDIA .. "Stone")
        pip:SetSize(22, 22)
        pip:SetPoint("LEFT", pipLabel, "RIGHT", 6 + (i - 1) * 26, 0)
        side.pips[i] = pip
    end

    local rules = UI.Text(side,
        "First move: 1 stone.\nEvery turn after: 2 stones.\nSix or more in a row wins.\n\nGlowing stones were the last turn's moves.",
        { ink = true, font = "GameFontHighlightSmall" })
    rules:SetPoint("TOPLEFT", 18, -184)
    rules:SetWidth(280)
    rules:SetTextColor(0.40, 0.30, 0.18)
end

local function Refresh()
    local s = current
    if not s or not boardFrame then return end
    local d = s.data
    local board = d.board
    local myTurn = GG.Turns:IsMyTurn(s)

    -- Which stones to mark: the winning line if the game is over, else the
    -- stones of the latest turn (or the current turn's, once it has started).
    local marked = {}
    if d.winLine then
        for _, i in ipairs(d.winLine) do marked[i] = true end
    else
        local list = (#d.turnStones > 0) and d.turnStones or d.lastStones
        for _, i in ipairs(list) do marked[i] = true end
    end

    local mySeat = s:SeatOf(s:Me())
    local ghost = mySeat and StoneColor(s, mySeat)

    for i, cell in ipairs(cells) do
        local seat = board[i]
        if seat ~= 0 then
            local c = StoneColor(s, seat)
            cell.stone:SetVertexColor(c[1], c[2], c[3])
            local r = RIM[seat]
            cell.rim:SetVertexColor(r[1], r[2], r[3])
            if not cell.stone:IsShown() then
                cell.stone:Show()
                cell.stone.popIn:Play()
            end
            cell.rim:Show()
        else
            cell.stone:Hide()
            cell.rim:Hide()
        end
        if marked[i] then
            cell.mark:SetVertexColor(d.winLine and 1 or 1, d.winLine and 0.85 or 1, d.winLine and 0.3 or 0.8)
            cell.mark:Show()
            cell.mark.pulse:Play()
        else
            cell.mark:Hide()
        end
        if ghost and myTurn and seat == 0 then
            cell.ghost:SetVertexColor(ghost[1], ghost[2], ghost[3], 0.55)
            cell.ghost:SetAlpha(0.55)
        else
            cell.ghost:SetAlpha(0)
        end
    end

    -- Side card.
    local currentPlayer = GG.Turns:Current(s)
    for seat, row in ipairs(side.rows) do
        local name = s.players[seat]
        local c = StoneColor(s, seat)
        row.stone:SetVertexColor(c[1], c[2], c[3])
        local r = RIM[seat]
        row.rim:SetVertexColor(r[1], r[2], r[3])
        GG.Theme:SetCrest(row.crest, s:GetFaction(name))
        row.name:SetText(Util.ShortName(name) .. (Util.IsMe(name) and " (you)" or ""))
        local count = 0
        for i = 1, N * N do if board[i] == seat then count = count + 1 end end
        row.sub:SetText(count .. " stones on the board")
        local active = s.status == "playing" and name == currentPlayer
        row.arrow:SetShown(active)
        if active then row.arrow.pulse:Play() end
    end

    local left = (s.status == "playing") and d.stonesLeft or 0
    for i, pip in ipairs(side.pips) do
        local seat = currentPlayer and s:SeatOf(currentPlayer)
        local c = seat and StoneColor(s, seat) or { 0.5, 0.5, 0.5 }
        pip:SetVertexColor(c[1], c[2], c[3])
        pip:SetShown(i <= left)
    end
    side.pipLabel:SetShown(s.status == "playing")

    if s.status == "playing" and myTurn then
        UI:SetGameStatus(UI.Gold(left == 1 and "Your turn! Place 1 stone" or ("Your turn! Place " .. left .. " stones")))
    else
        UI:SetGameStatus(nil)
    end
end

-------------------------------------------------------------------------------
-- Module callbacks
-------------------------------------------------------------------------------

function Game.OnSessionStart(session)
    current = session
    local d = session.data
    d.board = EmptyBoard()
    d.count = 0
    d.stonesLeft = 1        -- the very first move is a single stone
    d.turnStones = {}       -- stones placed so far this turn
    d.lastStones = {}       -- stones of the previous turn
    d.winLine = nil
    if not boardFrame then BuildBoard() end
    boardFrame:Show()
    side:Show()
    Refresh()

    if session:IsHost() then
        GG.Turns:Start(session, Util.Shuffle(Util.Copy(session.players)))
    end
end

-- Host: check a stone.
function Game.OnAction(session, sender, op, args)
    if op ~= "PLACE" or session.status ~= "playing" then return end
    local d = session.data
    if GG.Turns:Current(session) ~= sender or d.stonesLeft <= 0 then return end
    local x, y = tonumber(args[1]), tonumber(args[2])
    if not x or not y or x % 1 ~= 0 or y % 1 ~= 0 or not OnBoard(x, y) then return end
    if d.board[Idx(x, y)] ~= 0 then return end

    session:Broadcast("SET", Idx(x, y), session:SeatOf(sender))

    if WinningLine(d.board, x, y) then
        session:End({ winners = { sender } })
    elseif d.count >= N * N then
        session:End({ draw = true })
    elseif d.stonesLeft <= 0 then
        session:Broadcast("NEXT")
        GG.Turns:Advance(session)
    else
        -- Second stone still to place: give a fresh look at the clock.
        GG.Turns:ResetTimer(session)
    end
end

-- Everyone: apply the host's announcements.
function Game.OnState(session, op, args)
    local d = session.data
    if op == "SET" then
        local i, seat = tonumber(args[1]), tonumber(args[2])
        if i and seat and d.board[i] == 0 then
            d.board[i] = seat
            d.count = d.count + 1
            d.stonesLeft = d.stonesLeft - 1
            d.turnStones[#d.turnStones + 1] = i
        end
    elseif op == "NEXT" then
        d.lastStones = d.turnStones
        d.turnStones = {}
        d.stonesLeft = 2
    elseif op == "SNAP" then
        d.board = BoardFromString(args[1] or "")
        d.stonesLeft = tonumber(args[2]) or 2
        d.turnStones = ListFromString(args[3])
        d.lastStones = ListFromString(args[4])
        d.count = 0
        for i = 1, N * N do if d.board[i] ~= 0 then d.count = d.count + 1 end end
    end
    if session == current then Refresh() end
end

function Game.OnSyncRequest(session, player)
    local d = session.data
    session:SendTo(player, "SNAP", BoardToString(d.board), d.stonesLeft,
        ListToString(d.turnStones), ListToString(d.lastStones))
end

function Game.OnSessionEnd(session, result)
    local d = session.data
    local last = d.turnStones[#d.turnStones]
    if last and not result.draw then
        local x, y = XY(last)
        d.winLine = WinningLine(d.board, x, y)
    end
    if session == current then Refresh() end
end

function Game.OnSessionClosed(session)
    if session == current then
        current = nil
        if boardFrame then boardFrame:Hide(); side:Hide() end
    end
end

GG.RegisterCallback(Game, "TURN_CHANGED", function(_, session)
    if session == current then Refresh() end
end)

-------------------------------------------------------------------------------
-- Practice bot
--
-- Looks at every "window" of 6 cells in a row. A window with only our stones
-- is a chance; one with only theirs is a threat. Each empty cell is scored by
-- the windows it belongs to, and the bot takes the best cell, one stone at a
-- time. Simple, but it blocks fours and finishes its own sixes.
-------------------------------------------------------------------------------
local ATTACK = { [0] = 1, 8, 40, 220, 3000, 1000000 }   -- by our stones already in the window
local DEFEND = { [0] = 0, 6, 30, 160, 2500, 500000 }    -- by their stones already in the window

local function ScoreCell(board, x, y, me)
    local score = 0
    for _, d in ipairs(DIRS) do
        for start = -(NEED - 1), 0 do
            local mine, theirs, valid = 0, 0, true
            for k = 0, NEED - 1 do
                local cx, cy = x + d[1] * (start + k), y + d[2] * (start + k)
                if not OnBoard(cx, cy) then valid = false; break end
                local v = board[Idx(cx, cy)]
                if v == me then mine = mine + 1 elseif v ~= 0 then theirs = theirs + 1 end
            end
            if valid then
                if theirs == 0 then score = score + ATTACK[mine]
                elseif mine == 0 then score = score + DEFEND[theirs] end
            end
        end
    end
    return score
end

local function BestCell(board, me)
    local best, bestScore = nil, -1
    local any = false
    for i = 1, N * N do
        if board[i] == 0 then
            local x, y = XY(i)
            -- Only consider cells near existing stones.
            local near = false
            for dy = -2, 2 do
                for dx = -2, 2 do
                    if OnBoard(x + dx, y + dy) and board[Idx(x + dx, y + dy)] ~= 0 then near = true end
                end
            end
            if near then
                any = true
                local sc = ScoreCell(board, x, y, me) + math.random() * 3
                if sc > bestScore then best, bestScore = i, sc end
            end
        end
    end
    if not any then return Idx(10, 10) end
    return best
end

function Game.BotAction(session, bot)
    local d = session.data
    if session.status ~= "playing" or GG.Turns:Current(session) ~= bot or d.stonesLeft <= 0 then return end
    local i = BestCell(d.board, session:SeatOf(bot))
    if not i then return end
    local x, y = XY(i)
    session:ActAs(bot, "PLACE", x, y)
    -- Second stone of the turn, after a short "thinking" pause.
    if session.status == "playing" and GG.Turns:Current(session) == bot and d.stonesLeft > 0 then
        C_Timer.After(0.7, function() Game.BotAction(session, bot) end)
    end
end

-- Exposed for the test suite (tools/wowsim). Not part of the module API.
Game._test = { WinningLine = WinningLine, Idx = Idx, XY = XY, BestCell = BestCell, N = N }

GG:RegisterGame(Game)
