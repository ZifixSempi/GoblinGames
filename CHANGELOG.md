# Changelog

## Unreleased

### Milestone 3: Deathroll and the dice helper

- New game: **Deathroll** for 2-40 players. Roll from 1000 (or 100, 10,000, 100,000), and each roll goes up to the last result. Whoever rolls a 1 loses. A big ROLL button, a tumbling number, a skull and "DEATH!" when it's over, and a roll log.
- Fair dice: rolls are real `/roll`s made by the server. The host's client checks each one (right player, right range, one roll per turn). Group up so every roll can be verified. Rolls the host can't see are accepted from the roller's report and marked "?".
- Running out of time, leaving or disconnecting counts as rolling a 1.
- Practice against the Training Dummy rolls privately, with nothing sent to your party.
- **Gold mode** (Settings, off by default): the host can set a stake before inviting, and the invite shows it. Players with gold mode off auto-decline staked games. The loser owes each winner in a **ledger** (Stats tab, with a "Paid" button). The addon never moves gold, and it shows a reminder to follow Blizzard's Terms of Use.
- Core: game options in the lobby (locked once invites go out), the dice helper (`GG.Dice`), and the ledger (`GG.Ledger`).


### Milestone 2: Connect 6

- New game: **Connect 6**, the "vertical checkers" game. A 9x8 standing rack: drop one chip per turn into a column, and it falls to the lowest open hole. Six or more in a row (across, up and down, or diagonal) wins.
- Poker-chip pieces: red chips with the Horde crest, blue chips with the Alliance crest. A gold or silver rim marks the seat, and same-faction opponents get a darker shade.
- Chips fall into place with an animation. A ghost chip shows where your drop will land, the last move glows, and the winning line lights up.
- Practice bot: it takes wins, blocks yours, and avoids setting you up.
- Core: a compact game header for big boards (`compactHeader = true`).
- Fixed: the window's close button now closes the window.
- Fixed: Connect 6 chips not appearing. Chips and the rack now share one frame with fixed draw layers.
- New: if a game hits a Lua error, Goblin Games prints a short "hit a bug" line in chat instead of failing silently.
- New logo and goblin art based on Zifix's character.

### Milestone 1: core and Tic-Tac-Toe

- Renamed to **GoblinGames**.
- New goblin-tavern look: wooden frame, plank floor, parchment cards, chunky buttons and tabs, a bobbing logo, and Grizzle the goblin, who tells you what to do on every screen.
- Clearer flow: Games → Lobby (numbered steps) → Game. A "Your Game" tab glows when it's your turn.
- Versus name plates, a burning-fuse turn timer, a Victory/Defeat banner and a coin shower when you win.
- Tic-Tac-Toe: carved wooden slots, pieces pop in, the winning line glows, and a wiggle when you click a spot you can't play.
- All art is original (tools/art/make_art.py). The title font is Luckiest Guy (Apache 2.0).

- Core addon with a lobby, invites (accept, decline, no-addon detection), a host-authoritative game protocol with sequence numbers and resync, and turn timers with forfeit on timeout or disconnect.
- One `.toc` covers Retail (Midnight), Mists Classic, Titan Reforged, TBC Anniversary and Classic Era.
- Main window with a game picker, lobby, game view, stats and settings, plus a minimap button, an Addon Compartment entry and `/gg` commands.
- Horde, Alliance and Neutral themes. Pieces always show their owner's faction crest.
- Win/loss/draw stats per game and per opponent, stored per character, with a SavedVariables migration system so updates never wipe data.
- Practice mode against a Training Dummy bot for solo testing.
- Retail's addon-chat lockdown during boss encounters and Mythic+ is respected: messages wait and turn timers pause.
- Tic-Tac-Toe module (Load-On-Demand).
