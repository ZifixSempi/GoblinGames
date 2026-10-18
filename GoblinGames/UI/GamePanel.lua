--[[----------------------------------------------------------------------------
  GoblinGames/UI/GamePanel.lua

  The frame a game is played in. The core draws the shared parts:
    - top:    each player's crest and name, whose turn it is, the countdown
    - middle: an empty "game area" the module fills with its board or table
    - bottom: Forfeit / Close, and Rematch for the host when the game is over

  Modules get the game area with GoblinGames.UI:GetGameArea() and can replace
  the status line with GoblinGames.UI:SetGameStatus("text").
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI
local Util = GG.Util

local panel, area, statusText, timerText, chips, forfeitButton, rematchButton
local customStatus

--- The frame a module should parent its board to. Sized to fill the space
--- between the player bar and the buttons.
function UI:GetGameArea()
    if not panel then UI:ShowPanel("game") end
    return area
end

--- Override the status line. Pass nil to go back to the automatic text.
function UI:SetGameStatus(text)
    customStatus = text
    UI:RefreshGamePanel()
end

local function PlayerChip(parent)
    local chip = CreateFrame("Frame", nil, parent)
    chip:SetSize(130, 26)
    chip.crest = chip:CreateTexture(nil, "ARTWORK")
    chip.crest:SetSize(22, 22)
    chip.crest:SetPoint("LEFT")
    chip.name = UI.Label(chip, "", "GameFontHighlightSmall")
    chip.name:SetPoint("LEFT", chip.crest, "RIGHT", 4, 0)
    chip.name:SetWidth(100)
    chip.arrow = chip:CreateTexture(nil, "OVERLAY")
    chip.arrow:SetSize(14, 14)
    chip.arrow:SetPoint("BOTTOM", chip.crest, "TOP", 0, -2)
    chip.arrow:SetTexture("Interface\\Buttons\\UI-MicroStream-Yellow")
    return chip
end

function UI:RefreshGamePanel()
    if not panel or not panel:IsShown() then return end
    local s = GG.Lobby.active
    if not s then return end

    -- Player chips.
    local current = GG.Turns:Current(s)
    for i, name in ipairs(s.players) do
        local chip = chips[i]
        if not chip then
            chip = PlayerChip(panel)
            chip:SetPoint("TOPLEFT", (i - 1) * 134, 0)
            chips[i] = chip
        end
        GG.Theme:SetCrest(chip.crest, s:GetFaction(name))
        local label = Util.ShortName(name)
        if s.left[name] then label = UI.Grey(label .. " (out)")
        elseif s.offlineSince[name] then label = UI.Red(label .. " (offline)")
        elseif Util.IsMe(name) then label = UI.Gold(label) end
        chip.name:SetText(label)
        chip.arrow:SetShown(s.status == "playing" and name == current)
        chip:SetShown(i <= 4) -- more than 4 players: modules show their own list
    end
    for i = #s.players + 1, #chips do chips[i]:Hide() end

    -- Status line.
    local text
    if customStatus then
        text = customStatus
    elseif s.status == "ended" then
        local r = s.result or {}
        if r.outcome == "win" then text = UI.Green("You won!")
        elseif r.outcome == "loss" then text = UI.Red("You lost.")
        elseif r.outcome == "draw" then text = UI.Gold("It's a draw.")
        else text = UI.Grey("Game over" .. (r.reason and (": " .. r.reason) or ".")) end
    elseif GG:IsCommLocked() then
        text = UI.Grey("Paused: addon messages are blocked during this encounter.")
    elseif GG.Turns:IsMyTurn(s) then
        text = UI.Gold("Your turn")
    elseif current then
        text = Util.ShortName(current) .. "'s turn"
    else
        text = UI.Grey("Starting...")
    end
    statusText:SetText(text)

    -- Buttons.
    local ended = s.status == "ended"
    forfeitButton:SetText(ended and "Close" or (s.isLocal and "Quit" or "Forfeit"))
    rematchButton:SetShown(ended and s:IsHost())
end

UI:RegisterPanel("game", "Game", function(container)
    panel = CreateFrame("Frame", nil, container)
    chips = {}

    statusText = UI.Label(panel, "", "GameFontNormalLarge")
    statusText:SetPoint("TOPLEFT", 0, -34)

    timerText = UI.Label(panel, "", "GameFontHighlightLarge")
    timerText:SetPoint("TOPRIGHT", -4, -34)

    area = CreateFrame("Frame", nil, panel)
    area:SetPoint("TOPLEFT", 0, -60)
    area:SetPoint("BOTTOMRIGHT", 0, 38)

    forfeitButton = UI.Button(panel, "Forfeit", 100, 26, function()
        local s = GG.Lobby.active
        if not s then return end
        if s.status == "ended" then
            GG.Lobby:Close(s)
        elseif s.isLocal then
            GG.Lobby:Close(s)
        else
            GG.Lobby:Leave(s)
        end
    end)
    forfeitButton:SetPoint("BOTTOMRIGHT", 0, 4)

    rematchButton = UI.Button(panel, "Rematch", 100, 26, function()
        local s = GG.Lobby.active
        if s then
            local ok, err = GG.Lobby:Rematch(s)
            if not ok and err then GG:Print(err) end
        end
    end)
    rematchButton:SetPoint("RIGHT", forfeitButton, "LEFT", -8, 0)

    -- Countdown: updated every frame while the panel is visible.
    panel:SetScript("OnUpdate", function()
        local s = GG.Lobby.active
        local remaining = s and s.status == "playing" and GG.Turns:Remaining(s)
        if remaining then
            local txt = Util.FormatSeconds(remaining)
            timerText:SetText(remaining < 10 and UI.Red(txt) or txt)
        else
            timerText:SetText("")
        end
    end)

    panel:SetScript("OnShow", function() UI:RefreshGamePanel() end)

    local listener = {}
    local function Refresh() UI:RefreshGamePanel() end
    GG.RegisterCallback(listener, "TURN_CHANGED", Refresh)
    GG.RegisterCallback(listener, "SESSION_UPDATED", Refresh)
    GG.RegisterCallback(listener, "SESSION_ENDED", Refresh)
    GG.RegisterCallback(listener, "COMM_LOCK_CHANGED", Refresh)
    GG.RegisterCallback(listener, "SESSION_STARTED", function() customStatus = nil; Refresh() end)
    GG.RegisterCallback(listener, "SESSION_CLOSED", function() customStatus = nil end)
    return panel
end)
