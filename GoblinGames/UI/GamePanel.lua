--[[----------------------------------------------------------------------------
  GoblinGames/UI/GamePanel.lua

  Where games are played. The core draws the shared parts:
    - the players' name plates, with a glow on whoever's turn it is,
      a big "VS" and a burning fuse for the turn timer
    - a status line ("Your turn!")
    - an empty "game area" that the module fills with its board or table
    - the result banner (+ coin shower when you win)
    - Forfeit / Rematch / Back buttons in the bottom-right corner

  Modules: GoblinGames.UI:GetGameArea() gives the frame to build in;
  GoblinGames.UI:SetGameStatus("text") overrides the status line (nil resets);
  a `hint` field on the module definition is what the goblin says on your turn.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI
local Util = GG.Util

local panel, area, statusText, plates, vsText, fuse, fuseText, banner
local quitButton, rematchButton, backButton
local customStatus, celebrated

--- The frame a module should parent its board to.
function UI:GetGameArea()
    if not panel then UI:ShowPanel("game") end
    return area
end

--- Override the status line. Pass nil to go back to the automatic text.
function UI:SetGameStatus(text)
    customStatus = text
    UI:RefreshGamePanel()
end

local function Plate(parent)
    local plate = CreateFrame("Frame", nil, parent)
    plate:SetSize(250, 52)
    local glow = plate:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(UI.MEDIA .. "ButtonGlow")
    glow:SetPoint("TOPLEFT", -14, 10)
    glow:SetPoint("BOTTOMRIGHT", 14, -10)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.85, 0.3)
    UI.AddPulse(glow, 0.3, 0.6)
    plate.glow = glow
    local bg = plate:CreateTexture(nil, "BORDER")
    bg:SetColorTexture(0, 0, 0, 0.45)
    bg:SetAllPoints()
    plate.crest = plate:CreateTexture(nil, "ARTWORK")
    plate.crest:SetSize(44, 44)
    plate.crest:SetPoint("LEFT", 4, 0)
    plate.name = UI.Text(plate, "", { fancy = true, size = 18 })
    plate.name:SetPoint("TOPLEFT", plate.crest, "TOPRIGHT", 8, -4)
    plate.name:SetWidth(186)
    plate.sub = UI.Text(plate, "", { font = "GameFontHighlightSmall" })
    plate.sub:SetPoint("TOPLEFT", plate.name, "BOTTOMLEFT", 0, -3)
    return plate
end

local function Say(s)
    if s.status == "ended" then
        local r = s.result or {}
        if r.outcome == "win" then UI:Say("HA! Knew you had it in ya. Rematch? Winners keep winning, I hear.")
        elseif r.outcome == "loss" then UI:Say("Ouch. Shake it off, champ. Rematch?")
        elseif r.outcome == "draw" then UI:Say("A draw! Nobody wins, nobody pays. My least favourite outcome.")
        else UI:Say("Game over" .. (r.reason and (": " .. r.reason) or "") .. ". Head back to Games for another round.") end
    elseif GG:IsCommLocked() then
        UI:Say("Boss fight! Blizzard pauses addon messages during encounters. We'll pick up right after.")
    elseif GG.Turns:IsMyTurn(s) then
        UI:Say("Your turn! " .. (s.def and s.def.hint or ""))
    elseif GG.Turns:Current(s) then
        UI:Say("Waiting on " .. Util.ShortName(GG.Turns:Current(s)) .. "... *taps foot*  (Rules? Press the |cff1f7a12?|r up top.)")
    end
end

function UI:RefreshGamePanel()
    if not panel or not panel:IsShown() then return end
    local s = GG.Lobby.active
    if not s or s.status == "lobby" then return end

    -- Big boards (Connect 6) ask for a compact header: no name plates, the
    -- status on the left and the fuse on the right, so the board gets the room.
    local compact = s.def and s.def.compactHeader
    if compact ~= panel.compact then
        panel.compact = compact
        statusText:ClearAllPoints()
        fuse:ClearAllPoints()
        area:ClearAllPoints()
        if compact then
            statusText:SetPoint("TOPLEFT", 4, -2)
            fuse:SetPoint("TOPRIGHT", -4, -8)
            area:SetPoint("TOPLEFT", 0, -30)
        else
            statusText:SetPoint("TOP", 0, -64)
            fuse:SetPoint("TOP", vsText, "BOTTOM", 0, -2)
            area:SetPoint("TOPLEFT", 0, -90)
        end
        area:SetPoint("BOTTOMRIGHT", 0, 0)
    end

    -- Name plates: two players face off left vs right; more players line up.
    local current = GG.Turns:Current(s)
    local count = compact and 0 or math.min(#s.players, 4)
    for i = 1, count do
        local name = s.players[i]
        local plate = plates[i]
        if not plate then
            plate = Plate(panel)
            plates[i] = plate
        end
        plate:ClearAllPoints()
        if count == 2 then
            plate:SetPoint(i == 1 and "TOPLEFT" or "TOPRIGHT", 0, -2)
        else
            plate:SetWidth(168)
            plate:SetPoint("TOPLEFT", (i - 1) * 176, -2)
        end
        GG.Theme:SetCrest(plate.crest, s:GetFaction(name))
        local label = Util.ShortName(name)
        if Util.IsMe(name) then label = label .. " (you)" end
        plate.name:SetText(label)
        local sub
        if s.left[name] then sub = UI.Grey("Out of the game")
        elseif s.offlineSince[name] then sub = UI.Red("Offline... waiting")
        elseif s.status == "playing" and name == current then sub = UI.Gold(Util.IsMe(name) and "Your turn!" or "Thinking...")
        else sub = UI.Grey(Util.IsBot(name) and "Made of straw" or (s:GetFaction(name) .. " champion")) end
        plate.sub:SetText(sub)
        local active = s.status == "playing" and name == current
        plate.glow:SetShown(active)
        if active then plate.glow.pulse:Play() else plate.glow.pulse:Stop() end
        plate:Show()
    end
    for i = count + 1, #plates do plates[i]:Hide() end
    vsText:SetShown(count == 2)
    statusText:SetJustifyH(compact and "LEFT" or "CENTER")

    -- Status line.
    local text
    if customStatus then
        text = customStatus
    elseif s.status == "ended" then
        text = ""
    elseif GG:IsCommLocked() then
        text = UI.Grey("Paused for a boss fight")
    elseif GG.Turns:IsMyTurn(s) then
        text = UI.Gold("Your turn!")
    elseif current then
        text = Util.ShortName(current) .. "'s turn"
    else
        text = UI.Grey("Shuffling...")
    end
    statusText:SetText(text)

    -- Result banner and buttons.
    local ended = s.status == "ended"
    if ended then
        local r = s.result or {}
        if r.outcome == "win" then banner:SetText("Victory!"); banner:SetColorKey("gold")
        elseif r.outcome == "loss" then banner:SetText("Defeat"); banner:SetColorKey("grey")
        elseif r.outcome == "draw" then banner:SetText("Draw!"); banner:SetColorKey("wood")
        else banner:SetText("Game over"); banner:SetColorKey("grey") end
        if not banner:IsShown() then
            banner:Show()
            banner.popIn:Play()
        end
        if r.outcome == "win" and celebrated ~= s then
            celebrated = s
            UI:CoinShower(UI.frame)
        end
    else
        banner:Hide()
    end

    quitButton:SetShown(not ended)
    -- Modules can rename it (Guild Bingo: "End night" for the host, "Leave" for players).
    local quitText = s.def and s.def.QuitLabel and GG:CallModule(s.def, "QuitLabel", s)
    quitButton:SetText(quitText or (s.isLocal and "Quit" or "Forfeit"))
    rematchButton:SetShown(ended and s:IsHost())
    backButton:SetShown(ended)
    Say(s)
end

UI:RegisterPanel("game", nil, function(container)
    panel = CreateFrame("Frame", nil, container)
    plates = {}

    vsText = UI.Text(panel, "VS", { fancy = true, size = 34, justify = "CENTER" })
    vsText:SetPoint("TOP", 0, -2)
    vsText:SetTextColor(1, 0.8, 0.25)

    -- The turn timer is a fuse that burns down.
    fuse = CreateFrame("StatusBar", nil, panel)
    fuse:SetSize(150, 8)
    fuse:SetPoint("TOP", vsText, "BOTTOM", 0, -2)
    fuse:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    fuse:SetMinMaxValues(0, 1)
    local fuseBg = fuse:CreateTexture(nil, "BACKGROUND")
    fuseBg:SetColorTexture(0, 0, 0, 0.5)
    fuseBg:SetAllPoints()
    fuseText = UI.Text(panel, "", { font = "GameFontHighlightSmall", justify = "CENTER" })
    fuseText:SetPoint("TOP", fuse, "BOTTOM", 0, -2)

    statusText = UI.Text(panel, "", { fancy = true, size = 20, justify = "CENTER" })
    statusText:SetPoint("TOP", 0, -64)

    area = CreateFrame("Frame", nil, panel)
    area:SetPoint("TOPLEFT", 0, -90)
    area:SetPoint("BOTTOMRIGHT", 0, 0)

    banner = UI.Ribbon(panel, "", 460, 92, "gold")
    banner:SetPoint("CENTER", area, "CENTER", 0, 10)
    banner:SetFrameLevel(panel:GetFrameLevel() + 40)
    banner.text:SetTextColor(1, 1, 0.9)
    UI.AddPopIn(banner)
    banner:Hide()

    -- Buttons live in the window's bottom-right corner.
    local actions = CreateFrame("Frame", nil, panel)
    actions:SetSize(1, 1)
    actions:SetPoint("BOTTOMRIGHT", UI.frame.actions, "BOTTOMRIGHT")
    quitButton = UI.Button(actions, "Forfeit", 110, 36, function()
        local s = GG.Lobby.active
        if not s then return end
        if s.isLocal then GG.Lobby:Close(s) else GG.Lobby:Leave(s) end
    end, "danger")
    quitButton:SetPoint("BOTTOMRIGHT")
    backButton = UI.Button(actions, "Back to games", 150, 36, function()
        local s = GG.Lobby.active
        if s then GG.Lobby:Close(s) end
    end, "wood")
    backButton:SetPoint("BOTTOMRIGHT")
    rematchButton = UI.Button(actions, "Rematch!", 130, 36, function()
        local s = GG.Lobby.active
        if s then
            local ok, err = GG.Lobby:Rematch(s)
            if not ok and err then GG:Print(err); UI:Say(err, true) end
        end
    end, "primary")
    rematchButton:SetPoint("RIGHT", backButton, "LEFT", -8, 0)

    -- Fuse: updated every frame while visible.
    panel:SetScript("OnUpdate", function()
        local s = GG.Lobby.active
        local remaining = s and s.status == "playing" and GG.Turns:Remaining(s)
        local length = s and s.turn and s.turn.length
        if remaining and length and length > 0 then
            local f = remaining / length
            fuse:SetValue(f)
            fuse:SetStatusBarColor(1, 0.35 + 0.5 * f, 0.1)
            fuseText:SetText(remaining < 10 and UI.Red(Util.FormatSeconds(remaining)) or Util.FormatSeconds(remaining))
            fuse:Show()
        else
            fuse:Hide()
            fuseText:SetText("")
        end
    end)

    panel:SetScript("OnShow", function() UI:RefreshGamePanel() end)

    local listener = {}
    local function Refresh() UI:RefreshGamePanel() end
    GG.RegisterCallback(listener, "TURN_CHANGED", Refresh)
    GG.RegisterCallback(listener, "SESSION_UPDATED", Refresh)
    GG.RegisterCallback(listener, "SESSION_ENDED", Refresh)
    GG.RegisterCallback(listener, "COMM_LOCK_CHANGED", Refresh)
    GG.RegisterCallback(listener, "SESSION_STARTED", function()
        customStatus = nil
        banner:Hide()
        Refresh()
    end)
    GG.RegisterCallback(listener, "SESSION_CLOSED", function()
        customStatus = nil
        banner:Hide()
    end)
    return panel
end)
