--[[----------------------------------------------------------------------------
  GoblinGames/Core/Database.lua

  SavedVariables: everything in the global `GoblinGamesDB` is written to
  WTF\Account\<ACCOUNT>\SavedVariables\GoblinGames.lua when you log out or
  /reload, and read back the next time the addon loads.

  Layout (managed by AceDB):
    GoblinGamesDB.global        shared by every character on the account
        .schemaVersion         which migrations have run (see below)
        .bingoLog              Guild Bingo winner log (Milestone 4)
        .ledger                gold-mode debts: { t, game, from, to, gold, settled }
    GoblinGamesDB.profiles      settings (theme, sounds, minimap ...)
    GoblinGamesDB.char["Name - Realm"]
        .stats[gameId]         { wins, losses, draws, opponents = { [name] = {w,l,d} } }

  ---------------------------------------------------------------------------
  MIGRATIONS: how updates avoid wiping anyone's stats

  Saved data outlives every version of the addon. When the shape of that data
  needs to change (rename a field, split a table ...), we never just start
  over. Instead:

    1. Add a new function at the END of the MIGRATIONS list below.
    2. It receives the raw saved table and reshapes it in place.
    3. On load, every migration newer than global.schemaVersion runs once,
       in order, and schemaVersion is bumped after each one.

  Rules for writing a migration:
    - Never delete a field before its data has been copied somewhere new.
    - Always check that a table exists before indexing it (old saves may be
      missing anything).
    - Never edit or reorder a migration that already shipped; add a new one.
  ---------------------------------------------------------------------------
------------------------------------------------------------------------------]]

local _, GG = ...

local MIGRATIONS = {
    -- [1] First release: nothing to convert yet. It exists so the pattern is
    -- in place and every save gets a schemaVersion from day one.
    function(raw)
    end,

    -- [2] Example for the future (keep this commented as a template):
    -- function(raw)
    --     for _, charData in pairs(raw.char or {}) do
    --         for gameId, s in pairs(charData.stats or {}) do
    --             s.draws = s.draws or s.ties or 0   -- copy old field
    --             s.ties = nil                       -- then remove it
    --         end
    --     end
    -- end,
}

GG.SCHEMA_VERSION = #MIGRATIONS

local defaults = {
    global = {
        schemaVersion = 0,
        bingoLog = {},
        ledger = {},              -- gold mode debts (see Core/Ledger.lua)
        triviaQuestions = {},     -- your own Trivia questions: { q = "...", a = { right, wrong, wrong, wrong } }
    },
    profile = {
        theme = "auto",           -- "auto" | "Horde" | "Alliance" | "Neutral"
        sounds = true,
        minimap = { hide = false, angle = 215 },
        acceptFrom = "known",     -- "known" (group, guild, friends) | "anyone" | "nobody"
        turnTimer = 60,           -- seconds per turn, 0 = no timer
        goldMode = false,         -- ledger-only gold tracking (Poker, Deathroll); OFF by default
        bingoMaxRank = 1,         -- guild ranks 0..N may host Guild Bingo (0 = Guild Master)
        announceBingo = false,    -- post Bingo winners in guild chat (host only)
        windowPos = nil,          -- remembered main window position
        debug = false,
    },
    char = {
        stats = {},
    },
}

local function RunMigrations(raw)
    raw.global = raw.global or {}
    local current = raw.global.schemaVersion or 0
    for version = current + 1, #MIGRATIONS do
        local ok, err = pcall(MIGRATIONS[version], raw)
        if not ok then
            -- Stop at the first failure so we never skip a step. The data is
            -- left as-is and the migration retries on the next login.
            GG:Print("|cffff4040Could not update saved data (step " .. version .. "):|r", err)
            return
        end
        raw.global.schemaVersion = version
    end
end

table.insert(GG.onLoad, function()
    -- GoblinGamesDB is nil on first install; create it so migrations can run.
    GoblinGamesDB = GoblinGamesDB or {}
    RunMigrations(GoblinGamesDB)

    -- AceDB wraps the raw table and fills in defaults on read, without
    -- writing defaults back to disk (keeps the saved file small).
    -- `true` = use the shared "Default" profile on every character.
    GG.db = LibStub("AceDB-3.0"):New("GoblinGamesDB", defaults, true)
end)

-------------------------------------------------------------------------------
-- Settings helpers
-------------------------------------------------------------------------------

function GG:GetSetting(key)
    return self.db.profile[key]
end

function GG:SetSetting(key, value)
    self.db.profile[key] = value
    self:Fire("SETTINGS_CHANGED", key, value)
end

-------------------------------------------------------------------------------
-- Stats
-------------------------------------------------------------------------------
local Stats = {}
GG.Stats = Stats

local function GameStats(gameId)
    local all = GG.db.char.stats
    local s = all[gameId]
    if not s then
        s = { wins = 0, losses = 0, draws = 0, opponents = {} }
        all[gameId] = s
    end
    return s
end

--- Record the result of one game for the local player.
-- @param gameId    e.g. "tictactoe"
-- @param result    "win" | "loss" | "draw"
-- @param opponents list of full names we played against (bots are skipped)
function Stats:Record(gameId, result, opponents)
    local s = GameStats(gameId)
    local field = (result == "win" and "wins") or (result == "loss" and "losses") or "draws"
    s[field] = s[field] + 1
    local short = (result == "win" and "w") or (result == "loss" and "l") or "d"
    for _, name in ipairs(opponents or {}) do
        if not GG.Util.IsBot(name) then
            local o = s.opponents[name] or { w = 0, l = 0, d = 0 }
            o[short] = o[short] + 1
            s.opponents[name] = o
        end
    end
end

function Stats:Get(gameId)
    return GameStats(gameId)
end
