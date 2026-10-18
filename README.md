# GoblinGames

Quick multiplayer games for World of Warcraft, played with your party, raid or
guild while you wait for queues, a raid to form, or guild night to start.
Frames are themed Horde or Alliance, and every piece shows its owner's faction
crest.

**Status:** Milestone 1 (core + Tic-Tac-Toe). Other games show as "Coming soon".

| Game | Players | Status |
|---|---|---|
| Tic-Tac-Toe | 2 | ✅ |
| Connect 6 | 2 | planned |
| Deathroll | 2+ | planned |
| Guild Bingo | any | planned |
| Go Fish | 2–6 | planned |
| Crazy Eights | 2–6 | planned |
| Blackjack | 2–8 | planned |
| Poker (chips) | 2–8 | planned |
| Liar's Dice | 2–6 | planned |
| Trivia | any | planned |

## Supported clients

A single download works on Retail (Midnight), Mists of Pandaria Classic,
Titan Reforged, Burning Crusade Anniversary and Classic Era.

## Using it

- `/gg` or the minimap button opens the window.
- **Practice** plays a Training Dummy offline: a good way to try a game alone.
- **Host** opens a lobby. Invite group members, your target, or anyone by name.
  Players without the addon are flagged as "No addon / offline".
- `/gg help` lists every command.

Invites are only accepted from your group, guild and friends by default
(change it in Settings). Everything runs on invisible addon messages; GoblinGames
never posts in chat on your behalf.

## Rules this addon follows

- It's free and open source, with no ads, donation requests or obfuscated code
  (Blizzard UI Add-On Development Policy).
- It never touches protected functions, and it can't move gold. Gold features
  (planned for Poker and Deathroll) will be ledger-only, optional and off by
  default.
- It honours Retail's addon-chat lockdown during boss encounters and Mythic+.
  Games pause and resume afterwards.

## Repository layout

```
GoblinGames/              core addon (lobby, comms, turns, UI, theming, stats)
  Core/                  logic
  UI/                    windows and widgets
  Libs/                  LibStub, CallbackHandler, AceComm (+ChatThrottleLib), AceDB
GoblinGames_TicTacToe/    a game module (Load-On-Demand)
docs/MODULE_API.md       how to write a game module
.pkgmeta                 BigWigs packager config
.github/workflows/       release automation
```

## Developing

Copy (or symlink) `GoblinGames` and `GoblinGames_TicTacToe` into
`World of Warcraft\_retail_\Interface\AddOns\` (or `_classic_`, `_classic_era_`),
then `/reload` after each change. Turn on `/gg debug` to see every message.

To add a game, read [docs/MODULE_API.md](docs/MODULE_API.md).

## Releasing

Push a tag such as `v0.1.0`. GitHub Actions runs the BigWigs packager, which
builds the zip and uploads it to GitHub Releases, and to CurseForge or Wago
once their API keys and project IDs are configured.

## Credits

Libraries from [Ace3](https://www.wowace.com/projects/ace3) (BSD licence, see
`GoblinGames/Libs/Ace3-LICENSE.txt`).
