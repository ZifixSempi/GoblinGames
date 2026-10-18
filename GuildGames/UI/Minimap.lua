--[[----------------------------------------------------------------------------
  GuildGames/UI/Minimap.lua

  A round button on the minimap edge (drag to move it around the rim) and,
  on Retail, an entry in the Addon Compartment (the small dropdown on the
  minimap). The compartment entry comes from the ## AddonCompartmentFunc
  lines in GuildGames.toc, which call the global functions at the bottom.

  Left-click: open/close the window. Right-click: settings.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI

local button

local function UpdatePosition()
    local angle = math.rad(GG.db.profile.minimap.angle or 215)
    -- Distance from the minimap centre to its rim, plus a little.
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("GuildGames")
    GameTooltip:AddLine("Left-click: open", 1, 1, 1)
    GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
    local s = GG.Lobby.active
    if s then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Current: " .. s.catalog.name .. " (" .. s.status .. ")", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function Build()
    button = CreateFrame("Button", "GuildGamesMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- The classic round minimap button look: icon, dark background, gold ring.
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Dice_02")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then UI:ShowPanel("settings") else UI:Toggle() end
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Dragging: follow the cursor around the rim and save the angle.
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            GG.db.profile.minimap.angle = angle
            UpdatePosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    UpdatePosition()
end

local function Refresh()
    if GG.db.profile.minimap.hide then
        if button then button:Hide() end
    else
        if not button then Build() end
        button:Show()
    end
end

table.insert(GG.onLogin, Refresh)

local listener = {}
GG.RegisterCallback(listener, "SETTINGS_CHANGED", function(_, key)
    if key == "minimap" then Refresh() end
end)

-------------------------------------------------------------------------------
-- Addon Compartment (Retail). These must be globals: the .toc names them.
-------------------------------------------------------------------------------
function GuildGames_OnAddonCompartmentClick(_, mouse)
    if mouse == "RightButton" then UI:ShowPanel("settings") else UI:Toggle() end
end

function GuildGames_OnAddonCompartmentEnter(_, menuButton)
    ShowTooltip(menuButton)
end

function GuildGames_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
