--[[----------------------------------------------------------------------------
  GoblinGames_TicTacToe/TicTacToe.lua

  Tic-Tac-Toe, and the reference example of a GoblinGames module.
  Read this alongside docs/MODULE_API.md: every module follows this shape.

    1. Describe the game in a table (`Game`) with callback functions.
    2. Keep all game state in session.data.
    3. Host side:   OnAction checks a move  -> session:Broadcast(...) the result.
    4. Every side:  OnState applies a broadcast -> redraw.
    5. Register:    GoblinGames:RegisterGame(Game)

  Pieces are faction crests. Each mark shows the crest of the player who
  placed it ("mixed" mode). If both players share a faction, the coloured ring
  tells them apart: gold for seat 1, silver for seat 2.
------------------------------------------------------------------------------]]

local GG = GoblinGames          -- the core's public API (a global set by GoblinGames)
local Util = GG.Util
local UI = GG.UI

local Game = { id = "tictactoe" }

local LINES = {
    { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },   -- rows
    { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },   -- columns
    { 1, 5, 9 }, { 3, 5, 7 },                -- diagonals
}

local SEAT_COLORS = {
    { 1.00, 0.82, 0.20 },  -- seat 1: gold
    { 0.75, 0.80, 0.90 },  -- seat 2: silver
}

-------------------------------------------------------------------------------
-- Rules (pure functions, no UI, no network: easy to reason about)
-------------------------------------------------------------------------------

--- Returns the winning seat and line, "draw", or nil if the game goes on.
local function Evaluate(board)
    for _, line in ipairs(LINES) do
        local a, b, c = board[line[1]], board[line[2]], board[line[3]]
        if a ~= 0 and a == b and b == c then return a, line end
    end
    for i = 1, 9 do
        if board[i] == 0 then return nil end
    end
    return "draw"
end

