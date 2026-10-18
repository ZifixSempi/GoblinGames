--[[----------------------------------------------------------------------------
  GoblinGames/UI/StatsPanel.lua

  "The Ledger": wins, losses and draws per game for this character, plus the
  opponents you've played most. Practice games don't count.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI
local Util = GG.Util

local function TopOpponents(opponents, limit)
    local list = {}
    for name, o in pairs(opponents) do
        list[#list + 1] = { name = name, w = o.w, l = o.l, d = o.d, total = o.w + o.l + o.d }
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    for i = limit + 1, #list do list[i] = nil end
    return list
end

UI:RegisterPanel("stats", "Stats", function(container)
    local panel = CreateFrame("Frame", nil, container)

    local card = UI.Card(panel)
    card:SetAllPoints()

    local heading = UI.Text(card, "The Ledger", { fancy = true, size = 26, ink = true })
    heading:SetPoint("TOPLEFT", 22, -16)
    local sub = UI.Text(card, "Every win, loss and draw, written down in very small print.", { ink = true, font = "GameFontHighlightSmall" })
    sub:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -2)
    sub:SetTextColor(0.48, 0.38, 0.25)

    local list = UI.ScrollList(card, 24,
        function(parent)
            local row = CreateFrame("Frame", nil, parent)
            row.left = UI.Text(row, "", { ink = true })
            row.left:SetPoint("LEFT", 4, 0)
            row.right = UI.Text(row, "", { ink = true })
            row.right:SetPoint("RIGHT", -8, 0)
            row.line = row:CreateTexture(nil, "BACKGROUND")
            row.line:SetColorTexture(0.45, 0.30, 0.15, 0.25)
            row.line:SetHeight(1)
            row.line:SetPoint("BOTTOMLEFT")
            row.line:SetPoint("BOTTOMRIGHT")
            return row
        end,
        function(row, item)
            if item.header then
                UI.FancyFont(row.left, 17)
                row.left:SetShadowColor(0, 0, 0, 0)
            else
                row.left:SetFontObject("GameFontHighlightSmall")
            end
            row.left:SetTextColor(UI.INK[1], UI.INK[2], UI.INK[3])
            row.left:SetText(item.left)
            row.right:SetText(item.right or "")
            row.line:SetShown(item.header == true)
        end)
    list:SetPoint("TOPLEFT", 18, -66)
    list:SetPoint("BOTTOMRIGHT", -40, 18)

    panel:SetScript("OnShow", function()
        local items = {}
        local totalWins = 0
        for _, entry in ipairs(GG.CATALOG) do
            local s = GG.Stats:Get(entry.id)
            local played = s.wins + s.losses + s.draws
            totalWins = totalWins + s.wins
            if played > 0 then
                items[#items + 1] = {
                    header = true,
                    left = entry.name,
                    right = ("%s   %s   %s"):format(UI.InkGreen(s.wins .. " won"), UI.InkRed(s.losses .. " lost"), UI.InkGrey(s.draws .. " drawn")),
                }
                for _, o in ipairs(TopOpponents(s.opponents, 5)) do
                    items[#items + 1] = {
                        left = "     vs " .. Util.ShortName(o.name),
                        right = UI.InkGrey(("%d-%d-%d"):format(o.w, o.l, o.d)),
                    }
                end
            end
        end
        if #items == 0 then
            items[1] = { left = UI.InkGrey("Nothing yet! Play a game with a friend to get on the books.") }
            UI:Say("An empty ledger! Go win something. Practice games don't count, by the way.")
        elseif totalWins == 0 then
            UI:Say("No wins yet? Everyone starts somewhere. Usually lower than that.")
        else
            UI:Say("Look at all those wins! I'm putting you on a poster.")
        end
        list:SetItems(items)
    end)
    return panel
end)
