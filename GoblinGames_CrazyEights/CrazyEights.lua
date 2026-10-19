--[[----------------------------------------------------------------------------
  GoblinGames_CrazyEights/CrazyEights.lua

  Crazy Eights for 2-6 players: the Uno-style shedding game. Built on the
  card engine (Core/Cards.lua) like Go Fish.

  RULES
    - Deal 7 cards each (2 players) or 5 each (3-6). One card is flipped to
      start the discard pile (never an 8: those get shuffled back).
    - On your turn, play ONE card that matches the top card's suit or rank.
    - Eights are wild: play one on anything and pick the next suit.
    - Can't (or won't) play? Draw one card. If it fits, you may play it;
      otherwise press Pass. One draw per turn.
    - Goblin rules (a lobby option, on by default), like Uno:
        2  = the next player draws 2 and misses their turn
        Q  = the next player is skipped
        A  = reverse the play order (with 2 players: you go again)
    - First to get rid of every card wins.
    - The draw pile runs out: the discard pile (minus its top card) is
      shuffled into a new one. If even that's empty and nobody can play for a
      full lap, the player with the fewest cards wins.

  HIDDEN INFORMATION
  Same pattern as Go Fish: only the host shuffles, deals and keeps the hands
  and the draw pile. Each player is whispered only THEIR hand ("HAND").
  Everyone gets the public table ("PUB": card counts, draw pile size, the top
  card, the suit to follow, the play order) and a log ("EV"). The host checks
  every card played against the real hand.

  Timeouts don't knock you out: the host plays for you (a matching card if
  there is one, otherwise a draw). Leaving shuffles your cards into the draw
  pile and the game carries on.
------------------------------------------------------------------------------]]

local GG = GoblinGames
local Util = GG.Util
local UI = GG.UI
local Cards = GG.Cards

local Game = {
    id = "crazyeights",
    compactHeader = true,
    hint = "Match the suit or the rank. Eights are wild!",
    options = {
        { key = "specials", label = "Card powers", default = 1, values = {
            { value = 1, text = "Goblin rules (2, Q, A)" },
            { value = 0, text = "Classic (just Eights)" } } },
    },
}

local LOG_LINES = 4
local current

local function Specials(session)
    return tonumber(session.options and session.options.specials) ~= 0
end

-- Can `card` go on the pile? (Works on every client: uses public info only.)
local function Playable(d, card)
    if not d.top or not card then return false end
    local rank = Cards.Rank(card)
    return rank == "8" or Cards.Suit(card) == d.suit or rank == Cards.Rank(d.top)
end

