--[[----------------------------------------------------------------------------
  GoblinGames_Trivia/Trivia.lua

  WoW trivia for any number of players: party, raid, or the whole guild.

  HOW IT PLAYS
    - The host is the quizmaster. Each question has four answers; everyone
      clicks one before the time runs out.
    - Right answers score by speed: the fastest gets 3 points, the second
      2, and every other right answer 1. Wrong or no answer: 0.
    - After each question the right answer is shown, with who got it.
    - Most points after the last question wins.

  OPTIONS (lobby)
    - questions: 5, 10 or 20      - seconds per question: 10, 15 or 20
    - topic: everything, lore & heroes, places & dungeons, game & fun
    - question set: built-in + yours, only yours, only built-in
    - host plays: the quizmaster's client knows the answers, so by default
      the host just runs the quiz. Turn it on for small groups of friends.

  It's an "open" game like Guild Bingo: the host can announce it to the
  guild, and latecomers can join between questions.

  THE QUESTION BANK
  Built-in questions are in Questions.lua. Your own questions are kept in
  your SavedVariables (GoblinGamesDB.global.triviaQuestions) and edited in
  game: /gg questions, or the "Edit questions" button in the Trivia lobby.
  Only the host's questions are used, and only the host's client knows the
  right answers until each reveal.
------------------------------------------------------------------------------]]

local GG = GoblinGames
local _, ns = ...
local Util = GG.Util
local UI = GG.UI

local Game = {
    id = "trivia",
    compactHeader = true,
    lateJoin = true,
    hint = "Pick the right answer, fast! Quicker right answers score more.",
    options = {
        { key = "count", label = "Questions", default = 10, values = {
            { value = 5, text = "5 questions" }, { value = 10, text = "10 questions" }, { value = 20, text = "20 questions" } } },
        { key = "seconds", label = "Time per question", default = 15, values = {
            { value = 10, text = "10 seconds" }, { value = 15, text = "15 seconds" }, { value = 20, text = "20 seconds" } } },
        { key = "topic", label = "Topic", default = "all", values = {
            { value = "all", text = "Everything" }, { value = "lore", text = "Lore & heroes" },
            { value = "places", text = "Places & dungeons" }, { value = "game", text = "Game & fun" } } },
        { key = "set", label = "Question set", default = 0, values = {
            { value = 0, text = "Built-in + yours" }, { value = 1, text = "Only yours" }, { value = 2, text = "Only built-in" } } },
        { key = "hostplays", label = "Host answers too", default = 0, values = {
            { value = 0, text = "No, host is quizmaster" }, { value = 1, text = "Yes (friends only!)" } } },
    },
}

local REVEAL_PAUSE = 6
local POINTS = { 3, 2 } -- 1st and 2nd right answers; everyone else right gets 1
local LETTERS = { "A", "B", "C", "D" }
local TOPIC_NAME = { lore = "Lore & heroes", places = "Places & dungeons", game = "Game & fun", custom = "Guild question" }

local current

local function HostPlays(session)
    return session.isLocal or tonumber(session.options and session.options.hostplays) == 1
end

local function IsPlaying(session, name)
    return name ~= session.host or HostPlays(session)
end
Game.IsPlaying = IsPlaying

-------------------------------------------------------------------------------
-- The question bank
-------------------------------------------------------------------------------
local function CustomQuestions()
    GG.db.global.triviaQuestions = GG.db.global.triviaQuestions or {}
    return GG.db.global.triviaQuestions
end

