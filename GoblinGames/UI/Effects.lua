--[[----------------------------------------------------------------------------
  GoblinGames/UI/Effects.lua

  Celebrations: a shower of gold coins and confetti when you win.

  Each coin is a texture with its own AnimationGroup (fall + spin + fade).
  We keep them in a pool and reuse them, rather than making new textures every
  time; WoW never frees textures, so pooling keeps memory flat.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI

local pool = {}
local layer

local CONFETTI = {
    { 1.00, 0.84, 0.25 }, { 0.40, 0.85, 0.30 }, { 0.95, 0.35, 0.30 },
    { 0.35, 0.65, 1.00 }, { 1.00, 0.55, 0.90 },
}

local function GetPiece()
    for _, piece in ipairs(pool) do
        if not piece.anim:IsPlaying() then return piece end
    end
    local tex = layer:CreateTexture(nil, "OVERLAY")
    local g = tex:CreateAnimationGroup()
    tex.fall = g:CreateAnimation("Translation")
    tex.spin = g:CreateAnimation("Rotation")
    tex.fade = g:CreateAnimation("Alpha")
    tex.fade:SetFromAlpha(1)
    tex.fade:SetToAlpha(0)
    g:SetScript("OnFinished", function() tex:Hide() end)
    tex.anim = g
    pool[#pool + 1] = tex
    return tex
end

--- Rain coins (and confetti) over a frame for a couple of seconds.
function UI:CoinShower(target, count)
    if not layer then
        layer = CreateFrame("Frame", nil, UIParent)
        layer:SetFrameStrata("FULLSCREEN_DIALOG")
    end
    layer:ClearAllPoints()
    layer:SetAllPoints(target)
    layer:Show()

    local width, height = target:GetWidth(), target:GetHeight()
    for i = 1, count or 36 do
        local piece = GetPiece()
        local isCoin = i % 3 ~= 0
        if isCoin then
            piece:SetTexture(UI.MEDIA .. "Coin")
            piece:SetVertexColor(1, 1, 1)
            local s = math.random(18, 30)
            piece:SetSize(s, s)
        else
            piece:SetTexture(UI.MEDIA .. "Spark")
            local c = CONFETTI[math.random(#CONFETTI)]
            piece:SetVertexColor(c[1], c[2], c[3])
            local s = math.random(10, 16)
            piece:SetSize(s, s)
        end
        piece:ClearAllPoints()
        piece:SetPoint("BOTTOM", layer, "TOPLEFT", math.random(10, math.max(20, math.floor(width) - 10)), -math.random(0, 40))

        local duration = 1.4 + math.random() * 1.2
        piece.fall:SetOffset(math.random(-40, 40), -(height + 60))
        piece.fall:SetDuration(duration)
        piece.fall:SetSmoothing("IN")
        piece.spin:SetDegrees(math.random(-540, 540))
        piece.spin:SetDuration(duration)
        piece.fade:SetStartDelay(duration * 0.7)
        piece.fade:SetDuration(duration * 0.3)
        piece.anim:Stop()
        piece:Show()
        -- Stagger the start so it pours rather than drops all at once.
        local delay = math.random() * 0.7
        piece.fall:SetStartDelay(delay)
        piece.spin:SetStartDelay(delay)
        piece.fade:SetStartDelay(delay + duration * 0.7)
        piece.anim:Play()
    end
end
