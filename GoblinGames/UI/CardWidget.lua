--[[----------------------------------------------------------------------------
  GoblinGames/UI/CardWidget.lua

  A playing card on screen, for every card game:

      local c = GG.UI.PlayingCard(parent, 64)   -- width; height is 1.43x
      c:SetCard("QH")    -- face up: queen of hearts
      c:SetBack()        -- face down (goblin card back)
      c:SetSelected(true)  c:SetDim(true)  c:SetGlow(true)
      c.onClick = function(card, button) ... end

  All art is ours (Media\CardFace, CardBack, Suits). Everything is drawn on
  the card's own frame with draw layers, so the stacking can't get mixed up.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI
local Cards = GG.Cards

local CROP = 183 / 256 -- the card occupies the top of a 128x256 texture
local SUIT_COORDS = { S = { 0, 0.25 }, H = { 0.25, 0.5 }, D = { 0.5, 0.75 }, C = { 0.75, 1 } }

local function SuitTexture(parent, layer, size)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(UI.MEDIA .. "Suits")
    t:SetSize(size, size)
    return t
end

function UI.PlayingCard(parent, width)
    width = width or 64
    local height = math.floor(width * 1.43 + 0.5)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(width, height)

    c.shadow = c:CreateTexture(nil, "BACKGROUND")
    c.shadow:SetColorTexture(0, 0, 0, 0.35)
    c.shadow:SetPoint("TOPLEFT", 3, -3)
    c.shadow:SetPoint("BOTTOMRIGHT", 3, -3)

    c.face = c:CreateTexture(nil, "BORDER")
    c.face:SetTexture(UI.MEDIA .. "CardFace")
    c.face:SetTexCoord(0, 1, 0, CROP)
    c.face:SetAllPoints()

    c.back = c:CreateTexture(nil, "BORDER", nil, 1)
    c.back:SetTexture(UI.MEDIA .. "CardBack")
    c.back:SetTexCoord(0, 1, 0, CROP)
    c.back:SetAllPoints()

    c.rank = UI.Text(c, "", { fancy = true, size = math.floor(width * 0.30), justify = "CENTER" })
    c.rank:SetPoint("TOPLEFT", width * 0.07, -height * 0.05)
    c.rank:SetShadowColor(0, 0, 0, 0)
    c.smallSuit = SuitTexture(c, "ARTWORK", width * 0.26)
    c.smallSuit:SetPoint("TOP", c.rank, "BOTTOM", 0, 0)
    c.bigSuit = SuitTexture(c, "ARTWORK", width * 0.62)
    c.bigSuit:SetPoint("CENTER", width * 0.06, -height * 0.08)
    c.rank2 = UI.Text(c, "", { fancy = true, size = math.floor(width * 0.22), justify = "CENTER" })
    c.rank2:SetPoint("BOTTOMRIGHT", -width * 0.08, height * 0.05)
    c.rank2:SetShadowColor(0, 0, 0, 0)

    c.dim = c:CreateTexture(nil, "OVERLAY")
    c.dim:SetColorTexture(0, 0, 0, 0.45)
    c.dim:SetAllPoints()
    c.dim:Hide()

    c.glow = c:CreateTexture(nil, "OVERLAY", nil, 1)
    c.glow:SetTexture(UI.MEDIA .. "ButtonGlow")
    c.glow:SetPoint("TOPLEFT", -8, 8)
    c.glow:SetPoint("BOTTOMRIGHT", 8, -8)
    c.glow:SetBlendMode("ADD")
    c.glow:SetVertexColor(1, 0.85, 0.3)
    c.glow:Hide()
    UI.AddPulse(c.glow, 0.35, 0.5)

    local hover = c:CreateTexture(nil, "HIGHLIGHT")
    hover:SetTexture(UI.MEDIA .. "ButtonGlow")
    hover:SetAllPoints()
    hover:SetBlendMode("ADD")
    c.hover = hover

    UI.AddPopIn(c)

    function c:SetCard(card)
        self.card = card
        self.back:Hide()
        self.face:Show()
        local rank, suit = Cards.Rank(card), Cards.Suit(card)
        local label = Cards.RankLabel(rank)
        local col = Cards.IsRed(card) and { 0.78, 0.10, 0.12 } or { 0.12, 0.12, 0.16 }
        self.rank:SetText(label)
        self.rank:SetTextColor(col[1], col[2], col[3])
        self.rank2:SetText(label)
        self.rank2:SetTextColor(col[1], col[2], col[3])
        local sc = SUIT_COORDS[suit]
        self.smallSuit:SetTexCoord(sc[1], sc[2], 0, 1)
        self.bigSuit:SetTexCoord(sc[1], sc[2], 0, 1)
        self.smallSuit:Show(); self.bigSuit:Show(); self.rank:Show(); self.rank2:Show()
    end

    function c:SetBack()
        self.card = nil
        self.back:Show()
        self.smallSuit:Hide(); self.bigSuit:Hide(); self.rank:Hide(); self.rank2:Hide()
    end

    function c:SetSelected(on)
        self.selected = on
        self.glow:SetShown(on and true or false)
        if on then self.glow.pulse:Play() end
    end

    function c:SetDim(on) self.dim:SetShown(on and true or false) end

    function c:SetClickable(on)
        self:EnableMouse(on and true or false)
        self.hover:SetAlpha(on and 1 or 0)
    end

    c:SetScript("OnClick", function(self, button)
        if self.onClick then GG:Safe("Cards", self.onClick, self, button) end
    end)

    c:SetBack()
    return c
end
