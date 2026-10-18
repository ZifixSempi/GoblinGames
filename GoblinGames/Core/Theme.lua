--[[----------------------------------------------------------------------------
  GoblinGames/Core/Theme.lua

  Horde / Alliance / Neutral look and sounds.

  - Each player sees frames in THEIR OWN faction's colours (setting: auto,
    force Horde, force Alliance, neutral).
  - Game pieces always show the faction of the player who owns them
    ("mixed" mode): your crest is your faction, your opponent's is theirs.

  Art: we only reference textures that ship with the game client (no Blizzard
  art is bundled in the addon). Where a newer client has a nicer *atlas*
  (a named region of a texture sheet, used with SetAtlas), we try it first and
  fall back to a plain texture file that exists on every client.
------------------------------------------------------------------------------]]

local _, GG = ...

local Theme = {}
GG.Theme = Theme

-------------------------------------------------------------------------------
-- Palettes
-------------------------------------------------------------------------------
-- Colours for our own textures (GoblinGames\Media). Those are drawn in light,
-- neutral tones and tinted with Texture:SetVertexColor, so one set of art
-- serves all three themes:
--   frame   the wooden window frame      planks  the background planks
--   accent  ribbons, selected tabs        primary the main "do it!" buttons
Theme.palettes = {
    Horde = {   -- scorched red wood and iron
        bg      = { 0.10, 0.03, 0.02, 0.95 },
        border  = { 0.62, 0.12, 0.08, 1 },
        title   = "ffff7a52",
        tile    = { 0.20, 0.06, 0.04, 0.9 },
        tileHi  = { 0.45, 0.12, 0.06, 0.9 },
        frame   = { 1.00, 0.66, 0.58 },
        planks  = { 1.00, 0.82, 0.78 },
        accent  = { 0.80, 0.18, 0.12 },
        primary = { 0.88, 0.26, 0.16 },
    },
    Alliance = {   -- blue banners, stone and gold
        bg      = { 0.03, 0.06, 0.16, 0.95 },
        border  = { 0.85, 0.68, 0.25, 1 },
        title   = "ffffd24a",
        tile    = { 0.06, 0.12, 0.28, 0.9 },
        tileHi  = { 0.12, 0.24, 0.50, 0.9 },
        frame   = { 0.70, 0.78, 1.00 },
        planks  = { 0.80, 0.84, 1.00 },
        accent  = { 0.20, 0.40, 0.86 },
        primary = { 0.26, 0.52, 0.98 },
    },
    Neutral = {   -- goblin green: Steamwheedle doesn't pick sides
        bg      = { 0.06, 0.06, 0.06, 0.95 },
        border  = { 0.60, 0.60, 0.60, 1 },
        title   = "ffb6f25a",
        tile    = { 0.14, 0.14, 0.14, 0.9 },
        tileHi  = { 0.28, 0.28, 0.28, 0.9 },
        frame   = { 1.00, 1.00, 1.00 },
        planks  = { 1.00, 1.00, 1.00 },
        accent  = { 0.30, 0.60, 0.18 },
        primary = { 0.36, 0.74, 0.24 },
    },
}

-- Colours that don't change with the theme.
Theme.fixed = {
    wood   = { 0.88, 0.66, 0.44 },   -- secondary buttons, idle tabs
    danger = { 0.82, 0.22, 0.18 },   -- forfeit / cancel
    gold   = { 1.00, 0.80, 0.28 },
    silver = { 0.78, 0.82, 0.92 },
    grey   = { 0.55, 0.55, 0.55 },
}

--- An {r,g,b} colour by name: a palette key (frame, planks, accent, primary)
--- or a fixed one (wood, danger, gold, silver, grey).
function Theme:Color(key)
    return self:GetPalette()[key] or self.fixed[key] or self.fixed.wood
end

-- Textures painted with a theme colour, repainted when the theme changes.
local painted = setmetatable({}, { __mode = "k" })

--- Tint a texture with a theme colour and keep it in sync with the theme.
function Theme:Paint(texture, key)
    painted[texture] = key
    local c = self:Color(key)
    texture:SetVertexColor(c[1], c[2], c[3])
end

-- Backdrop textures (all part of the base client on every flavor).
-- Horde gets the heavy dialog border tinted iron-red; Alliance gets the same
-- frame in gold, which reads as carved stone with gilded trim.
local BACKDROPS = {
    Horde = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 26,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    },
    Alliance = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 26,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    },
    Neutral = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
}

-- Crests: atlas first (newer clients), file fallback (every client).
local CRESTS = {
    Horde    = { atlas = "MountJournalIcons-Horde",    file = "Interface\\FriendsFrame\\PlusManz-Horde" },
    Alliance = { atlas = "MountJournalIcons-Alliance", file = "Interface\\FriendsFrame\\PlusManz-Alliance" },
    Neutral  = { file = "Interface\\Icons\\INV_Misc_Dice_02" },
}

