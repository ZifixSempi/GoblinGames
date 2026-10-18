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

    -- Two columns: everyday settings on the left, gold and guild on the right.
    local cols = { { x = 22, y = -60 }, { x = 360, y = -60 } }
    local function Place(col, widget, height)
        widget:SetPoint("TOPLEFT", cols[col].x, cols[col].y)
        cols[col].y = cols[col].y - (height or 36)
    end
    local function Section(col, text)
        local fs = UI.Text(card, text, { fancy = true, size = 16, ink = true })
        Place(col, fs, 24)
    end

    Section(1, "Everyday")
    Place(1, UI.CycleButton(card, "Look", {
        { value = "auto", text = "My faction" },
        { value = "Horde", text = "Horde" },
        { value = "Alliance", text = "Alliance" },
        { value = "Neutral", text = "Goblin (neutral)" },
    }, Get("theme"), Set("theme"), 150, 135))

    Place(1, UI.CycleButton(card, "Take invites from", {
        { value = "known", text = "Group, guild, friends" },
        { value = "anyone", text = "Anyone" },
        { value = "nobody", text = "Nobody" },
    }, Get("acceptFrom"), Set("acceptFrom"), 150, 135))

    Place(1, UI.CycleButton(card, "Turn timer (I host)", {
        { value = 30, text = "30 seconds" },
        { value = 60, text = "60 seconds" },
        { value = 90, text = "90 seconds" },
        { value = 120, text = "2 minutes" },
        { value = 0, text = "No timer" },
    }, Get("turnTimer"), Set("turnTimer"), 150, 135))

    Place(1, UI.Checkbox(card, "Play sounds", Get("sounds"), Set("sounds")), 30)
    Place(1, UI.Checkbox(card, "Show minimap button",
        function() return not GG.db.profile.minimap.hide end,
        function(v)
            GG.db.profile.minimap.hide = not v
            GG:Fire("SETTINGS_CHANGED", "minimap", v)
        end), 30)

    Section(2, "Gold")
    Place(2, UI.Checkbox(card, "Gold mode (stakes go in a ledger)", Get("goldMode"), Set("goldMode")), 26)
    local goldNote = UI.Text(card, GG.Ledger.TOS_REMINDER, { ink = true, font = "GameFontHighlightSmall" })
    goldNote:SetWidth(300)
    goldNote:SetTextColor(0.62, 0.20, 0.12)
    Place(2, goldNote, 52)

    Section(2, "Guild Bingo")
    local rankChoices = {}
    for i = 0, 4 do
        local name = GG.Util.GuildRankName(i)
        local text = (i == 0) and "Guild Master only" or ("Ranks 0-" .. i)
        if name then text = (i == 0) and (name .. " only") or ("Up to " .. name) end
        rankChoices[#rankChoices + 1] = { value = i, text = text }
    end
    rankChoices[#rankChoices + 1] = { value = 99, text = "Anyone in the guild" }
    Place(2, UI.CycleButton(card, "Who can host", rankChoices,
        Get("bingoMaxRank"), Set("bingoMaxRank"), 160, 110))
    Place(2, UI.Checkbox(card, "Post winners in guild chat (when I host)",
        Get("announceBingo"), Set("announceBingo")), 26)
    local bingoNote = UI.Text(card, "Players only see Bingo games from hosts who meet THEIR own \"who can host\" setting.",
        { ink = true, font = "GameFontHighlightSmall" })
    bingoNote:SetWidth(300)
    bingoNote:SetTextColor(0.48, 0.38, 0.25)
    Place(2, bingoNote, 30)

    local note = UI.Text(card,
        "Pieces always show each player's own faction; the look only changes your window. " ..
        "Stats are saved per character and survive addon updates.", { ink = true, font = "GameFontHighlightSmall" })
    note:SetPoint("BOTTOMLEFT", 24, 18)
    note:SetWidth(640)
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
