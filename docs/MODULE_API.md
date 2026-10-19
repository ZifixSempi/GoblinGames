# GoblinGames module API

Every game is its own Load-On-Demand addon that plugs into the core. The core
handles invites, networking, turns, timers, stats, theming and the window; a
module only supplies its rules, its board, and its message handlers.

`GoblinGames_TicTacToe/TicTacToe.lua` is the simplest reference implementation;
`GoblinGames_Connect6/Connect6.lua` shows animated pieces built from several
layers, a side panel, a compact header and a smarter bot. Copy one when starting a new game.

## 1. Files

```
GoblinGames_MyGame/
    GoblinGames_MyGame.toc
    MyGame.lua
```

```toc
## Interface: 120105, 50504, 38002, 20506, 11509
## Title: |cff6fdc4fGoblin|r|cffd4af37Games|r - My Game
## Notes: One line describing the game.
## Author: Zifix
## Version: @project-version@
## IconTexture: Interface\Icons\INV_Misc_Dice_01
## Group: GoblinGames
## X-Curse-Project-ID: 000000
## LoadOnDemand: 1
## Dependencies: GoblinGames

MyGame.lua
```

Then:

1. Add an entry for the game to `GG.CATALOG` in `GoblinGames/Core/Modules.lua`
   (id, addon folder name, display name, min/max players, icon, description).
   Optional flags: `practice = true` (has a bot), `open = true` (announced to
   the whole guild instead of invite-only), `officerHost = true` (only the
   guild ranks chosen in Settings may host).
   The game picker reads the catalog, so the game shows up without its module
   being loaded.
2. Add the folder to `.pkgmeta` under `move-folders`.

## 2. Registering

```lua
local GG = GoblinGames            -- global published by the core
local Game = { id = "mygame" }   -- must match the catalog id

function Game.OnSessionStart(session) ... end   -- required
-- every other callback below is optional

GG:RegisterGame(Game)            -- last line of the file
```

## 3. Callbacks

| Callback | Runs on | When |
|---|---|---|
| `OnSessionStart(session)` | everyone | The game begins. Build or reset your board. **Host:** set up the state and call `GG.Turns:Start`. |
| `OnAction(session, sender, op, args)` | host | A player (or bot) asked to do something. Check it against the rules; if it's legal, `session:Broadcast` the result. Ignore anything illegal. |
| `OnState(session, op, args, isPrivate)` | everyone | The host announced a change (`Broadcast`, or `SendTo` with `isPrivate = true`). Apply it to `session.data` and redraw. |
| `OnSyncRequest(session, player)` | host | A player missed messages (loading screen, packet gap). Send them a full snapshot with `session:SendTo(player, "SNAP", ...)`. |
| `OnPlayerLeft(session, name, reason)` | host | Someone forfeited, timed out or disconnected (`reason` = `"forfeit"`, `"timeout"`, `"offline"`). Return `true` if you handled it and the game continues; otherwise the core ends 2-player games and skips the player's turn in bigger ones. |
| `OnTurnTimeout(session, name)` | host | The turn clock ran out. Default: the player is removed (`OnPlayerLeft` with `"timeout"`). Define this to, for example, auto-pass instead. |
| `OnSessionEnd(session, result)` | everyone | The game is over. `result = { winners, draw, reason, outcome }`, where `outcome` is `"win"`, `"loss"`, `"draw"` or nil, from this client's point of view. Stats and sounds are already handled. |
| `OnSessionClosed(session)` | everyone | The session is gone. Hide your board. |
| `BotAction(session, botName)` | host | Practice games only: it's the bot's turn. Pick a move and call `session:ActAs(botName, op, ...)`. Defining this enables the **Practice** button. |
| `turnTimer` (field, not a function) | | Override the turn length in seconds (`0` = no timer). If unset, the host's setting is used. |
| `compactHeader` (field) | | `true` for big boards: hides the name plates and puts the status line and timer in one thin row (Connect 6 uses it). |
| `options` (field) | | Lobby options the host picks before inviting: `{ { key, label, default, values = { {value, text}, ... }, gold = true? } }`. Read them in game as `session.options[key]`. `gold = true` options only appear with gold mode on. A `stake` option is understood by the core (invite popup, consent, `GG.Lobby.Stake(session)`). |
| `lateJoin` (field) | | `true` lets players join an open game that's already running. The core sends them START and calls `OnSyncRequest` for them. |
| `QuitLabel(session)` | everyone | Optional. Returns the text for the quit button (Bingo: "End night" / "Leave"). |
| `hint` (field) | | What the goblin says when it's your turn, e.g. `"Click an empty slot. Three in a row wins!"` |

