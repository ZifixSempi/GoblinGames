--[[----------------------------------------------------------------------------
  GoblinGames/Core/Dice.lua

  The dice helper: real /roll results from the game server.

  WHY NOT math.random()?
  A number made up by an addon could be faked by anyone with a modified copy.
  A /roll is made by the SERVER, which then prints a system message like
      "Zifix rolls 523 (1-1000)"
  to the roller, their party or raid, and players nearby. We read that message
  (CHAT_MSG_SYSTEM), so the number can't be faked by the roller's addon.
  This is why dice games want everyone in the same GROUP: then every
  player's client, including the host's, sees every roll.

  RandomRoll(min, max) is Blizzard's function behind /roll. It's allowed for
  addons; if a client ever refuses it, the player can simply type /roll and
  we'll read the result the same way.

  Usage:
      GG.Dice:Roll(1, 1000)
      GG.RegisterCallback(myTable, "DICE_ROLLED", function(event, name, roll, min, max) end)
  `name` is always the full "Name-Realm".
------------------------------------------------------------------------------]]

local _, GG = ...

local Dice = {}
GG.Dice = Dice

--- Ask the server for a roll. Returns true if the request was sent.
function Dice:Roll(min, max)
    min, max = math.floor(min or 1), math.floor(max or 100)
    local ok = pcall(RandomRoll, min, max)
    if not ok then
        GG:Print("Couldn't roll for you. Type |cffffd100/roll " .. (min == 1 and max or (min .. " " .. max)) .. "|r instead.")
        return false
    end
    return true
end

-- RANDOM_ROLL_RESULT is Blizzard's localized "%s rolls %d (%d-%d)". Turning it
-- into a Lua pattern makes this work in every language.
local rollPattern
local function BuildPattern()
    local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    fmt = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")   -- escape magic characters
    fmt = fmt:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")    -- %s -> name, %d -> number
    return "^" .. fmt .. "$"
end

--- Parse a system message. Returns fullName, roll, min, max or nil.
function Dice.Parse(text)
    if type(text) ~= "string" then return nil end
    rollPattern = rollPattern or BuildPattern()
    local name, roll, min, max = text:match(rollPattern)
    if not name then return nil end
    -- Some locales put the numbers in a different order; ours has them as
    -- roll, min, max, which is what the English string uses.
    return GG.Util.FullName(name), tonumber(roll), tonumber(min), tonumber(max)
end

GG:RegisterEvent("CHAT_MSG_SYSTEM", function(_, text)
    -- Retail (Midnight) can hand addons "secret" values during boss encounters;
    -- we can't read those, and nobody's dicing mid-pull anyway.
    if issecretvalue and issecretvalue(text) then return end
    local name, roll, min, max = Dice.Parse(text)
    if name then
        GG:Debug("roll", name, roll, min, max)
        GG:Fire("DICE_ROLLED", name, roll, min, max)
    end
end)
