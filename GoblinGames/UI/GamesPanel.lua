--[[----------------------------------------------------------------------------
  GoblinGames/UI/GamesPanel.lua

  The game picker. Installed games get a big parchment card with two clear
  choices: "Play with friends" and "Practice". Games that aren't out yet sit
  on a "Coming soon" shelf as little coins, so they don't clutter the page.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI

local CARD_W, CARD_H, GAP = 340, 150, 12

local SAY = "Pick a game! |cff1f7a12Play with friends|r invites people, |cff1f7a12Practice|r is just you. New here? Press |cff1f7a12How to play|r."

local function Report(ok, err)
    if not ok and err then GG:Print(err); UI:Say(err, true) end
end

local function PlayerText(entry)
    if entry.max >= 100 then return entry.min .. "+ players" end
    if entry.min == entry.max then return entry.min .. " players" end
    return entry.min .. "-" .. entry.max .. " players"
end

local function BuildCard(parent, entry)
    local card = UI.Card(parent)
    card:SetSize(CARD_W, CARD_H)

    local coin = UI.CoinIcon(card, 70, entry.icon)
    coin:SetPoint("TOPLEFT", 12, -12)

    local name = UI.Text(card, entry.name, { fancy = true, size = 20, ink = true })
    name:SetPoint("TOPLEFT", coin, "TOPRIGHT", 10, -4)

    local players = UI.Text(card, PlayerText(entry), { ink = true, font = "GameFontNormalSmall" })
    players:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    players:SetTextColor(0.48, 0.38, 0.25)

    local desc = UI.Text(card, entry.desc, { ink = true, font = "GameFontHighlightSmall" })
    desc:SetPoint("TOPLEFT", players, "BOTTOMLEFT", 0, -6)
    desc:SetWidth(CARD_W - 110)

    local play = UI.Button(card, "Play with friends", 170, 32, function()
        Report(GG.Lobby:CreateHosted(entry.id))
    end, "primary")
    play:SetPoint("BOTTOMLEFT", 14, 14)

    if entry.practice then
        local practice = UI.Button(card, "Practice", 128, 32, function()
            Report(GG.Lobby:StartPractice(entry.id))
        end, "wood")
        practice:SetPoint("LEFT", play, "RIGHT", 8, 0)
        practice.tooltip = "Play the Training Dummy. Just you, no invites, doesn't count toward stats."
    end
    play.tooltip = "Open a lobby and invite people. The game starts once enough of them accept."

    local rules = UI.Button(card, "How to play", 96, 22, function() UI:ShowRules(entry.id) end, "wood")
    rules:SetPoint("TOPRIGHT", -12, -12)
    return card
end

local function BuildSoonCoin(parent, entry)
    local coin = UI.CoinIcon(parent, 46, entry.icon)
    coin.icon:SetDesaturated(true)
    coin.icon:SetVertexColor(0.8, 0.8, 0.8)
    coin:EnableMouse(true)
    coin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(entry.name)
        GameTooltip:AddLine(entry.desc, 1, 1, 1, true)
        GameTooltip:AddLine("Coming soon!", 0.6, 0.9, 0.4)
        GameTooltip:Show()
    end)
    coin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return coin
end

UI:RegisterPanel("games", "Games", function(container)
    local panel = CreateFrame("Frame", nil, container)

    local heading = UI.Text(panel, "Pick yer game!", { fancy = true, size = 24 })
    heading:SetPoint("TOPLEFT", 6, -4)

    -- Cards for installed games (scrolls once there are more than four).
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -40)
    scroll:SetPoint("BOTTOMRIGHT", -24, 74)
    local grid = CreateFrame("Frame", nil, scroll)
    grid:SetSize(CARD_W * 2 + GAP, 1)
    scroll:SetScrollChild(grid)

    -- Coming-soon shelf along the bottom.
    local shelf = CreateFrame("Frame", nil, panel)
    shelf:SetPoint("BOTTOMLEFT", 0, 0)
    shelf:SetPoint("BOTTOMRIGHT", 0, 0)
    shelf:SetHeight(66)
    local shelfBg = shelf:CreateTexture(nil, "BACKGROUND")
    shelfBg:SetColorTexture(0, 0, 0, 0.3)
    shelfBg:SetAllPoints()
    local soonLabel = UI.Text(shelf, "Coming\nsoon!", { fancy = true, size = 16, justify = "CENTER" })
    soonLabel:SetPoint("LEFT", 12, 0)

    local cards, soon = {}, {}

    local function Layout()
        for _, c in pairs(cards) do c:Hide() end
        for _, c in pairs(soon) do c:Hide() end
        local n, s = 0, 0
        for _, entry in ipairs(GG.CATALOG) do
            if GG:IsGameInstalled(entry.id) then
                local card = cards[entry.id] or BuildCard(grid, entry)
                cards[entry.id] = card
                local col, row = n % 2, math.floor(n / 2)
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", col * (CARD_W + GAP), -row * (CARD_H + GAP))
                card:Show()
                n = n + 1
            else
                local coin = soon[entry.id] or BuildSoonCoin(shelf, entry)
                soon[entry.id] = coin
                coin:ClearAllPoints()
                coin:SetPoint("LEFT", 96 + s * 52, 0)
                coin:Show()
                s = s + 1
            end
        end
        grid:SetHeight(math.max(1, math.ceil(n / 2) * (CARD_H + GAP)))
        shelf:SetShown(s > 0)
    end

    panel:SetScript("OnShow", function()
        Layout()
        UI:Say(SAY)
    end)
    return panel
end)

-- The "current" tab has no panel of its own: it shows the lobby or the game.
UI:RegisterPanel("current", "Your Game", function(container)
    return CreateFrame("Frame", nil, container)
end)
