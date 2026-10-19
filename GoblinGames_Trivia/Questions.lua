--[[----------------------------------------------------------------------------
  GoblinGames_Trivia/Questions.lua

  The built-in question bank. Every question has four answers and the RIGHT
  ANSWER IS ALWAYS FIRST here; the game shuffles them before asking.

    c = category:  "lore"   lore and heroes
                   "places" zones, cities, dungeons and raids
                   "game"   classes, expansions, professions, holidays...

  Players add their own questions in game (/gg questions); those live in
  your SavedVariables, not in this file.

  Want to add more here? Copy a line, keep the right answer first, and keep
  each answer short (they're shown on buttons).
------------------------------------------------------------------------------]]

local _, ns = ...

ns.QUESTIONS = {
    -- Lore and heroes
    { c = "lore", q = "Who led the Horde to Kalimdor at the end of Warcraft III?", a = { "Thrall", "Grom Hellscream", "Cairne Bloodhoof", "Vol'jin" } },
    { c = "lore", q = "What is the name of the Lich King's cursed runeblade?", a = { "Frostmourne", "Ashbringer", "Shadowmourne", "Gorehowl" } },
    { c = "lore", q = "Who took up the Helm of Domination after Arthas fell?", a = { "Bolvar Fordragon", "Tirion Fordring", "Darion Mograine", "Uther the Lightbringer" } },
    { c = "lore", q = "Before she became the Banshee Queen, Sylvanas Windrunner was a...", a = { "High elf", "Night elf", "Human", "Draenei" } },
    { c = "lore", q = "What is Thrall's orcish birth name?", a = { "Go'el", "Durotan", "Orgrim", "Kilrogg" } },
    { c = "lore", q = "Who is Anduin Wrynn's father?", a = { "Varian Wrynn", "Llane Wrynn", "Terenas Menethil", "Bolvar Fordragon" } },
    { c = "lore", q = "What was Deathwing's name before he was corrupted?", a = { "Neltharion", "Malygos", "Nozdormu", "Kalecgos" } },
    { c = "lore", q = "Which Dragon Aspect guards the flow of time?", a = { "Nozdormu", "Ysera", "Alexstrasza", "Malygos" } },
    { c = "lore", q = "Who is the Aspect of the red dragonflight, the Life-Binder?", a = { "Alexstrasza", "Ysera", "Onyxia", "Sindragosa" } },
    { c = "lore", q = "Which Dragon Aspect watched over the Emerald Dream?", a = { "Ysera", "Nozdormu", "Alexstrasza", "Neltharion" } },
    { c = "lore", q = "Which fallen titan leads the Burning Legion?", a = { "Sargeras", "Kil'jaeden", "Archimonde", "Aman'Thul" } },
    { c = "lore", q = "Who is the high priestess of Elune who leads the night elves?", a = { "Tyrande Whisperwind", "Maiev Shadowsong", "Shandris Feathermoon", "Jarod Shadowsong" } },
    { c = "lore", q = "Illidan Stormrage's twin brother is...", a = { "Malfurion Stormrage", "Cenarius", "Xavius", "Kael'thas Sunstrider" } },
    { c = "lore", q = "Who greets you with \"You are not prepared!\"?", a = { "Illidan Stormrage", "Arthas Menethil", "Kel'Thuzad", "Ragnaros" } },
    { c = "lore", q = "Which tauren chieftain died after a mak'gora with Garrosh?", a = { "Cairne Bloodhoof", "Baine Bloodhoof", "Hamuul Runetotem", "Magatha Grimtotem" } },
    { c = "lore", q = "Who is Garrosh Hellscream's father?", a = { "Grom Hellscream", "Orgrim Doomhammer", "Durotan", "Kargath Bladefist" } },
    { c = "lore", q = "Which Bronzebeard was King of Ironforge in classic WoW?", a = { "Magni", "Muradin", "Brann", "Moira" } },
    { c = "lore", q = "Who is the High Tinker of the gnomes?", a = { "Gelbin Mekkatorque", "Sicco Thermaplugg", "Chromie", "Millhouse Manastorm" } },
    { c = "lore", q = "Which goblin trade prince leads the Bilgewater Cartel?", a = { "Jastor Gallywix", "Gazlowe", "Revilgaz", "Noggenfogger" } },
    { c = "lore", q = "Who is Jaina Proudmoore's father?", a = { "Daelin Proudmoore", "Antonidas", "Terenas Menethil", "Genn Greymane" } },
    { c = "lore", q = "Which city did Jaina found on the coast of Kalimdor?", a = { "Theramore", "Kul Tiras", "Southshore", "Nethergarde" } },
    { c = "lore", q = "Who ordered the destruction of Theramore with a mana bomb?", a = { "Garrosh Hellscream", "Sylvanas Windrunner", "Thrall", "Vol'jin" } },
    { c = "lore", q = "Which pandaren brewmaster joined Rexxar in The Frozen Throne?", a = { "Chen Stormstout", "Li Li Stormstout", "Taran Zhu", "Mr. Bubbles" } },
    { c = "lore", q = "What was the name of Arthas's horse?", a = { "Invincible", "Mograine", "Midnight", "Thunderhoof" } },
    { c = "lore", q = "Who murdered King Terenas Menethil II?", a = { "Arthas", "Kel'Thuzad", "Sylvanas", "Uther" } },
    { c = "lore", q = "Which world tree stands atop Mount Hyjal?", a = { "Nordrassil", "Teldrassil", "Shaladrassil", "Vordrassil" } },
    { c = "lore", q = "In which expansion was Teldrassil burned?", a = { "Battle for Azeroth", "Cataclysm", "Legion", "Shadowlands" } },
    { c = "lore", q = "The Scourge's necromancer cult is called the...", a = { "Cult of the Damned", "Shadow Council", "Twilight's Hammer", "Scarlet Crusade" } },
    { c = "lore", q = "Ragnaros the Firelord rules which element?", a = { "Fire", "Earth", "Air", "Water" } },
    { c = "lore", q = "Onyxia is the daughter of...", a = { "Deathwing", "Nefarian", "Alexstrasza", "Sinestra" } },
    { c = "lore", q = "Who was Khadgar's master?", a = { "Medivh", "Antonidas", "Rhonin", "Kel'Thuzad" } },
    { c = "lore", q = "Which orc warlock founded the Shadow Council?", a = { "Gul'dan", "Ner'zhul", "Blackhand", "Cho'gall" } },
    { c = "lore", q = "What is the orcs' home world?", a = { "Draenor", "Argus", "Outland", "Kalimdor" } },
    { c = "lore", q = "The draenei's ancient home world is...", a = { "Argus", "Draenor", "K'aresh", "Xoroth" } },
    { c = "lore", q = "Who is the prophet who leads the draenei?", a = { "Velen", "Nobundo", "Akama", "Maraad" } },
    { c = "lore", q = "Which moon goddess do the night elves worship?", a = { "Elune", "An'she", "Mu'sha", "Eonar" } },
    { c = "lore", q = "Which troll tribe did Vol'jin lead?", a = { "Darkspear", "Gurubashi", "Amani", "Zandalari" } },
    { c = "lore", q = "Who became Warchief of the Horde after Garrosh was defeated?", a = { "Vol'jin", "Thrall", "Baine Bloodhoof", "Lor'themar Theron" } },
    { c = "lore", q = "What is High Overlord Saurfang's first name?", a = { "Varok", "Dranosh", "Broxigar", "Nazgrim" } },
    { c = "lore", q = "What does the orcish battle cry \"Lok'tar ogar!\" mean?", a = { "Victory or death!", "For the Horde!", "Blood and thunder!", "Strength and honor!" } },
    { c = "lore", q = "Which bronze dragon often appears as a little gnome?", a = { "Chromie", "Soridormi", "Anachronos", "Nozdormu" } },
    { c = "lore", q = "Which Old God was imprisoned beneath Ahn'Qiraj?", a = { "C'Thun", "Yogg-Saron", "N'Zoth", "Y'Shaarj" } },
    { c = "lore", q = "Which Old God was imprisoned in Ulduar?", a = { "Yogg-Saron", "C'Thun", "N'Zoth", "G'huun" } },
    { c = "lore", q = "Who was the first Lich King, before Arthas?", a = { "Ner'zhul", "Kel'Thuzad", "Gul'dan", "Anub'arak" } },
    { c = "lore", q = "Which paladin wielded the Ashbringer before it was corrupted?", a = { "Alexandros Mograine", "Uther the Lightbringer", "Tirion Fordring", "Turalyon" } },

    -- Places, dungeons and raids
    { c = "places", q = "What is the capital city of the blood elves?", a = { "Silvermoon City", "Dalaran", "Quel'Danas", "Shattrath City" } },
    { c = "places", q = "What is the draenei capital on Azeroth?", a = { "The Exodar", "Shattrath City", "Telaar", "Darnassus" } },
    { c = "places", q = "Which city sits atop the mesas of Mulgore?", a = { "Thunder Bluff", "Camp Taurajo", "Bloodhoof Village", "Freewind Post" } },
    { c = "places", q = "Which city lies beneath the ruins of Lordaeron?", a = { "Undercity", "Deathknell", "Brill", "Stratholme" } },
    { c = "places", q = "Which city did the night elves build on Teldrassil?", a = { "Darnassus", "Astranaar", "Auberdine", "Suramar" } },
    { c = "places", q = "In which zone do orcs and trolls start their adventure?", a = { "Durotar", "Mulgore", "The Barrens", "Tirisfal Glades" } },
    { c = "places", q = "In which zone do human characters start?", a = { "Elwynn Forest", "Westfall", "Dun Morogh", "Redridge Mountains" } },
    { c = "places", q = "On which island do goblin characters start?", a = { "Kezan", "The Lost Isles", "Zandalar", "Kul Tiras" } },
    { c = "places", q = "Which gnome city was lost to radiation and troggs?", a = { "Gnomeregan", "Mechagon", "Ironforge", "Uldaman" } },
    { c = "places", q = "The goblin port of Booty Bay is in...", a = { "Stranglethorn Vale", "Tanaris", "The Barrens", "Feralas" } },
    { c = "places", q = "Which zone is home to the goblin town of Gadgetzan?", a = { "Tanaris", "Thousand Needles", "Silithus", "Un'Goro Crater" } },
    { c = "places", q = "The goblin port of Ratchet is in...", a = { "The Barrens", "Durotar", "Azshara", "Dustwallow Marsh" } },
    { c = "places", q = "Which snowy zone holds the goblin town of Everlook?", a = { "Winterspring", "Dun Morogh", "Alterac Mountains", "Hyjal" } },
    { c = "places", q = "Which goblin cartel runs Booty Bay and Gadgetzan?", a = { "Steamwheedle Cartel", "Bilgewater Cartel", "Venture Company", "Blackfuse Company" } },
    { c = "places", q = "Shattrath City is in which Outland zone?", a = { "Terokkar Forest", "Nagrand", "Zangarmarsh", "Hellfire Peninsula" } },
    { c = "places", q = "In Wrath of the Lich King, Dalaran floats above...", a = { "Crystalsong Forest", "Dragonblight", "Icecrown", "Borean Tundra" } },
    { c = "places", q = "Who is the final boss of the classic Deadmines?", a = { "Edwin VanCleef", "Mr. Smite", "Captain Greenskin", "Cookie" } },
    { c = "places", q = "Which gang ambushes travellers all over Westfall?", a = { "Defias Brotherhood", "Syndicate", "Dark Iron dwarves", "Riverpaw gnolls" } },
    { c = "places", q = "Where did Leeroy Jenkins make his famous charge?", a = { "Upper Blackrock Spire", "Molten Core", "Scholomance", "Stratholme" } },
    { c = "places", q = "In which raid do you first face Ragnaros?", a = { "Molten Core", "Blackwing Lair", "Firelands", "Blackrock Depths" } },
    { c = "places", q = "Nefarian waits at the top of which classic raid?", a = { "Blackwing Lair", "Molten Core", "Onyxia's Lair", "Blackrock Spire" } },
    { c = "places", q = "Hakkar the Soulflayer is fought in...", a = { "Zul'Gurub", "Zul'Aman", "Zul'Farrak", "Sunken Temple" } },
    { c = "places", q = "Kel'Thuzad's floating necropolis is called...", a = { "Naxxramas", "Acherus", "Scholomance", "Icecrown Citadel" } },
    { c = "places", q = "Which Burning Crusade raid ends with Illidan?", a = { "Black Temple", "Sunwell Plateau", "Tempest Keep", "Hyjal Summit" } },
    { c = "places", q = "Which Burning Crusade raid ends with Kil'jaeden?", a = { "Sunwell Plateau", "Black Temple", "Karazhan", "Magtheridon's Lair" } },
    { c = "places", q = "Where do players finally face the Lich King?", a = { "Icecrown Citadel", "Naxxramas", "Ulduar", "Utgarde Pinnacle" } },
    { c = "places", q = "Which raid ends with a fight against Garrosh Hellscream?", a = { "Siege of Orgrimmar", "Throne of Thunder", "Dragon Soul", "Heart of Fear" } },
    { c = "places", q = "Medivh's tower in Deadwind Pass is called...", a = { "Karazhan", "Dalaran", "Nethergarde Keep", "Grim Batol" } },
    { c = "places", q = "Which continent is Orgrimmar on?", a = { "Kalimdor", "Eastern Kingdoms", "Northrend", "Pandaria" } },
    { c = "places", q = "In which zone does Hogger the gnoll cause trouble?", a = { "Elwynn Forest", "Westfall", "Duskwood", "Loch Modan" } },
    { c = "places", q = "The Dark Portal stands in which Eastern Kingdoms zone?", a = { "Blasted Lands", "Swamp of Sorrows", "Burning Steppes", "Badlands" } },

    -- Classes, expansions, professions and fun
    { c = "game", q = "Which expansion added the Death Knight class?", a = { "Wrath of the Lich King", "The Burning Crusade", "Cataclysm", "Legion" } },
    { c = "game", q = "Which expansion added the Monk class?", a = { "Mists of Pandaria", "Warlords of Draenor", "Cataclysm", "Legion" } },
    { c = "game", q = "Which expansion added the Demon Hunter class?", a = { "Legion", "The Burning Crusade", "Warlords of Draenor", "Shadowlands" } },
    { c = "game", q = "Which expansion added the Evoker class?", a = { "Dragonflight", "Shadowlands", "Battle for Azeroth", "The War Within" } },
    { c = "game", q = "Which expansion made goblins and worgen playable?", a = { "Cataclysm", "Wrath of the Lich King", "Mists of Pandaria", "The Burning Crusade" } },
    { c = "game", q = "Which expansion made blood elves and draenei playable?", a = { "The Burning Crusade", "Wrath of the Lich King", "Cataclysm", "Legion" } },
    { c = "game", q = "What was the level cap in the original World of Warcraft?", a = { "60", "50", "70", "80" } },
    { c = "game", q = "What was the level cap in Wrath of the Lich King?", a = { "80", "70", "85", "90" } },
    { c = "game", q = "How many silver coins make one gold?", a = { "100", "10", "1,000", "50" } },
    { c = "game", q = "Which item takes you back to the inn where you set your home?", a = { "Hearthstone", "Soulstone", "Moonstone", "Homecoming Rune" } },
    { c = "game", q = "Which profession brews potions and flasks?", a = { "Alchemy", "Inscription", "Herbalism", "Cooking" } },
    { c = "game", q = "Which profession, added in Wrath, makes glyphs?", a = { "Inscription", "Enchanting", "Jewelcrafting", "Engineering" } },
    { c = "game", q = "Which profession, added in The Burning Crusade, cuts gems?", a = { "Jewelcrafting", "Mining", "Blacksmithing", "Engineering" } },
    { c = "game", q = "Which profession lets you build rocket boots and goblin jumper cables?", a = { "Engineering", "Tailoring", "Leatherworking", "Blacksmithing" } },
    { c = "game", q = "Which holiday brings the Headless Horseman back each autumn?", a = { "Hallow's End", "Brewfest", "Day of the Dead", "Harvest Festival" } },
    { c = "game", q = "Which festival is all about beer, rams and Dark Iron party crashers?", a = { "Brewfest", "Midsummer Fire Festival", "Lunar Festival", "Pilgrim's Bounty" } },
    { c = "game", q = "Which travelling carnival visits once a month?", a = { "Darkmoon Faire", "Trial of the Crusader", "Gurubashi Arena", "Brawler's Guild" } },
    { c = "game", q = "Which winter holiday features Greatfather Winter?", a = { "Feast of Winter Veil", "Lunar Festival", "Love is in the Air", "Noblegarden" } },
    { c = "game", q = "What noise is a murloc best known for?", a = { "Mrglglglgl!", "Hrrrrrnngh!", "Kekekeke!", "Ook ook!" } },
    { c = "game", q = "What kind of creature is Hogger?", a = { "Gnoll", "Kobold", "Murloc", "Ogre" } },
    { c = "game", q = "What do kobold miners famously say about candles?", a = { "You no take candle!", "Candle is mine!", "Light the candle!", "Candle go boom!" } },
    { c = "game", q = "Which class can tame beasts as permanent pets?", a = { "Hunter", "Druid", "Shaman", "Warlock" } },
    { c = "game", q = "Which class can summon a Soulstone and an imp?", a = { "Warlock", "Mage", "Priest", "Death Knight" } },
    { c = "game", q = "Which class can turn enemies into sheep with Polymorph?", a = { "Mage", "Warlock", "Shaman", "Druid" } },
    { c = "game", q = "Which class drops totems on the ground?", a = { "Shaman", "Druid", "Paladin", "Monk" } },
}
