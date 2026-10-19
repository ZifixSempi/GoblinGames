--[[ Simulated tests for Crazy Eights.
       lua5.1 tools/wowsim/test_crazyeights.lua        (SEED=n to vary randomness) ]]

package.path = "tools/wowsim/?.lua;" .. package.path
local Sim = require("sim")
Sim.verbose = os.getenv("VERBOSE") ~= nil

local ADDONS = { "GoblinGames", "GoblinGames_TicTacToe", "GoblinGames_CrazyEights" }
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

math.randomseed(tonumber(os.getenv("SEED") or "8"))

local alice = Sim.NewClient({ name = "Alice", faction = "Horde", group = 1, addons = ADDONS, root = "." })
local bob = Sim.NewClient({ name = "Bob", faction = "Alliance", group = 1, addons = ADDONS, root = "." })
local eve = Sim.NewClient({ name = "Eve", faction = "Horde", group = 1, addons = ADDONS, root = "." })
for _, c in ipairs({ alice, bob, eve }) do Sim.Login(c, { "GoblinGames" }) end
Sim.Advance(1)
local A, B, E = alice.GG, bob.GG, eve.GG
for _, G in ipairs({ A, B, E }) do G.db.profile.turnTimer = 0 end
local AN, BN, EN = "Alice-TestRealm", "Bob-TestRealm", "Eve-TestRealm"

