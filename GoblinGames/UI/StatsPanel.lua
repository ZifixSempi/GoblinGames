--[[----------------------------------------------------------------------------
  GoblinGames/UI/StatsPanel.lua

  Wins, losses and draws per game for this character, plus the opponents
  you've played most. Practice games against the Training Dummy don't count.
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

    local heading = UI.Label(panel, "Your record", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 4, 0)

    local list = UI.ScrollList(panel, 20,
        function(parent)
            local row = CreateFrame("Frame", nil, parent)
            row.left = UI.Label(row, "")
            row.left:SetPoint("LEFT", 4, 0)
            row.right = UI.Label(row, "")
            row.right:SetPoint("RIGHT", -8, 0)
            return row
        end,
        function(row, item)
            row.left:SetText(item.left)
            row.left:SetFontObject(item.header and "GameFontNormal" or "GameFontHighlightSmall")
            row.right:SetText(item.right or "")
        end)
    list:SetPoint("TOPLEFT", 0, -30)
    list:SetPoint("BOTTOMRIGHT", -24, 0)

    panel:SetScript("OnShow", function()
        local items = {}
        for _, entry in ipairs(GG.CATALOG) do
            local s = GG.Stats:Get(entry.id)
            local played = s.wins + s.losses + s.draws
            if played > 0 then
                items[#items + 1] = {
                    header = true,
                    left = GG.Theme:TitleText(entry.name),
                    right = ("%s  %s  %s"):format(UI.Green(s.wins .. " W"), UI.Red(s.losses .. " L"), UI.Grey(s.draws .. " D")),
                }
                for _, o in ipairs(TopOpponents(s.opponents, 5)) do
                    items[#items + 1] = {
                        left = "    vs " .. Util.ShortName(o.name),
                        right = ("%d-%d-%d"):format(o.w, o.l, o.d),
                    }
                end
            end
        end
        if #items == 0 then
            items[1] = { left = UI.Grey("No games played yet. Practice games don't count.") }
        end
        list:SetItems(items)
    end)
    return panel
end)