**Every value in `args` is a string.** Convert with `tonumber()`. Booleans
arrive as `"1"` and `"0"`, and `nil` arrives as `""`. Local delivery (the host's
own moves, practice games) uses the same rule, so code that works locally also
works over the network.

### Optional: a lobby tool button

`lobbyTool = { label = "Edit questions", onClick = function(session) end }`
adds one button for the host under "How to play" in the lobby (Trivia uses it
for its question editor).

### Optional: who's actually playing

`IsPlaying(session, name) -> bool`: return false for someone who runs the game
but doesn't play it (the Blackjack dealer). They get no win/loss stat.

## 4. The session object

| Field / method | Meaning |
|---|---|
| `session.id`, `.gameId`, `.host` | Identifiers. Player names are always full `Name-Realm`. |
| `session.players` | Ordered list of player names; identical on every client. |
| `session.data` | Your game state. Start it in `OnSessionStart`. |
| `session.status` | `"lobby"`, `"playing"` or `"ended"`. |
| `session.isLocal` | `true` in practice games (nothing goes over the network). |
| `session.left[name]` | The reason a player dropped out, or nil. |
| `session:IsHost()`, `session:Me()` | |
| `session:SeatOf(name)` | 1-based index into `players`. |
| `session:GetFaction(name)` | `"Horde"`, `"Alliance"` or `"Neutral"`. Use it for that player's pieces ("mixed" mode). |
| `session:IsActive(name)`, `session:ActivePlayers()`, `session:Others()` | |
| `session:SendAction(op, ...)` | **Player → host.** "I want to do this." |
| `session:Broadcast(op, ...)` | **Host → everyone, including the host.** Sequenced, so clients detect gaps. |
| `session:SendTo(name, op, ...)` | **Host → one player, by whisper.** Use it for hidden cards and dice. Not sequenced; include everything the player needs. |
| `session:ActAs(botName, op, ...)` | Host, practice only. Make a move for the bot. |
| `session:End({ winners = {...}, draw = bool, reason = "text" })` | Host. Finishes the game for everyone. |

Op names starting with `_` are reserved for the core. Keep messages short: they
are split into 255-byte chunks automatically, but every chunk costs throttle
budget.

## 5. Turns

```lua
GG.Turns:Start(session, orderList)   -- host; orderList[1] goes first
GG.Turns:Advance(session)            -- host; next active player
GG.Turns:Advance(session, name)      -- host; specific player
GG.Turns:ResetTimer(session)         -- host; fresh clock, same player
GG.Turns:Current(session)            -- anyone
GG.Turns:IsMyTurn(session)
GG.Turns:Remaining(session)          -- seconds, or nil with no timer
```

Games without turns (Trivia, Bingo, Deathroll rounds) simply never call
`Turns:Start`.

## 6. UI helpers

```lua
local area = GG.UI:GetGameArea()   -- parent your board to this frame
GG.UI:SetGameStatus("Pick two cards to discard")   -- nil = automatic text
GG.Theme:SetCrest(texture, faction)
GG.Theme:ApplyFrame(frame, "tile")  -- frame needs GG.UI.BACKDROP as its template
GG.Theme:PlaySound("turn")          -- "victory" | "defeat" | "turn" | "invite" | "click"
GG.UI.Button(parent, text, w, h, onClick, style)  -- style: "primary" | "wood" | "danger"
GG.UI.Card(parent)                  -- parchment card (use { ink = true } text on it)
GG.UI.Text(parent, text, { fancy = true, size = 18, ink = true })
GG.UI.Ribbon(parent, text, w, h, colorKey)
GG.UI.AddPopIn(region)              -- then region.popIn:Play()
GG.UI.AddPulse(region)              -- then region.pulse:Play()
GG.UI:CoinShower(frame)             -- celebration
GG.UI:Say("text")                   -- make the goblin say something
GG.UI.MEDIA .. "Slot"               -- our own textures: Slot, Ring, Coin, Parchment ...
```

