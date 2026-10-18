--[[----------------------------------------------------------------------------
  GoblinGames/Core/Util.lua

  Small helpers used everywhere: player names, tables, randomness.

  About names: WoW identifies players across connected realms as
  "Name-Realm". Addon messages always report the sender that way, but unit
  functions like UnitName("party1") may return just "Name" for same-realm
  players. To compare names reliably we ALWAYS store the full form, and only
  shorten names (Ambiguate) when showing them on screen.
------------------------------------------------------------------------------]]

local _, GG = ...

local Util = {}
GG.Util = Util

local myFullName

--- Our own realm without spaces, e.g. "AeriePeak". GetNormalizedRealmName can
--- return nil during the first moments of login, so we fall back to GetRealmName.
function Util.MyRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName() or ""):gsub("[%s%-]", "")
    end
    return realm
end

--- Our own full name, "Name-Realm".
function Util.PlayerName()
    if not myFullName then
        local name = UnitName("player")
        local realm = Util.MyRealm()
        if name and realm ~= "" then myFullName = name .. "-" .. realm end
        return myFullName or name
    end
    return myFullName
end

--- Turn "Name" or "Name-Realm" into "Name-Realm".
function Util.FullName(name)
    if not name or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. Util.MyRealm()
end

--- Full name of a unit token ("target", "party2" ...), or nil.
function Util.UnitFullName(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    local name, realm = UnitName(unit)
    if not name then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return Util.FullName(name)
end

--- Name for display: drops our own realm, keeps other realms.
--- Ambiguate is Blizzard's helper for exactly this.
function Util.ShortName(fullName)
    if not fullName then return "?" end
    if Util.IsBot(fullName) then return fullName:match("^[^-]+") end
    return Ambiguate(fullName, "none")
end

function Util.IsMe(fullName)
    return fullName == Util.PlayerName()
end

--- Bots only exist in local practice games. Their "realm" is the fake
--- suffix "-Practice", so they can never collide with a real player.
Util.BOT_SUFFIX = "-Practice"
function Util.IsBot(fullName)
    return fullName ~= nil and fullName:sub(-#Util.BOT_SUFFIX) == Util.BOT_SUFFIX
end

--- Is this player in our party or raid right now?
--- UnitInParty/UnitInRaid accept a name; same-realm members need the short name.
function Util.IsInMyGroup(fullName)
    if not IsInGroup() then return false end
    local short = Ambiguate(fullName, "none")
    return (UnitInParty(short) or UnitInRaid(short)) and true or false
end

--- Channel to reach our whole group, or nil when solo.
--- In instance groups (LFG dungeons, battlegrounds) "PARTY"/"RAID" don't work
--- for addon messages; "INSTANCE_CHAT" does.
function Util.GroupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end

--- Full names of everyone in our group except us.
function Util.GroupMembers()
    local list = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local n = Util.UnitFullName("raid" .. i)
            if n and not Util.IsMe(n) then list[#list + 1] = n end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local n = Util.UnitFullName("party" .. i)
            if n then list[#list + 1] = n end
        end
    end
    table.sort(list)
    return list
end

-------------------------------------------------------------------------------
-- Guild roster cache
-- Checking guild membership by scanning the roster every time would be slow,
-- so we rebuild a lookup table whenever the roster changes.
-------------------------------------------------------------------------------
local guildMembers = {}

local function RebuildGuild()
    wipe(guildMembers)
    if not IsInGuild() then return end
    for i = 1, GetNumGuildMembers() do
        local name = GetGuildRosterInfo(i)
        if name then guildMembers[Util.FullName(name)] = true end
    end
end
GG:RegisterEvent("GUILD_ROSTER_UPDATE", RebuildGuild)
GG:RegisterEvent("PLAYER_GUILD_UPDATE", RebuildGuild)

function Util.IsGuildMember(fullName)
    return guildMembers[fullName] == true
end

--- Is this name on our (character) friends list?
function Util.IsFriend(fullName)
    if not C_FriendList or not C_FriendList.GetFriendInfo then return false end
    local info = C_FriendList.GetFriendInfo(Ambiguate(fullName, "none"))
    return info ~= nil
end

-------------------------------------------------------------------------------
-- Tables and randomness
-------------------------------------------------------------------------------

--- Shuffle a list in place (Fisher-Yates) and return it.
function Util.Shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

function Util.Copy(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

function Util.IndexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then return i end
    end
    return nil
end

--- A short random id, used for session ids: 6 base-36 characters.
function Util.RandomId()
    local chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    local out = {}
    for i = 1, 6 do
        local n = math.random(#chars)
        out[i] = chars:sub(n, n)
    end
    return table.concat(out)
end

--- "1:05" style countdown text.
function Util.FormatSeconds(sec)
    sec = math.max(0, math.floor(sec + 0.5))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end