-------------------------------------------------------------------------------
-- Faction
-------------------------------------------------------------------------------

--- The player's real faction: "Horde", "Alliance" or "Neutral"
--- (a Pandaren before choosing a side is Neutral).
function Theme:GetPlayerFaction()
    local faction = UnitFactionGroup("player")
    if faction == "Horde" or faction == "Alliance" then return faction end
    return "Neutral"
end

--- The faction whose theme we draw frames with, after applying the setting.
function Theme:GetThemeFaction()
    local mode = GG.db and GG.db.profile.theme or "auto"
    if mode == "auto" then return self:GetPlayerFaction() end
    return mode
end

function Theme:GetPalette()
    return self.palettes[self:GetThemeFaction()] or self.palettes.Neutral
end

--- Normalise any faction string we receive over the network.
function Theme:Sanitize(faction)
    if faction == "Horde" or faction == "Alliance" then return faction end
    return "Neutral"
end

-------------------------------------------------------------------------------
-- Applying the theme to frames
-------------------------------------------------------------------------------
local themedFrames = {}

--- Give a frame the current faction backdrop. The frame must inherit
--- "BackdropTemplate" (CreateFrame("Frame", nil, parent, "BackdropTemplate")).
--- The frame is remembered and repainted when the theme setting changes.
function Theme:ApplyFrame(frame, variant)
    themedFrames[frame] = variant or "panel"
    local faction = self:GetThemeFaction()
    local p = self.palettes[faction]
    if variant == "tile" then
        frame:SetBackdrop(BACKDROPS.Neutral)
        frame:SetBackdropColor(unpack(p.tile))
        frame:SetBackdropBorderColor(p.border[1], p.border[2], p.border[3], 0.8)
    else
        frame:SetBackdrop(BACKDROPS[faction])
        frame:SetBackdropColor(unpack(p.bg))
        frame:SetBackdropBorderColor(unpack(p.border))
    end
end

function Theme:Refresh()
    for frame, variant in pairs(themedFrames) do
        self:ApplyFrame(frame, variant)
    end
    for texture, key in pairs(painted) do
        self:Paint(texture, key)
    end
    GG:Fire("THEME_CHANGED")
end

--- Colour text in the theme's title colour.
function Theme:TitleText(text)
    return "|c" .. self:GetPalette().title .. text .. "|r"
end

--- Put a faction crest on a texture. Used for pieces, so it takes the faction
--- of the piece's OWNER, not the theme faction.
function Theme:SetCrest(texture, faction)
    local crest = CRESTS[self:Sanitize(faction)]
    -- C_Texture.GetAtlasInfo returns nil for atlases this client doesn't have.
    if crest.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(crest.atlas) then
        texture:SetAtlas(crest.atlas)
    else
        texture:SetTexture(crest.file)
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

-------------------------------------------------------------------------------
-- Sounds
--
-- PlaySound takes a "sound kit" id. Blizzard names common ones in the SOUNDKIT
-- table, but names and ids differ a little between clients, so each sound is a
-- list of candidates: the first one this client can play wins.
-- PlaySound returns willPlay = false for ids it doesn't know.
-------------------------------------------------------------------------------
local function Kit(name) return SOUNDKIT and SOUNDKIT[name] end

local SOUNDS = {
    victory_Horde    = function() return { Kit("PVP_VICTORY_HORDE"), 8455, Kit("IG_QUEST_LIST_COMPLETE") } end,
    victory_Alliance = function() return { Kit("PVP_VICTORY_ALLIANCE"), 8454, Kit("IG_QUEST_LIST_COMPLETE") } end,
    victory_Neutral  = function() return { Kit("IG_QUEST_LIST_COMPLETE"), Kit("READY_CHECK") } end,
    defeat           = function() return { Kit("IG_QUEST_FAILED"), 847 } end,
    turn             = function() return { Kit("READY_CHECK"), Kit("RAID_WARNING") } end,
    invite           = function() return { Kit("IG_PLAYER_INVITE"), Kit("READY_CHECK") } end,
    click            = function() return { Kit("IG_MAINMENU_OPTION_CHECKBOX_ON"), 856 } end,
}

--- Play a themed sound: "victory", "defeat", "turn", "invite" or "click".
function Theme:PlaySound(kind)
    if GG.db and not GG.db.profile.sounds then return end
    if kind == "victory" then kind = "victory_" .. self:GetPlayerFaction() end
    local candidates = SOUNDS[kind] and SOUNDS[kind]()
    if not candidates then return end
    for i = 1, 4 do -- fixed range: the list may contain nil holes
        local id = candidates[i]
        if id then
            local ok, willPlay = pcall(PlaySound, id, "Master")
            if ok and willPlay then return end
        end
    end
end

-- Repaint when the theme setting changes.
GG.RegisterCallback(Theme, "SETTINGS_CHANGED", function(_, key)
    if key == "theme" then Theme:Refresh() end
end)
