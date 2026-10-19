--[[----------------------------------------------------------------------------
  GoblinGames_GoFish/GoFish.lua

  Go Fish for 2-6 players, and the first card game on the card engine
  (Core/Cards.lua).

  RULES
    - Deal 7 cards each (2-3 players) or 5 each (4-6). The rest is the pond.
    - On your turn, ask one player for a rank you already hold.
        * They have some: they hand over ALL of them, and you go again.
        * They don't: "Go Fish!" Draw from the pond. If you drew the rank you
          asked for, you go again; otherwise the turn passes.
    - Four of a kind is a book: it's laid down at once.
    - Empty hand: draw one from the pond at the start of your turn. Pond
      empty too: you sit out until the end.
    - When all 13 books are made, most books wins (ties share the win).

  HIDDEN INFORMATION
  The host shuffles and deals and keeps every hand. Each player is whispered
  only THEIR hand ("HAND"). Everyone gets the public state ("PUB": how many
  cards each player holds, the pond size, who has which books) and an event
  log ("EV": who asked whom for what). The host checks every ask against the
  real hands.

  Timeouts don't knock you out here: the host asks for you, at random.
  Leaving puts your cards back in the pond and the game carries on.
------------------------------------------------------------------------------]]

local GG = GoblinGames
local Util = GG.Util
local UI = GG.UI
local Cards = GG.Cards

local Game = {
    id = "gofish",
    compactHeader = true,
    hint = "Click a card, click a player, then Ask!",
}

local LOG_LINES = 5
local current

