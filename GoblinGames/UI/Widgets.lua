--[[----------------------------------------------------------------------------
  GoblinGames/UI/Widgets.lua

  The building blocks of the goblin-tavern look: wooden frames, parchment
  cards, chunky buttons, ribbons, speech bubbles and a few animations.

  ART: everything in GoblinGames\Media is our own original art (made by
  tools/art/make_art.py). Addons may ship their own textures and fonts; what
  we must NOT do is copy Blizzard's art files into the addon. Most textures are
  drawn in light neutral tones and tinted per faction with SetVertexColor
  (see Theme:Paint).

  FONT: titles use "Luckiest Guy" (Apache 2.0 licence, in Media). It only
  has Latin letters, so Russian, Korean and Chinese clients fall back to the
  game's own fonts automatically.

  WHY LUA, NOT XML: both work. These widgets are built from code because they
  change with the faction theme and the game being played. Taint-wise they're
  all plain frames we own; nothing here touches protected Blizzard frames.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = {}
GG.UI = UI

UI.MEDIA = "Interface\\AddOns\\GoblinGames\\Media\\"
UI.BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

local FANCY_FONT = UI.MEDIA .. "LuckiestGuy-Regular.ttf"
local NON_LATIN = { koKR = true, zhCN = true, zhTW = true, ruRU = true }
local useFancy = not NON_LATIN[GetLocale()]

-- Text colours: light text on wood, dark ink on parchment.
UI.INK = { 0.29, 0.17, 0.07 }
UI.CREAM = { 1.00, 0.95, 0.80 }

-------------------------------------------------------------------------------
-- Text
-------------------------------------------------------------------------------

--- Set a FontString to the chunky title font (or the game font as fallback).
function UI.FancyFont(fs, size)
    if useFancy then fs:SetFont(FANCY_FONT, size, "") end
    if not fs:GetFont() then
        fs:SetFontObject(size >= 22 and "GameFontNormalHuge" or size >= 15 and "GameFontNormalLarge" or "GameFontNormal")
    end
    fs:SetShadowOffset(1, -2)
    fs:SetShadowColor(0, 0, 0, 0.85)
end

--- Create text.
-- opts.size   fancy font size (only with opts.fancy)
-- opts.fancy  use the title font
-- opts.ink    dark text for parchment
-- opts.font   a Blizzard font object name for body text (default GameFontHighlight)
function UI.Text(parent, text, opts)
    opts = opts or {}
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if opts.fancy then
        UI.FancyFont(fs, opts.size or 16)
    else
        fs:SetFontObject(opts.font or "GameFontHighlight")
    end
    if opts.ink then
        fs:SetTextColor(UI.INK[1], UI.INK[2], UI.INK[3])
        fs:SetShadowColor(0, 0, 0, 0)
    elseif opts.color then
        fs:SetTextColor(opts.color[1], opts.color[2], opts.color[3])
    elseif opts.fancy then
        fs:SetTextColor(UI.CREAM[1], UI.CREAM[2], UI.CREAM[3])
    end
    fs:SetJustifyH(opts.justify or "LEFT")
    fs:SetText(text or "")
    return fs
end

--- Plain label with a Blizzard font object (kept for modules).
function UI.Label(parent, text, font)
    return UI.Text(parent, text, { font = font })
end

-------------------------------------------------------------------------------
-- Nine-slice: stretch a framed texture to any size without distorting corners
-------------------------------------------------------------------------------

--- file: texture path; texSize: its width (square); corner: corner size in the
--- texture (px); screen: corner size on screen. Returns the 9 textures.
function UI.NineSlice(frame, file, texSize, corner, screen, layer, sublevel)
    local c = corner / texSize
    local parts = {}
    local function Part(l, r, t, b)
        local tex = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
        tex:SetTexture(file)
        tex:SetTexCoord(l, r, t, b)
        parts[#parts + 1] = tex
        return tex
    end
    local tl = Part(0, c, 0, c);         tl:SetSize(screen, screen); tl:SetPoint("TOPLEFT")
    local tr = Part(1 - c, 1, 0, c);     tr:SetSize(screen, screen); tr:SetPoint("TOPRIGHT")
    local bl = Part(0, c, 1 - c, 1);     bl:SetSize(screen, screen); bl:SetPoint("BOTTOMLEFT")
    local br = Part(1 - c, 1, 1 - c, 1); br:SetSize(screen, screen); br:SetPoint("BOTTOMRIGHT")
    local t = Part(c, 1 - c, 0, c);      t:SetPoint("TOPLEFT", tl, "TOPRIGHT"); t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    local b = Part(c, 1 - c, 1 - c, 1);  b:SetPoint("TOPLEFT", bl, "TOPRIGHT"); b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local l = Part(0, c, c, 1 - c);      l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    local r = Part(1 - c, 1, c, 1 - c);  r:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    local m = Part(c, 1 - c, c, 1 - c);  m:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); m:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    return parts
end

--- A parchment card (dark text goes on these).
function UI.Card(parent)
    local card = CreateFrame("Frame", nil, parent)
    card.parts = UI.NineSlice(card, UI.MEDIA .. "Parchment", 128, 24, 18)
    return card
end

-------------------------------------------------------------------------------
-- Animations
--
-- AnimationGroups are Blizzard's built-in tweening: they move, scale, rotate
-- or fade a frame or texture smoothly without us running code every frame.
-------------------------------------------------------------------------------
local function ScaleAnim(group, from, to, duration, order)
    local a = group:CreateAnimation("Scale")
    if a.SetScaleFrom then
        a:SetScaleFrom(from, from)
        a:SetScaleTo(to, to)
    else
        a:SetScale(to / from, to / from)
    end
    a:SetDuration(duration)
    if order then a:SetOrder(order) end
    return a
end
UI.ScaleAnim = ScaleAnim

--- A quick "boing": grow a little and settle back. Call region.bounce:Play().
function UI.AddBounce(region, amount)
    local g = region:CreateAnimationGroup()
    local up = ScaleAnim(g, 1, amount or 1.12, 0.09, 1)
    up:SetSmoothing("OUT")
    local down = ScaleAnim(g, amount or 1.12, 1, 0.16, 2)
    down:SetSmoothing("IN_OUT")
    region.bounce = g
    return g
end

--- Gentle endless bobbing up and down (mascot, turn arrow).
function UI.AddBob(region, pixels, seconds)
    local g = region:CreateAnimationGroup()
    g:SetLooping("BOUNCE")
    local a = g:CreateAnimation("Translation")
    a:SetOffset(0, pixels or 4)
    a:SetDuration(seconds or 0.9)
    a:SetSmoothing("IN_OUT")
    g:Play()
    return g
end

--- Endless soft pulse of transparency (glows, "your turn" highlights).
function UI.AddPulse(region, low, seconds)
    local g = region:CreateAnimationGroup()
    g:SetLooping("BOUNCE")
    local a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(low or 0.35)
    a:SetDuration(seconds or 0.7)
    a:SetSmoothing("IN_OUT")
    region.pulse = g
    return g
end

--- Pop in: start big and see-through, land at normal size. region.popIn:Play()
function UI.AddPopIn(region)
    local g = region:CreateAnimationGroup()
    local s = ScaleAnim(g, 1.8, 1, 0.22)
    s:SetSmoothing("OUT")
    local a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(0.15)
    region.popIn = g
    return g
end

-------------------------------------------------------------------------------
-- Buttons
--
-- Styles: "primary" (faction colour: the main action), "wood" (secondary),
-- "danger" (forfeit / cancel), "accent". The texture is three slices (left
-- cap, stretchy middle, right cap) so buttons can be any width.
-------------------------------------------------------------------------------
local BUTTON_TEX = UI.MEDIA .. "Button"

function UI.Button(parent, text, width, height, onClick, style)
    height = height or 30
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, height)
    b.style = style or "wood"

    local cap = height * 0.5   -- each cap is 32x64 px in the texture: half as wide as tall
    local l = b:CreateTexture(nil, "BACKGROUND")
    l:SetTexture(BUTTON_TEX); l:SetTexCoord(0, 0.125, 0, 1)
    l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(cap)
    local r = b:CreateTexture(nil, "BACKGROUND")
    r:SetTexture(BUTTON_TEX); r:SetTexCoord(0.875, 1, 0, 1)
    r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMRIGHT"); r:SetWidth(cap)
    local m = b:CreateTexture(nil, "BACKGROUND")
    m:SetTexture(BUTTON_TEX); m:SetTexCoord(0.125, 0.875, 0, 1)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    b.parts = { l, m, r }

    local glow = b:CreateTexture(nil, "ARTWORK")
    glow:SetTexture(UI.MEDIA .. "ButtonGlow")
    glow:SetAllPoints()
    glow:SetBlendMode("ADD")
    glow:Hide()

    local label = UI.Text(b, text, { fancy = true, size = math.floor(height * 0.46 + 0.5), justify = "CENTER" })
    label:SetPoint("CENTER", 0, 2)
    b.label = label

    -- Our own SetText/GetText so the label uses the fancy font.
    function b:SetText(t) label:SetText(t) end
    function b:GetText() return label:GetText() end

    function b:SetStyle(newStyle)
        self.style = newStyle
        for _, part in ipairs(self.parts) do GG.Theme:Paint(part, newStyle) end
    end
    b:SetStyle(b.style)

    UI.AddBounce(b, 1.06)
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then glow:Show(); self.bounce:Play() end
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        glow:Hide()
        GameTooltip:Hide()
    end)
    b:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then label:SetPoint("CENTER", 1, 0) end
    end)
    b:SetScript("OnMouseUp", function()
        label:SetPoint("CENTER", 0, 2)
    end)
    b:SetScript("OnDisable", function(self)
        for _, part in ipairs(self.parts) do part:SetDesaturated(true) end
        label:SetTextColor(0.6, 0.6, 0.6)
        glow:Hide()
    end)
    b:SetScript("OnEnable", function(self)
        for _, part in ipairs(self.parts) do part:SetDesaturated(false) end
        label:SetTextColor(UI.CREAM[1], UI.CREAM[2], UI.CREAM[3])
    end)
    if onClick then
        b:SetScript("OnClick", function(self, ...)
            GG.Theme:PlaySound("click")
            onClick(self, ...)
        end)
    end
    return b
