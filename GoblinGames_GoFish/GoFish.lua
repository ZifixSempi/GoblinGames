--[[----------------------------------------------------------------------------
  GoblinGames_GoFish/GoFish.lua

  Go Fish for 2-6 players, and the first card game on the card engine
  (Core/Cards.lua).

  RULES (the "pairs" version most people grew up with)
    - Deal 7 cards each (2-3 players) or 5 each (4-6). The rest is the pond.
    - Two cards of the same rank make a PAIR. Click a glowing pair in your
      hand to lay it down: it leaves your hand and scores you 1 point. You can
      do this any time, even when it isn't your turn.
    - On your turn, ask one player for a rank you hold.
        * They have some: they hand over ALL of them, and you go again.
        * They don't: "Go Fish!" Draw from the pond. If you drew the rank you
          asked for, you go again; otherwise the turn passes.
    - Empty hand: draw one from the pond at the start of your turn.
    - The game ends once the pond is empty and nobody can make another pair
      by asking. Any pairs still in hands are laid down for their owners, and
      the most pairs wins (26 in the deck; ties share the win).

  HIDDEN INFORMATION
  The host shuffles and deals and keeps every hand. Each player is whispered
  only THEIR hand ("HAND"). Everyone gets the public state ("PUB": how many
  cards each player holds, the pond size, who has laid down which pairs) and
  an event log ("EV": who asked whom for what). The host checks every ask and
  every pair against the real hands.

  Timeouts don't knock you out here: the host lays down your pairs and asks
  for you, at random. Leaving puts your cards back in the pond and the game
  carries on.
------------------------------------------------------------------------------]]

local GG = GoblinGames
local Util = GG.Util
local UI = GG.UI
local Cards = GG.Cards

local Game = {
    id = "gofish",
    compactHeader = true,
    hint = "Click a glowing pair to score it. Then pick a card and Ask!",
}

local LOG_LINES = 5
local current

