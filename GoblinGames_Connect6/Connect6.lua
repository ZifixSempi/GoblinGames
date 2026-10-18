--[[----------------------------------------------------------------------------
  GoblinGames_Connect6/Connect6.lua

  Connect 6, the "vertical checkers game": drop checkers into a standing rack
  (like the classic Connect Six box game, and Connect Four's big brother).

  RULES
    - Players take turns dropping ONE checker into a column. It falls to the
      lowest empty hole.
    - Six or more of your checkers in a row (across, up-down or diagonal) wins.
    - A full rack with no winner is a draw.
  The rack is COLS x ROWS (9 x 8): wide enough for six in every direction.

  HOW IT FOLLOWS THE MODULE PATTERN (see docs/MODULE_API.md)
    - A move is one action: session:SendAction("DROP", column).
    - The host checks it, works out where the checker lands, and Broadcasts
      "SET" (hole index + seat). Every client applies it in OnState.
    - "SNAP" is the whole rack (sent when a player missed messages).

  PIECES: poker chips. Horde chips are red with the Horde crest, Alliance
  chips blue with the Alliance crest (neutral: goblin green). A gold rim marks
  the first seat and silver the second; same-faction opponents get a darker
  shade, so the two players can always be told apart.

  ART: the rack is one small tile (a square of golden panel with a round hole)
  repeated across the board. The checkers are drawn BEHIND the panel, so they
  show through the holes, and they "fall" into place with a Translation
  animation.
------------------------------------------------------------------------------]]

local GG = GoblinGames
local Util = GG.Util
local UI = GG.UI

local COLS, ROWS = 9, 8
local NEED = 6

local Game = {
    id = "connect6",
    hint = "Click a column to drop a chip. Six in a row wins!",
    compactHeader = true,   -- ask the core for the big-board layout
}

local DIRS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }

-------------------------------------------------------------------------------
-- Rules (pure functions). Row 1 is the TOP of the rack, ROWS is the bottom.
-------------------------------------------------------------------------------
local function Idx(col, row) return (row - 1) * COLS + col end
local function ColRow(i) return (i - 1) % COLS + 1, math.floor((i - 1) / COLS) + 1 end
local function OnBoard(col, row) return col >= 1 and col <= COLS and row >= 1 and row <= ROWS end

local function EmptyBoard()
    local b = {}
    for i = 1, COLS * ROWS do b[i] = 0 end
    return b
end

--- The row a checker dropped in `col` lands in, or nil if the column is full.
local function LandingRow(board, col)
    for row = ROWS, 1, -1 do
        if board[Idx(col, row)] == 0 then return row end
    end
    return nil
end