end

-------------------------------------------------------------------------------
-- Ribbon banner with text
-------------------------------------------------------------------------------
function UI.Ribbon(parent, text, width, height, colorKey)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 300, height or 64)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(UI.MEDIA .. "Ribbon")
    tex:SetAllPoints()
    GG.Theme:Paint(tex, colorKey or "accent")
    f.tex = tex
    local fs = UI.Text(f, text, { fancy = true, size = math.floor((height or 64) * 0.36), justify = "CENTER" })
    fs:SetPoint("CENTER", 0, (height or 64) * 0.10)
    f.text = fs
    function f:SetText(t) fs:SetText(t) end
    function f:SetColorKey(key) GG.Theme:Paint(tex, key) end
    return f
end

-------------------------------------------------------------------------------
-- Speech bubble (the tail points left, at whoever is talking)
-------------------------------------------------------------------------------
function UI.Bubble(parent)
    local f = CreateFrame("Frame", nil, parent)
    UI.NineSlice(f, UI.MEDIA .. "Bubble", 128, 32, 16, "ARTWORK")
    local tail = f:CreateTexture(nil, "ARTWORK", nil, 1)
    tail:SetTexture(UI.MEDIA .. "BubbleTail")
    tail:SetSize(20, 20)
    tail:SetPoint("RIGHT", f, "LEFT", 4, -6)
    f.tail = tail
    local fs = UI.Text(f, "", { ink = true, font = "GameFontHighlight" })
    fs:SetPoint("TOPLEFT", 14, -10)
    fs:SetPoint("BOTTOMRIGHT", -14, 10)
    fs:SetJustifyV("MIDDLE")
    fs:SetWordWrap(true)
    f.text = fs
    return f