-------------------------------------------------------------------------------
-- Host: rules engine
--
-- Host-only data:   d.hands[name] = {cards}   d.deck = {cards} (draw pile)
--                   d.discard = {cards} (bottom .. top)   d.drew = name
-- Everyone's data:  d.counts[name], d.deckCount, d.top, d.suit, d.dir,
--                   d.myHand, d.log
-------------------------------------------------------------------------------
local function PublicState(session)
    local d = session.data
    local counts = {}
    for _, p in ipairs(session.players) do counts[#counts + 1] = p .. ":" .. #(d.hands[p] or {}) end
    return table.concat(counts, ";"), #d.deck, d.top, d.suit, d.dir
end

local function SendPublic(session)
    session:Broadcast("PUB", PublicState(session))
end

local function SendHand(session, player)
    Cards.SendHand(session, player, Cards.Sort(session.data.hands[player] or {}))
end

-- Draw n cards for a player, reshuffling the discard pile if the draw pile
-- runs dry. Returns the cards drawn.
local function DrawCards(session, player, n)
    local d = session.data
    local got = {}
    for _ = 1, n do
        if #d.deck == 0 and #d.discard > 1 then
            local top = table.remove(d.discard)
            d.deck, d.discard = d.discard, { top }
            Cards.Shuffle(d.deck)
            session:Broadcast("EV", "SHUFFLE")
        end
        local card = table.remove(d.deck)
        if not card then break end
        table.insert(d.hands[player], card)
        got[#got + 1] = card
    end
    return got
end

-- The player `steps` seats away in the current direction (skips leavers).
local function NextPlayer(session, from, steps)
    local d = session.data
    local order = session.turn.order
    local idx = Util.IndexOf(order, from) or 1
    local name = from
    for _ = 1, steps or 1 do
        for _ = 1, #order do
            idx = (idx - 1 + d.dir) % #order + 1
            if session:IsActive(order[idx]) then break end
        end
        name = order[idx]
    end
    return name
end

-- Hand the turn on. `skip` = the next player misses their turn.
local function PassTurn(session, skip)
    local d = session.data
    local cur = GG.Turns:Current(session)
    local nxt = NextPlayer(session, cur, 1)
    if skip then
        session:Broadcast("EV", "SKIP", nxt)
        nxt = NextPlayer(session, nxt, 1)
    end
    d.drew = nil
    GG.Turns:Advance(session, nxt)
end

-- Out of cards to draw, and a whole lap of passing: fewest cards wins.
local function Stalemate(session)
    local d = session.data
    local best, winners = math.huge, {}
    for _, p in ipairs(session:ActivePlayers()) do
        local n = #d.hands[p]
        if n < best then best, winners = n, { p } elseif n == best then winners[#winners + 1] = p end
    end
    local everyone = #winners == #session:ActivePlayers()
    session:End({ winners = everyone and {} or winners, draw = everyone, reason = "no cards left to draw; fewest cards wins" })
end

local function Play(session, player, card, suit)
    local d = session.data
    if session.status ~= "playing" or GG.Turns:Current(session) ~= player then return false end
    local hand = d.hands[player]
    local at = Cards.Contains(hand, card)
    if not at or not Playable(d, card) then return false end

    table.remove(hand, at)
    table.insert(d.discard, card)
    d.top = card
    local rank = Cards.Rank(card)
    if rank == "8" then
        if not (suit and suit:match("^[SHDC]$")) then suit = Cards.Suit(card) end
        d.suit = suit
    else
        d.suit = Cards.Suit(card)
    end
    d.stuck = 0
    session:Broadcast("EV", "PLAY", player, card, rank == "8" and d.suit or "")

    if #hand == 0 then
        SendHand(session, player)
        SendPublic(session)
        session:End({ winners = { player }, reason = Util.ShortName(player) .. " played their last card" })
        return true
    end

    local skip = false
    if Specials(session) then
        if rank == "2" then
            local victim = NextPlayer(session, player, 1)
            local got = DrawCards(session, victim, 2)
            session:Broadcast("EV", "TWO", victim, #got)
            SendHand(session, victim)
            skip = true
        elseif rank == "Q" then
            skip = true
        elseif rank == "A" then
            d.dir = -d.dir
            session:Broadcast("EV", "REVERSE", player)
            if #session:ActivePlayers() == 2 then skip = true end
        end
    end
    SendHand(session, player)
    SendPublic(session)
    PassTurn(session, skip)
    return true
end

local function Draw(session, player)
    local d = session.data
    if session.status ~= "playing" or GG.Turns:Current(session) ~= player or d.drew == player then return false end
    local got = DrawCards(session, player, 1)
    d.drew = player
    session:Broadcast("EV", "DRAW", player, #got)
    SendHand(session, player)
    SendPublic(session)
    if #got == 0 then
        -- Nothing to draw: the only thing left to do is pass.
        d.stuck = (d.stuck or 0) + 1
    end
    GG.Turns:ResetTimer(session) -- a fresh clock to decide on the new card
    return true
end

local function Pass(session, player)
    local d = session.data
    if session.status ~= "playing" or GG.Turns:Current(session) ~= player then return false end
    if d.drew ~= player then return false end -- draw first
    session:Broadcast("EV", "PASS", player)
    if (d.stuck or 0) >= #session:ActivePlayers() then
        Stalemate(session)
        return true
    end
    PassTurn(session, false)
    return true
end

-- Which suit should an Eight call? The one you hold the most of.
local function BestSuit(hand, except)
    local count, best, bestN = {}, "S", -1
    for _, c in ipairs(hand) do
        if c ~= except and Cards.Rank(c) ~= "8" then
            local s = Cards.Suit(c)
            count[s] = (count[s] or 0) + 1
        end
    end
    for _, s in ipairs(Cards.SUITS) do
        if (count[s] or 0) > bestN then best, bestN = s, count[s] or 0 end
    end
    return best
end

-- Play for someone (timeouts and the practice dummy): a matching card if
-- possible (Eights last), otherwise draw, then play the draw or pass.
local function AutoTurn(session, player)
    local d = session.data
    local function TryPlay()
        local hand, choice = d.hands[player], nil
        for _, c in ipairs(hand) do
            if Playable(d, c) and Cards.Rank(c) ~= "8" then choice = c; break end
        end
        if not choice then
            for _, c in ipairs(hand) do if Playable(d, c) then choice = c; break end end
        end
        if choice then return Play(session, player, choice, BestSuit(hand, choice)) end
        return false
    end
    if TryPlay() then return end
    if d.drew ~= player then
        Draw(session, player)
        if TryPlay() then return end
    end
    Pass(session, player)
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------
local view = {}
local seats, handCards = {}, {}
local Refresh

local function SendPlay(card, suit)
    local s = current
    if not s or not GG.Turns:IsMyTurn(s) then return end
    s:SendAction("PLAY", card, suit or "")
    view.picking = nil
    if view.picker then view.picker:Hide() end
end

local function CardClick(c)
    local s = current
    if not s or not c.card or not GG.Turns:IsMyTurn(s) then return end
    if not Playable(s.data, c.card) then
        UI:Say("That one doesn't match. Same suit or same rank, or an Eight!", true)
        return
    end
    if Cards.Rank(c.card) == "8" then
        view.picking = c.card -- choose a suit first
        Refresh()
        return
    end
    SendPlay(c.card)
end

local function PickSuit(suit)
    if view.picking then SendPlay(view.picking, suit) end
end

local function DrawOrPass()
    local s = current
    if not s or not GG.Turns:IsMyTurn(s) then return end
    if s.data.iDrew then
        s:SendAction("PASS")
    else
        s:SendAction("DRAW")
    end
end

local function Build()
    local area = UI:GetGameArea()

    for i = 1, 5 do
        local seat = UI.CardSeat(area)
        seat:SetPoint("TOPLEFT", (i - 1) * 140, 0)
        seat:EnableMouse(true)
        seats[i] = seat
    end

    -- The table: draw pile, discard pile, suit to follow, log, Draw/Pass.
    local mid = UI.Card(area)
    mid:SetPoint("TOPLEFT", 0, -96)
    mid:SetPoint("RIGHT", area, "RIGHT", 0, 0)
    mid:SetHeight(112)
    view.middle = mid

    view.deck = CreateFrame("Button", nil, mid)
    view.deck:SetSize(50, 72)
    view.deck:SetPoint("TOPLEFT", 16, -12)
    for b = 1, 3 do
        local t = view.deck:CreateTexture(nil, "ARTWORK", nil, b)
        t:SetTexture(UI.MEDIA .. "CardBack")
        t:SetTexCoord(0, 1, 0, 183 / 256)
        t:SetSize(46, 66)
        t:SetPoint("TOPLEFT", (b - 1) * 2, -(b - 1) * 2)
        view.deck[b] = t
    end
    local hl = view.deck:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(UI.MEDIA .. "ButtonGlow")
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    view.deck:SetScript("OnClick", function() GG:Safe("Crazy Eights", DrawOrPass) end)
    view.deckText = UI.Text(mid, "", { fancy = true, size = 13, ink = true, justify = "CENTER" })
    view.deckText:SetPoint("TOP", view.deck, "BOTTOM", 0, -4)

    view.top = UI.PlayingCard(mid, 56)
    view.top:SetPoint("TOPLEFT", 84, -12)
    view.top:SetClickable(false)
    view.topText = UI.Text(mid, "Pile", { fancy = true, size = 13, ink = true, justify = "CENTER" })
    view.topText:SetPoint("TOP", view.top, "BOTTOM", 0, -4)

    view.suit = UI.SuitIcon(mid, 40)
    view.suit:SetPoint("TOPLEFT", 156, -14)
    view.suitText = UI.Text(mid, "", { ink = true, font = "GameFontNormalSmall" })
    view.suitText:SetPoint("TOPLEFT", 150, -60)
    view.suitText:SetWidth(110)
    view.dirText = UI.Text(mid, "", { ink = true, font = "GameFontHighlightSmall" })
    view.dirText:SetPoint("TOPLEFT", view.suitText, "BOTTOMLEFT", 0, -4)
    view.dirText:SetTextColor(0.48, 0.38, 0.25)

    view.log = UI.Text(mid, "", { ink = true, font = "GameFontHighlightSmall" })
    view.log:SetPoint("TOPLEFT", 272, -12)
    view.log:SetWidth(260)
    view.log:SetJustifyV("TOP")
    view.log:SetSpacing(2)

    view.action = UI.Button(mid, "Draw a card", 150, 36, function() GG:Safe("Crazy Eights", DrawOrPass) end, "primary")
    view.action:SetPoint("BOTTOMRIGHT", -14, 12)

    -- "Eight! Pick a suit": four big pips over the table.
    local picker = CreateFrame("Frame", nil, mid)
    picker:SetPoint("TOPLEFT", 6, -6)
    picker:SetPoint("BOTTOMRIGHT", -6, 6)
    picker:SetFrameLevel(mid:GetFrameLevel() + 20)
    picker:EnableMouse(true)
    UI.NineSlice(picker, UI.MEDIA .. "Parchment", 128, 24, 16)
    local title = UI.Text(picker, "Crazy Eight! Pick the next suit:", { fancy = true, size = 18, ink = true })
    title:SetPoint("TOPLEFT", 18, -14)
    for i, suit in ipairs(Cards.SUITS) do
        local b = CreateFrame("Button", nil, picker)
        b:SetSize(64, 64)
        b:SetPoint("BOTTOMLEFT", 18 + (i - 1) * 84, 10)
        local icon = UI.SuitIcon(b, 54)
        icon:SetPoint("CENTER")
        icon:SetSuit(suit)
        local glow = b:CreateTexture(nil, "HIGHLIGHT")
        glow:SetTexture(UI.MEDIA .. "ButtonGlow")
        glow:SetAllPoints()
        glow:SetBlendMode("ADD")
        b:SetScript("OnClick", function() GG:Safe("Crazy Eights", PickSuit, suit) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(Cards.SuitName(suit))
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local cancel = UI.Button(picker, "Never mind", 120, 30, function()
        view.picking = nil
        Refresh()
    end, "wood")
    cancel:SetPoint("BOTTOMRIGHT", -14, 14)
    picker:Hide()
    view.picker = picker

    view.hand = CreateFrame("Frame", nil, area)
    view.hand:SetPoint("TOPLEFT", 0, -216)
    view.hand:SetPoint("BOTTOMRIGHT", 0, 0)
end

local function LogLine(d, text)
    d.log[#d.log + 1] = text
    while #d.log > LOG_LINES do table.remove(d.log, 1) end
end

local function Name(p) return Util.IsMe(p) and "You" or Util.ShortName(p) end

local SUIT_COLOR = { S = "222233", C = "222233", H = "b01818", D = "b01818" }
local function SuitWord(suit, singular)
    local word = singular and Cards.SuitSingular(suit) or Cards.SuitName(suit)
    return "|cff" .. (SUIT_COLOR[suit] or "222233") .. word .. "|r"
end

function Refresh()
    local s = current
    if not s or not view.middle then return end
    local d = s.data
    local myTurn = GG.Turns:IsMyTurn(s)
    local cur = GG.Turns:Current(s)
    local playing = s.status == "playing"

    -- Opponents, in play order starting after you.
    local order = (s.turn and s.turn.order) or s.players
    local others = {}
    local myIdx = Util.IndexOf(order, s:Me()) or 0
    for k = 1, #order do
        local p = order[(myIdx + k - 1) % #order + 1]
        if not Util.IsMe(p) then others[#others + 1] = p end
    end
    for i, seat in ipairs(seats) do
        local p = others[i]
        if p then
            seat:Show()
            seat:SetPlayer(s, p)
            local n = d.counts[p] or 0
            seat:SetCount(n)
            seat:SetBadge(playing and n == 1 and not s.left[p] and "LAST CARD!" or nil)
            seat:SetTurn(playing and p == cur)
        else
            seat:Hide()
            seat.player = nil
        end
    end

    -- The table.
    for b = 1, 3 do view.deck[b]:SetShown((d.deckCount or 0) >= b) end
    view.deckText:SetText("Draw: " .. (d.deckCount or 0))
    if d.top then view.top:SetCard(d.top); view.top:Show() else view.top:Hide() end
    if d.suit then
        view.suit:SetSuit(d.suit)
        if d.top and Cards.Rank(d.top) == "8" then
            view.suitText:SetText("Eight! Play a " .. SuitWord(d.suit, true) .. " (or an 8)")
        else
            view.suitText:SetText("Match " .. SuitWord(d.suit) .. " or " .. Cards.RankPlural(Cards.Rank(d.top)))
        end
    end
    local twoOnly = #s:ActivePlayers() == 2
    view.dirText:SetText(twoOnly and "" or (d.dir == -1 and "Order: reversed!" or "Order: normal"))
    view.log:SetText(#d.log > 0 and table.concat(d.log, "\n") or UI.InkGrey("Cards are dealt. Good luck!"))

    -- Draw / Pass button.
    if not playing then
        view.action:Hide()
    else
        view.action:Show()
        view.action:SetEnabled(myTurn)
        if not myTurn then
            view.action:SetText(cur and ("Waiting on " .. Util.ShortName(cur)) or "Waiting...")
        elseif d.iDrew then
            view.action:SetText("Pass")
        else
            view.action:SetText("Draw a card")
        end
    end
    view.deck:EnableMouse(playing and myTurn and not d.iDrew)

    -- Suit picker.
    if view.picking and not (myTurn and Cards.Contains(d.myHand, view.picking)) then view.picking = nil end
    view.picker:SetShown(view.picking ~= nil)

    -- Your hand: playable cards pop up and glow on your turn; the rest dim.
    local hand = d.myHand
    local n = #hand
    local width = 62
    local avail = view.hand:GetWidth()
    if not avail or avail < 100 then avail = 704 end
    local step = (n > 1) and math.min(width + 8, (avail - width) / (n - 1)) or 0
    local startX = (avail - (width + step * math.max(0, n - 1))) / 2
    local anyPlayable = false
    for k, card in ipairs(hand) do
        local c = handCards[k]
        if not c then
            c = UI.PlayingCard(view.hand, width)
            c.onClick = CardClick
            handCards[k] = c
        end
        c:SetFrameLevel(view.hand:GetFrameLevel() + k)
        c:SetCard(card)
        local ok = playing and myTurn and Playable(d, card)
        if ok then anyPlayable = true end
        c:SetSelected(ok or view.picking == card)
        c:SetDim(playing and myTurn and not ok)
        c:ClearAllPoints()
        c:SetPoint("BOTTOMLEFT", startX + (k - 1) * step, ok and 30 or 14)
        c:SetClickable(playing and myTurn)
        c:Show()
    end
    for k = n + 1, #handCards do handCards[k]:Hide() end

    if playing and myTurn then
        if view.picking then
            UI:SetGameStatus(UI.Gold("Pick a suit for your Eight!"))
        elseif anyPlayable then
            UI:SetGameStatus(UI.Gold("Your turn! Click a glowing card to play it."))
        elseif d.iDrew then
            UI:SetGameStatus(UI.Gold("Nothing fits. Press Pass."))
        else
            UI:SetGameStatus(UI.Gold("Nothing fits. Draw a card!"))
        end
    else
        UI:SetGameStatus(nil)
    end
end

-------------------------------------------------------------------------------
-- Module callbacks
-------------------------------------------------------------------------------
function Game.OnSessionStart(session)
    current = session
    local d = session.data
    d.myHand, d.counts, d.deckCount, d.dir, d.log = {}, {}, 0, 1, {}
    d.top, d.suit, d.iDrew = nil, nil, nil
    view.picking = nil
    if not view.middle then Build() end
    view.middle:Show(); view.hand:Show()
    Refresh()

    if session:IsHost() then
        d.deck = Cards.Shuffle(Cards.NewDeck())
        d.hands, d.discard, d.stuck = {}, {}, 0
        local per = (#session.players == 2) and 7 or 5
        for _, p in ipairs(session.players) do d.hands[p] = Cards.Draw(d.deck, per) end
        -- Flip the first card. An Eight goes back in and we try again.
        local first = table.remove(d.deck)
        while Cards.Rank(first) == "8" do
            table.insert(d.deck, 1, first)
            first = table.remove(d.deck)
        end
        d.discard[1] = first
        d.top, d.suit = first, Cards.Suit(first)
        for _, p in ipairs(session.players) do SendHand(session, p) end
        SendPublic(session)
        GG.Turns:Start(session, Util.Shuffle(Util.Copy(session.players)))
    end
end

function Game.OnAction(session, sender, op, args)
    if op == "PLAY" then
        local card, suit = args[1], args[2]
        if not Cards.IsValid(card) then return end
        Play(session, sender, card, suit)
    elseif op == "DRAW" then
        Draw(session, sender)
    elseif op == "PASS" then
        Pass(session, sender)
    end
end

function Game.OnState(session, op, args)
    local d = session.data
    if op == "HAND" then
        d.myHand = Cards.Sort(Cards.Decode(args[1]))
    elseif op == "PUB" then
        d.counts = {}
        for name, n in (args[1] or ""):gmatch("([^:;]+):(%d+)") do d.counts[name] = tonumber(n) end
        d.deckCount = tonumber(args[2]) or 0
        d.top = Cards.IsValid(args[3]) and args[3] or nil
        d.suit = (args[4] or ""):match("^[SHDC]$")
        d.dir = tonumber(args[5]) or 1
    elseif op == "EV" then
        local kind = args[1]
        if kind == "PLAY" then
            local who, card, called = args[2], args[3], args[4]
            local text = ("%s played the %s"):format(Name(who), Cards.Name(card))
            if called and called ~= "" then text = text .. ": |cff1f7a12" .. Cards.SuitName(called) .. "!|r" end
            LogLine(d, text)
            if Util.IsMe(who) then d.iDrew = nil end
        elseif kind == "DRAW" then
            local who, n = args[2], tonumber(args[3]) or 0
            LogLine(d, n > 0 and ("%s drew a card."):format(Name(who)) or ("%s couldn't draw: no cards left!"):format(Name(who)))
            if Util.IsMe(who) then d.iDrew, d.iDrewTurn = true, session.turn and session.turn.number end
        elseif kind == "PASS" then
            LogLine(d, ("%s passed."):format(Name(args[2])))
        elseif kind == "SKIP" then
            LogLine(d, ("|cffa51d12%s %s skipped!|r"):format(Name(args[2]), Util.IsMe(args[2]) and "are" or "is"))
        elseif kind == "TWO" then
            LogLine(d, ("|cffa51d12%s %s %d cards!|r"):format(Name(args[2]), Util.IsMe(args[2]) and "draw" or "draws", tonumber(args[3]) or 2))
            if Util.IsMe(args[2]) then GG.Theme:PlaySound("defeat") end
        elseif kind == "REVERSE" then
            LogLine(d, "Reverse! The play order flips.")
        elseif kind == "SHUFFLE" then
            LogLine(d, "The pile was shuffled into a new draw pile.")
        elseif kind == "OUT" then
            LogLine(d, ("%s left; their cards were shuffled into the draw pile."):format(Name(args[2])))
        end
    end
    if session == current then Refresh() end
end

function Game.OnSyncRequest(session, player)
    SendHand(session, player)
    session:SendTo(player, "PUB", PublicState(session))
end

function Game.OnTurnTimeout(session, name)
    AutoTurn(session, name)
end

function Game.OnPlayerLeft(session, name)
    if Util.IsMe(name) or #session:ActivePlayers() <= 1 then return false end
    local d = session.data
    for _, c in ipairs(d.hands[name] or {}) do table.insert(d.deck, c) end
    d.hands[name] = {}
    Cards.Shuffle(d.deck)
    session:Broadcast("EV", "OUT", name)
    SendPublic(session)
    if GG.Turns:Current(session) == name then
        d.drew = nil
        GG.Turns:Advance(session, NextPlayer(session, name, 1))
    end
    return true
end

function Game.OnSessionEnd(session)
    if session == current then view.picking = nil; Refresh() end
end

function Game.OnSessionClosed(session)
    if session == current then
        current = nil
        if view.middle then view.middle:Hide(); view.hand:Hide() end
        for _, seat in ipairs(seats) do seat:Hide() end
        UI:SetGameStatus(nil)
    end
end

GG.RegisterCallback(Game, "TURN_CHANGED", function(_, session)
    -- A new turn (the turn number moved on): you haven't drawn yet. A draw
    -- restarts the clock without changing the number, so it keeps iDrew.
    local d = session.data
    if d.iDrew and d.iDrewTurn ~= (session.turn and session.turn.number) then d.iDrew = nil end
    if session == current then Refresh() end
end)

function Game.BotAction(session, bot)
    if session.status ~= "playing" or GG.Turns:Current(session) ~= bot then return end
    AutoTurn(session, bot)
end

Game._test = { Play = Play, Draw = Draw, Pass = Pass, Playable = Playable, AutoTurn = AutoTurn,
    CardClick = CardClick, PickSuit = PickSuit, DrawOrPass = DrawOrPass, view = view }

GG:RegisterGame(Game)
