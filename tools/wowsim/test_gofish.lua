--[[ Simulated tests for the card engine and Go Fish.
       lua5.1 tools/wowsim/test_gofish.lua        (SEED=n to vary randomness) ]]

package.path = "tools/wowsim/?.lua;" .. package.path
local Sim = require("sim")
Sim.verbose = os.getenv("VERBOSE") ~= nil

local ADDONS = { "GoblinGames", "GoblinGames_TicTacToe", "GoblinGames_GoFish" }
local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1; print("  ok   " .. label)
    else failed = failed + 1; print("  FAIL " .. label) end
end
local function NoErrors(...)
    for _, c in ipairs({ ... }) do
        check(#c.errors == 0, c.name .. " had no Lua errors (" .. #c.errors .. ")")
        if #c.errors > 0 then print("       " .. tostring(c.errors[1])) end
        c.errors = {}
    end
end

math.randomseed(tonumber(os.getenv("SEED") or "5"))

local alice = Sim.NewClient({ name = "Alice", faction = "Horde", group = 1, addons = ADDONS, root = "." })
local bob = Sim.NewClient({ name = "Bob", faction = "Alliance", group = 1, addons = ADDONS, root = "." })
local eve = Sim.NewClient({ name = "Eve", faction = "Horde", group = 1, addons = ADDONS, root = "." })
for _, c in ipairs({ alice, bob, eve }) do Sim.Login(c, { "GoblinGames" }) end
Sim.Advance(1)
local A, B, E = alice.GG, bob.GG, eve.GG
for _, G in ipairs({ A, B, E }) do G.db.profile.turnTimer = 0 end
local AN, BN, EN = "Alice-TestRealm", "Bob-TestRealm", "Eve-TestRealm"
local byName = { [AN] = A, [BN] = B, [EN] = E }

print("\n== Card engine")
do
    local C = A.Cards
    local deck = C.NewDeck()
    check(#deck == 52, "a deck has 52 cards")
    local seen = {}
    for _, c in ipairs(deck) do seen[c] = true end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    check(n == 52, "all 52 are different")
    check(#C.NewDeck(2) == 104, "two decks: 104 cards")
    C.Shuffle(deck)
    local hand = C.Draw(deck, 7)
    check(#hand == 7 and #deck == 45, "drawing 7 leaves 45")
    check(C.Name("QH") == "Queen of Hearts" and C.Name("TS") == "10 of Spades", "card names")
    check(C.RankLabel("T") == "10" and C.RankPlural("6") == "Sixes", "rank labels")
    check(C.IsRed("AD") and not C.IsRed("AC"), "red and black")
    local h = { "KS", "2H", "KD", "AC" }
    C.Sort(h)
    check(h[1] == "AC" and h[2] == "2H" and h[4] == "KD", "sorting by rank then suit")
    local taken = C.TakeRank(h, "K")
    check(#taken == 2 and #h == 2 and C.CountRank(h, "K") == 0, "taking all kings")
    local dec = C.Decode("AS,10X,KH,zz")
    check(#dec == 2 and dec[2] == "KH", "decoding skips junk")
    check(C.Encode({ "AS", "KH" }) == "AS,KH", "encoding")
end

-- Spy on every addon message so we can prove hands stay hidden.
local delivered = {}
Sim.dropFilter = function(from, to, text)
    delivered[#delivered + 1] = { to = to.name, text = text }
    return false
end

local function StartGame(guests)
    local s = A.Lobby:CreateHosted("gofish")
    for _, g in ipairs(guests) do A.Lobby:Invite(s, g.name) end
    Sim.Advance(4) -- the message throttle spaces the invites out
    for _, g in ipairs(guests) do
        if g.GG.Lobby.invites[s.id] then g.GG.Lobby:AcceptInvite(s.id) end
    end
    Sim.Advance(1.5)
    if s.status == "lobby" then A.Lobby:Start(s); Sim.Advance(1) end
    return s
end

local function Session(G, id) return G.Lobby.active end

print("\n== Three players: dealing and hidden hands")
local s = StartGame({ bob, eve })
local d = s.data
local T = A:GetGame("gofish")._test
do
    check(s.status == "playing", "game started")
    check(#d.hands[AN] + #d.hands[BN] + #d.hands[EN] + #d.pond
        + 4 * (#(d.hostBooks[AN] or {}) + #(d.hostBooks[BN] or {}) + #(d.hostBooks[EN] or {})) == 52,
        "every card is somewhere (hands + pond + books = 52)")
    check(#d.pond == 52 - 21, "3 players get 7 cards each")
    local bs, es = B.Lobby.active, E.Lobby.active
    check(bs.data.hands == nil and bs.data.pond == nil, "Bob's client has no copy of anyone's hand or the pond")
    local function same(a, b)
        if #a ~= #b then return false end
        local sa, sb = A.Cards.Sort(A.Util.Copy(a)), A.Cards.Sort(A.Util.Copy(b))
        for i = 1, #sa do if sa[i] ~= sb[i] then return false end end
        return true
    end
    check(same(bs.data.myHand, d.hands[BN]), "Bob got exactly his own hand")
    check(same(es.data.myHand, d.hands[EN]), "Eve got exactly her own hand")
    check(same(d.myHand, d.hands[AN]), "the host sees its own hand in the UI")
    check(bs.data.counts[EN] == #d.hands[EN] and bs.data.stock == #d.pond, "Bob sees Eve's card count and the pond size")

    -- No HAND message ever reached a player it didn't belong to.
    local leak = false
    for _, m in ipairs(delivered) do
        local cards = m.text:match("HAND%^(.*)$") or m.text:match("HAND~c(.*)$")
        if m.text:find("HAND", 1, true) then
            local owner = m.to .. "-TestRealm"
            for c in m.text:gmatch("[A2-9TJQK][SHDC]") do
                if not A.Cards.Contains(d.hands[owner] or {}, c) and #m.text < 200 then
                    -- a card in the message that isn't in the recipient's hand
                    local inHand = false
                    for _, hc in ipairs(byName[owner].Lobby.active.data.myHand) do if hc == c then inHand = true end end
                    if not inHand then leak = true end
                end
            end
        end
    end
    check(not leak, "hands only ever went to their owners")
    local handMsgs = 0
    for _, m in ipairs(delivered) do if m.text:find("HAND", 1, true) then handMsgs = handMsgs + 1 end end
    check(handMsgs == 2, "exactly one private hand message per guest (" .. handMsgs .. ")")
    NoErrors(alice, bob, eve)
end

-- Helpers to drive turns from whichever client is up.
local function Cur() return A.Turns:Current(s) end
local function Give(name, cards)
    -- Rig a hand on the host for a test. (Only the host has the real hands.)
    local all = {}
    for _, p in ipairs({ AN, BN, EN }) do
        for _, c in ipairs(d.hands[p]) do all[#all + 1] = c end
    end
    for _, c in ipairs(d.pond) do all[#all + 1] = c end
    return all
end

print("\n== Asking")
do
    -- Rig the deal: known hands, known pond.
    d.hands[AN] = { "7S", "7H", "2C", "9D" }
    d.hands[BN] = { "7D", "KC", "KD" }
    d.hands[EN] = { "3S", "4S" }
    d.pond = { "5C", "6C", "9H" } -- top of the pond is the END ("9H" first)
    d.hostBooks = {}
    s.turn.current = AN

    -- Invalid asks are ignored.
    check(not T.Ask(s, AN, BN, "K"), "can't ask for a rank you don't hold")
    check(not T.Ask(s, AN, AN, "7"), "can't ask yourself")
    check(not T.Ask(s, BN, AN, "K"), "can't ask out of turn")
    -- Bob tries over the network out of turn: nothing happens.
    local bs = B.Lobby.active
    bs:SendAction("ASK", AN, "K")
    Sim.Advance(0.5)
    check(#d.hands[AN] == 4, "Bob's out-of-turn ask over the network was rejected")

    -- Alice asks Bob for sevens: gets one, goes again.
    check(T.Ask(s, AN, BN, "7"), "Alice asks Bob for Sevens")
    Sim.Advance(0.5)
    check(A.Cards.CountRank(d.hands[AN], "7") == 3 and A.Cards.CountRank(d.hands[BN], "7") == 0, "Bob handed over his seven")
    check(Cur() == AN, "Alice got a seven, so she goes again")
    check(#bs.data.myHand == 2 and bs.data.counts[AN] == 5, "Bob's view updated (hand and Alice's count)")
    local log = bs.data.log[#bs.data.log] or ""
    check(log:find("Sevens") and log:find("got 1"), "Bob's log says what happened")

    -- Alice asks Eve for nines: Go Fish, draws the 9H: lucky, goes again.
    check(T.Ask(s, AN, EN, "9"), "Alice asks Eve for Nines")
    Sim.Advance(0.5)
    check(A.Cards.CountRank(d.hands[AN], "9") == 2 and Cur() == AN, "Go Fish! drew the nine she asked for, so she goes again")
    check(bs.data.stock == 2, "pond shrank to 2")

    -- Alice asks Eve for twos: Go Fish, draws 6C: turn passes.
    T.Ask(s, AN, EN, "2")
    Sim.Advance(0.5)
    check(Cur() ~= AN, "an unlucky draw passes the turn")
    NoErrors(alice, bob, eve)
end

print("\n== Books")
do
    d.hands[AN] = { "QS", "QH", "QD", "3C" }
    d.hands[BN] = { "QC", "8D" }
    d.hands[EN] = { "3H" }
    d.pond = { "4H", "4D" }
    s.turn.current = AN
    T.Ask(s, AN, BN, "Q")
    Sim.Advance(0.5)
    check(#d.hostBooks[AN] == 1 and d.hostBooks[AN][1] == "Q", "four queens make a book")
    check(A.Cards.CountRank(d.hands[AN], "Q") == 0, "the book left Alice's hand")
    local es = E.Lobby.active
    check(es.data.books[AN] and es.data.books[AN][1] == "Q", "Eve sees Alice's book")
    NoErrors(alice, bob, eve)
end

print("\n== Empty hands draw from the pond")
do
    d.hands[AN] = { "3C", "5S" }
    d.hands[BN] = { "3D" }
    d.hands[EN] = { "8C" }
    d.pond = { "JH", "JD" }
    s.turn.current = AN
    T.Ask(s, AN, BN, "3") -- takes Bob's last card
    Sim.Advance(0.5)
    check(#d.hands[BN] == 0, "Bob is out of cards")
    T.Ask(s, AN, EN, "5") -- Go Fish (JD), turn passes to... Bob or Eve
    Sim.Advance(0.5)
    if Cur() == BN then
        check(#d.hands[BN] == 1, "Bob's turn: he drew a card from the pond")
    else
        check(#d.hands[EN] >= 1, "Eve's turn: she still has cards")
    end
    NoErrors(alice, bob, eve)
end

print("\n== Timeout: the host asks for you")
do
    d.hands[AN] = { "2S", "2H" }
    d.hands[BN] = { "2D", "6S" }
    d.hands[EN] = { "6D" }
    d.pond = { "9C", "9S", "TC" }
    s.turn.current = BN
    A:GetGame("gofish").OnTurnTimeout(s, BN)
    Sim.Advance(0.5)
    check(#d.hands[BN] ~= 2 or #d.hands[AN] ~= 2 or #d.hands[EN] ~= 1 or #d.pond ~= 3, "a random ask was made for Bob")
    NoErrors(alice, bob, eve)
end

print("\n== Eve leaves: her cards go back in the pond")
do
    d.hands[AN] = { "2S", "4H" }
    d.hands[BN] = { "2D", "4S" }
    d.hands[EN] = { "6D", "7D", "8D" }
    d.pond = { "9C" }
    s.turn.current = EN
    E.Lobby:Leave()
    Sim.Advance(1)
    check(s.status == "playing", "the game carries on with two")
    check(#d.pond == 4 and #d.hands[EN] == 0, "Eve's 3 cards went back into the pond")
    check(Cur() ~= EN, "it isn't the leaver's turn any more")
    NoErrors(alice, bob, eve)
end

print("\n== Playing to the end")
do
    -- The rigged hands above aren't a real deck, so deal a fresh game for two.
    s.status = "ended"
    A.Lobby:Close(s)
    if B.Lobby.active then B.Lobby:Close(B.Lobby.active) end
    if E.Lobby.active then E.Lobby:Close(E.Lobby.active) end
    Sim.Advance(1)
    s = StartGame({ bob })
    d = s.data
    check(s.status == "playing" and #s.players == 2, "a fresh two-player game")
    local G = A:GetGame("gofish")
    local guard = 0
    while s.status == "playing" and guard < 400 do
        guard = guard + 1
        local cur = Cur()
        if cur then
            -- Use the same random-ask logic as timeouts.
            G.OnTurnTimeout(s, cur)
        end
        Sim.Advance(0.3)
    end
    check(s.status ~= "playing", "the game finished (" .. guard .. " asks)")
    local total = #(d.hostBooks[AN] or {}) + #(d.hostBooks[BN] or {}) + #(d.hostBooks[EN] or {})
    check(total == 13, "all 13 books were made (" .. total .. ")")
    local bs = B.Lobby.active
    Sim.Advance(30) -- let the message throttle catch up
    bs = B.Lobby.active
    check(bs and bs.status == "ended", "Bob saw the game end (" .. tostring(bs and bs.status) .. ")")
    local result = s.result or {}
    local a, b = #(d.hostBooks[AN] or {}), #(d.hostBooks[BN] or {})
    if a > b then check(result.outcome == "win", "Alice has more books and won")
    elseif b > a then check(result.outcome == "loss", "Bob has more books and won")
    else check(result.outcome == "draw", "equal books: a draw") end
    NoErrors(alice, bob, eve)
    A.Lobby:Close(s); B.Lobby:Close(bs)
    if E.Lobby.active then E.Lobby:Close(E.Lobby.active) end
    Sim.Advance(1)
end

print("\n== Practice against the Training Dummy")
do
    local sent = bob.sent
    local p = B.Lobby:StartPractice("gofish")
    check(p and p.isLocal, "practice started")
    local BT = B:GetGame("gofish")._test
    local pd = p.data
    check(#pd.hands[BN] == 7 and #pd.hands[p.players[2]] == 7, "both get 7 cards")
    local guard = 0
    while p.status == "playing" and guard < 600 do
        guard = guard + 1
        if B.Turns:IsMyTurn(p) then
            -- Click a card, then Ask (one opponent is picked automatically).
            local hand = pd.myHand
            BT.CardClick({ card = hand[math.random(#hand)] })
            BT.DoAsk()
        end
        Sim.Advance(1)
    end
    check(p.status == "ended", "practice game finished (" .. guard .. " steps)")
    check(bob.sent == sent, "practice sends nothing over the network")
    NoErrors(bob)
end

Sim.dropFilter = nil
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
