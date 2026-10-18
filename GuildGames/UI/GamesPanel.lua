--[[----------------------------------------------------------------------------
  GuildGames/UI/GamesPanel.lua

  The game picker: one tile per game in the catalog. Installed games get
  "Host" and "Practice" buttons; the rest say "Coming soon".
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI

local COLS = 2
local TILE_W, TILE_H = 254, 74
local GAP = 8

local function Report(ok, err)
    if not ok and err then GG:Print(err) end
end

local function BuildTile(parent, entry)
    local tile = UI.Panel(parent, "tile")
    tile:SetSize(TILE_W, TILE_H)

    local icon = tile:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", 10, -10)
    icon:SetTexture(entry.icon)

    local name = UI.Label(tile, entry.name, "GameFontNormal")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)

    local players = UI.Label(tile, "", "GameFontNormalSmall")
    players:SetPoint("LEFT", name, "RIGHT", 6, 0)
    if entry.max >= 100 then
        players:SetText(UI.Grey(entry.min .. "+ players"))
    elseif entry.min == entry.max then
        players:SetText(UI.Grey(entry.min .. " players"))
    else
        players:SetText(UI.Grey(entry.min .. "-" .. entry.max .. " players"))
    end

    local desc = UI.Label(tile, entry.desc, "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    desc:SetWidth(TILE_W - 70)

    local host = UI.Button(tile, "Host", 70, 20, function()
        Report(GG.Lobby:CreateHosted(entry.id))
    end)
    host:SetPoint("BOTTOMRIGHT", -8, 8)

    local practice = UI.Button(tile, "Practice", 80, 20, function()
        Report(GG.Lobby:StartPractice(entry.id))
    end)
    practice:SetPoint("RIGHT", host, "LEFT", -4, 0)

    local soon = UI.Label(tile, UI.Grey("Coming soon"), "GameFontNormalSmall")
    soon:SetPoint("BOTTOMRIGHT", -12, 12)

    function tile:Refresh()
        local installed = GG:IsGameInstalled(entry.id)
        host:SetShown(installed)
        practice:SetShown(installed)
        soon:SetShown(not installed)
        icon:SetDesaturated(not installed)
    end
    return tile
end

UI:RegisterPanel("games", "Games", function(container)
    local panel = CreateFrame("Frame", nil, container)

    local heading = UI.Label(panel, "Pick a game", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 4, 0)

    local hint = UI.Label(panel, UI.Grey("Host invites players from your group, guild or by name. Practice plays a Training Dummy, offline."), "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)

    -- Ten tiles don't fit on one screen, so they sit in a scroll frame.
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -44)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    local grid = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(grid)
    local rows = math.ceil(#GG.CATALOG / COLS)
    grid:SetSize(COLS * (TILE_W + GAP), rows * (TILE_H + GAP))

    local tiles = {}
    for i, entry in ipairs(GG.CATALOG) do
        local tile = BuildTile(grid, entry)
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        tile:SetPoint("TOPLEFT", col * (TILE_W + GAP), -row * (TILE_H + GAP))
        tiles[i] = tile
    end

    panel:SetScript("OnShow", function()
        for _, tile in ipairs(tiles) do tile:Refresh() end
    end)
    return panel
end)