local delivered = {}
Sim.dropFilter = function(from, to, text)
    delivered[#delivered + 1] = { to = to.name, text = text }
    return false
end

local function StartGame(guests, options)
    local s = A.Lobby:CreateHosted("crazyeights")
    for k, v in pairs(options or {}) do A.Lobby:SetOption(s, k, v) end
    for _, g in ipairs(guests) do A.Lobby:Invite(s, g.name) end
    Sim.Advance(4)
    for _, g in ipairs(guests) do
        if g.GG.Lobby.invites[s.id] then g.GG.Lobby:AcceptInvite(s.id) end
    end
    Sim.Advance(1.5)
    if s.status == "lobby" then A.Lobby:Start(s); Sim.Advance(1) end
    return s
end

local function same(a, b)
    if #a ~= #b then return false end
    local sa, sb = A.Cards.Sort(A.Util.Copy(a)), A.Cards.Sort(A.Util.Copy(b))
    for i = 1, #sa do if sa[i] ~= sb[i] then return false end end
    return true
end

print("\n== Three players: the deal")
local s = StartGame({ bob, eve })
local d = s.data
local T = A:GetGame("crazyeights")._test
local bs, es = B.Lobby.active, E.Lobby.active
do
    check(s.status == "playing" and #s.players == 3, "game started with three")
    check(#d.hands[AN] == 5 and #d.hands[BN] == 5 and #d.hands[EN] == 5, "3+ players get 5 cards each")
    check(#d.deck + #d.discard + 15 == 52, "every card is somewhere")
    check(A.Cards.Rank(d.top) ~= "8", "the first card flipped is never an Eight")
    check(bs.data.top == d.top and bs.data.suit == A.Cards.Suit(d.top), "Bob sees the top card and the suit to follow")
    check(bs.data.hands == nil and bs.data.deck == nil, "Bob's client has nobody's hand and no draw pile")
    check(same(bs.data.myHand, d.hands[BN]) and same(es.data.myHand, d.hands[EN]), "each guest got exactly their own hand")
    check(bs.data.counts[EN] == 5 and bs.data.deckCount == #d.deck, "Bob sees counts and the draw pile size")
    local handMsgs = 0
    for _, m in ipairs(delivered) do if m.text:find("HAND", 1, true) then handMsgs = handMsgs + 1 end end
    check(handMsgs == 2, "one private hand message per guest")
    check(s.options.specials == 1, "Goblin rules are on by default")
    NoErrors(alice, bob, eve)
end

local function Cur() return A.Turns:Current(s) end
local function Rig(top, suit, hands, deck)
    d.top, d.suit, d.discard = top, suit or A.Cards.Suit(top), { top }
    d.hands[AN], d.hands[BN], d.hands[EN] = hands[1], hands[2], hands[3]
    d.deck = deck or { "3C", "4C", "5C", "6C", "7C" }
    d.dir, d.drew, d.stuck = 1, nil, 0
    s.turn.order = { AN, BN, EN }
end

print("\n== Matching")
do
    Rig("9H", nil, { { "9S", "KH", "2C", "4D" }, { "5H", "JD", "TC" }, { "3S", "QS", "6D" } })
    s.turn.current = AN
    check(T.Playable(d, "9S") and T.Playable(d, "KH"), "same rank or same suit fits")
    check(not T.Playable(d, "2C"), "neither suit nor rank: no")
    check(T.Playable(d, "8C"), "an Eight fits anything")
    check(not T.Play(s, AN, "2C"), "the host refuses a card that doesn't match")
    check(not T.Play(s, AN, "AH"), "the host refuses a card you don't have")
    check(not T.Play(s, BN, "5H"), "can't play out of turn")
    bs:SendAction("PLAY", "5H")
    Sim.Advance(0.5)
    check(#d.hands[BN] == 3, "Bob's out-of-turn play over the network was ignored")

    check(T.Play(s, AN, "KH"), "Alice plays the King of Hearts")
    Sim.Advance(0.5)
    check(d.top == "KH" and #d.hands[AN] == 3 and Cur() == BN, "it's on the pile and Bob is next")
    check(bs.data.top == "KH" and bs.data.counts[AN] == 3, "Bob's table shows it")
    check((bs.data.log[#bs.data.log] or ""):find("King of Hearts"), "the log says what was played")
    NoErrors(alice, bob, eve)
end

print("\n== Eights are wild")
do
    Rig("9H", nil, { { "8C", "2S" }, { "5H", "JD", "TC" }, { "3S", "QS", "6D" } })
    s.turn.current = AN
    check(T.Play(s, AN, "8C", "S"), "Alice plays an Eight and calls Spades")
    Sim.Advance(0.5)
    check(d.suit == "S" and bs.data.suit == "S", "Spades must be followed now")
    check(T.Playable(d, "3S") and not T.Playable(d, "5H") and T.Playable(d, "8D"), "a Spade or an 8 fits; a Heart doesn't")

    -- Bob's client: clicking an Eight opens the suit picker, picking sends it.
    d.hands[BN] = { "8D", "JD" }
    bs.data.myHand = { "8D", "JD" }
    local BT = B:GetGame("crazyeights")._test
    BT.CardClick({ card = "8D" })
    check(BT.view.picking == "8D", "Bob's suit picker opened")
    BT.PickSuit("D")
    Sim.Advance(0.5)
    check(d.top == "8D" and d.suit == "D" and Cur() == EN, "Bob's Eight called Diamonds")
    NoErrors(alice, bob, eve)
end

print("\n== Draw, then play or pass")
do
    Rig("9H", nil, { { "2C", "3C" }, { "5S", "JD" }, { "3S", "QS", "6D" } }, { "4C", "KH" })
    s.turn.current = AN
    check(not T.Pass(s, AN), "you can't pass before drawing")
    check(T.Draw(s, AN), "Alice draws")
    Sim.Advance(0.5)
    check(#d.hands[AN] == 3 and A.Cards.Contains(d.hands[AN], "KH"), "she got the King of Hearts")
    check(not T.Draw(s, AN), "only one draw per turn")
    check(d.iDrew and Cur() == AN, "her client knows she drew, and it's still her turn")
    check(T.Play(s, AN, "KH"), "she plays the card she drew")
    Sim.Advance(0.5)
    check(Cur() == BN and not d.iDrew, "Bob's turn; Alice's draw flag is cleared")

    -- Bob draws a dud and passes.
    T.Draw(s, BN)
    Sim.Advance(0.5)
    check(bs.data.iDrew, "Bob's client shows Pass now")
    B:GetGame("crazyeights")._test.DrawOrPass()
    Sim.Advance(0.5)
    check(Cur() == EN, "Bob passed")
    NoErrors(alice, bob, eve)
end

print("\n== Goblin rules: 2, Q and A")
do
    Rig("9H", nil, { { "2H", "QH", "AH", "5C" }, { "5S", "JD", "TC" }, { "3S", "QS", "6D" } },
        { "4C", "4D", "4S", "4H" })
    s.turn.current = AN
    T.Play(s, AN, "2H")
    Sim.Advance(0.5)
    check(#d.hands[BN] == 5, "a 2: Bob draws two cards")
    check(Cur() == EN, "and misses his turn")
    check(#bs.data.myHand == 5, "Bob's hand shows the two new cards")

    s.turn.current = AN
    d.drew = nil
    T.Play(s, AN, "QH")
    Sim.Advance(0.5)
    check(Cur() == EN, "a Queen skips Bob")

    s.turn.current = AN
    T.Play(s, AN, "AH")
    Sim.Advance(0.5)
    check(d.dir == -1 and Cur() == EN, "an Ace reverses: Eve (before Alice) is next")
    check(bs.data.dir == -1, "everyone sees the order flipped")
    NoErrors(alice, bob, eve)
end

print("\n== Last card and winning")
do
    Rig("9H", nil, { { "5H", "6S" }, { "5S", "JD" }, { "3S", "QS", "6D" } })
    s.turn.current = AN
    T.Play(s, AN, "5H")
    Sim.Advance(0.5)
    check(bs.data.counts[AN] == 1, "Alice is on her last card")
    local BT = B:GetGame("crazyeights")._test
    s.turn.current = BN
    T.Play(s, BN, "5S")
    Sim.Advance(0.5)
    s.turn.current = AN
    T.Play(s, AN, "6S")
    Sim.Advance(1)
    check(s.status == "ended" and s.result and s.result.outcome == "win", "Alice played her last card and won")
    Sim.Advance(5)
    check(bs.status == "ended", "Bob saw the game end")
    NoErrors(alice, bob, eve)
end

print("\n== Classic rules and leaving")
do
    A.Lobby:Close(s); B.Lobby:Close(bs); E.Lobby:Close(es)
    Sim.Advance(1)
    s = StartGame({ bob, eve }, { specials = 0 })
    d = s.data
    bs, es = B.Lobby.active, E.Lobby.active
    check(s.status == "playing" and bs.options.specials == 0, "a Classic game (no card powers)")
    Rig("9H", nil, { { "2H", "QH", "5C" }, { "5S", "JD", "TC" }, { "3S", "QS", "6D" } })
    s.turn.current = AN
    T.Play(s, AN, "2H")
    Sim.Advance(0.5)
    check(#d.hands[BN] == 3 and Cur() == BN, "a 2 is just a 2 in Classic")

    local before = #d.deck
    E.Lobby:Leave()
    Sim.Advance(1)
    check(s.status == "playing", "Eve left; the game carries on")
    check(#d.deck == before + 3, "Eve's cards went into the draw pile")
    NoErrors(alice, bob, eve)
end

print("\n== Timeout and stalemate")
do
    Rig("9H", nil, { { "2C", "4S" }, { "5S", "JD", "TC" }, {} }, {})
    d.discard = { "9H" }
    s.turn.current = AN
    A:GetGame("crazyeights").OnTurnTimeout(s, AN)
    Sim.Advance(0.5)
    check(Cur() == BN, "Alice timed out with nothing to play and nothing to draw: she passed")
    A:GetGame("crazyeights").OnTurnTimeout(s, BN)
    Sim.Advance(0.5)
    check(s.status == "ended", "a full lap with no plays and no cards: the game ends")
    check(s.result and s.result.outcome == "win", "Alice had the fewest cards and won")
    NoErrors(alice, bob, eve)
end

print("\n== Whole games, played by the auto-player")
do
    A.Lobby:Close(s); B.Lobby:Close(bs)
    if E.Lobby.active then E.Lobby:Close(E.Lobby.active) end
    Sim.Advance(1)
    s = StartGame({ bob, eve })
    d = s.data
    local G = A:GetGame("crazyeights")
    local guard = 0
    while s.status == "playing" and guard < 500 do
        guard = guard + 1
        G.OnTurnTimeout(s, Cur())
        Sim.Advance(0.2)
    end
    check(s.status == "ended", "the game finished (" .. guard .. " turns)")
    local total = #d.deck + #d.discard
    for _, p in ipairs(s.players) do total = total + #d.hands[p] end
    check(total == 52, "no card was lost or copied (" .. total .. ")")
    Sim.Advance(30)
    check(B.Lobby.active and B.Lobby.active.status == "ended", "Bob saw it end")
    NoErrors(alice, bob, eve)
    A.Lobby:Close(s); B.Lobby:Close(B.Lobby.active); E.Lobby:Close(E.Lobby.active)
    Sim.Advance(1)
end

print("\n== Practice against the Training Dummy")
do
    local sent = bob.sent
    local p = B.Lobby:StartPractice("crazyeights")
    check(p and p.isLocal, "practice started")
    local pd = p.data
    check(#pd.hands[BN] == 7, "two players: 7 cards each")
    local BT = B:GetGame("crazyeights")._test
    local guard = 0
    while p.status == "playing" and guard < 600 do
        guard = guard + 1
        if B.Turns:IsMyTurn(p) then
            -- Play like a person: click a glowing card, or draw / pass.
            local played = false
            for _, c in ipairs(pd.myHand) do
                if BT.Playable(pd, c) then
                    BT.CardClick({ card = c })
                    if BT.view.picking then BT.PickSuit("H") end
                    played = true
                    break
                end
            end
            if not played then BT.DrawOrPass() end
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