--- The winning line through (col, row) if that checker makes six or more, else nil.
local function WinningLine(board, col, row)
    local seat = board[Idx(col, row)]
    if seat == 0 then return nil end
    for _, d in ipairs(DIRS) do
        local line = { Idx(col, row) }
        for sign = -1, 1, 2 do
            local c, r = col + d[1] * sign, row + d[2] * sign
            while OnBoard(c, r) and board[Idx(c, r)] == seat do
                line[#line + 1] = Idx(c, r)
                c, r = c + d[1] * sign, r + d[2] * sign
            end
        end
        if #line >= NEED then return line end
    end
    return nil
end

local function IsFull(board)
    for col = 1, COLS do
        if board[Idx(col, 1)] == 0 then return false end
    end
    return true
end

local function BoardToString(board) return table.concat(board) end
local function BoardFromString(text)
    local b = EmptyBoard()
    for i = 1, COLS * ROWS do b[i] = tonumber(text:sub(i, i)) or 0 end
    return b
end

-------------------------------------------------------------------------------
-- Rack UI
-------------------------------------------------------------------------------
local CELL = 38             -- size of one hole tile
local PAD = 8               -- frame around the holes
local RACK_W = COLS * CELL + 2 * PAD
local RACK_H = ROWS * CELL + 2 * PAD

local FACTION_COLOR = {
    Horde    = { 0.86, 0.20, 0.14 },
    Alliance = { 0.24, 0.46, 1.00 },
    Neutral  = { 0.38, 0.76, 0.26 },
}
local RIM = { { 1.00, 0.80, 0.25 }, { 0.80, 0.84, 0.92 } }

local rack, holes, columns, side
local current
local hoverCol

local function CheckerColor(session, seat)
    local faction = session:GetFaction(session.players[seat])
    local c = FACTION_COLOR[faction] or FACTION_COLOR.Neutral
    local other = session:GetFaction(session.players[seat == 1 and 2 or 1])
    if seat == 2 and other == faction then
        return { c[1] * 0.5, c[2] * 0.5, c[3] * 0.5 }
    end
    return c
end

local Refresh -- defined below

--- A chip: tinted base + white edge notches + faction crest + seat rim.
--- All four are textures on `parent`, in the given draw layer, stacked with
--- sublevels. Using draw layers (not separate frames) makes the stacking
--- order fixed: WoW can renumber frame levels, but never reorders layers.
local function MakeChip(parent, size, layer)
    layer = layer or "ARTWORK"
    local chip = { parts = {} }
    local function Part(sub, file)
        local t = parent:CreateTexture(nil, layer, nil, sub)
        if file then t:SetTexture(UI.MEDIA .. file) end
        chip.parts[#chip.parts + 1] = t
        return t
    end
    chip.base = Part(0, "Chip")
    chip.base:SetSize(size, size)
    chip.notches = Part(1, "ChipNotches")
    chip.notches:SetAllPoints(chip.base)
    chip.crest = Part(2)
    chip.crest:SetSize(size * 0.52, size * 0.52)
    chip.crest:SetPoint("CENTER", chip.base, "CENTER")
    chip.rim = Part(3, "StoneRim")
    chip.rim:SetAllPoints(chip.base)
    function chip:SetPoint(...) self.base:ClearAllPoints(); self.base:SetPoint(...) end
    function chip:ClearAllPoints() self.base:ClearAllPoints() end
    function chip:Show() for _, t in ipairs(self.parts) do t:Show() end end
    function chip:Hide() for _, t in ipairs(self.parts) do t:Hide() end end
    function chip:IsShown() return self.base:IsShown() end
    function chip:SetAlpha(a) for _, t in ipairs(self.parts) do t:SetAlpha(a) end end
    -- Falling animation: every layer gets the same jump-up-then-drop.
    chip.falls = {}
    for _, t in ipairs(chip.parts) do
        local g = t:CreateAnimationGroup()
        local up = g:CreateAnimation("Translation")
        up:SetDuration(0.001)
        up:SetOrder(1)
        local down = g:CreateAnimation("Translation")
        down:SetSmoothing("IN")
        down:SetOrder(2)
        chip.falls[#chip.falls + 1] = { group = g, up = up, down = down }
    end
    function chip:Fall(distance, seconds)
        for _, f in ipairs(self.falls) do
            f.up:SetOffset(0, distance)
            f.down:SetOffset(0, -distance)
            f.down:SetDuration(seconds)
            f.group:Stop()
            f.group:Play()
        end
    end
    return chip
end

local function PaintChip(chip, session, seat)
    local c = CheckerColor(session, seat)
    chip.base:SetVertexColor(c[1], c[2], c[3])
    GG.Theme:SetCrest(chip.crest, session:GetFaction(session.players[seat]))
    local r = RIM[seat]
    chip.rim:SetVertexColor(r[1], r[2], r[3])
end

local function OnColumnClick(colButton)
    local s = current
    if not s or s.status ~= "playing" then return end
    if not GG.Turns:IsMyTurn(s) or not LandingRow(s.data.board, colButton.col) then
        colButton.shake:Play()
        return
    end
    s:SendAction("DROP", colButton.col)
end

local function BuildRack()
    local area = UI:GetGameArea()

    rack = CreateFrame("Frame", nil, area)
    rack:SetSize(RACK_W, RACK_H)
    rack:SetPoint("TOPLEFT", 14, -2)

    -- Dark inside of the rack: what you see through an empty hole.
    local back = rack:CreateTexture(nil, "BACKGROUND", nil, -6)
    back:SetColorTexture(0.06, 0.05, 0.08, 1)
    back:SetPoint("TOPLEFT", PAD, -PAD)
    back:SetPoint("BOTTOMRIGHT", -PAD, PAD)

    -- Everything is drawn on the rack frame itself, stacked by draw layer:
    --   BACKGROUND  the dark inside of the rack
    --   BORDER      the chips (behind the panel, seen through the holes)
    --   ARTWORK     the golden panel with its holes
    --   OVERLAY     glows for the last move / winning line
    local panel = rack

    -- The golden panel: one hole tile per cell, plus a solid rim around it.
    holes = {}
    for i = 1, COLS * ROWS do
        local col, row = ColRow(i)
        local x, y = PAD + (col - 1) * CELL, -(PAD + (row - 1) * CELL)

        local tile = panel:CreateTexture(nil, "ARTWORK")
        tile:SetTexture(UI.MEDIA .. "RackHole")
        tile:SetSize(CELL, CELL)
        tile:SetPoint("TOPLEFT", x, y)

        local h = {}
        h.chip = MakeChip(rack, CELL - 6, "BORDER")
        h.chip:SetPoint("CENTER", rack, "TOPLEFT", x + CELL / 2, y - CELL / 2)
        h.chip:Hide()

        -- Glow for the last move and the winning line (on top of the panel).
        h.mark = panel:CreateTexture(nil, "OVERLAY")
        h.mark:SetTexture(UI.MEDIA .. "ButtonGlow")
        h.mark:SetSize(CELL + 8, CELL + 8)
        h.mark:SetPoint("CENTER", rack, "TOPLEFT", x + CELL / 2, y - CELL / 2)
        h.mark:SetBlendMode("ADD")
        h.mark:Hide()
        UI.AddPulse(h.mark, 0.25, 0.5)

        holes[i] = h
    end
    -- Solid golden frame around the holes.
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", PAD, true }, { "BOTTOMLEFT", "BOTTOMRIGHT", PAD, true },
                         { "TOPLEFT", "BOTTOMLEFT", PAD, false }, { "TOPRIGHT", "BOTTOMRIGHT", PAD, false } }) do
        local t = panel:CreateTexture(nil, "ARTWORK", nil, -1)
        t:SetColorTexture(0.93, 0.74, 0.20, 1)
        t:SetPoint(e[1]); t:SetPoint(e[2])
        if e[4] then t:SetHeight(e[3]) else t:SetWidth(e[3]) end
    end
    local outline = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
    outline:SetColorTexture(0.35, 0.22, 0.04, 1)
    outline:SetPoint("TOPLEFT", -2, 2)
    outline:SetPoint("BOTTOMRIGHT", 2, -2)

    -- The stand's two feet, in the theme's accent colour.
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local foot = rack:CreateTexture(nil, "BACKGROUND", nil, -8)
        foot:SetTexture(UI.MEDIA .. "Button")
        foot:SetSize(70, 18)
        foot:SetPoint("TOP", rack, "BOTTOM" .. side, side == "LEFT" and 18 or -18, 4)
        GG.Theme:Paint(foot, "accent")
    end

    -- One invisible button per column: hover shows where the checker would
    -- land, click drops it.
    columns = {}
    for col = 1, COLS do
        local b = CreateFrame("Button", nil, rack)
        b:SetSize(CELL, ROWS * CELL)
        b:SetPoint("TOPLEFT", PAD + (col - 1) * CELL, -PAD)
        b.col = col
        local glow = b:CreateTexture(nil, "HIGHLIGHT")
        glow:SetColorTexture(1, 1, 0.8, 0.10)
        glow:SetAllPoints()
        b.ghost = MakeChip(b, CELL - 6, "OVERLAY")
        b.ghost:SetAlpha(0.5)
        b.ghost:Hide()
        b:SetScript("OnEnter", function(self) hoverCol = self.col; Refresh() end)
        b:SetScript("OnLeave", function(self) if hoverCol == self.col then hoverCol = nil; Refresh() end end)
        b:SetScript("OnClick", function(self) GG:Safe("Connect 6", OnColumnClick, self) end)
        local shake = b:CreateAnimationGroup()
        for n, dx in ipairs({ 4, -8, 6, -2 }) do
            local t = shake:CreateAnimation("Translation")
            t:SetOffset(dx, 0)
            t:SetDuration(0.04)
            t:SetOrder(n)
        end
        b.shake = shake
        columns[col] = b
    end

    -- Side card: players and rules.
    side = UI.Card(area)
    side:SetPoint("TOPLEFT", rack, "TOPRIGHT", 22, 0)
    side:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
    local title = UI.Text(side, "Connect 6", { fancy = true, size = 22, ink = true })
    title:SetPoint("TOPLEFT", 16, -14)
    side.rows = {}
    for seat = 1, 2 do
        local row = CreateFrame("Frame", nil, side)
        row:SetSize(250, 40)
        row:SetPoint("TOPLEFT", 14, -48 - (seat - 1) * 46)
        row.chip = MakeChip(row, 34)
        row.chip:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.name = UI.Text(row, "", { ink = true })
        row.name:SetPoint("TOPLEFT", row.chip.base, "TOPRIGHT", 8, -2)
        row.sub = UI.Text(row, "", { ink = true, font = "GameFontHighlightSmall" })
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
        row.glow = row:CreateTexture(nil, "OVERLAY")
        row.glow:SetTexture(UI.MEDIA .. "ButtonGlow")
        row.glow:SetPoint("TOPLEFT", -8, 6)
        row.glow:SetPoint("BOTTOMRIGHT", 8, -6)
        row.glow:SetBlendMode("ADD")
        row.glow:SetVertexColor(1, 0.75, 0.2)
        UI.AddPulse(row.glow, 0.3, 0.6)
        side.rows[seat] = row
    end
    local rules = UI.Text(side,
        "Take turns dropping one chip into a column. It falls to the lowest open hole.\n\n" ..
        "Get six in a row: across, up and down, or diagonally.\n\nThe glowing chip was the last move.",
        { ink = true, font = "GameFontHighlightSmall" })
    rules:SetPoint("TOPLEFT", 18, -152)
    rules:SetPoint("RIGHT", side, "RIGHT", -16, 0)
    rules:SetTextColor(0.40, 0.30, 0.18)
end

-- Make a checker fall from the top row into hole i.
local function DropAnimation(i)
    local _, row = ColRow(i)
    local dist = (row - 1) * CELL
    if dist <= 0 then return end
    holes[i].chip:Fall(dist, 0.08 + 0.045 * (row - 1))
end

function Refresh()
    local s = current
    if not s or not rack then return end
    local d = s.data
    local board = d.board
    local myTurn = GG.Turns:IsMyTurn(s)

    local marked = {}
    if d.winLine then
        for _, i in ipairs(d.winLine) do marked[i] = true end
    elseif d.lastMove then
        marked[d.lastMove] = true
    end

    for i, h in ipairs(holes) do
        local seat = board[i]
        if seat ~= 0 then
            PaintChip(h.chip, s, seat)
            if not h.chip:IsShown() then
                h.chip:Show()
                if d.animate == i then DropAnimation(i) end
            end
        else
            h.chip:Hide()
        end
        h.mark:SetShown(marked[i] == true)
        if marked[i] then
            if d.winLine then h.mark:SetVertexColor(1, 0.85, 0.3) else h.mark:SetVertexColor(1, 1, 0.85) end
            h.mark.pulse:Play()
        end
    end

    -- Ghost checker where your drop would land.
    local mySeat = s:SeatOf(s:Me())
    for col, b in ipairs(columns) do
        local row = LandingRow(board, col)
        if myTurn and mySeat and row and col == hoverCol then
            PaintChip(b.ghost, s, mySeat)
            b.ghost:ClearAllPoints()
            b.ghost:SetPoint("CENTER", b, "TOPLEFT", CELL / 2, -((row - 1) * CELL + CELL / 2))
            b.ghost:Show()
        else
            b.ghost:Hide()
        end
    end

    local currentPlayer = GG.Turns:Current(s)
    for seat, row in ipairs(side.rows) do
        local name = s.players[seat]
        PaintChip(row.chip, s, seat)
        row.name:SetText(Util.ShortName(name) .. (Util.IsMe(name) and " (you)" or ""))
        local active = s.status == "playing" and name == currentPlayer
        row.sub:SetText(active and (Util.IsMe(name) and "Your turn!" or "Thinking...") or (seat == 1 and "Gold rim" or "Silver rim"))
        row.glow:SetShown(active)
        if active then row.glow.pulse:Play() end
    end
end

-------------------------------------------------------------------------------
-- Module callbacks
-------------------------------------------------------------------------------

function Game.OnSessionStart(session)
    current = session
    local d = session.data
    d.board = EmptyBoard()
    d.lastMove = nil
    d.winLine = nil
    if not rack then BuildRack() end
    rack:Show()
    side:Show()
    Refresh()

    if session:IsHost() then
        GG.Turns:Start(session, Util.Shuffle(Util.Copy(session.players)))
    end
end

-- Host: check a drop.
function Game.OnAction(session, sender, op, args)
    if op ~= "DROP" or session.status ~= "playing" then return end
    if GG.Turns:Current(session) ~= sender then return end
    local col = tonumber(args[1])
    if not col or col % 1 ~= 0 or col < 1 or col > COLS then return end
    local d = session.data
    local row = LandingRow(d.board, col)
    if not row then return end                       -- column full

    session:Broadcast("SET", Idx(col, row), session:SeatOf(sender))

    if WinningLine(d.board, col, row) then
        session:End({ winners = { sender } })
    elseif IsFull(d.board) then
        session:End({ draw = true })
    else
        GG.Turns:Advance(session)
    end
end

-- Everyone: apply the host's announcements.
function Game.OnState(session, op, args)
    local d = session.data
    if op == "SET" then
        local i, seat = tonumber(args[1]), tonumber(args[2])
        if i and seat and d.board[i] == 0 then
            d.board[i] = seat
            d.lastMove = i
            d.animate = i
        end
    elseif op == "SNAP" then
        d.board = BoardFromString(args[1] or "")
        d.lastMove = tonumber(args[2])
        d.animate = nil
    end
    if session == current then Refresh() end
end

function Game.OnSyncRequest(session, player)
    session:SendTo(player, "SNAP", BoardToString(session.data.board), session.data.lastMove or "")
end

function Game.OnSessionEnd(session, result)
    local d = session.data
    if d.lastMove and not result.draw then
        d.winLine = WinningLine(d.board, ColRow(d.lastMove))
    end
    if session == current then Refresh() end
end

function Game.OnSessionClosed(session)
    if session == current then
        current = nil
        if rack then rack:Hide(); side:Hide() end
    end
end

GG.RegisterCallback(Game, "TURN_CHANGED", function(_, session)
    if session == current then Refresh() end
end)

-------------------------------------------------------------------------------
-- Practice bot
--   1. Win now if it can.
--   2. Otherwise block the opponent's winning drop.
--   3. Otherwise score each column by the six-long "windows" its landing
--      hole belongs to, and avoid drops that hand the opponent a win in the
--      hole right above.
-------------------------------------------------------------------------------
local ATTACK = { [0] = 1, 6, 30, 160, 1200, 100000 }
local DEFEND = { [0] = 0, 4, 22, 120, 1000, 50000 }

local function ScoreHole(board, col, row, me)
    local score = 0
    for _, d in ipairs(DIRS) do
        for start = -(NEED - 1), 0 do
            local mine, theirs, valid = 0, 0, true
            for k = 0, NEED - 1 do
                local c, r = col + d[1] * (start + k), row + d[2] * (start + k)
                if not OnBoard(c, r) then valid = false; break end
                local v = board[Idx(c, r)]
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

local function WinningDrop(board, seat)
    for col = 1, COLS do
        local row = LandingRow(board, col)
        if row then
            board[Idx(col, row)] = seat
            local wins = WinningLine(board, col, row) ~= nil
            board[Idx(col, row)] = 0
            if wins then return col end
        end
    end
end

local function BestColumn(board, me)
    local them = (me == 1) and 2 or 1
    local win = WinningDrop(board, me)
    if win then return win end
    local block = WinningDrop(board, them)
    if block then return block end

    local best, bestScore = nil, -math.huge
    for col = 1, COLS do
        local row = LandingRow(board, col)
        if row then
            local score = ScoreHole(board, col, row, me)
            -- Don't set up the opponent: would our checker let them win above it?
            if row > 1 then
                board[Idx(col, row)] = me
                board[Idx(col, row - 1)] = them
                if WinningLine(board, col, row - 1) then score = score - 40000 end
                board[Idx(col, row - 1)] = 0
                board[Idx(col, row)] = 0
            end
            -- A slight taste for the middle, plus a pinch of chaos.
            score = score + (COLS / 2 - math.abs(col - (COLS + 1) / 2)) * 2 + math.random() * 3
            if score > bestScore then best, bestScore = col, score end
        end
    end
    return best
end

function Game.BotAction(session, bot)
    if session.status ~= "playing" or GG.Turns:Current(session) ~= bot then return end
    local col = BestColumn(session.data.board, session:SeatOf(bot))
    if col then session:ActAs(bot, "DROP", col) end
end

-- Exposed for the test suite (tools/wowsim). Not part of the module API.
Game._test = {
    WinningLine = WinningLine, LandingRow = LandingRow, BestColumn = BestColumn,
    Idx = Idx, ColRow = ColRow, COLS = COLS, ROWS = ROWS,
}

GG:RegisterGame(Game)