--- Questions for a game, already filtered by topic and set, shuffled.
local function PickQuestions(options)
    local topic = options.topic or "all"
    local set = tonumber(options.set) or 0
    local pool = {}
    if set ~= 1 then
        for _, q in ipairs(ns.QUESTIONS) do
            if topic == "all" or q.c == topic then pool[#pool + 1] = q end
        end
    end
    if set ~= 2 then
        for _, q in ipairs(CustomQuestions()) do
            pool[#pool + 1] = { c = "custom", q = q.q, a = q.a }
        end
    end
    if #pool == 0 then
        -- "Only yours" with no questions of your own yet: use the built-in ones.
        for _, q in ipairs(ns.QUESTIONS) do pool[#pool + 1] = q end
    end
    Util.Shuffle(pool)
    local count = math.min(tonumber(options.count) or 10, #pool)
    local list = {}
    for i = 1, count do list[i] = pool[i] end
    return list
end

-------------------------------------------------------------------------------
-- Host: running the quiz
--
-- Host-only: d.questions (with answers), d.correct (index for the current
--            question after shuffling), d.answers[name] = { choice, order }
-- Everyone:  d.n, d.total, d.phase "question" | "reveal", d.q = { text, cat,
--            answers = {4} }, d.endsAt, d.scores[name], d.myChoice,
--            d.answered[name] = true, d.reveal = { correct, results }
-------------------------------------------------------------------------------
local function ScoreString(session)
    local d = session.data
    local list = {}
    for _, p in ipairs(session.players) do
        if IsPlaying(session, p) then list[#list + 1] = p .. ":" .. (d.hostScores[p] or 0) end
    end
    return table.concat(list, ";")
end

local function Players(session)
    local list = {}
    for _, p in ipairs(session.players) do
        if session:IsActive(p) and IsPlaying(session, p) then list[#list + 1] = p end
    end
    return list
end

local Ask, Reveal

-- Practice: the Training Dummy answers after a few seconds, right 60% of the time.
local function DummyAnswers(session, answer)
    local d = session.data
    local n = d.n
    for _, p in ipairs(session.players) do
        if Util.IsBot(p) then
            C_Timer.After(2 + math.random() * 6, function()
                if session.status == "playing" and d.n == n and d.hostPhase == "question" then
                    local choice = (math.random() < 0.6) and d.correct or ((d.correct % 4) + 1)
                    answer(session, p, n, choice)
                end
            end)
        end
    end
end

local Answer

local function Finish(session)
    local d = session.data
    local best, winners = 0, {}
    for _, p in ipairs(Players(session)) do
        local sc = d.hostScores[p] or 0
        if sc > best then best, winners = sc, { p } elseif sc == best and sc > 0 then winners[#winners + 1] = p end
    end
    local everyone = #winners > 1 and #winners == #Players(session)
    session:End({ winners = everyone and {} or winners, draw = everyone,
        reason = best > 0 and ("top score: %d"):format(best) or "nobody scored" })
end

function Ask(session)
    local d = session.data
    if session.status ~= "playing" then return end
    if d.n >= #d.questions then Finish(session); return end
    d.n = d.n + 1
    local src = d.questions[d.n]
    -- Shuffle the answers; remember where the right one went.
    local order = Util.Shuffle({ 1, 2, 3, 4 })
    local shown = {}
    for i, from in ipairs(order) do
        shown[i] = src.a[from]
        if from == 1 then d.correct = i end
    end
    d.answers, d.answerCount = {}, 0
    d.askedAt = GetTime()
    d.qText, d.qCat, d.qShown = src.q, src.c or "custom", shown
    d.hostPhase = "question"
    session:Broadcast("Q", d.n, #d.questions, d.qCat, d.seconds, src.q, shown[1], shown[2], shown[3], shown[4])
    if session.isLocal then DummyAnswers(session, Answer) end

    d.runId = (d.runId or 0) + 1
    local id = d.runId
    C_Timer.After(d.seconds, function()
        if session.status == "playing" and d.runId == id and d.hostPhase == "question" then Reveal(session) end
    end)
end

function Reveal(session)
    local d = session.data
    if d.hostPhase ~= "question" then return end
    d.hostPhase = "reveal"
    -- Right answers in the order they arrived score 3, 2, then 1.
    local right = {}
    for name, a in pairs(d.answers) do
        if a.choice == d.correct then right[#right + 1] = { name = name, order = a.order } end
    end
    table.sort(right, function(x, y) return x.order < y.order end)
    local points = {}
    for i, r in ipairs(right) do
        points[r.name] = POINTS[i] or 1
        d.hostScores[r.name] = (d.hostScores[r.name] or 0) + points[r.name]
    end
    local results = {}
    for name, a in pairs(d.answers) do
        results[#results + 1] = name .. ":" .. a.choice .. ":" .. (points[name] or 0)
    end
    session:Broadcast("REVEAL", d.n, d.correct, table.concat(results, ";"))
    session:Broadcast("SCORES", ScoreString(session))

    d.runId = (d.runId or 0) + 1
    local id = d.runId
    C_Timer.After(REVEAL_PAUSE, function()
        if session.status == "playing" and d.runId == id then Ask(session) end
    end)
end

function Answer(session, player, n, choice)
    local d = session.data
    n, choice = tonumber(n), tonumber(choice)
    if session.status ~= "playing" or d.hostPhase ~= "question" or n ~= d.n then return false end
    if not IsPlaying(session, player) or not session:IsActive(player) then return false end
    if not choice or choice < 1 or choice > 4 or d.answers[player] then return false end -- first answer counts
    d.answerCount = d.answerCount + 1
    d.answers[player] = { choice = choice, order = d.answerCount, time = GetTime() - d.askedAt }
    session:Broadcast("LOCK", d.n, player)
    -- Everyone has answered: no need to wait for the clock.
    local all = true
    for _, p in ipairs(Players(session)) do
        if not d.answers[p] then all = false; break end
    end
    if all then
        local id = d.runId
        C_Timer.After(0.6, function()
            if d.runId == id then Reveal(session) end
        end)
    end
    return true
end

-------------------------------------------------------------------------------
-- UI: the quiz
-------------------------------------------------------------------------------
local view = {}
local Refresh

local function Choose(index)
    local s = current
    if not s or s.status ~= "playing" or s.data.phase ~= "question" or s.data.myChoice then return end
    if not IsPlaying(s, s:Me()) then return end
    s.data.myChoice = index
    s:SendAction("ANS", s.data.n, index)
    Refresh()
end

local function Build()
    local area = UI:GetGameArea()

    -- Question card.
    local qc = UI.Card(area)
    qc:SetPoint("TOPLEFT", 0, 0)
    qc:SetSize(462, 128)
    view.qcard = qc
    view.number = UI.Text(qc, "", { fancy = true, size = 15, ink = true })
    view.number:SetPoint("TOPLEFT", 16, -12)
    view.topic = UI.Text(qc, "", { ink = true, font = "GameFontNormalSmall", justify = "RIGHT" })
    view.topic:SetPoint("TOPRIGHT", -16, -14)
    view.topic:SetTextColor(0.48, 0.38, 0.25)
    view.question = UI.Text(qc, "", { ink = true, font = "GameFontNormalLarge" })
    view.question:SetPoint("TOPLEFT", 16, -36)
    view.question:SetWidth(430)
    view.question:SetJustifyH("LEFT")
    view.question:SetJustifyV("TOP")
    view.question:SetSpacing(3)
    -- The fuse: a shrinking bar of time.
    view.fuseBack = qc:CreateTexture(nil, "ARTWORK")
    view.fuseBack:SetColorTexture(0, 0, 0, 0.25)
    view.fuseBack:SetPoint("BOTTOMLEFT", 16, 12)
    view.fuseBack:SetSize(380, 8)
    view.fuse = qc:CreateTexture(nil, "ARTWORK", nil, 1)
    view.fuse:SetColorTexture(1, 0.6, 0.1, 1)
    view.fuse:SetPoint("LEFT", view.fuseBack, "LEFT")
    view.fuse:SetSize(380, 8)
    view.clock = UI.Text(qc, "", { fancy = true, size = 15, ink = true, justify = "RIGHT" })
    view.clock:SetPoint("BOTTOMRIGHT", -16, 8)

    -- Four answer buttons, 2 x 2.
    view.answers = {}
    for i = 1, 4 do
        local b = UI.Button(area, "", 226, 52, function() GG:Safe("Trivia", Choose, i) end, "wood")
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", qc, "BOTTOMLEFT", col * 236, -10 - row * 60)
        b.letter = UI.Text(b, LETTERS[i], { fancy = true, size = 20, justify = "LEFT" })
        b.letter:SetPoint("LEFT", 14, 1)
        b.letter:SetTextColor(1, 0.85, 0.4)
        -- Answers can be long, so use the regular game font, wrapped, left of the letter.
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", 40, 1)
        b.label:SetPoint("RIGHT", -34, 1)
        b.label:SetFontObject("GameFontHighlight")
        b.label:SetJustifyH("LEFT")
        b.label:SetWordWrap(true)
        b.mark = b:CreateTexture(nil, "OVERLAY")
        b.mark:SetSize(22, 22)
        b.mark:SetPoint("RIGHT", -10, 0)
        view.answers[i] = b
    end

    view.feedback = UI.Text(area, "", { fancy = true, size = 16 })
    view.feedback:SetPoint("TOPLEFT", qc, "BOTTOMLEFT", 2, -140)
    view.feedback:SetWidth(460)
    view.feedback:SetJustifyH("LEFT")
    view.detail = UI.Text(area, "", { font = "GameFontHighlight" })
    view.detail:SetPoint("TOPLEFT", view.feedback, "BOTTOMLEFT", 0, -4)
    view.detail:SetWidth(460)
    view.detail:SetJustifyH("LEFT")
    view.detail:SetTextColor(1, 0.92, 0.7)

    view.skip = UI.Button(area, "Next question", 140, 30, function()
        local s = current
        if s and s:IsHost() then s:SendAction("SKIP") end
    end, "wood")
    view.skip:SetPoint("BOTTOMLEFT", 0, 4)
    view.skip.tooltip = "Reveal the answer now (quizmaster only)."

    -- Scoreboard.
    local sb = UI.Card(area)
    sb:SetPoint("TOPRIGHT", 0, 0)
    sb:SetPoint("BOTTOMRIGHT", 0, 0)
    sb:SetWidth(232)
    view.board = sb
    local title = UI.Text(sb, "Scoreboard", { fancy = true, size = 17, ink = true })
    title:SetPoint("TOP", 0, -12)
    view.rows = {}
    for i = 1, 12 do
        local r = {}
        r.rank = UI.Text(sb, "", { fancy = true, size = 13, ink = true, justify = "RIGHT" })
        r.rank:SetPoint("TOPLEFT", 10, -36 - (i - 1) * 21)
        r.rank:SetWidth(22)
        r.crest = sb:CreateTexture(nil, "ARTWORK")
        r.crest:SetSize(14, 14)
        r.crest:SetPoint("LEFT", r.rank, "RIGHT", 4, 0)
        r.name = UI.Text(sb, "", { ink = true, font = "GameFontNormalSmall" })
        r.name:SetPoint("LEFT", r.crest, "RIGHT", 4, 0)
        r.name:SetWidth(120)
        r.name:SetJustifyH("LEFT")
        r.score = UI.Text(sb, "", { fancy = true, size = 13, ink = true, justify = "RIGHT" })
        r.score:SetPoint("TOPRIGHT", sb, "TOPRIGHT", -14, -36 - (i - 1) * 21)
        r.tick = sb:CreateTexture(nil, "OVERLAY")
        r.tick:SetSize(12, 12)
        r.tick:SetPoint("RIGHT", r.score, "LEFT", -4, 0)
        view.rows[i] = r
    end
    view.more = UI.Text(sb, "", { ink = true, font = "GameFontHighlightSmall", justify = "CENTER" })
    view.more:SetPoint("BOTTOM", 0, 12)
    view.more:SetTextColor(0.48, 0.38, 0.25)

    -- The fuse ticks down on its own.
    view.ticker = CreateFrame("Frame", nil, qc)
    view.ticker:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        if self.t < 0.1 then return end
        self.t = 0
        local s = current
        if not s or s.data.phase ~= "question" or not s.data.endsAt then return end
        local left = math.max(0, s.data.endsAt - GetTime())
        local frac = s.data.seconds > 0 and left / s.data.seconds or 0
        view.fuse:SetWidth(math.max(1, 380 * frac))
        view.fuse:SetColorTexture(frac < 0.3 and 1 or 1, frac < 0.3 and 0.25 or 0.6, 0.1, 1)
        view.clock:SetText(math.ceil(left))
    end)
end

local function Name(p) return Util.IsMe(p) and "You" or Util.ShortName(p) end

function Refresh()
    local s = current
    if not s or not view.qcard then return end
    local d = s.data
    local playing = s.status == "playing"
    local amPlayer = IsPlaying(s, s:Me())

    -- Question.
    if d.q then
        view.number:SetText(("Question %d of %d"):format(d.n, d.total))
        view.topic:SetText(TOPIC_NAME[d.q.cat] or "")
        view.question:SetText(d.q.text)
    else
        view.number:SetText("Get ready...")
        view.topic:SetText("")
        view.question:SetText("The quizmaster is shuffling the questions.")
    end
    local revealing = d.phase == "reveal" and d.reveal
    view.fuseBack:SetShown(d.phase == "question")
    view.fuse:SetShown(d.phase == "question")
    view.clock:SetShown(d.phase == "question")

    -- Answers.
    for i, b in ipairs(view.answers) do
        local text = d.q and d.q.answers[i] or ""
        b:SetText(text)
        b:SetShown(d.q ~= nil)
        local style = "wood"
        local mark
        if revealing then
            if i == d.reveal.correct then style = "primary"; mark = "Interface\\RaidFrame\\ReadyCheck-Ready"
            elseif i == d.myChoice then style = "danger"; mark = "Interface\\RaidFrame\\ReadyCheck-NotReady" end
        elseif d.myChoice == i then
            style = "accent"
        end
        if b.style ~= style then b:SetStyle(style) end
        if mark then b.mark:SetTexture(mark); b.mark:Show() else b.mark:Hide() end
        b:SetEnabled(playing and amPlayer and d.phase == "question" and not d.myChoice)
        b:SetAlpha((d.phase == "question" and d.myChoice and d.myChoice ~= i) and 0.6 or 1)
    end

    -- Feedback.
    local answeredCount = 0
    for _ in pairs(d.answered) do answeredCount = answeredCount + 1 end
    local playerCount = 0
    for _, p in ipairs(s.players) do if s:IsActive(p) and IsPlaying(s, p) then playerCount = playerCount + 1 end end
    if not playing and s.status == "ended" then
        view.feedback:SetText(UI.Gold("That's the quiz!"))
        view.detail:SetText("")
    elseif revealing then
        local mine = d.reveal.results[s:Me()]
        if not amPlayer then
            view.feedback:SetText(UI.Gold("The answer: " .. LETTERS[d.reveal.correct] .. ". " .. (d.q.answers[d.reveal.correct] or "")))
        elseif mine and mine.points > 0 then
            view.feedback:SetText(UI.Green(("Right! +%d"):format(mine.points)))
        elseif mine then
            view.feedback:SetText(UI.Red("Wrong! It was " .. LETTERS[d.reveal.correct] .. "."))
        else
            view.feedback:SetText(UI.Red("Too slow! It was " .. LETTERS[d.reveal.correct] .. "."))
        end
        local fast = {}
        for _, r in ipairs(d.reveal.ranked) do
            fast[#fast + 1] = Name(r.name) .. " +" .. r.points
            if #fast == 4 then break end
        end
        view.detail:SetText(#fast > 0 and ("Fastest: " .. table.concat(fast, ", ")) or "Nobody got that one!")
    elseif d.phase == "question" then
        if not amPlayer then
            view.feedback:SetText(UI.Gold("You're the quizmaster."))
        elseif d.myChoice then
            view.feedback:SetText(UI.Gold("Locked in: " .. LETTERS[d.myChoice] .. "!"))
        else
            view.feedback:SetText(UI.Gold("Quick! Pick an answer."))
        end
        view.detail:SetText(("Answers in: %d of %d"):format(answeredCount, playerCount))
    else
        view.feedback:SetText("")
        view.detail:SetText("")
    end
    view.skip:SetShown(playing and s:IsHost() and not s.isLocal and d.phase == "question")

    -- Scoreboard.
    local list = {}
    for name, sc in pairs(d.scores) do list[#list + 1] = { name = name, score = sc } end
    for _, p in ipairs(s.players) do
        if IsPlaying(s, p) and d.scores[p] == nil then list[#list + 1] = { name = p, score = 0 } end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.name < b.name
    end)
    local myRank
    for i, e in ipairs(list) do if Util.IsMe(e.name) then myRank = i end end
    for i, r in ipairs(view.rows) do
        local e = list[i]
        if e then
            r.rank:SetText(i .. ".")
            GG.Theme:SetCrest(r.crest, s:GetFaction(e.name))
            r.crest:Show()
            r.name:SetText(Util.IsMe(e.name) and ("|cff1f7a12" .. Util.ShortName(e.name) .. "|r") or Util.ShortName(e.name))
            r.score:SetText(e.score)
            if d.phase == "question" and d.answered[e.name] then
                r.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
                r.tick:Show()
            elseif revealing and d.reveal.results[e.name] then
                r.tick:SetTexture(d.reveal.results[e.name].points > 0 and "Interface\\RaidFrame\\ReadyCheck-Ready"
                    or "Interface\\RaidFrame\\ReadyCheck-NotReady")
                r.tick:Show()
            else
                r.tick:Hide()
            end
        else
            r.rank:SetText(""); r.name:SetText(""); r.score:SetText(""); r.crest:Hide(); r.tick:Hide()
        end
    end
    if #list > #view.rows then
        view.more:SetText(("+%d more%s"):format(#list - #view.rows, myRank and myRank > #view.rows and (" (you're #" .. myRank .. ")") or ""))
    else
        view.more:SetText("")
    end

    if playing and amPlayer and d.phase == "question" and not d.myChoice then
        UI:SetGameStatus(UI.Gold("Quick! Pick an answer."))
    else
        UI:SetGameStatus(nil)
    end
end

-------------------------------------------------------------------------------
-- UI: the question editor (/gg questions)
-------------------------------------------------------------------------------
local editor

local function BuildEditor()
    editor = CreateFrame("Frame", "GoblinGamesTriviaEditor", UIParent)
    editor:SetSize(560, 470)
    editor:SetPoint("CENTER", 0, 20)
    editor:SetFrameStrata("FULLSCREEN_DIALOG")
    editor:SetToplevel(true)
    editor:EnableMouse(true)
    editor:SetMovable(true)
    editor:RegisterForDrag("LeftButton")
    editor:SetScript("OnDragStart", editor.StartMoving)
    editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
    editor:SetClampedToScreen(true)
    UI.NineSlice(editor, UI.MEDIA .. "Parchment", 128, 24, 20)
    table.insert(UISpecialFrames, "GoblinGamesTriviaEditor")

    local title = UI.Text(editor, "Your Trivia Questions", { fancy = true, size = 22, ink = true })
    title:SetPoint("TOPLEFT", 20, -16)
    local sub = UI.Text(editor, "Saved on this account. Used when you host Trivia.", { ink = true, font = "GameFontNormalSmall" })
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    sub:SetTextColor(0.48, 0.38, 0.25)

    -- The form.
    local y = -70
    local function Field(label, width, color)
        local l = UI.Text(editor, label, { ink = true, font = "GameFontNormalSmall" })
        l:SetPoint("TOPLEFT", 20, y)
        if color then l:SetTextColor(color[1], color[2], color[3]) end
        local box = UI.EditBox(editor, width)
        box:SetPoint("TOPLEFT", 120, y + 4)
        y = y - 28
        return box
    end
    editor.q = Field("Question", 410)
    editor.q:SetMaxLetters(160)
    editor.a = {}
    editor.a[1] = Field("Right answer", 300, { 0.12, 0.48, 0.07 })
    editor.a[2] = Field("Wrong answer", 300, { 0.65, 0.11, 0.07 })
    editor.a[3] = Field("Wrong answer", 300, { 0.65, 0.11, 0.07 })
    editor.a[4] = Field("Wrong answer", 300, { 0.65, 0.11, 0.07 })
    for _, box in ipairs(editor.a) do box:SetMaxLetters(48) end

    editor.msg = UI.Text(editor, "", { ink = true, font = "GameFontHighlightSmall" })
    editor.msg:SetPoint("TOPLEFT", 20, y - 6)
    local add = UI.Button(editor, "Add question", 140, 30, function()
        local q = (editor.q:GetText() or ""):trim()
        local a = {}
        for i, box in ipairs(editor.a) do a[i] = (box:GetText() or ""):trim() end
        if q == "" or a[1] == "" or a[2] == "" or a[3] == "" or a[4] == "" then
            editor.msg:SetText("|cffa51d12Fill in the question and all four answers.|r")
            return
        end
        table.insert(CustomQuestions(), { q = q, a = a })
        editor.q:SetText("")
        for _, box in ipairs(editor.a) do box:SetText("") end
        editor.msg:SetText("|cff1f7a12Added! You have " .. #CustomQuestions() .. " questions.|r")
        editor:RefreshList()
    end, "primary")
    add:SetPoint("TOPRIGHT", -20, y)

    -- The list.
    local listTop = y - 40
    local listTitle = UI.Text(editor, "Your questions", { fancy = true, size = 15, ink = true })
    listTitle:SetPoint("TOPLEFT", 20, listTop)
    editor.rows = {}
    editor.page = 1
    local PER_PAGE = 6
    for i = 1, PER_PAGE do
        local row = CreateFrame("Frame", nil, editor)
        row:SetSize(520, 24)
        row:SetPoint("TOPLEFT", 20, listTop - 22 - (i - 1) * 26)
        row.text = UI.Text(row, "", { ink = true, font = "GameFontHighlightSmall" })
        row.text:SetPoint("LEFT", 0, 0)
        row.text:SetWidth(440)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.del = UI.Button(row, "Delete", 70, 22, function()
            if row.index then
                table.remove(CustomQuestions(), row.index)
                editor:RefreshList()
            end
        end, "danger")
        row.del:SetPoint("RIGHT", 0, 0)
        editor.rows[i] = row
    end
    editor.empty = UI.Text(editor, "No questions yet. Add one above!", { ink = true, font = "GameFontHighlightSmall" })
    editor.empty:SetPoint("TOPLEFT", 20, listTop - 26)
    editor.prev = UI.Button(editor, "<", 34, 26, function() editor.page = editor.page - 1; editor:RefreshList() end, "wood")
    editor.prev:SetPoint("BOTTOMLEFT", 20, 18)
    editor.pageText = UI.Text(editor, "", { ink = true, font = "GameFontNormalSmall", justify = "CENTER" })
    editor.pageText:SetPoint("LEFT", editor.prev, "RIGHT", 6, 0)
    editor.pageText:SetWidth(70)
    editor.next = UI.Button(editor, ">", 34, 26, function() editor.page = editor.page + 1; editor:RefreshList() end, "wood")
    editor.next:SetPoint("LEFT", editor.pageText, "RIGHT", 6, 0)
    local done = UI.Button(editor, "Done", 120, 32, function() editor:Hide() end, "primary")
    done:SetPoint("BOTTOMRIGHT", -20, 16)

    function editor:RefreshList()
        local list = CustomQuestions()
        local pages = math.max(1, math.ceil(#list / PER_PAGE))
        self.page = math.max(1, math.min(self.page, pages))
        for i, row in ipairs(self.rows) do
            local index = (self.page - 1) * PER_PAGE + i
            local q = list[index]
            if q then
                row.index = index
                row.text:SetText(index .. ". " .. q.q .. "  |cff1f7a12(" .. (q.a[1] or "?") .. ")|r")
                row:Show()
            else
                row.index = nil
                row:Hide()
            end
        end
        self.empty:SetShown(#list == 0)
        self.pageText:SetText(self.page .. " / " .. pages)
        self.prev:SetEnabled(self.page > 1)
        self.next:SetEnabled(self.page < pages)
    end
    UI.AddPopIn(editor)
end

function Game.OpenEditor()
    if not editor then BuildEditor() end
    editor.msg:SetText("")
    editor:RefreshList()
    editor:Show()
    editor.popIn:Play()
end

-- A button in the Trivia lobby (host only) that opens the editor.
Game.lobbyTool = { label = "Edit questions", onClick = function() Game.OpenEditor() end }

-------------------------------------------------------------------------------
-- Module callbacks
-------------------------------------------------------------------------------
function Game.OnSessionStart(session)
    current = session
    local d = session.data
    d.n, d.total, d.phase, d.q = 0, 0, nil, nil
    d.scores, d.answered, d.myChoice, d.reveal = {}, {}, nil, nil
    d.seconds = tonumber(session.options and session.options.seconds) or 15
    if not view.qcard then Build() end
    view.qcard:Show(); view.board:Show()
    for _, b in ipairs(view.answers) do b:Show() end

    if session:IsHost() then
        d.questions = PickQuestions(session.options or {})
        d.hostScores = {}
        session:Broadcast("SCORES", ScoreString(session))
        -- A short breath before the first question.
        d.runId = 1
        C_Timer.After(2, function()
            if session.status == "playing" and d.runId == 1 then Ask(session) end
        end)
    end
    Refresh()
end

function Game.OnAction(session, sender, op, args)
    if op == "ANS" then
        Answer(session, sender, args[1], args[2])
    elseif op == "SKIP" and sender == session.host then
        Reveal(session)
    end
end

function Game.OnState(session, op, args)
    local d = session.data
    if op == "Q" then
        d.n, d.total = tonumber(args[1]) or 0, tonumber(args[2]) or 0
        d.seconds = tonumber(args[4]) or d.seconds
        local left = tonumber(args[10]) or d.seconds -- sync messages say how long is left
        d.q = { cat = args[3], text = args[5] or "", answers = { args[6], args[7], args[8], args[9] } }
        d.phase, d.myChoice, d.answered, d.reveal = "question", nil, {}, nil
        d.endsAt = GetTime() + left
        if session == current then GG.Theme:PlaySound("turn") end
    elseif op == "LOCK" then
        if tonumber(args[1]) == d.n then d.answered[args[2]] = true end
    elseif op == "REVEAL" then
        local results, ranked = {}, {}
        for name, choice, points in (args[3] or ""):gmatch("([^:;]+):(%d+):(%d+)") do
            results[name] = { choice = tonumber(choice), points = tonumber(points) }
            if tonumber(points) > 0 then ranked[#ranked + 1] = { name = name, points = tonumber(points) } end
        end
        table.sort(ranked, function(a, b) return a.points > b.points end)
        d.reveal = { correct = tonumber(args[2]) or 1, results = results, ranked = ranked }
        d.phase = "reveal"
        local mine = results[session:Me()]
        if session == current and mine then
            GG.Theme:PlaySound(mine.points > 0 and "victory" or "defeat")
        end
    elseif op == "SCORES" then
        d.scores = {}
        for name, sc in (args[1] or ""):gmatch("([^:;]+):(%d+)") do d.scores[name] = tonumber(sc) end
    end
    if session == current then Refresh() end
end

-- A latecomer (or a resync): scores, then the question in progress.
function Game.OnSyncRequest(session, player)
    local d = session.data
    session:SendTo(player, "SCORES", ScoreString(session))
    if d.hostPhase == "question" and d.qShown then
        local left = math.max(1, d.seconds - (GetTime() - d.askedAt))
        session:SendTo(player, "Q", d.n, #d.questions, d.qCat, d.seconds, d.qText,
            d.qShown[1], d.qShown[2], d.qShown[3], d.qShown[4], math.floor(left))
    end
end

function Game.OnPlayerLeft(session, name)
    if Util.IsMe(name) then return false end -- the quizmaster left: the core ends it
    local d = session.data
    if #Players(session) == 0 then
        Finish(session)
    elseif d.hostPhase == "question" then
        -- If everyone still here has answered, reveal now.
        local all = true
        for _, p in ipairs(Players(session)) do if not d.answers[p] then all = false end end
        if all then Reveal(session) end
    end
    return true
end

function Game.QuitLabel(session)
    return (session:IsHost() and not session.isLocal) and "End quiz" or "Leave"
end

function Game.OnSessionEnd(session)
    if session == current then Refresh() end
end

function Game.OnSessionClosed(session)
    if session == current then
        current = nil
        if view.qcard then
            view.qcard:Hide(); view.board:Hide(); view.skip:Hide()
            for _, b in ipairs(view.answers) do b:Hide() end
            view.feedback:SetText(""); view.detail:SetText("")
        end
        UI:SetGameStatus(nil)
    end
end

-- Practice mode is offered because the dummy can play (see DummyAnswers).
function Game.BotAction() end

Game._test = { PickQuestions = PickQuestions, Answer = Answer, Reveal = Reveal, Choose = Choose,
    CustomQuestions = CustomQuestions, IsPlaying = IsPlaying, view = view, Ask = Ask }

GG:RegisterGame(Game)