Give your game a rule sheet in `Core/Rules.lua` (`GG.RULES[id] = { title,
intro, sections = { { "Heading", "Text" } } }`). The "How to play" buttons and
`/gg rules <id>` show it; `GG.UI:ShowRules(id)` opens it from code.

Add a game's entry to `GG.CATALOG` with `practice = true` when the module has a
`BotAction`, so the Practice button appears.

## 6b. Cards (hidden hands)

```lua
local Cards = GG.Cards       -- cards are 2-char strings: "AS", "TH" (T = ten), "QC"
local deck = Cards.Shuffle(Cards.NewDeck())     -- host only; NewDeck(2) = two decks
local hand = Cards.Draw(deck, 7)                -- off the top
Cards.Sort(hand); Cards.TakeRank(hand, "7"); Cards.CountRank(hand, "7"); Cards.Contains(hand, "AS")
Cards.Name("QH")  -- "Queen of Hearts"        Cards.RankPlural("7") -- "Sevens"
Cards.SendHand(session, player, hand)           -- whispers "HAND" to that player only

local c = GG.UI.PlayingCard(parent, 64)         -- a card on screen (height = 1.43 x width)
c:SetCard("QH"); c:SetBack(); c:SetSelected(true); c:SetDim(true); c.onClick = function(card) end
local seat = GG.UI.CardSeat(parent)             -- an opponent: crest, name, card backs, score, badge
seat:SetPlayer(session, name); seat:SetCount(5); seat:SetBadge("LAST CARD!"); seat:SetTurn(true)
local pip = GG.UI.SuitIcon(parent, 40); pip:SetSuit("H")
local die = GG.UI.Die(parent, 40); die:SetFace(5); die:SetFace(0) --[[ hidden ]]; die:SetGlow(true)
```

Pattern for hidden information (see Go Fish): keep the real hands and deck in
host-only fields (`d.hands`, `d.pond`), whisper each hand with
`Cards.SendHand`, broadcast only public numbers (card counts, deck size), and
re-send both in `OnSyncRequest`. Validate every action against the host's
hands, never against what the client claims.

## 7. Dice and gold

```lua
GG.Dice:Roll(1, 1000)                       -- a real /roll, made by the server
GG.RegisterCallback(t, "DICE_ROLLED", function(event, fullName, roll, min, max) end)
GG.Lobby.Stake(session)                     -- 0 or the gold stake
GG.Ledger:Add(gameId, fromName, toName, gold)   -- only records entries involving you
```

Host-side pattern for dice games (see Deathroll): accept a roll only if it's
the current player's turn, the range is right, and it's the first roll this
turn. If the host can't see a roll (players not grouped), let the roller
`SendAction("REPORT", ...)` it and accept it after a short wait, marked as
unverified.

## 8. Events you can listen to

```lua
GG.RegisterCallback(myTable, "TURN_CHANGED", function(event, session) ... end)
```

Available events: `SESSION_CREATED`, `SESSION_UPDATED`, `SESSION_STARTED`,
`SESSION_ENDED`, `SESSION_CLOSED`, `TURN_CHANGED`, `INVITE_RECEIVED`,
`INVITE_CLEARED`, `SETTINGS_CHANGED`, `THEME_CHANGED`, `COMM_LOCK_CHANGED`,
`DICE_ROLLED`, `LEDGER_CHANGED`.

Each table can register one function per event.

## 9. Rules of the road

- **Never call protected functions.** Trading, mailing, moving gold and
  targeting are all protected. Games only track things; players act themselves.
- **No chat spam.** Talk through addon messages. Only Guild Bingo's optional,
  officer-enabled win announcement writes to visible chat.
- **Hidden information goes through `session:SendTo`.** `Broadcast` on a group
  channel reaches every member of the group, including people not playing.
- **Gold stays a ledger.** Gold features must be optional, off by default, and
  show a reminder to follow Blizzard's Terms of Use.
