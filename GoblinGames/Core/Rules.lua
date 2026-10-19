--[[----------------------------------------------------------------------------
  GoblinGames/Core/Rules.lua

  "How to play" text for every game. It lives in the core (not in the game
  modules) so the rules can be shown before a game is loaded or installed.

  Each entry: { intro = "one line", sections = { { "Heading", "Text" }, ... } }
  Shown by UI/HowToPlay.lua. Keep the language short and friendly.
------------------------------------------------------------------------------]]

local _, GG = ...

GG.RULES = {
    general = {
        title = "Goblin Games",
        intro = "Quick games to play with your party, raid or guild while you wait.",
        sections = {
            { "Starting a game", "Go to the Games tab and pick a game card.\n- |cff1f7a12Play with friends|r opens a lobby. Invite people from your group, your target, or anyone by name.\n- |cff1f7a12Practice|r plays against the Training Dummy, just you." },
            { "Joining a game", "When someone invites you, a note pops up at the top of your screen. Press |cff1f7a12Let's play!|r, or type |cffa51d12/gg accept|r." },
            { "During a game", "The |cff1f7a12Your Game|r tab glows when it's your turn. The fuse at the top is your turn timer; let it run out and you're out of the game.\nGrizzle (the goblin in the corner) always tells you what to do next." },
            { "Commands", "/gg  open or close the window\n/gg practice <game>  play the Training Dummy\n/gg accept / decline  answer the newest invite\n/gg rules <game>  show these rules\n/gg who  see who in your group or guild has the addon" },
        },
    },

    tictactoe = {
        title = "Tic-Tac-Toe",
        intro = "Get three of your crests in a row before your opponent does.",
        sections = {
            { "Your turn", "Click an empty slot to place your faction crest." },
            { "Winning", "Three in a row wins: across, down or diagonally. A full board with no row is a draw." },
            { "Telling pieces apart", "Pieces show each player's own faction. If you're both the same faction, the gold ring is player 1 and the silver ring is player 2." },
        },
    },

    connect6 = {
        title = "Connect 6",
        intro = "Drop chips into the rack. First to get six in a row wins.",
        sections = {
            { "Your turn", "Click any column to drop one chip. It falls to the lowest open hole. A see-through chip shows where it will land." },
            { "Winning", "Six (or more) of your chips in a row wins: across, up and down, or diagonally. A full rack with no winner is a draw." },
            { "Tips", "Watch the glowing chip: that's the last move. Block your opponent's long lines early, because six takes a while to build and a while to stop." },
        },
    },

    deathroll = {
        title = "Deathroll",
        intro = "Roll lower and lower. Whoever rolls a 1 loses.",
        sections = {
            { "Rolling", "The first player rolls from 1 to the start value (usually 1000). Each next player rolls from 1 up to the previous result. Press ROLL, or type /roll with the number shown." },
            { "Losing", "Roll a 1 and you're dead; everyone else wins. Running out of time or leaving also counts as rolling a 1." },
            { "Fair dice", "Rolls are real /rolls from the server. Group up with the other players so the host can see and verify every roll (marked with a check). Rolls the host can't see get a ?." },
            { "Gold (optional)", "With gold mode on (Settings), the host can set a stake before inviting. The loser owes each winner, tracked in a ledger on the Stats tab. The addon never moves gold: trade it yourself, and follow Blizzard's Terms of Use." },
        },
    },

    bingo = {
        title = "Guild Bingo",
        intro = "Officer-hosted prize nights for the whole guild.",
        sections = {
            { "Joining", "When an officer opens Bingo night, everyone in the guild with Goblin Games gets a popup. Press |cff1f7a12Let's play!|r. You can join late, too." },
            { "Playing", "Your card marks itself as numbers are called. Watch the pattern for this round (shown top right): any line, four corners, X, or blackout (every square)." },
            { "BINGO!", "When your card has the pattern, the BINGO! button lights up. Press it fast! The caller's addon checks your card, and the first valid Bingo wins the round." },
            { "Hosting (officers)", "Play with friends, then Announce to guild!. Start the night, pick a pattern, and press Start round. Numbers are called automatically (or by hand). Winners go in the winner log on the Stats tab; press Given once a prize is handed out. Who may host is set in Settings." },
        },
    },

    gofish = {
        title = "Go Fish",
        intro = "Collect books: all four cards of the same rank.",
        sections = {
            { "Your turn", "Click a card in your hand to pick a rank (you must hold at least one), click an opponent, then press Ask." },
            { "Got any?", "If they have that rank, they hand over every one of them and you go again. If not: Go Fish! You draw from the pond. Draw the rank you asked for and you go again; otherwise the turn passes." },
            { "Books", "Four of a kind is a book. It's laid down automatically and scores a point." },
            { "Empty hands", "Run out of cards and you draw one from the pond. When the pond is empty too, you sit out until the end. If nobody else has cards to ask, you just draw one and pass." },
            { "Tips", "With only one opponent they're picked for you. Hover over a player to see their books. Run out of time and the goblin asks for you, at random!" },
            { "Winning", "When all 13 books are made, whoever has the most books wins. Ties share the win." },
        },
    },

    crazyeights = {
        title = "Crazy Eights",
        intro = "Get rid of all your cards first. Eights are wild!",
        sections = {
            { "Your turn", "Play a card that matches the top card's suit or rank. Can't? Draw a card." },
            { "Eights", "An 8 can be played on anything, and you pick the next suit." },
            { "Winning", "The first player with no cards left wins." },
        },
    },

    blackjack = {
        title = "Blackjack",
        intro = "Beat the dealer's hand without going over 21.",
        sections = {
            { "The deal", "The host is the dealer. Everyone gets two cards; the dealer shows one." },
            { "Your turn", "Hit to take another card, or Stand to stop. Over 21 is a bust." },
            { "Winning", "Closer to 21 than the dealer wins. An Ace counts as 1 or 11; face cards are 10." },
        },
    },

    poker = {
        title = "Poker (Texas Hold'em)",
        intro = "Make the best five-card hand from your two cards and five shared cards.",
        sections = {
            { "Chips", "Everyone plays with chips. Gold mode only keeps a ledger; the addon never moves gold." },
            { "Rounds", "Bet after your two cards, after the flop (3 shared cards), after the turn (4th) and after the river (5th)." },
            { "Winning", "Best hand at the showdown, or the last player who hasn't folded, takes the pot." },
        },
    },

    liarsdice = {
        title = "Liar's Dice",
        intro = "Bid on hidden dice, or call LIAR!",
        sections = {
            { "Bidding", "Everyone rolls hidden dice. Bid how many of a face are on the whole table; each bid must go higher." },
            { "LIAR!", "Think the last bid is too high? Call Liar! Dice are revealed and the loser of the call loses a die." },
            { "Winning", "Last player with dice left wins." },
        },
    },

    trivia = {
        title = "Trivia",
        intro = "Warcraft lore questions. Fastest correct answer scores.",
        sections = {
            { "Playing", "A question appears for everyone. Pick your answer quickly: the first correct answer gets the most points." },
            { "Winning", "Highest score after the last question wins." },
        },
    },
}

--- Build the rules text for a game as one formatted string.
function GG:RulesText(gameId)
    local r = self.RULES[gameId] or self.RULES.general
    local parts = { "|cff5a3412" .. r.intro .. "|r" }
    for _, section in ipairs(r.sections) do
        parts[#parts + 1] = "\n|cffa51d12" .. section[1] .. "|r\n" .. section[2]
    end
    return r.title, table.concat(parts, "\n")
end