end

-------------------------------------------------------------------------------
-- Round game icon in a gold ring
-------------------------------------------------------------------------------
function UI.CoinIcon(parent, size, iconPath)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", size * 0.14, -size * 0.14)
    icon:SetPoint("BOTTOMRIGHT", -size * 0.14, size * 0.14)
    icon:SetTexture(iconPath)
    -- SetMask clips the square icon into a circle (newer clients); without it
    -- we just trim the icon's border.
    if icon.SetMask then
        icon:SetMask(UI.MEDIA .. "CircleMask")
    else
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local ring = f:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(UI.MEDIA .. "Ring")
    ring:SetAllPoints()
    f.icon, f.ring = icon, ring
    return f
end

-------------------------------------------------------------------------------
-- Form controls (used on parchment, so they use dark ink)
-------------------------------------------------------------------------------

--- A checkbox with its own label. We add our own FontString instead of the
--- template's, because its field name differs between clients (.text / .Text).
function UI.Checkbox(parent, label, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    local fs = UI.Text(cb, label, { ink = true })
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label = fs
    cb:SetScript("OnShow", function(self) self:SetChecked(getter()) end)
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
        GG.Theme:PlaySound("click")
    end)
    return cb
end

--- A button that cycles through choices on each click. We use this instead of
--- a dropdown: dropdown APIs differ a lot between Retail and Classic, and
--- older dropdowns were a well-known taint source.
--- options = { { value = x, text = "Shown" }, ... }
function UI.CycleButton(parent, label, options, getter, setter, width, labelWidth)
    labelWidth = labelWidth or 185
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize((width or 190) + labelWidth + 5, 30)
    local fs = UI.Text(holder, label, { ink = true })
    fs:SetPoint("LEFT")
    fs:SetWidth(labelWidth)
    local b = UI.Button(holder, "", width or 190, 28)
    b:SetPoint("LEFT", fs, "RIGHT", 4, 0)

    local function Refresh()
        local current = getter()
        for _, o in ipairs(options) do
            if o.value == current then b:SetText(o.text); return end
        end
        b:SetText(options[1].text)
    end
    b:SetScript("OnClick", function()
        local current = getter()
        local index = 1
        for i, o in ipairs(options) do if o.value == current then index = i end end
        setter(options[index % #options + 1].value)
        GG.Theme:PlaySound("click")
        Refresh()
    end)
    holder:SetScript("OnShow", Refresh)
    holder.Refresh = Refresh
    holder.button = b
    return holder
end

--- A one-line text input.
function UI.EditBox(parent, width, onEnter)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width or 140, 22)
    e:SetAutoFocus(false)
    e:SetScript("OnEnterPressed", function(self)
        if onEnter then onEnter(self:GetText()) end
        self:ClearFocus()
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

--- A vertical scrolling list. list:SetItems(items) redraws;
--- createRow(parent) builds a row, updateRow(row, item) fills it.
function UI.ScrollList(parent, rowHeight, createRow, updateRow)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)

    local rows = {}
    function scroll:SetItems(items)
        for i, item in ipairs(items) do
            local row = rows[i]
            if not row then
                row = createRow(content)
                row:SetHeight(rowHeight)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
                row:SetPoint("RIGHT", content, "RIGHT")
                rows[i] = row
            end
            updateRow(row, item)
            row:Show()
        end
        for i = #items + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(1, #items * rowHeight))
    end
    return scroll
end

-------------------------------------------------------------------------------
-- Ready-check icons (Blizzard textures, referenced not copied)
-------------------------------------------------------------------------------
UI.ICON_READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
UI.ICON_NO = "Interface\\RaidFrame\\ReadyCheck-NotReady"
UI.ICON_WAIT = "Interface\\RaidFrame\\ReadyCheck-Waiting"

-------------------------------------------------------------------------------
-- Colour codes for inline text
-------------------------------------------------------------------------------
function UI.Color(text, hex) return "|cff" .. hex .. text .. "|r" end
function UI.Grey(text) return UI.Color(text, "909090") end
function UI.Green(text) return UI.Color(text, "40ff40") end
function UI.Red(text) return UI.Color(text, "ff5050") end
function UI.Gold(text) return UI.Color(text, "ffd100") end
-- Darker versions that read well on parchment.
function UI.InkGreen(text) return UI.Color(text, "1f7a12") end
function UI.InkRed(text) return UI.Color(text, "a51d12") end
function UI.InkGrey(text) return UI.Color(text, "7a6a55") end