-------------------------------------------------------------------------------
-- Host: rules engine
--
-- Host-only data:   d.hands[name] = {cards}   d.pond = {cards} (the deck)
--                   d.hostPairs[name] = {ranks}
-- Everyone's data:  d.counts[name], d.stock (pond size), d.pairs[name] = {ranks},
--                   d.myHand (from the private HAND message), d.log
-------------------------------------------------------------------------------
local function PublicState(session)
    local d = session.data
    local counts, pairs_ = {}, {}
    for _, p in ipairs(session.players) do
        counts[#counts + 1] = p .. ":" .. #(d.hands[p] or {})
        pairs_[#pairs_ + 1] = p .. ":" .. table.concat(d.hostPairs[p] or {})
    end
    return table.concat(counts, ";"), #d.pond, table.concat(pairs_, ";")
end

local function SendPublic(session)
    session:Broadcast("PUB", PublicState(session))
end

local function SendHand(session, player)
    Cards.SendHand(session, player, Cards.Sort(session.data.hands[player] or {}))
end

-- Take one pair of `rank` out of a player's hand and score it.
local function TakePair(session, player, rank, auto)
    local d = session.data
    local hand = d.hands[player]
    if not hand or Cards.CountRank(hand, rank) < 2 then return false end
    local removed = 0
    for i = #hand, 1, -1 do
        if removed < 2 and Cards.Rank(hand[i]) == rank then
            table.remove(hand, i)
            removed = removed + 1
        end
    end
    d.hostPairs[player] = d.hostPairs[player] or {}
    table.insert(d.hostPairs[player], rank)
    session:Broadcast("EV", "PAIR", player, rank, auto and "1" or "")
    return true
end

-- Lay down every pair a player holds (timeouts, the dummy, end of game).
local function TakeAllPairs(session, player, auto)
    local d = session.data
    local any = false
    for _, rank in ipairs(Cards.RANKS) do
        while Cards.CountRank(d.hands[player] or {}, rank) >= 2 do
            TakePair(session, player, rank, auto)
            any = true
        end
    end
    return any
end

local function CanPlay(session, player)
    local d = session.data
    return session:IsActive(player) and (#(d.hands[player] or {}) > 0 or #d.pond > 0)
end

-- Other players who could be asked (still in, holding cards).
local function Targets(session, player)
    local list = {}
    for _, p in ipairs(session.players) do
        if p ~= player and session:IsActive(p) and #(session.data.hands[p] or {}) > 0 then list[#list + 1] = p end
    end
    return list
end

-- Is there nothing left to win by asking? (Pond empty, and every rank still
-- in play is held by just one player, so those cards are already pairs.)
local function NothingLeft(session)
    local d = session.data
    if #d.pond > 0 then return false end
    local holder = {}
    for _, p in ipairs(session.players) do
        for _, c in ipairs(d.hands[p] or {}) do
            local r = Cards.Rank(c)
            if holder[r] and holder[r] ~= p then return false end
            holder[r] = p
        end
    end
    return true
end

local function CheckEnd(session)
    local d = session.data
    if session.status ~= "playing" then return true end
    if not NothingLeft(session) then return false end

    -- Pairs nobody clicked still count for their owners.
    for _, p in ipairs(session:ActivePlayers()) do TakeAllPairs(session, p, true) end
    SendPublic(session)

    local best, winners = -1, {}
    local active = session:ActivePlayers()
    for _, p in ipairs(active) do
        local n = #(d.hostPairs[p] or {})
        if n > best then best, winners = n, { p } elseif n == best then winners[#winners + 1] = p end
    end
    local everyone = #winners == #active and #winners > 1
    session:End({ winners = everyone and {} or winners, draw = everyone,
        reason = ("most pairs: %d"):format(math.max(best, 0)) })
    return true
end

-- Start of someone's turn. An empty hand draws from the pond. If nobody has
-- cards to ask, the player just fishes and passes. Returns true if the
-- player can now ask someone.
local function BeginTurn(session, player)
    local d = session.data
    if #d.hands[player] == 0 and #d.pond > 0 then
        table.insert(d.hands[player], table.remove(d.pond))
        session:Broadcast("EV", "DRAW", player)
        SendHand(session, player)
        SendPublic(session)
    end
    if #d.hands[player] > 0 and #Targets(session, player) > 0 then return true end
    if #d.hands[player] > 0 and #d.pond > 0 then
        table.insert(d.hands[player], table.remove(d.pond))
        session:Broadcast("EV", "FISH", player, "")
        SendHand(session, player)
        SendPublic(session)
    end
    return false
end

-- Pass the turn to the next player who can play.
local function NextTurn(session)
    for _ = 1, #session.players * 2 do
        if CheckEnd(session) then return end
        GG.Turns:Advance(session)
        local cur = GG.Turns:Current(session)
        if CanPlay(session, cur) and BeginTurn(session, cur) then return end
    end
    CheckEnd(session)
end

-- After a player's hand shrinks on their own turn (laid a pair), make sure
-- they can still ask; if not, top them up or move on.
local function KeepTurnGoing(session, player)
    if session.status ~= "playing" or GG.Turns:Current(session) ~= player then return end
    if not BeginTurn(session, player) then NextTurn(session) end
end

-- A player clicks a pair. Allowed any time during the game.
local function LayPair(session, player, rank)
    if session.status ~= "playing" or not session:IsActive(player) then return false end
    if not TakePair(session, player, rank) then return false end
    SendHand(session, player)
    SendPublic(session)
    if CheckEnd(session) then return true end
    KeepTurnGoing(session, player)
    return true
end

-- The heart of the game: `asker` asks `target` for `rank`.
local function Ask(session, asker, target, rank)
    local d = session.data
    if session.status ~= "playing" or GG.Turns:Current(session) ~= asker then return false end
    if target == asker or not session:IsActive(target) then return false end
    if #(d.hands[target] or {}) == 0 then return false end
    if Cards.CountRank(d.hands[asker] or {}, rank) == 0 then return false end

    local taken = Cards.TakeRank(d.hands[target], rank)
    session:Broadcast("EV", "ASK", asker, target, rank, #taken)
    local again
    if #taken > 0 then
        for _, c in ipairs(taken) do table.insert(d.hands[asker], c) end
        again = true
    else
        local card = table.remove(d.pond)
        if card then
            table.insert(d.hands[asker], card)
            again = Cards.Rank(card) == rank
            session:Broadcast("EV", "FISH", asker, again and rank or "")
        else
            session:Broadcast("EV", "NOFISH", asker)
        end
    end
    SendHand(session, asker)
    if #taken > 0 then SendHand(session, target) end
    SendPublic(session)

    if CheckEnd(session) then return true end
    if again and CanPlay(session, asker) and BeginTurn(session, asker) then
        GG.Turns:ResetTimer(session) -- your turn again, with a fresh clock
    else
        NextTurn(session)
    end
    return true
end

-- Lay down pairs, then make a legal random ask (timeouts and the dummy).
local function AutoTurn(session, player)
    local d = session.data
    if TakeAllPairs(session, player, false) then
        SendHand(session, player)
        SendPublic(session)
        if CheckEnd(session) then return end
        KeepTurnGoing(session, player)
        if session.status ~= "playing" or GG.Turns:Current(session) ~= player then return end
    end
    local hand = d.hands[player] or {}
    local targets = Targets(session, player)
    if #hand == 0 or #targets == 0 then NextTurn(session); return end
    local rank = Cards.Rank(hand[math.random(#hand)])
    Ask(session, player, targets[math.random(#targets)], rank)
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------
local view = {}
local seats, handCards = {}, {}
local Refresh

local function Selected()
    local s = current
    -- With only one opponent, they're picked for you.
    if s and not view.selTarget then
        local only
        for _, p in ipairs(s.players) do
            if not Util.IsMe(p) and s:IsActive(p) and (s.data.counts[p] or 0) > 0 then
                if only then only = false; break end
                only = p
            end
        end
        if only then return view.selRank, only end
    end
    return view.selRank, view.selTarget
end

local function SeatClick(seat)
    local s = current
    if not seat.player or not s or not s:IsActive(seat.player) or (s.data.counts[seat.player] or 0) == 0 then return end
    view.selTarget = seat.player
    Refresh()
end

-- Clicking a card: if it's part of a pair, lay the pair down and score it.
-- Otherwise pick its rank for your next ask.
local function CardClick(card)
    local s = current
    if not card.card or not s or s.status ~= "playing" then return end
    local rank = Cards.Rank(card.card)
    if Cards.CountRank(s.data.myHand, rank) >= 2 then
        s:SendAction("PAIR", rank)
        if view.selRank == rank then view.selRank = nil end
        return
    end
    view.selRank = (view.selRank == rank) and nil or rank
    Refresh()
end

local function DoAsk()
    local s = current
    if not s or not GG.Turns:IsMyTurn(s) then return end
    local rank, target = Selected()
    if not rank or not target then return end
    s:SendAction("ASK", target, rank)
    view.selRank = nil
end

local function Build()
    local area = UI:GetGameArea()

    -- Opponents along the top.
    for i = 1, 5 do
        local seat = CreateFrame("Button", nil, area)
        seat:SetSize(134, 78)
        seat:SetPoint("TOPLEFT", (i - 1) * 140, 0)
        seat.parts = UI.NineSlice(seat, UI.MEDIA .. "Parchment", 128, 24, 14)
        seat.glow = seat:CreateTexture(nil, "OVERLAY")
        seat.glow:SetTexture(UI.MEDIA .. "ButtonGlow")
        seat.glow:SetPoint("TOPLEFT", -10, 8)
        seat.glow:SetPoint("BOTTOMRIGHT", 10, -8)
        seat.glow:SetBlendMode("ADD")
        seat.glow:SetVertexColor(1, 0.75, 0.2)
        UI.AddPulse(seat.glow, 0.3, 0.6)
        seat.target = seat:CreateTexture(nil, "OVERLAY", nil, 1)
        seat.target:SetTexture(UI.MEDIA .. "Ring")
        seat.target:SetSize(26, 26)
        seat.target:SetPoint("TOPRIGHT", -4, -4)
        seat.target:SetVertexColor(0.3, 1, 0.3)
        seat.crest = seat:CreateTexture(nil, "ARTWORK")
        seat.crest:SetSize(20, 20)
        seat.crest:SetPoint("TOPLEFT", 8, -8)
        seat.name = UI.Text(seat, "", { ink = true, font = "GameFontNormalSmall" })
        seat.name:SetPoint("LEFT", seat.crest, "RIGHT", 4, 0)
        seat.name:SetWidth(84)
        seat.backs = {}
        for b = 1, 3 do
            local t = seat:CreateTexture(nil, "ARTWORK", nil, b)
            t:SetTexture(UI.MEDIA .. "CardBack")
            t:SetTexCoord(0, 1, 0, 183 / 256)
            t:SetSize(24, 34)
            t:SetPoint("BOTTOMLEFT", 10 + (b - 1) * 9, 8)
            seat.backs[b] = t
        end
        seat.count = UI.Text(seat, "", { fancy = true, size = 15, ink = true })
        seat.count:SetPoint("LEFT", seat.backs[3], "RIGHT", 4, 0)
        -- Score: two little face-up cards and the number of pairs.
        seat.pairIcon = {}
        for b = 1, 2 do
            local t = seat:CreateTexture(nil, "ARTWORK", nil, b)
            t:SetTexture(UI.MEDIA .. "CardFace")
            t:SetTexCoord(0, 1, 0, 183 / 256)
            t:SetSize(16, 23)
            t:SetPoint("BOTTOMRIGHT", -40 + (b - 1) * 6, 10 + (b - 1) * 2)
            seat.pairIcon[b] = t
        end
        seat.score = UI.Text(seat, "", { fancy = true, size = 18, ink = true })
        seat.score:SetPoint("BOTTOMLEFT", seat, "BOTTOMRIGHT", -26, 10)
        seat:SetScript("OnClick", function(self) GG:Safe("Go Fish", SeatClick, self) end)
        seat:SetScript("OnEnter", function(self)
            if not self.pairList then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(Util.ShortName(self.player))
            GameTooltip:AddLine(self.pairList, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        seat:SetScript("OnLeave", function() GameTooltip:Hide() end)
        seats[i] = seat
    end

    -- Middle: the pond, the log, your score, the Ask button.
    view.middle = UI.Card(area)
    view.middle:SetPoint("TOPLEFT", 0, -86)
    view.middle:SetPoint("RIGHT", area, "RIGHT", 0, 0)
    view.middle:SetHeight(116)

    view.pond = {}
    for b = 1, 3 do
        local t = view.middle:CreateTexture(nil, "ARTWORK", nil, b)
        t:SetTexture(UI.MEDIA .. "CardBack")
        t:SetTexCoord(0, 1, 0, 183 / 256)
        t:SetSize(48, 69)
        t:SetPoint("TOPLEFT", 16 + (b - 1) * 4, -12 - (b - 1) * 3)
        view.pond[b] = t
    end
    view.pondText = UI.Text(view.middle, "", { fancy = true, size = 14, ink = true, justify = "CENTER" })
    view.pondText:SetPoint("TOP", view.pond[1], "BOTTOM", 4, -8)

    view.log = UI.Text(view.middle, "", { ink = true, font = "GameFontHighlightSmall" })
    view.log:SetPoint("TOPLEFT", 92, -12)
    view.log:SetWidth(330)
    view.log:SetJustifyV("TOP")
    view.log:SetSpacing(2)

    view.myScore = UI.Text(view.middle, "", { fancy = true, size = 20, ink = true, justify = "RIGHT" })
    view.myScore:SetPoint("TOPRIGHT", -16, -12)
    view.myPairs = UI.Text(view.middle, "", { ink = true, font = "GameFontHighlightSmall", justify = "RIGHT" })
    view.myPairs:SetPoint("TOPRIGHT", view.myScore, "BOTTOMRIGHT", 0, -2)
    view.myPairs:SetWidth(240)

    -- "+1!" that pops up when you score a pair.
    view.plus = UI.Text(view.middle, "+1 Pair!", { fancy = true, size = 26, justify = "CENTER" })
    view.plus:SetTextColor(0.35, 1, 0.35)
    view.plus:SetPoint("RIGHT", view.myScore, "LEFT", -12, -4)
    view.plus:Hide()
    UI.AddPopIn(view.plus)

    view.ask = UI.Button(view.middle, "Ask!", 240, 38, function() GG:Safe("Go Fish", DoAsk) end, "primary")
    view.ask:SetPoint("BOTTOMRIGHT", -14, 12)

    -- Your hand along the bottom.
    view.hand = CreateFrame("Frame", nil, area)
    view.hand:SetPoint("TOPLEFT", 0, -212)
    view.hand:SetPoint("BOTTOMRIGHT", 0, 0)
end

local function LogLine(d, text)
    d.log[#d.log + 1] = text
    while #d.log > LOG_LINES do table.remove(d.log, 1) end
end

local function Name(p) return Util.IsMe(p) and "You" or Util.ShortName(p) end

function Refresh()
    local s = current
    if not s or not view.middle then return end
    local d = s.data
    local me = s:Me()
    local myTurn = GG.Turns:IsMyTurn(s)
    local cur = GG.Turns:Current(s)

    -- Forget selections that no longer make sense.
    if view.selRank and Cards.CountRank(d.myHand, view.selRank) == 0 then view.selRank = nil end
    if view.selTarget and (not s:IsActive(view.selTarget) or (d.counts[view.selTarget] or 0) == 0) then view.selTarget = nil end

    local rank, target = Selected()

    -- Opponents.
    local i = 0
    for _, p in ipairs(s.players) do
        if not Util.IsMe(p) then
            i = i + 1
            local seat = seats[i]
            if seat then
                seat.player = p
                seat:Show()
                GG.Theme:SetCrest(seat.crest, s:GetFaction(p))
                seat.name:SetText(Util.ShortName(p) .. (s.left[p] and " (left)" or ""))
                local n = d.counts[p] or 0
                for b, t in ipairs(seat.backs) do t:SetShown(n >= b) end
                seat.count:SetText(n)
                local pr = d.pairs[p] or {}
                seat.score:SetText(#pr)
                local names = {}
                for _, r in ipairs(pr) do names[#names + 1] = Cards.RankPlural(r) end
                seat.pairList = #names > 0 and ("Pairs: " .. table.concat(names, ", ")) or "No pairs yet"
                local active = s.status == "playing" and p == cur
                seat.glow:SetShown(active)
                if active then seat.glow.pulse:Play() end
                seat.target:SetShown(target == p and s.status == "playing")
            end
        end
    end
    for j = i + 1, #seats do seats[j]:Hide(); seats[j].player = nil end

    -- Pond and log.
    for b, t in ipairs(view.pond) do t:SetShown(d.stock >= b) end
    view.pondText:SetText(d.stock > 0 and ("Pond: " .. d.stock) or "Pond empty")
    view.log:SetText(#d.log > 0 and table.concat(d.log, "\n") or UI.InkGrey("Cards are dealt. Good luck!"))
    local mine = d.pairs[me] or {}
    local names = {}
    for _, r in ipairs(mine) do names[#names + 1] = Cards.RankLabel(r) end
    view.myScore:SetText("Your pairs: " .. #mine)
    view.myPairs:SetText(table.concat(names, "  "))

    -- Ask button.
    if s.status ~= "playing" then
        view.ask:Hide()
    else
        view.ask:Show()
        view.ask:SetEnabled(myTurn and rank ~= nil and target ~= nil)
        if not myTurn then
            view.ask:SetText(cur and ("Waiting on " .. Util.ShortName(cur)) or "Waiting...")
        elseif not rank then
            view.ask:SetText("Pick a card first")
        elseif not target then
            view.ask:SetText("Now pick a player")
        else
            view.ask:SetText("Ask " .. Util.ShortName(target) .. " for " .. Cards.RankPlural(rank) .. "!")
        end
    end

    -- Hand.
    local hand = d.myHand
    local n = #hand
    local width = 62
    local avail = view.hand:GetWidth()
    if not avail or avail < 100 then avail = 704 end
    local step = (n > 1) and math.min(width + 8, (avail - width) / (n - 1)) or 0
    local startX = (avail - (width + step * math.max(0, n - 1))) / 2
    local havePair = false
    for k, card in ipairs(hand) do
        local c = handCards[k]
        if not c then
            c = UI.PlayingCard(view.hand, width)
            c.onClick = CardClick
            -- A little green "PAIR!" tag over cards you can score.
            c.tag = UI.Text(c, "PAIR!", { fancy = true, size = 14, justify = "CENTER" })
            c.tag:SetTextColor(0.4, 1, 0.4)
            c.tag:SetPoint("BOTTOM", c, "TOP", 0, 2)
            handCards[k] = c
        end
        c:SetFrameLevel(view.hand:GetFrameLevel() + k)
        c:SetCard(card)
        -- Pairs glow green (click to score); the rank you'll ask for glows gold.
        local isPair = Cards.CountRank(hand, Cards.Rank(card)) >= 2
        local sel = isPair or (view.selRank and Cards.Rank(card) == view.selRank)
        if isPair then
            havePair = true
            c.glow:SetVertexColor(0.3, 1, 0.3)
        else
            c.glow:SetVertexColor(1, 0.85, 0.3)
        end
        c:SetSelected(sel and s.status == "playing")
        c.tag:SetShown(isPair and s.status == "playing")
        c:ClearAllPoints()
        c:SetPoint("BOTTOMLEFT", startX + (k - 1) * step, (sel and s.status == "playing") and 30 or 14)
        c:SetClickable(s.status == "playing")
        c:Show()
    end
    for k = n + 1, #handCards do handCards[k]:Hide() end

    if s.status == "playing" and havePair then
        UI:SetGameStatus(UI.Green("You have a pair! Click the green cards to score it."))
    elseif s.status == "playing" and myTurn then
        UI:SetGameStatus(UI.Gold(n == 0 and "Your turn! (no cards: waiting for the pond)" or "Your turn! Card, player, Ask."))
    else
        UI:SetGameStatus(nil)
    end
end

-------------------------------------------------------------------------------
-- Module callbacks
-------------------------------------------------------------------------------
local function ParsePublic(d, counts, stock, pairList)
    d.counts = {}
    for name, n in (counts or ""):gmatch("([^:;]+):(%d+)") do d.counts[name] = tonumber(n) end
    d.stock = tonumber(stock) or 0
    d.pairs = {}
    for name, ranks in (pairList or ""):gmatch("([^:;]+):([^;]*)") do
        local list = {}
        for r in ranks:gmatch(".") do list[#list + 1] = r end
        d.pairs[name] = list
    end
end

function Game.OnSessionStart(session)
    current = session
    local d = session.data
    d.myHand, d.counts, d.pairs, d.stock, d.log = {}, {}, {}, 0, {}
    view.selRank, view.selTarget = nil, nil
    if not view.middle then Build() end
    view.middle:Show(); view.hand:Show()
    Refresh()

    if session:IsHost() then
        -- Shuffle and deal. Only the host ever sees the deck.
        d.pond = Cards.Shuffle(Cards.NewDeck())
        d.hands, d.hostPairs = {}, {}
        local per = (#session.players <= 3) and 7 or 5
        for _, p in ipairs(session.players) do d.hands[p] = Cards.Draw(d.pond, per) end
        for _, p in ipairs(session.players) do SendHand(session, p) end
        SendPublic(session)
        GG.Turns:Start(session, Util.Shuffle(Util.Copy(session.players)))
    end
end

function Game.OnAction(session, sender, op, args)
    if op == "ASK" then
        local target, rank = args[1], args[2]
        if not target or not rank or not rank:match("^[A2-9TJQK]$") then return end
        Ask(session, sender, target, rank)
    elseif op == "PAIR" then
        local rank = args[1]
        if not rank or not rank:match("^[A2-9TJQK]$") then return end
        LayPair(session, sender, rank)
    end
end

function Game.OnState(session, op, args, isPrivate)
    local d = session.data
    if op == "HAND" then
        d.myHand = Cards.Sort(Cards.Decode(args[1]))
    elseif op == "PUB" then
        ParsePublic(d, args[1], args[2], args[3])
    elseif op == "EV" then
        local kind = args[1]
        if kind == "ASK" then
            local asker, target, rank, n = args[2], args[3], args[4], tonumber(args[5]) or 0
            if n > 0 then
                LogLine(d, ("%s asked %s for %s: |cff1f7a12got %d!|r"):format(Name(asker), Name(target), Cards.RankPlural(rank), n))
                if Util.IsMe(target) then GG.Theme:PlaySound("defeat") end
            else
                LogLine(d, ("%s asked %s for %s: |cffa51d12Go Fish!|r"):format(Name(asker), Name(target), Cards.RankPlural(rank)))
            end
        elseif kind == "FISH" then
            local who, lucky = args[2], args[3]
            if lucky and lucky ~= "" then
                LogLine(d, ("%s fished up the %s! Again!"):format(Name(who), Cards.RankName(lucky)))
            else
                LogLine(d, ("%s drew from the pond."):format(Name(who)))
            end
        elseif kind == "NOFISH" then
            LogLine(d, ("%s: the pond is empty!"):format(Name(args[2])))
        elseif kind == "PAIR" then
            local who, rank, auto = args[2], args[3], args[4] == "1"
            if not auto then
                LogLine(d, ("|cff1f7a12%s laid down a pair of %s!|r"):format(Name(who), Cards.RankPlural(rank)))
            end
            if Util.IsMe(who) and session == current and view.plus then
                GG.Theme:PlaySound("click")
                view.plus:Show()
                view.plus.popIn:Play()
                C_Timer.After(1.2, function() view.plus:Hide() end)
            end
        elseif kind == "DRAW" then
            LogLine(d, ("%s had no cards and drew one."):format(Name(args[2])))
        elseif kind == "OUT" then
            LogLine(d, ("%s left; their cards went back in the pond."):format(Name(args[2])))
        end
    end
    if session == current then Refresh() end
end

function Game.OnSyncRequest(session, player)
    SendHand(session, player)
    session:SendTo(player, "PUB", PublicState(session))
end

-- Out of time: the host lays down your pairs and asks for you, at random.
function Game.OnTurnTimeout(session, name)
    AutoTurn(session, name)
end

-- Someone leaves: their cards go back in the pond and the rest play on.
-- Returning false hands the decision back to the core (the host leaving, or
-- only one player left, ends the game).
function Game.OnPlayerLeft(session, name)
    if Util.IsMe(name) or #session:ActivePlayers() <= 1 then return false end
    local d = session.data
    for _, c in ipairs(d.hands[name] or {}) do table.insert(d.pond, c) end
    d.hands[name] = {}
    Cards.Shuffle(d.pond)
    session:Broadcast("EV", "OUT", name)
    SendPublic(session)
    if not CheckEnd(session) and GG.Turns:Current(session) == name then
        NextTurn(session)
    end
    return true
end

function Game.OnSessionEnd(session)
    if session == current then Refresh() end
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
    if session == current then Refresh() end
end)

function Game.BotAction(session, bot)
    if session.status ~= "playing" or GG.Turns:Current(session) ~= bot then return end
    AutoTurn(session, bot)
end

Game._test = { Ask = Ask, LayPair = LayPair, DoAsk = DoAsk, CardClick = CardClick, SeatClick = SeatClick, view = view }

GG:RegisterGame(Game)
