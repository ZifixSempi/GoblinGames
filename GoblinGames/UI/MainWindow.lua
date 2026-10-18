--[[----------------------------------------------------------------------------
  GoblinGames/UI/MainWindow.lua

  The main window: title bar, a navigation column on the left and one content
  panel at a time on the right (Games, Lobby, Game, Stats, Settings).

  Panels are registered by the other UI files with UI:RegisterPanel(name, build)
  and built lazily the first time the window opens, so nothing is created
  until the player actually uses the addon.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI

local WIDTH, HEIGHT = 700, 500
local NAV_WIDTH = 120

local panelBuilders, panelOrder = {}, {}
UI.panels = {}

--- name: key, label: nav button text (nil = no nav button), build(container) -> frame
function UI:RegisterPanel(name, label, build)
    panelBuilders[name] = build
    panelOrder[#panelOrder + 1] = { name = name, label = label }
end

local frame

local function BuildWindow()
    -- The global name is what UISpecialFrames needs: frames listed there
    -- close when the player presses Escape.
    frame = CreateFrame("Frame", "GoblinGamesMainFrame", UIParent, UI.BACKDROP)
    GG.Theme:ApplyFrame(frame)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        GG.db.profile.windowPos = { point, relPoint, x, y }
    end)
    local pos = GG.db.profile.windowPos
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("CENTER")
    end
    frame:Hide()
    table.insert(UISpecialFrames, "GoblinGamesMainFrame")

    -- Title: our crest and name.
    local crest = frame:CreateTexture(nil, "ARTWORK")
    crest:SetSize(32, 32)
    crest:SetPoint("TOPLEFT", 14, -12)
    frame.crest = crest

    local title = UI.Label(frame, "", "GameFontNormalLarge")
    title:SetPoint("LEFT", crest, "RIGHT", 8, 0)
    frame.title = title

    local version = UI.Label(frame, UI.Grey("v" .. GG.version), "GameFontNormalSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local function PaintTitle()
        GG.Theme:SetCrest(crest, GG.Theme:GetThemeFaction())
        title:SetText(GG.Theme:TitleText("GoblinGames"))
    end
    PaintTitle()
    GG.RegisterCallback(frame, "THEME_CHANGED", PaintTitle)

    -- Content area.
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", NAV_WIDTH + 20, -54)
    content:SetPoint("BOTTOMRIGHT", -16, 16)
    frame.content = content

    -- Navigation buttons + panels.
    local y = -58
    frame.navButtons = {}
    for _, info in ipairs(panelOrder) do
        local panel = panelBuilders[info.name](content)
        panel:SetAllPoints(content)
        panel:Hide()
        UI.panels[info.name] = panel
        if info.label then
            local b = UI.Button(frame, info.label, NAV_WIDTH, 26, function() UI:ShowPanel(info.name) end)
            b:SetPoint("TOPLEFT", 16, y)
            y = y - 30
            frame.navButtons[info.name] = b
        end
    end

    UI.frame = frame
    UI:UpdateNav()
end

--- Show one panel and hide the rest.
function UI:ShowPanel(name)
    if not frame then BuildWindow() end
    for key, panel in pairs(self.panels) do
        if key == name then panel:Show() else panel:Hide() end
    end
    self.currentPanel = name
    for key, button in pairs(frame.navButtons) do
        if key == name then button:LockHighlight() else button:UnlockHighlight() end
    end
    frame:Show()
end

--- The "Lobby" and "Game" buttons only make sense when there's a session.
function UI:UpdateNav()
    if not frame then return end
    local s = GG.Lobby.active
    local lobby, game = frame.navButtons.lobby, frame.navButtons.game
    if lobby then lobby:SetEnabled(s ~= nil and s.status == "lobby") end
    if game then game:SetEnabled(s ~= nil and s.status ~= "lobby") end
end

function UI:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        self:Open()
    end
end

--- Open on the most useful panel: the current game or lobby, else the picker.
function UI:Open(panel)
    if not panel then
        local s = GG.Lobby.active
        if s and s.status == "lobby" then panel = "lobby"
        elseif s then panel = "game"
        else panel = self.currentPanel or "games" end
        if (panel == "lobby" or panel == "game") and not s then panel = "games" end
    end
    self:ShowPanel(panel)
end

-- Follow the session through its life: lobby -> game -> back to the picker.
local watcher = {}
GG.RegisterCallback(watcher, "SESSION_CREATED", function(_, s)
    UI:UpdateNav()
    if s.status == "lobby" then UI:ShowPanel("lobby") end
end)
GG.RegisterCallback(watcher, "SESSION_STARTED", function()
    UI:UpdateNav()
    UI:ShowPanel("game")
end)
GG.RegisterCallback(watcher, "SESSION_CLOSED", function()
    UI:UpdateNav()
    if frame and frame:IsShown() and (UI.currentPanel == "lobby" or UI.currentPanel == "game") then
        UI:ShowPanel("games")
    end
end)
GG.RegisterCallback(watcher, "SESSION_UPDATED", function() UI:UpdateNav() end)
GG.RegisterCallback(watcher, "SESSION_ENDED", function() UI:UpdateNav() end)
