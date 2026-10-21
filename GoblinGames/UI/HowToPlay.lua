--[[----------------------------------------------------------------------------
  GoblinGames/UI/HowToPlay.lua

  The "How to play" note: a parchment sheet with the rules of a game.
  Opened by:
    - the "?" button in the main window's top corner (the game you're in,
      or the game whose lobby you're in, or a general guide)
    - the "How to play" button on every game card and in the lobby
    - /gg rules <game>
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI

local sheet

local function Build()
    sheet = CreateFrame("Frame", "GoblinGamesRulesFrame", UIParent)
    sheet:SetSize(470, 440)
    sheet:SetPoint("CENTER", 0, 30)
    sheet:SetFrameStrata("FULLSCREEN_DIALOG")
    sheet:SetToplevel(true)
    sheet:EnableMouse(true)
    sheet:SetMovable(true)
    sheet:RegisterForDrag("LeftButton")
    sheet:SetScript("OnDragStart", sheet.StartMoving)
    sheet:SetScript("OnDragStop", sheet.StopMovingOrSizing)
    sheet:SetClampedToScreen(true)
    UI.NineSlice(sheet, UI.MEDIA .. "Parchment", 128, 24, 20)
    table.insert(UISpecialFrames, "GoblinGamesRulesFrame") -- Escape closes it

    local head = sheet:CreateTexture(nil, "OVERLAY")
    head:SetTexture(UI.MEDIA .. "Emblem")
    head:SetSize(48, 48)
    head:SetPoint("TOPLEFT", 16, -12)

    sheet.title = UI.Text(sheet, "", { fancy = true, size = 24, ink = true })
    sheet.title:SetPoint("LEFT", head, "RIGHT", 8, 4)
    local sub = UI.Text(sheet, "How to play", { ink = true, font = "GameFontNormalSmall" })
    sub:SetPoint("TOPLEFT", sheet.title, "BOTTOMLEFT", 0, -2)
    sub:SetTextColor(0.48, 0.38, 0.25)

    -- Scrolling text, for the longer rule sheets.
    local scroll = CreateFrame("ScrollFrame", nil, sheet, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 22, -72)
    scroll:SetPoint("BOTTOMRIGHT", -40, 62)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 10)
    scroll:SetScrollChild(content)
    sheet.body = UI.Text(content, "", { ink = true })
    sheet.body:SetPoint("TOPLEFT")
    sheet.body:SetWidth(400)
    sheet.body:SetSpacing(2)
    sheet.content = content
    sheet.scroll = scroll

    local ok = UI.Button(sheet, "Got it!", 140, 34, function() sheet:Hide() end, "primary")
    ok:SetPoint("BOTTOM", 0, 18)
    UI.AddPopIn(sheet)
end

--- Show the rules for a game id (or "general").
function UI:ShowRules(gameId)
    if not sheet then Build() end
    local title, text = GG:RulesText(gameId or "general")
    sheet.title:SetText(title)
    sheet.body:SetText(text)
    sheet.content:SetHeight(math.max(10, (sheet.body:GetStringHeight() or 300) + 10))
    if sheet.scroll.SetVerticalScroll then sheet.scroll:SetVerticalScroll(0) end
    sheet:Show()
    sheet.popIn:Play()
end

--- Which game's rules does the "?" button mean right now?
function UI:ContextGame()
    local s = GG.Lobby.active
    if s then return s.gameId end
    return "general"
end
