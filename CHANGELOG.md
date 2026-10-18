# Changelog

## Unreleased

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
