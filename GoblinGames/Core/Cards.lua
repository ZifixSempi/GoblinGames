--[[----------------------------------------------------------------------------
  GoblinGames/Core/Cards.lua

  The card engine shared by Go Fish, Crazy Eights, Blackjack and Poker.

  CARDS are 2-character strings: rank + suit.
      ranks  A 2 3 4 5 6 7 8 9 T J Q K      (T = ten)
      suits  S H D C                         (spades, hearts, diamonds, clubs)
  e.g. "AS" = ace of spades, "TH" = ten of hearts. Short, so whole hands fit
  in one addon message.

  HIDDEN HANDS (casual-level security, as agreed for the project)
  Only the HOST shuffles and deals. Each player's hand is whispered to that
  player alone (GG.Cards.SendHand -> session:SendTo). Everyone else only
  learns how many cards a player holds. The host's client checks every move
  against the hands it dealt, so a modified client can't play a card it
  doesn't have.
------------------------------------------------------------------------------]]

local _, GG = ...

local Cards = {}
GG.Cards = Cards

Cards.RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K" }
Cards.SUITS = { "S", "H", "D", "C" }

local RANK_INDEX, SUIT_INDEX = {}, {}
for i, r in ipairs(Cards.RANKS) do RANK_INDEX[r] = i end
for i, s in ipairs(Cards.SUITS) do SUIT_INDEX[s] = i end

local RANK_NAME = { A = "Ace", T = "10", J = "Jack", Q = "Queen", K = "King" }
local RANK_PLURAL = { A = "Aces", ["2"] = "Twos", ["3"] = "Threes", ["4"] = "Fours", ["5"] = "Fives",
    ["6"] = "Sixes", ["7"] = "Sevens", ["8"] = "Eights", ["9"] = "Nines", T = "Tens", J = "Jacks",
    Q = "Queens", K = "Kings" }
local SUIT_NAME = { S = "Spades", H = "Hearts", D = "Diamonds", C = "Clubs" }

function Cards.Rank(card) return card:sub(1, 1) end
function Cards.Suit(card) return card:sub(2, 2) end
function Cards.RankIndex(card) return RANK_INDEX[card:sub(1, 1)] end
function Cards.SuitIndex(card) return SUIT_INDEX[card:sub(2, 2)] end
function Cards.IsRed(card) local s = card:sub(2, 2) return s == "H" or s == "D" end
function Cards.IsValid(card)
    return type(card) == "string" and #card == 2 and RANK_INDEX[card:sub(1, 1)] ~= nil and SUIT_INDEX[card:sub(2, 2)] ~= nil
end

--- "A", "2" ... "10", "J", "Q", "K": what's printed in the card's corner.
function Cards.RankLabel(rank) return rank == "T" and "10" or rank end
function Cards.RankName(rank) return RANK_NAME[rank] or rank end
function Cards.RankPlural(rank) return RANK_PLURAL[rank] or rank end
function Cards.Name(card)
    return Cards.RankName(Cards.Rank(card)) .. " of " .. SUIT_NAME[Cards.Suit(card)]
end

--- A fresh, ordered deck (or several decks shuffled together later).
function Cards.NewDeck(decks)
    local deck = {}
    for _ = 1, decks or 1 do
        for _, s in ipairs(Cards.SUITS) do
            for _, r in ipairs(Cards.RANKS) do deck[#deck + 1] = r .. s end
        end
    end
    return deck
end

--- Shuffle in place (host only: everyone else must never see the order).
function Cards.Shuffle(deck)
    return GG.Util.Shuffle(deck)
end

--- Take n cards off the top of the deck (fewer if it runs out).
function Cards.Draw(deck, n)
    local out = {}
    for _ = 1, n or 1 do
        local c = table.remove(deck)
        if not c then break end
        out[#out + 1] = c
    end
    return out
end

--- Sort a hand by rank, then suit (in place).
function Cards.Sort(hand)
    table.sort(hand, function(a, b)
        local ra, rb = RANK_INDEX[a:sub(1, 1)], RANK_INDEX[b:sub(1, 1)]
        if ra ~= rb then return ra < rb end
        return SUIT_INDEX[a:sub(2, 2)] < SUIT_INDEX[b:sub(2, 2)]
    end)
    return hand
end

--- Remove every card of `rank` from a hand; returns the removed cards.
function Cards.TakeRank(hand, rank)
    local taken = {}
    for i = #hand, 1, -1 do
        if hand[i]:sub(1, 1) == rank then
            taken[#taken + 1] = table.remove(hand, i)
        end
    end
    return taken
end

function Cards.CountRank(hand, rank)
    local n = 0
    for _, c in ipairs(hand) do if c:sub(1, 1) == rank then n = n + 1 end end
    return n
end

function Cards.Contains(hand, card)
    for i, c in ipairs(hand) do if c == card then return i end end
    return nil
end

function Cards.Encode(list) return table.concat(list, ",") end
function Cards.Decode(text)
    local list = {}
    for c in (text or ""):gmatch("[^,]+") do
        if Cards.IsValid(c) then list[#list + 1] = c end
    end
    return list
end

--- Host: whisper a player their hand (bots and the host itself are handled
--- locally by session:SendTo).
function Cards.SendHand(session, player, hand, op)
    session:SendTo(player, op or "HAND", Cards.Encode(hand))
end
