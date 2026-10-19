--[[----------------------------------------------------------------------------
  GoblinGames/UI/DiceWidget.lua

  A die on screen (Media\Dice: our own art, faces 1-6 plus a hidden "?" die).

      local die = GG.UI.Die(parent, 40)
      die:SetFace(5)     -- show a five
      die:SetFace(0)     -- hidden (the "?" die)
      die:SetFace(nil)   -- hide it
      die:SetGlow(true)  -- highlight (e.g. dice that count for a bid)
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI

-- The sheet is 4 x 2 cells of 64px in a 256 x 128 texture.
local function CellCoords(cell)
    local col, row = (cell - 1) % 4, math.floor((cell - 1) / 4)
    return col / 4, (col + 1) / 4, row / 2, (row + 1) / 2
end

function UI.Die(parent, size, layer)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.tex = f:CreateTexture(nil, layer or "ARTWORK")
    f.tex:SetTexture(UI.MEDIA .. "Dice")
    f.tex:SetAllPoints()
    f.glow = f:CreateTexture(nil, "OVERLAY")
    f.glow:SetTexture(UI.MEDIA .. "ButtonGlow")
    f.glow:SetPoint("TOPLEFT", -size * 0.2, size * 0.2)
    f.glow:SetPoint("BOTTOMRIGHT", size * 0.2, -size * 0.2)
    f.glow:SetBlendMode("ADD")
    f.glow:SetVertexColor(0.4, 1, 0.4)
    f.glow:Hide()

    function f:SetFace(face)
        self.face = face
        if face == nil then self:Hide(); return end
        local cell = (face >= 1 and face <= 6) and face or 7
        self.tex:SetTexCoord(CellCoords(cell))
        self:Show()
    end
    function f:SetGlow(on) self.glow:SetShown(on and true or false) end
    UI.AddPopIn(f)
    f:SetFace(0)
    return f
end
