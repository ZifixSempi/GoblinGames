# Changelog

## Unreleased

### Milestone 5: Card engine, Go Fish and How to play

- New game: **Go Fish** for 2-6 players, played with pairs. Pairs in your hand glow green with a "PAIR!" tag: click one to lay it down and score a point (any time, even on someone else's turn). On your turn, click a card, click a player and press Ask. The pond sits in the middle with a running log of who asked whom, and the most pairs wins (ties share).
  - Hidden hands: only the host shuffles and deals, each player is whispered only their own hand, and the host checks every ask and every pair.
  - Running out of time lays down your pairs and makes a random ask for you. Leaving puts your cards back in the pond and the game carries on.
  - Practice against the Training Dummy.
- **How to play** everywhere: a "?" in the window's corner (rules for the game you're in), a "How to play" button on every game card and in the lobby, and `/gg rules <game>`.
- Core: the shared card engine (`GG.Cards`: decks, shuffling, dealing, hidden hands) and a playing-card widget (`GG.UI.PlayingCard`) with our own card art, ready for Crazy Eights, Blackjack and Poker.


### Milestone 4: Guild Bingo

- New game: **Guild Bingo**, for officer-hosted prize nights.
  - The officer presses "Announce to guild!" and every guild member with the addon gets a join popup. Latecomers can join mid-night and catch up on the numbers already called.
  - The caller's desk has a pattern picker (any line, four corners, X, blackout), automatic calling (every 5, 8 or 12 seconds) or calling by hand, plus pause and announce-again buttons.
  - Cards mark themselves with your faction's chips. The BINGO! button lights up when your card has the pattern, and the host's client checks your card against the numbers it actually called.
  - Fair cards: every card is rebuilt from a shared seed, so no cards are sent and nobody can claim a card they don't have.
  - A winner log (round, pattern, winner, time) sits on the Stats tab with a "Given" button for prizes. Winners can optionally be posted in guild chat.
  - Practice: you and the Training Dummy each play a card against a robot caller.
- Hosting is limited to the guild ranks chosen in Settings, and every client checks the host's rank against its own setting.
- Core: open guild games (`open = true`), late joining (`lateJoin = true`), officer-only hosting (`officerHost = true`), modules can rename the quit button (`QuitLabel`), and the guild roster cache now tracks ranks.
- Settings now have two columns: Everyday, plus Gold and Guild Bingo.


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
