--[[----------------------------------------------------------------------------
  GoblinGames/Core/Modules.lua

  The game catalog and the module registry.

  Each game lives in its own Load-On-Demand addon (## LoadOnDemand: 1). WoW
  doesn't load those at login; we call C_AddOns.LoadAddOn("GoblinGames_X") the
  first time the game is needed. That keeps memory low for people who only
  ever play one or two games.

  Because a module isn't loaded until it's needed, the core keeps a static
  CATALOG so the game picker can list every game without loading anything.
  When a module loads, it calls GoblinGames:RegisterGame(def) to plug its rules
  and UI into the core. See docs/MODULE_API.md for the full definition.
------------------------------------------------------------------------------]]

local _, GG = ...

-- practice = true shows a "Practice" button (the module defines BotAction).
-- open = true: announced to the whole guild instead of invite-only.
-- officerHost = true: only the guild ranks chosen in Settings may host it.
GG.CATALOG = {
    { id = "tictactoe",   addon = "GoblinGames_TicTacToe",   name = "Tic-Tac-Toe",   min = 2, max = 2, practice = true,
      icon = "Interface\\Icons\\INV_Misc_Note_02",       desc = "Three in a row, with faction crests." },
    { id = "connect6",    addon = "GoblinGames_Connect6",    name = "Connect 6",     min = 2, max = 2, practice = true,
      icon = "Interface\\Icons\\INV_Misc_Coin_04",  desc = "Drop checkers into the rack. Six in a row wins!" },
    { id = "deathroll",   addon = "GoblinGames_Deathroll",   name = "Deathroll",     min = 2, max = 40, practice = true,
      icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", desc = "/roll down from 1000. Whoever rolls 1 loses." },
    { id = "bingo",       addon = "GoblinGames_Bingo",       name = "Guild Bingo",   min = 2, max = 1000, practice = true,
      open = true, officerHost = true,
      icon = "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01", desc = "Officer-hosted prize nights." },
    { id = "gofish",      addon = "GoblinGames_GoFish",      name = "Go Fish",       min = 2, max = 6, practice = true,
      icon = "Interface\\Icons\\INV_Misc_Fish_02",       desc = "Ask for cards, make pairs, score points." },
    { id = "crazyeights", addon = "GoblinGames_CrazyEights", name = "Crazy Eights",  min = 2, max = 6, practice = true,
      icon = "Interface\\Icons\\INV_Misc_Note_01", desc = "Uno-style: match suit or rank. Eights are wild!" },
    { id = "blackjack",   addon = "GoblinGames_Blackjack",   name = "Blackjack",     min = 2, max = 8, practice = true,
      icon = "Interface\\Icons\\INV_Misc_Coin_02",       desc = "The host deals. Beat the house to 21!" },
    { id = "poker",       addon = "GoblinGames_Poker",       name = "Poker",         min = 2, max = 8, practice = true,
      icon = "Interface\\Icons\\INV_Misc_Coin_17",       desc = "Texas Hold'em with chips. Bluff the goblins!" },
    { id = "liarsdice",   addon = "GoblinGames_LiarsDice",   name = "Liar's Dice",   min = 2, max = 6, practice = true,
      icon = "Interface\\Icons\\INV_Misc_Dice_01",       desc = "Bid on hidden dice, or call Liar!" },
    { id = "trivia",      addon = "GoblinGames_Trivia",      name = "Trivia",        min = 1, max = 1000,
      icon = "Interface\\Icons\\INV_Misc_Book_09",       desc = "Fastest correct lore answer scores." },
}

local byId = {}
for _, entry in ipairs(GG.CATALOG) do byId[entry.id] = entry end

function GG:GetCatalogEntry(gameId)
    return byId[gameId]
end

-------------------------------------------------------------------------------
-- Registry
-------------------------------------------------------------------------------
local games = {}   -- gameId -> module definition

--- Called by a game module when it loads. `def.id` must match a CATALOG id.
function GG:RegisterGame(def)
    assert(type(def) == "table" and def.id, "RegisterGame needs a table with an id")
    assert(byId[def.id], "Unknown game id: " .. tostring(def.id))
    assert(def.OnSessionStart, def.id .. ": OnSessionStart is required")
    def.catalog = byId[def.id]
    games[def.id] = def
end

function GG:GetGame(gameId)
    return games[gameId]
end

-- C_AddOns is on every current client; the globals are fallbacks.
local AddOns = C_AddOns or {}
local LoadAddOn = AddOns.LoadAddOn or _G.LoadAddOn
local GetAddOnInfo = AddOns.GetAddOnInfo or _G.GetAddOnInfo
local IsAddOnLoaded = AddOns.IsAddOnLoaded or _G.IsAddOnLoaded

--- Is the module for this game installed (whether loaded or not)?
function GG:IsGameInstalled(gameId)
    local entry = byId[gameId]
    if not entry then return false end
    if games[gameId] then return true end
    if AddOns.DoesAddOnExist then return AddOns.DoesAddOnExist(entry.addon) end
    local ok, _, _, _, _, reason = pcall(GetAddOnInfo, entry.addon)
    return ok and reason ~= "MISSING"
end

--- Make sure a game's module is loaded. Returns def, or nil + error text.
function GG:LoadGame(gameId)
    if games[gameId] then return games[gameId] end
    local entry = byId[gameId]
    if not entry then return nil, "Unknown game." end
    if not self:IsGameInstalled(gameId) then
        return nil, entry.name .. " isn't installed yet."
    end
    if not IsAddOnLoaded(entry.addon) then
        local loaded, reason = LoadAddOn(entry.addon)
        if not loaded then
            if reason == "DISABLED" then
                return nil, entry.name .. " is disabled. Enable " .. entry.addon .. " in the AddOns list at the character screen."
            end
            return nil, "Couldn't load " .. entry.name .. " (" .. tostring(reason) .. ")."
        end
    end
    if not games[gameId] then
        return nil, entry.addon .. " loaded but didn't register a game."
    end
    return games[gameId]
end
