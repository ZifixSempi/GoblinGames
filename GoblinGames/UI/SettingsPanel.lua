--[[----------------------------------------------------------------------------
  GoblinGames/UI/SettingsPanel.lua

  Settings inside our own window, plus a small entry in Blizzard's AddOns
  options (Esc > Options > AddOns) that opens it.

  Blizzard's options API changed in 10.0 (the "Settings" API replaced
  InterfaceOptions_AddCategory). We check which one this client has.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI

UI:RegisterPanel("settings", "Settings", function(container)
    local panel = CreateFrame("Frame", nil, container)

    local card = UI.Card(panel)
    card:SetAllPoints()

    local heading = UI.Text(card, "House Rules", { fancy = true, size = 26, ink = true })
    heading:SetPoint("TOPLEFT", 22, -16)

    local function Get(key) return function() return GG:GetSetting(key) end end
    local function Set(key) return function(v) GG:SetSetting(key, v) end end

    local y = -62
    local function Place(widget, height)
        widget:SetPoint("TOPLEFT", 26, y)
        y = y - (height or 38)
    end

    Place(UI.CycleButton(card, "Look", {
        { value = "auto", text = "My faction" },
        { value = "Horde", text = "Horde" },
        { value = "Alliance", text = "Alliance" },
        { value = "Neutral", text = "Goblin (neutral)" },
    }, Get("theme"), Set("theme")))

    Place(UI.CycleButton(card, "Take invites from", {
        { value = "known", text = "Group, guild, friends" },
        { value = "anyone", text = "Anyone" },
        { value = "nobody", text = "Nobody" },
    }, Get("acceptFrom"), Set("acceptFrom")))

    Place(UI.CycleButton(card, "Turn timer (when I host)", {
        { value = 30, text = "30 seconds" },
        { value = 60, text = "60 seconds" },
        { value = 90, text = "90 seconds" },
        { value = 120, text = "2 minutes" },
        { value = 0, text = "No timer" },
    }, Get("turnTimer"), Set("turnTimer")))

    Place(UI.Checkbox(card, "Play sounds", Get("sounds"), Set("sounds")), 32)

    Place(UI.Checkbox(card, "Show minimap button",
        function() return not GG.db.profile.minimap.hide end,
        function(v)
            GG.db.profile.minimap.hide = not v
            GG:Fire("SETTINGS_CHANGED", "minimap", v)
        end), 32)

    local note = UI.Text(card,
        "Game pieces always show each player's own faction crest; the look only changes your window.\n" ..
        "Your stats are saved per character and survive addon updates.", { ink = true, font = "GameFontHighlightSmall" })
    note:SetPoint("TOPLEFT", 28, y - 12)
    note:SetWidth(600)
    note:SetTextColor(0.48, 0.38, 0.25)

    panel:SetScript("OnShow", function()
        UI:Say("Fiddle with whatever you like. I'll pretend I didn't see.")
    end)
    return panel
end)

-------------------------------------------------------------------------------
-- Entry in Blizzard's options window
-------------------------------------------------------------------------------
table.insert(GG.onLogin, function()
    local canvas = CreateFrame("Frame")
    canvas.name = "GoblinGames"
    local text = UI.Label(canvas, "GoblinGames settings live in the addon's own window.", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 16, -16)
    -- We deliberately don't close Blizzard's options window from code: hiding
    -- Blizzard panels from an addon is a classic source of taint. Our window
    -- uses the DIALOG strata, so it opens on top of it instead.
    local open = UI.Button(canvas, "Open GoblinGames", 160, 26, function()
        UI:ShowPanel("settings")
    end)
    open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(canvas, "GoblinGames")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(canvas)
    end
end)
