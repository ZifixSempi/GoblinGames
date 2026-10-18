--[[----------------------------------------------------------------------------
  GuildGames/Slash.lua

  Slash commands. WoW finds them through globals named SLASH_<KEY>1, 2 ...
  and the handler in SlashCmdList["<KEY>"].

    /gg                     open or close the window
    /gg practice <game>     play a Training Dummy (solo test), e.g. /gg practice tictactoe
    /gg host <game>         open a lobby for a game
    /gg invite <name>       invite a player to your lobby
    /gg start               start your lobby
    /gg leave               leave your lobby or forfeit the current game
    /gg accept | decline    answer the newest invite
    /gg who                 list group and guild members who have GuildGames
    /gg stats | settings    open those panels
    /gg debug               print every addon message sent and received
------------------------------------------------------------------------------]]

local _, GG = ...

local Util = GG.Util

-- Accept "tictactoe", "TicTacToe", "tic-tac-toe" or "ttt" for the same game.
local ALIASES = { ttt = "tictactoe", c6 = "connect6", dr = "deathroll", ld = "liarsdice", c8 = "crazyeights", bj = "blackjack" }

local function FindGame(text)
    if not text or text == "" then return nil end
    local key = text:lower():gsub("[%s%-'_]", "")
    key = ALIASES[key] or key
    if GG:GetCatalogEntry(key) then return key end
    for _, entry in ipairs(GG.CATALOG) do
        if entry.name:lower():gsub("[%s%-'_]", "") == key then return entry.id end
    end
end

local function GameList()
    local ids = {}
    for _, entry in ipairs(GG.CATALOG) do
        if GG:IsGameInstalled(entry.id) then ids[#ids + 1] = entry.id end
    end
    return table.concat(ids, ", ")
end

local function Report(ok, err)
    if not ok and err then GG:Print(err) end
end

local function Help()
    GG:Print("commands:")
    local lines = {
        "/gg - open the window",
        "/gg practice <game> - play a Training Dummy (installed: " .. GameList() .. ")",
        "/gg host <game> - open a lobby",
        "/gg invite <name> - invite a player to your lobby",
        "/gg start - start your lobby   /gg leave - leave or forfeit",
        "/gg accept | decline - answer the newest invite",
        "/gg who - who in your group or guild has GuildGames",
        "/gg stats | settings | debug",
    }
    for _, line in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("   " .. line) end
end

local function NewestInvite()
    local newest
    for _, invite in pairs(GG.Lobby.invites) do
        if not newest or invite.expires > newest.expires then newest = invite end
    end
    return newest
end

local commands = {}

commands.practice = function(arg)
    local id = FindGame(arg)
    if not id then return GG:Print("Which game? Installed: " .. GameList()) end
    Report(GG.Lobby:StartPractice(id))
end
commands.test = commands.practice

commands.host = function(arg)
    local id = FindGame(arg)
    if not id then return GG:Print("Which game? Installed: " .. GameList()) end
    Report(GG.Lobby:CreateHosted(id))
end

commands.invite = function(arg)
    local s = GG.Lobby.active
    if not s or not s:IsHost() or s.status ~= "lobby" then
        return GG:Print("Host a game first: /gg host <game>")
    end
    if not arg or arg == "" then
        arg = Util.UnitFullName("target")
        if not arg then return GG:Print("Usage: /gg invite <name> (or target a player)") end
    end
    Report(GG.Lobby:Invite(s, arg))
end

commands.start = function()
    local s = GG.Lobby.active
    if not s or not GG.Lobby:CanStart(s) then
        return GG:Print("Nothing to start yet: you need a lobby with enough players who accepted.")
    end
    GG.Lobby:Start(s)
end

commands.leave = function()
    if not GG.Lobby.active then return GG:Print("You're not in a game.") end
    GG.Lobby:Leave(GG.Lobby.active)
end
commands.forfeit = commands.leave

commands.accept = function()
    local invite = NewestInvite()
    if not invite then return GG:Print("No pending invites.") end
    GG.Lobby:AcceptInvite(invite.id)
end

commands.decline = function()
    local invite = NewestInvite()
    if not invite then return GG:Print("No pending invites.") end
    GG.Lobby:DeclineInvite(invite.id, "declined")
end

commands.who = function()
    GG:Print("Asking your group and guild...")
    GG.Comm:WhoHasAddon(function(results)
        local names = {}
        for name, version in pairs(results) do
            names[#names + 1] = Util.ShortName(name) .. " (" .. version .. ")"
        end
        table.sort(names)
        if #names == 0 then
            GG:Print("Nobody else answered.")
        else
            GG:Print(#names .. " with GuildGames: " .. table.concat(names, ", "))
        end
    end)
end

commands.stats = function() GG.UI:ShowPanel("stats") end
commands.settings = function() GG.UI:ShowPanel("settings") end
commands.config = commands.settings
commands.options = commands.settings

commands.debug = function()
    GG.db.profile.debug = not GG.db.profile.debug
    GG:Print("Debug messages " .. (GG.db.profile.debug and "on." or "off."))
end

commands.help = Help

SLASH_GUILDGAMES1 = "/gg"
SLASH_GUILDGAMES2 = "/guildgames"
SlashCmdList.GUILDGAMES = function(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        GG.UI:Toggle()
    elseif commands[cmd] then
        commands[cmd](arg)
    else
        Help()
    end
end
