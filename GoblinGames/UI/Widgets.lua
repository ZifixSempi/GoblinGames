--[[----------------------------------------------------------------------------
  GoblinGames/UI/Widgets.lua

  Small building blocks for our windows, all created in Lua with CreateFrame.

  Why Lua instead of XML for frames? Both work. XML is nice for static layouts,
  but our windows change with the game being played, and building them in Lua
  keeps each piece next to the code that drives it. Game modules are free to
  use XML for their boards if they prefer.

  Taint note: every frame here is a plain (insecure) frame we own. We never
  touch Blizzard's protected frames or call protected functions, so opening our
  window in combat is safe.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = {}
GG.UI = UI

-- "BackdropTemplate" gives a frame SetBackdrop(); it exists on every current
-- client, the check is just defensive.
UI.BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

--- A themed panel (faction border and background).
function UI.Panel(parent, variant)
    local f = CreateFrame("Frame", nil, parent, UI.BACKDROP)
    GG.Theme:ApplyFrame(f, variant)
    return f
end

--- A standard red Blizzard button.
function UI.Button(parent, text, width, height, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, height or 22)
    b:SetText(text)
    if onClick then
        b:SetScript("OnClick", function(self, ...)
            GG.Theme:PlaySound("click")
            onClick(self, ...)
        end)
    end
    return b
end

--- A text label.
function UI.Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

--- A checkbox with its own label. We add our own FontString instead of using
--- the template's, because its name differs between clients (.text / .Text).
function UI.Checkbox(parent, label, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local fs = UI.Label(cb, label)
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label = fs
    cb:SetScript("OnShow", function(self) self:SetChecked(getter()) end)
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
        GG.Theme:PlaySound("click")
    end)
    return cb
end

--- A button that cycles through a list of choices on each click.
--- options = { { value = x, text = "Shown" }, ... }
--- We use this instead of a dropdown menu: Blizzard's dropdown APIs differ a
--- lot between Retail and Classic, and older dropdowns were a known taint source.
function UI.CycleButton(parent, label, options, getter, setter, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize((width or 160) + 170, 24)
    local fs = UI.Label(holder, label)
    fs:SetPoint("LEFT")
    fs:SetWidth(165)
    local b = UI.Button(holder, "", width or 160, 22)
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
        local nextOption = options[index % #options + 1]
        setter(nextOption.value)
        GG.Theme:PlaySound("click")
        Refresh()
    end)
    holder:SetScript("OnShow", Refresh)
    holder.Refresh = Refresh
    return holder
end

--- A one-line text input.
function UI.EditBox(parent, width, onEnter)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width or 140, 20)
    e:SetAutoFocus(false)
    e:SetScript("OnEnterPressed", function(self)
        if onEnter then onEnter(self:GetText()) end
        self:ClearFocus()
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

--- A vertical scrolling list of rows.
--   list:SetItems(items) redraws; createRow(parent) builds one row frame;
--   updateRow(row, item) fills it in.
function UI.ScrollList(parent, rowHeight, createRow, updateRow)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)

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

--- Coloured text helpers.
function UI.Color(text, hex) return "|cff" .. hex .. text .. "|r" end
function UI.Grey(text) return UI.Color(text, "909090") end
function UI.Green(text) return UI.Color(text, "40ff40") end
function UI.Red(text) return UI.Color(text, "ff5050") end
function UI.Gold(text) return UI.Color(text, "ffd100") end
