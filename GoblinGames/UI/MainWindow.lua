--[[----------------------------------------------------------------------------
  GoblinGames/UI/MainWindow.lua

  The main window, laid out like a goblin's tavern table:

     (LOGO)  Goblin Games                    [Games][Your Game][Stats][Settings]  X
     +-------------------------------------------------------------------------+
     |                         content panel                                   |
     +-------------------------------------------------------------------------+
     (goblin) "speech bubble with what to do next"             [action buttons]

  Panels register themselves with UI:RegisterPanel(name, tabLabel, build) and
  are built the first time the window opens. A panel can put its buttons in
  the bottom-right corner by anchoring them to UI.frame.actions.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI

local WIDTH, HEIGHT = 760, 580

local panelBuilders, panelOrder = {}, {}
UI.panels = {}

--- name: key; tabLabel: text on its tab (nil = no tab); build(container) -> frame
function UI:RegisterPanel(name, tabLabel, build)
    panelBuilders[name] = build
    panelOrder[#panelOrder + 1] = { name = name, label = tabLabel }
end

local frame

-- Little lines under the title. One is picked each time the window opens.
local TAGLINES = {
    "Step right up, friend!",
    "No refunds. Some fun.",
    "Time is money. Games are cheaper.",
    "Waiting in a queue? Lose some coin!",
    "Proudly unlicensed by the Steamwheedle Cartel.",
}

local function MakeTab(parent, label, onClick)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(118, 36)
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(UI.MEDIA .. "Tab")
    bg:SetTexCoord(0, 1, 0, 0.6)
    bg:SetAllPoints()
    tab.bg = bg
    local text = UI.Text(tab, label, { fancy = true, size = 15, justify = "CENTER" })
    text:SetPoint("CENTER", 0, 0)
    tab.text = text
    local glow = tab:CreateTexture(nil, "ARTWORK")
    glow:SetTexture(UI.MEDIA .. "ButtonGlow")
    glow:SetAllPoints()
    glow:SetBlendMode("ADD")
    glow:Hide()
    tab.glow = glow
    UI.AddBounce(tab, 1.06)
    tab:SetScript("OnEnter", function(self) self.bounce:Play() end)
    tab:SetScript("OnClick", function()
        GG.Theme:PlaySound("click")
        onClick()
    end)
    function tab:SetSelected(on)
        GG.Theme:Paint(bg, on and "accent" or "wood")
        text:SetTextColor(on and 1 or 0.85, on and 0.95 or 0.80, on and 0.80 or 0.70)
    end
    tab:SetSelected(false)
    return tab
end

local function BuildWindow()
    -- The global name is what UISpecialFrames needs: frames listed there close
    -- when the player presses Escape.
    frame = CreateFrame("Frame", "GoblinGamesMainFrame", UIParent)
    UI.frame = frame
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
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
        frame:SetPoint("CENTER", 0, 20)
    end
    frame:Hide()
    table.insert(UISpecialFrames, "GoblinGamesMainFrame")

    -- Plank floor (tiled) inside a wooden frame (nine-slice).
    local planks = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    planks:SetTexture(UI.MEDIA .. "Planks", "REPEAT", "REPEAT")
    planks:SetHorizTile(true)
    planks:SetVertTile(true)
    planks:SetPoint("TOPLEFT", 16, -16)
    planks:SetPoint("BOTTOMRIGHT", -16, 16)
    GG.Theme:Paint(planks, "planks")

    local border = CreateFrame("Frame", nil, frame)
    border:SetAllPoints()
    border:SetFrameLevel(frame:GetFrameLevel() + 20)
    for _, part in ipairs(UI.NineSlice(border, UI.MEDIA .. "Frame", 256, 64, 40, "BORDER")) do
        GG.Theme:Paint(part, "frame")
    end

    -- A dark strip behind the header so the title pops.
    local header = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    header:SetColorTexture(0, 0, 0, 0.35)
    header:SetPoint("TOPLEFT", 16, -16)
    header:SetPoint("TOPRIGHT", -16, -16)
    header:SetHeight(86)

    -- Logo badge, poking out of the top-left corner and bobbing gently.
    local logoHolder = CreateFrame("Frame", nil, border)
    logoHolder:SetSize(124, 124)
    logoHolder:SetPoint("TOPLEFT", -34, 36)
    logoHolder:SetFrameLevel(border:GetFrameLevel() + 5)
    local logo = logoHolder:CreateTexture(nil, "OVERLAY")
    logo:SetTexture(UI.MEDIA .. "Logo")
    logo:SetAllPoints()
    UI.AddBob(logo, 3, 1.6)

    local title = UI.Text(frame, "Goblin Games", { fancy = true, size = 34 })
    title:SetPoint("TOPLEFT", 100, -26)
    frame.title = title
    local tagline = UI.Text(frame, "", { font = "GameFontHighlight" })
    -- Sits to the right of the title, clear of the tabs below.
    tagline:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 16, 6)
    tagline:SetWidth(300)
    tagline:SetTextColor(0.95, 0.85, 0.6)
    frame.tagline = tagline

    -- The close button must be a child of the window itself: Blizzard's
    -- UIPanelCloseButton hides its *parent* when clicked. We raise its frame
    -- level so it still draws on top of the wooden border.
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetFrameLevel(border:GetFrameLevel() + 6)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- "?" right next to the close button: rules for whatever you're doing.
    local help = UI.Button(frame, "?", 30, 30, function() UI:ShowRules(UI:ContextGame()) end, "wood")
    help:SetPoint("RIGHT", close, "LEFT", -4, 0)
    help:SetFrameLevel(border:GetFrameLevel() + 6)
    help.tooltip = "How to play"

    local function PaintTitle()
        local c = GG.Theme:GetPalette().title
        title:SetText("|c" .. c .. "Goblin|r Games")
    end
    PaintTitle()
    GG.RegisterCallback(frame, "THEME_CHANGED", PaintTitle)

    -- Content area and the bottom strip.
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 28, -108)
    content:SetPoint("BOTTOMRIGHT", -28, 84)
    frame.content = content

    local actions = CreateFrame("Frame", nil, frame)
    actions:SetSize(1, 34)
    actions:SetPoint("BOTTOMRIGHT", -34, 30)
    frame.actions = actions

    -- Tabs along the top edge of the content.
    frame.tabs = {}
    for _, info in ipairs(panelOrder) do
        local panel = panelBuilders[info.name](content)
        panel:SetAllPoints(content)
        panel:Hide()
        UI.panels[info.name] = panel
        if info.label then
            frame.tabs[info.name] = MakeTab(frame, info.label, function() UI:ShowPanel(info.name) end)
        end
    end

    UI:BuildMascot(frame)
    UI:UpdateTabs()

    frame:SetScript("OnShow", function()
        tagline:SetText(TAGLINES[math.random(#TAGLINES)])
    end)
end

--- Lay the tabs out right-to-left; the "Your Game" tab only shows during a game.
local TAB_ORDER = { "settings", "stats", "current", "games" }
function UI:UpdateTabs()
    if not frame then return end
    local s = GG.Lobby.active
    local x = -40
    for _, name in ipairs(TAB_ORDER) do
        local tab = frame.tabs[name]
        if tab then
            local visible = name ~= "current" or s ~= nil
            tab:SetShown(visible)
            if visible then
                tab:ClearAllPoints()
                tab:SetPoint("BOTTOMRIGHT", frame.content, "TOPRIGHT", x + 40, 2)
                x = x - 122
            end
        end
    end
    local current = frame.tabs.current
    if current then
        if s and s.status == "lobby" then current.text:SetText("Lobby")
        elseif s then current.text:SetText("Your Game") end
        -- Make the tab glow when it's your turn and you're looking elsewhere.
        local wantsAttention = s and GG.Turns:IsMyTurn(s) and self.currentPanel ~= "current"
        if wantsAttention then
            current.glow:Show()
            if not current.glow.pulse then UI.AddPulse(current.glow, 0.2, 0.5) end
            current.glow.pulse:Play()
        else
            current.glow:Hide()
        end
    end
end

--- Show one panel and hide the rest.
function UI:ShowPanel(name)
    if not frame then BuildWindow() end
    -- "lobby" and "game" share the "current" tab.
    if name == "lobby" or name == "game" then
        local s = GG.Lobby.active
        name = "current"
        UI.currentSub = (s and s.status == "lobby") and "lobby" or "game"
    elseif name == "current" then
        local s = GG.Lobby.active
        if not s then name = "games" else UI.currentSub = (s.status == "lobby") and "lobby" or "game" end
    end
    for key, panel in pairs(self.panels) do
        local show = (key == name) or (name == "current" and key == UI.currentSub)
        panel:SetShown(show)
    end
    self.currentPanel = name
    for key, tab in pairs(frame.tabs) do tab:SetSelected(key == name) end
    self:UpdateTabs()
    frame:Show()
end

function UI:Toggle()
    if frame and frame:IsShown() then frame:Hide() else self:Open() end
end

--- Open on the most useful panel: the current game if there is one.
function UI:Open(panel)
    if not panel then
        panel = GG.Lobby.active and "current" or (self.currentPanel or "games")
    end
    self:ShowPanel(panel)
end

-- Follow the session through its life: lobby -> game -> back to the picker.
local watcher = {}
GG.RegisterCallback(watcher, "SESSION_CREATED", function()
    UI:ShowPanel("current")
end)
GG.RegisterCallback(watcher, "SESSION_STARTED", function()
    UI:ShowPanel("current")
end)
GG.RegisterCallback(watcher, "SESSION_CLOSED", function()
    if frame and frame:IsShown() and UI.currentPanel == "current" then
        UI:ShowPanel("games")
    else
        UI:UpdateTabs()
    end
end)
GG.RegisterCallback(watcher, "SESSION_UPDATED", function() UI:UpdateTabs() end)
GG.RegisterCallback(watcher, "SESSION_ENDED", function() UI:UpdateTabs() end)
GG.RegisterCallback(watcher, "TURN_CHANGED", function() UI:UpdateTabs() end)
