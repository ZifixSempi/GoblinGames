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
            row.button = UI.Button(row, "Paid", 64, 20, function(self)
                if self.onClick then self.onClick() end
            end, "wood")
            row.button:SetPoint("RIGHT", -4, 0)
            row.button.tooltip = "Mark this as settled once the gold has changed hands in a trade."
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
            row.button.onClick = item.onClick
            row.button:SetText(item.buttonText or "Paid")
            row.button.tooltip = item.buttonTip
            row.button:SetShown(item.onClick ~= nil)
            row.right:ClearAllPoints()
            row.right:SetPoint("RIGHT", item.onClick and -74 or -8, 0)
        end)
    list:SetPoint("TOPLEFT", 18, -66)
    list:SetPoint("BOTTOMRIGHT", -40, 18)

    local function Fill()
        local items = {}

        -- Gold ledger first: open debts (only when there are any).
        local open = GG.Ledger:Open()
        if #open > 0 then
            items[#items + 1] = { header = true, left = "Gold ledger", right = UI.InkGrey("settle up in a trade, then press Paid") }
            for _, o in ipairs(open) do
                local e = o.entry
                local entry = GG:GetCatalogEntry(e.game)
                local what = (entry and entry.name or e.game) .. ", " .. date("%b %d", e.t)
                local line
                if Util.IsMe(e.from) then
                    line = UI.InkRed("You owe ") .. Util.ShortName(e.to) .. UI.InkRed(" " .. e.gold .. "g")
                else
                    line = Util.ShortName(e.from) .. UI.InkGreen(" owes you " .. e.gold .. "g")
                end
                local index = o.index
                items[#items + 1] = { left = "     " .. line, right = UI.InkGrey(what),
                    onClick = function() GG.Ledger:Settle(index) end, buttonText = "Paid",
                    buttonTip = "Mark this as settled once the gold has changed hands in a trade." }
            end
        end

        -- Guild Bingo winners whose prize hasn't been handed out (host's log).
        local log = GG.db.global.bingoLog
        local pending = {}
        for i = #log, 1, -1 do
            if not log[i].prizeGiven then pending[#pending + 1] = i end
        end
        if #pending > 0 then
            items[#items + 1] = { header = true, left = "Bingo prizes to hand out", right = UI.InkGrey(#pending .. " waiting") }
            for _, i in ipairs(pending) do
                local e = log[i]
                items[#items + 1] = {
                    left = "     " .. Util.ShortName(e.winner) .. UI.InkGrey((" round %d, %s"):format(e.round, e.pattern)),
                    right = UI.InkGrey(date("%b %d %H:%M", e.t)),
                    onClick = function() e.prizeGiven = true; e.givenAt = time(); GG:Fire("BINGO_LOG_CHANGED") end,
                    buttonText = "Given",
                    buttonTip = "Mark the prize as handed out.",
                }
            end
        end

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
    end

    panel:SetScript("OnShow", Fill)
    GG.RegisterCallback(panel, "LEDGER_CHANGED", function() if panel:IsShown() then Fill() end end)
    GG.RegisterCallback(panel, "BINGO_LOG_CHANGED", function() if panel:IsShown() then Fill() end end)
    return panel
end)