-------------------------------------------------------------------------------
-- Host: rules engine
--
-- Host-only data:   d.hands[name] = {cards}   d.pond = {cards} (the deck)
-- Everyone's data:  d.counts[name], d.stock (pond size), d.books[name] = {ranks},
--                   d.myHand (from the private HAND message), d.log
-------------------------------------------------------------------------------
local function PublicState(session)
    local d = session.data
    local counts, books = {}, {}
    for _, p in ipairs(session.players) do
        counts[#counts + 1] = p .. ":" .. #(d.hands[p] or {})
        books[#books + 1] = p .. ":" .. table.concat(d.hostBooks[p] or {})
    end
    return table.concat(counts, ";"), #d.pond, table.concat(books, ";")
end

local function SendPublic(session)
    session:Broadcast("PUB", PublicState(session))
end

local function SendHand(session, player)
    Cards.SendHand(session, player, Cards.Sort(session.data.hands[player] or {}))
end

local function TotalBooks(d)
    local n = 0
    for _, list in pairs(d.hostBooks) do n = n + #list end
    return n
end

-- Lay down any four-of-a-kinds in a player's hand.
local function MakeBooks(session, player)
    local d = session.data
    local hand = d.hands[player]
    for _, rank in ipairs(Cards.RANKS) do
        if Cards.CountRank(hand, rank) >= 4 then
            Cards.TakeRank(hand, rank)
            d.hostBooks[player] = d.hostBooks[player] or {}
            table.insert(d.hostBooks[player], rank)
            session:Broadcast("EV", "BOOK", player, rank)
        end
    end
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

local function CheckEnd(session)
    local d = session.data
    if session.status ~= "playing" then return true end
    local anyone = false
    for _, p in ipairs(session.players) do
        if CanPlay(session, p) and #d.hands[p] > 0 then anyone = true end
    end
    if TotalBooks(d) >= 13 or (not anyone and #d.pond == 0) then
        local best, winners = -1, {}
        local active = session:ActivePlayers()
        for _, p in ipairs(active) do
            local n = #(d.hostBooks[p] or {})
            if n > best then best, winners = n, { p } elseif n == best then winners[#winners + 1] = p end
        end
        local everyone = #winners == #active and #winners > 1
        session:End({ winners = everyone and {} or winners, draw = everyone,
            reason = ("most books: %d"):format(math.max(best, 0)) })
        return true
    end
    return false
end

-- Start of someone's turn. An empty hand draws from the pond. If nobody has
-- cards to ask, the player just fishes and passes. Returns true if the
-- player can now ask someone.
local function BeginTurn(session, player)
    local d = session.data
    if #d.hands[player] == 0 and #d.pond > 0 then
        table.insert(d.hands[player], table.remove(d.pond))
        session:Broadcast("EV", "DRAW", player)
        MakeBooks(session, player)
        SendHand(session, player)
        SendPublic(session)
    end
    if #d.hands[player] > 0 and #Targets(session, player) > 0 then return true end
    if #d.hands[player] > 0 and #d.pond > 0 then
        table.insert(d.hands[player], table.remove(d.pond))
        session:Broadcast("EV", "FISH", player, "")
        MakeBooks(session, player)
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
    MakeBooks(session, asker)
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

-- A legal random ask (used for timeouts and by the practice dummy).
local function RandomAsk(session, player, smart)
    local d = session.data
    local hand = d.hands[player] or {}
    local targets = Targets(session, player)
    if #hand == 0 or #targets == 0 then NextTurn(session); return end
    local rank = Cards.Rank(hand[math.random(#hand)])
    if smart and math.random() < 0.6 then
        -- The dummy usually asks for the rank it holds the most of.
        local bestN = 0
        for _, c in ipairs(hand) do
            local n = Cards.CountRank(hand, Cards.Rank(c))
            if n > bestN then rank, bestN = Cards.Rank(c), n end
        end
    end
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

local function CardClick(card)
    if not card.card then return end
    local rank = Cards.Rank(card.card)
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
        seat.book = seat:CreateTexture(nil, "ARTWORK")
        seat.book:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        seat.book:SetSize(20, 20)
        seat.book:SetPoint("BOTTOMRIGHT", -34, 12)
        seat.books = UI.Text(seat, "", { fancy = true, size = 15, ink = true })
        seat.books:SetPoint("LEFT", seat.book, "RIGHT", 4, 0)
        seat:SetScript("OnClick", function(self) GG:Safe("Go Fish", SeatClick, self) end)
        seat:SetScript("OnEnter", function(self)
            if not self.bookList then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(Util.ShortName(self.player))
            GameTooltip:AddLine(self.bookList, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        seat:SetScript("OnLeave", function() GameTooltip:Hide() end)
        seats[i] = seat
    end

    -- Middle: the pond, the log, your books, the Ask button.
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

    view.myBooks = UI.Text(view.middle, "", { ink = true, font = "GameFontHighlightSmall" })
    view.myBooks:SetPoint("TOPRIGHT", -16, -12)
    view.myBooks:SetWidth(240)
    view.myBooks:SetJustifyH("RIGHT")

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
                local bk = d.books[p] or {}
                seat.books:SetText(#bk)
                local names = {}
                for _, r in ipairs(bk) do names[#names + 1] = Cards.RankPlural(r) end
                seat.bookList = #names > 0 and ("Books: " .. table.concat(names, ", ")) or "No books yet"
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
    local mine = d.books[me] or {}
    local names = {}
    for _, r in ipairs(mine) do names[#names + 1] = Cards.RankPlural(r) end
    view.myBooks:SetText("|cff5a3412Your books: " .. #mine .. "|r\n" .. table.concat(names, ", "))

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
    for k, card in ipairs(hand) do
        local c = handCards[k]
        if not c then
            c = UI.PlayingCard(view.hand, width)
            c.onClick = CardClick
            handCards[k] = c
        end
        c:SetFrameLevel(view.hand:GetFrameLevel() + k)
        c:SetCard(card)
        local sel = view.selRank and Cards.Rank(card) == view.selRank
        c:SetSelected(sel)
        c:ClearAllPoints()
        c:SetPoint("BOTTOMLEFT", startX + (k - 1) * step, sel and 30 or 14)
        c:SetClickable(s.status == "playing")
        c:Show()
    end
    for k = n + 1, #handCards do handCards[k]:Hide() end

    if s.status == "playing" and myTurn then
        UI:SetGameStatus(UI.Gold(n == 0 and "Your turn! (no cards: waiting for the pond)" or "Your turn! Card, player, Ask."))
    else
        UI:SetGameStatus(nil)
    end
end

-------------------------------------------------------------------------------
-- Module callbacks
-------------------------------------------------------------------------------
local function ParsePublic(d, counts, stock, books)
    d.counts = {}
    for name, n in (counts or ""):gmatch("([^:;]+):(%d+)") do d.counts[name] = tonumber(n) end
    d.stock = tonumber(stock) or 0
    d.books = {}
    for name, ranks in (books or ""):gmatch("([^:;]+):([^;]*)") do
        local list = {}
        for r in ranks:gmatch(".") do list[#list + 1] = r end
        d.books[name] = list
    end
end

function Game.OnSessionStart(session)
    current = session
    local d = session.data
    d.myHand, d.counts, d.books, d.stock, d.log = {}, {}, {}, 0, {}
    view.selRank, view.selTarget = nil, nil
    if not view.middle then Build() end
    view.middle:Show(); view.hand:Show()
    Refresh()

    if session:IsHost() then
        -- Shuffle and deal. Only the host ever sees the deck.
        d.pond = Cards.Shuffle(Cards.NewDeck())
        d.hands, d.hostBooks = {}, {}
        local per = (#session.players <= 3) and 7 or 5
        for _, p in ipairs(session.players) do d.hands[p] = Cards.Draw(d.pond, per) end
        for _, p in ipairs(session.players) do MakeBooks(session, p) end
        for _, p in ipairs(session.players) do SendHand(session, p) end
        SendPublic(session)
        GG.Turns:Start(session, Util.Shuffle(Util.Copy(session.players)))
    end
end

function Game.OnAction(session, sender, op, args)
    if op ~= "ASK" then return end
    local target, rank = args[1], args[2]
    if not target or not rank or not rank:match("^[A2-9TJQK]$") then return end
    Ask(session, sender, target, rank)
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
        elseif kind == "BOOK" then
            LogLine(d, ("|cff5a3412%s made a book of %s!|r"):format(Name(args[2]), Cards.RankPlural(args[3])))
            if Util.IsMe(args[2]) then GG.Theme:PlaySound("victory") end
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

-- Out of time: the host asks for you, at random.
function Game.OnTurnTimeout(session, name)
    RandomAsk(session, name, false)
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
    RandomAsk(session, bot, true)
end

Game._test = { Ask = Ask, DoAsk = DoAsk, CardClick = CardClick, SeatClick = SeatClick, view = view }

GG:RegisterGame(Game)
