--[[----------------------------------------------------------------------------
  GoblinGames/Core/Ledger.lua

  Gold mode: a LEDGER of who owes whom. Nothing more.

  POLICY NOTES (please keep it this way)
    - Addons cannot move gold: trading and mailing are protected actions that
      only the player can perform. We never try to automate them.
    - Gold mode is OFF by default and has to be switched on in Settings.
    - It only records debts. Players settle up themselves in the trade window
      and tick the entry off here.
    - Players are reminded to follow Blizzard's Terms of Use (no real-money
      wagering, no scams).

  Entries live in GoblinGamesDB.global.ledger (shared by all your characters)
  and are only ever added, or marked settled: never deleted by an update.
------------------------------------------------------------------------------]]

local _, GG = ...

local Ledger = {}
GG.Ledger = Ledger

Ledger.TOS_REMINDER = "Gold mode only keeps a ledger: it never moves gold. Settle up yourself in the trade " ..
    "window, and play by Blizzard's Terms of Use (no real-money bets)."

function GG:GoldModeOn()
    return self.db and self.db.profile.goldMode == true
end

--- Record that `from` owes `to` some gold. Only entries involving the local
--- player are kept (everyone records their own side).
function Ledger:Add(gameId, from, to, gold)
    gold = tonumber(gold) or 0
    if gold <= 0 then return end
    if not (GG.Util.IsMe(from) or GG.Util.IsMe(to)) then return end
    local log = GG.db.global.ledger
    log[#log + 1] = { t = time(), game = gameId, from = from, to = to, gold = gold, settled = false }
    if GG.Util.IsMe(from) then
        GG:Print(("Ledger: you owe |cffffd100%dg|r to %s. Trade it to them when you can."):format(gold, GG.Util.ShortName(to)))
    else
        GG:Print(("Ledger: %s owes you |cffffd100%dg|r."):format(GG.Util.ShortName(from), gold))
    end
    GG:Fire("LEDGER_CHANGED")
end

--- Unsettled entries, newest first.
function Ledger:Open()
    local list = {}
    for i, e in ipairs(GG.db.global.ledger) do
        if not e.settled then list[#list + 1] = { index = i, entry = e } end
    end
    table.sort(list, function(a, b) return a.entry.t > b.entry.t end)
    return list
end

function Ledger:Settle(index)
    local e = GG.db.global.ledger[index]
    if e then
        e.settled = true
        e.settledAt = time()
        GG:Fire("LEDGER_CHANGED")
    end
end

-- Remind once when gold mode is switched on.
GG.RegisterCallback(Ledger, "SETTINGS_CHANGED", function(_, key, value)
    if key == "goldMode" and value then GG:Print(Ledger.TOS_REMINDER) end
end)