local function EmptyBoard()
    return { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
end

local function BoardToString(board)
    return table.concat(board)
end

local function BoardFromString(text)
    local board = EmptyBoard()
    for i = 1, 9 do board[i] = tonumber(text:sub(i, i)) or 0 end
    return board
end

-------------------------------------------------------------------------------
-- Board UI
-------------------------------------------------------------------------------
local CELL = 96
local boardFrame, cells, legend
local current -- the session the board is showing

local function OnCellClick(cell)
    local s = current
    if not s or s.status ~= "playing" then return end
    if not GG.Turns:IsMyTurn(s) or s.data.board[cell.index] ~= 0 then return end
    s:SendAction("MOVE", cell.index)
end

local function BuildBoard()
    local area = UI:GetGameArea()
    boardFrame = CreateFrame("Frame", nil, area)
    boardFrame:SetSize(CELL * 3 + 16, CELL * 3 + 16)
    boardFrame:SetPoint("TOP", 0, -4)

    cells = {}
    for i = 1, 9 do
        local cell = CreateFrame("Button", nil, boardFrame, UI.BACKDROP)
        cell:SetSize(CELL, CELL)
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        cell:SetPoint("TOPLEFT", 4 + col * (CELL + 4), -4 - row * (CELL + 4))
        cell.index = i
        GG.Theme:ApplyFrame(cell, "tile")

        cell.crest = cell:CreateTexture(nil, "ARTWORK")
        cell.crest:SetSize(CELL - 24, CELL - 24)
        cell.crest:SetPoint("CENTER")

        cell.glow = cell:CreateTexture(nil, "OVERLAY")
        cell.glow:SetAllPoints()
        cell.glow:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight")
        cell.glow:SetBlendMode("ADD")
        cell.glow:Hide()

        cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        cell:SetScript("OnClick", OnCellClick)
        cells[i] = cell
    end

    legend = UI.Label(area, "", "GameFontHighlightSmall")
    legend:SetPoint("TOP", boardFrame, "BOTTOM", 0, -6)
    legend:SetJustifyH("CENTER")
end

local function Refresh()
    local s = current
    if not s or not boardFrame then return end
    local board = s.data.board
    local winSeat, winLine = Evaluate(board)
    local glowing = {}
    if type(winSeat) == "number" then
        for _, idx in ipairs(winLine) do glowing[idx] = true end
    end
    local myTurn = GG.Turns:IsMyTurn(s)

    for i, cell in ipairs(cells) do
        local seat = board[i]
        if seat ~= 0 then
            GG.Theme:SetCrest(cell.crest, s:GetFaction(s.players[seat]))
            cell.crest:Show()
            local c = SEAT_COLORS[seat]
            cell:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        else
            cell.crest:Hide()
            GG.Theme:ApplyFrame(cell, "tile")
        end
        cell.glow:SetShown(glowing[i] == true)
        -- Only show the hover highlight on cells you can actually play.
        cell:GetHighlightTexture():SetAlpha((myTurn and seat == 0) and 1 or 0)
    end

    local parts = {}
    for seat, name in ipairs(s.players) do
        local hex = seat == 1 and "ffd133" or "c0ccE6"
        parts[#parts + 1] = UI.Color((seat == 1 and "Gold" or "Silver") .. " ring: ", hex) .. Util.ShortName(name)
    end
    legend:SetText(table.concat(parts, "     "))
end

-------------------------------------------------------------------------------
-- Module callbacks (see docs/MODULE_API.md)
-------------------------------------------------------------------------------

-- Everyone: the game just started. Build or reset the board.
function Game.OnSessionStart(session)
    current = session
    session.data.board = EmptyBoard()
    if not boardFrame then BuildBoard() end
    boardFrame:Show()
    legend:Show()
    Refresh()

    -- Host: pick who goes first, at random, and start the clock.
    if session:IsHost() then
        local order = Util.Shuffle(Util.Copy(session.players))
        GG.Turns:Start(session, order)
    end
end

-- Host only: a player (or the practice bot) wants to make a move. Check it.
function Game.OnAction(session, sender, op, args)
    if op ~= "MOVE" or session.status ~= "playing" then return end
    if GG.Turns:Current(session) ~= sender then return end           -- not their turn
    local cell = tonumber(args[1])
    if not cell or cell < 1 or cell > 9 or cell % 1 ~= 0 then return end
    if session.data.board[cell] ~= 0 then return end                  -- taken

    -- Legal: tell everyone (this also applies it on our own board).
    session:Broadcast("SET", cell, session:SeatOf(sender))

    local result = Evaluate(session.data.board)
    if result == "draw" then
        session:End({ draw = true })
    elseif result then
        session:End({ winners = { session.players[result] } })
    else
        GG.Turns:Advance(session)
    end
end

-- Everyone: the host announced a change.
function Game.OnState(session, op, args)
    if op == "SET" then
        local cell, seat = tonumber(args[1]), tonumber(args[2])
        if cell and seat then session.data.board[cell] = seat end
    elseif op == "SNAP" then
        session.data.board = BoardFromString(args[1] or "")
    end
    if session == current then Refresh() end
end

-- Host only: a player missed messages; send them the whole board.
function Game.OnSyncRequest(session, player)
    session:SendTo(player, "SNAP", BoardToString(session.data.board))
end

function Game.OnSessionEnd(session)
    if session == current then Refresh() end
end

function Game.OnSessionClosed(session)
    if session == current then
        current = nil
        if boardFrame then boardFrame:Hide(); legend:Hide() end
    end
end

-- Redraw on turn changes (the hover highlight depends on whose turn it is).
GG.RegisterCallback(Game, "TURN_CHANGED", function(_, session)
    if session == current then Refresh() end
end)

-------------------------------------------------------------------------------
-- Practice bot: win if it can, block if it must, else centre, corner, edge.
-------------------------------------------------------------------------------
local function FindLineFinisher(board, seat)
    for _, line in ipairs(LINES) do
        local mine, empty = 0, nil
        for _, idx in ipairs(line) do
            if board[idx] == seat then mine = mine + 1
            elseif board[idx] == 0 then empty = idx end
        end
        if mine == 2 and empty then return empty end
    end
end

function Game.BotAction(session, bot)
    local board = session.data.board
    local mySeat = session:SeatOf(bot)
    local theirSeat = (mySeat == 1) and 2 or 1
    -- A little mercy: 1 time in 4 the dummy doesn't notice your threat.
    local choice = FindLineFinisher(board, mySeat)
        or (math.random(4) > 1 and FindLineFinisher(board, theirSeat))
    if not choice and board[5] == 0 then choice = 5 end
    if not choice then
        local options = {}
        for _, idx in ipairs({ 1, 3, 7, 9 }) do if board[idx] == 0 then options[#options + 1] = idx end end
        if #options == 0 then
            for idx = 1, 9 do if board[idx] == 0 then options[#options + 1] = idx end end
        end
        choice = options[math.random(#options)]
    end
    if choice then session:ActAs(bot, "MOVE", choice) end
end

GG:RegisterGame(Game)
