--[[----------------------------------------------------------------------------
  GoblinGames/UI/LobbyPanel.lua

  The lobby before a game starts, laid out as numbered steps:
    Host:  1. Invite players  ->  2. Who's coming  ->  [Start game!]
    Guest: "You're in! Waiting for the host..."  [Leave]
  The goblin's speech bubble always says what to do next.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI
local Util = GG.Util

local STATUS = {
    sent     = { icon = UI.ICON_WAIT,  text = "Invite sent..." },
    pending  = { icon = UI.ICON_WAIT,  text = "Thinking about it" },
    accepted = { icon = UI.ICON_READY, text = "Ready!" },
    declined = { icon = UI.ICON_NO,    text = "Declined" },
    noaddon  = { icon = UI.ICON_NO,    text = "No Goblin Games (or offline)" },
}
local DECLINE_REASON = {
    busy = "Busy in another game", nogame = "Missing this game", notaccepting = "Not taking invites",
    timeout = "Didn't answer", version = "Different version", left = "Left the lobby",
    nogold = "Gold mode is off for them",
}

local function StepCard(parent, title)
    local card = UI.Card(parent)
    local heading = UI.Text(card, title, { fancy = true, size = 18, ink = true })
    heading:SetPoint("TOPLEFT", 16, -14)
    card.heading = heading
    return card
end

UI:RegisterPanel("lobby", nil, function(container)
    local panel = CreateFrame("Frame", nil, container)

    local ribbon = UI.Ribbon(panel, "", 420, 64)
    ribbon:SetPoint("TOP", 0, 6)
    local rulesButton = UI.Button(panel, "How to play", 110, 26, function()
        if GG.Lobby.active then UI:ShowRules(GG.Lobby.active.gameId) end
    end, "wood")
    rulesButton:SetPoint("TOPRIGHT", 0, -4)

    -- A game can add one tool button for the host, e.g. Trivia's question
    -- editor: def.lobbyTool = { label = "...", onClick = function() end }.
    local toolButton = UI.Button(panel, "", 130, 26, function()
        local s = GG.Lobby.active
        local tool = s and s.def and s.def.lobbyTool
        if tool then GG:Safe("Lobby tool", tool.onClick, s) end
    end, "wood")
    toolButton:SetPoint("TOPRIGHT", rulesButton, "BOTTOMRIGHT", 0, -4)
    toolButton:Hide()

    local sub = UI.Text(panel, "", { font = "GameFontHighlight", justify = "CENTER" })
    sub:SetPoint("TOP", ribbon, "BOTTOM", 0, 2)
    sub:SetTextColor(1, 0.92, 0.7)

    ---------------------------------------------------------------------------
    -- Host, step 1: invite
    ---------------------------------------------------------------------------
    local inviteCard = StepCard(panel, "1. Invite players")
    inviteCard:SetPoint("TOPLEFT", 0, -82)
    inviteCard:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -6, 0)

    local nameBox
    local function InviteName(name)
        local s = GG.Lobby.active
        if not s or not name or name:trim() == "" then return end
        local ok, err = GG.Lobby:Invite(s, name:trim())
        if not ok and err then GG:Print(err); UI:Say(err, true) end
        if nameBox then nameBox:SetText("") end
    end

    -- Open games (Guild Bingo): one button tells the whole guild.
    local announceButton = UI.Button(inviteCard, "Announce to guild!", 170, 30, function()
        local s = GG.Lobby.active
        if not s then return end
        local ok, err = GG.Lobby:Announce(s)
        if ok then
            UI:Say("Announced! Everyone in the guild with Goblin Games gets a popup to join.", true)
        elseif err then
            UI:Say(err, true)
        end
    end, "primary")
    announceButton:SetPoint("TOPRIGHT", -14, -10)
    announceButton.tooltip = "Sends a join popup to every guild member who has Goblin Games."

    local groupLabel = UI.Text(inviteCard, "From your group:", { ink = true, font = "GameFontNormalSmall" })
    groupLabel:SetPoint("TOPLEFT", inviteCard.heading, "BOTTOMLEFT", 0, -6)
    groupLabel:SetTextColor(0.48, 0.38, 0.25)

    local groupList = UI.ScrollList(inviteCard, 28,
        function(parent)
            local row = CreateFrame("Frame", nil, parent)
            row.name = UI.Text(row, "", { ink = true })
            row.name:SetPoint("LEFT", 4, 0)
            row.button = UI.Button(row, "Invite", 76, 24, function(self) InviteName(self:GetParent().player) end, "primary")
            row.button:SetPoint("RIGHT", -4, 0)
            return row
        end,
        function(row, name)
            row.player = name
            row.name:SetText(Util.ShortName(name))
        end)
    groupList:SetPoint("TOPLEFT", groupLabel, "BOTTOMLEFT", -2, -4)
    groupList:SetPoint("BOTTOMRIGHT", -34, 88)

    local emptyGroup = UI.Text(inviteCard, "You're not in a group. Type a name below,\nor target someone and press Invite target.", { ink = true, font = "GameFontHighlightSmall" })
    emptyGroup:SetPoint("TOPLEFT", groupLabel, "BOTTOMLEFT", 0, -8)
    emptyGroup:SetTextColor(0.48, 0.38, 0.25)

    local byName = UI.Text(inviteCard, "Or by name:", { ink = true, font = "GameFontNormalSmall" })
    byName:SetPoint("BOTTOMLEFT", 18, 66)
    byName:SetTextColor(0.48, 0.38, 0.25)
    nameBox = UI.EditBox(inviteCard, 170, InviteName)
    nameBox:SetPoint("BOTTOMLEFT", 22, 44)
    local nameButton = UI.Button(inviteCard, "Invite", 80, 26, function() InviteName(nameBox:GetText()) end, "primary")
    nameButton:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)

    local targetButton = UI.Button(inviteCard, "Invite target", 140, 26, function()
        local name = Util.UnitFullName("target")
        if name then InviteName(name) else UI:Say("Target a player first, then press Invite target.", true) end
    end, "wood")
    targetButton:SetPoint("BOTTOMLEFT", 16, 12)

    ---------------------------------------------------------------------------
    -- Host, step 2: who's coming
    ---------------------------------------------------------------------------
    local whoCard = StepCard(panel, "2. Who's coming")
    whoCard:SetPoint("TOPLEFT", panel, "TOP", 6, -82)
    whoCard:SetPoint("BOTTOMRIGHT", 0, 0)

    local playerList = UI.ScrollList(whoCard, 30,
        function(parent)
            local row = CreateFrame("Frame", nil, parent)
            row.crest = row:CreateTexture(nil, "ARTWORK")
            row.crest:SetSize(24, 24)
            row.crest:SetPoint("LEFT", 2, 0)
            row.name = UI.Text(row, "", { ink = true })
            row.name:SetPoint("LEFT", row.crest, "RIGHT", 6, 4)
            row.status = UI.Text(row, "", { ink = true, font = "GameFontHighlightSmall" })
            row.status:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(20, 20)
            row.icon:SetPoint("RIGHT", -6, 0)
            return row
        end,
        function(row, item)
            if item.faction then
                GG.Theme:SetCrest(row.crest, item.faction)
                row.crest:SetDesaturated(false)
            else
                row.crest:SetTexture(UI.MEDIA .. "GoblinFace")
                row.crest:SetDesaturated(true)
            end
            row.name:SetText(item.label)
            row.status:SetText(item.status)
            row.icon:SetTexture(item.icon)
        end)
    playerList:SetPoint("TOPLEFT", whoCard.heading, "BOTTOMLEFT", -2, -8)
    playerList:SetPoint("BOTTOMRIGHT", -34, 14)

    -- Game options (e.g. Deathroll's start value and gold stake), at the
    -- bottom of the "Who's coming" card. They lock once invites go out.
    local optionsBox = CreateFrame("Frame", nil, whoCard)
    optionsBox:SetPoint("BOTTOMLEFT", 14, 12)
    optionsBox:SetPoint("BOTTOMRIGHT", -14, 12)
    optionsBox:SetHeight(1)
    local optionsNote = UI.Text(optionsBox, "", { ink = true, font = "GameFontHighlightSmall" })
    optionsNote:SetTextColor(0.48, 0.38, 0.25)
    local optionWidgets = {}
    local optionsFor -- session id the widgets were built for

    local function BuildOptions(s)
        for _, w in ipairs(optionWidgets) do w:Hide() end
        optionWidgets = {}
        optionsFor = s.id
        local y = 0
        local defs = (s.def and s.def.options) or {}
        for i = #defs, 1, -1 do
            local o = defs[i]
            if not o.gold or GG:GoldModeOn() then
                local w = UI.CycleButton(optionsBox, o.label, o.values,
                    function() return s.options[o.key] end,
                    function(v) GG.Lobby:SetOption(s, o.key, v) end, 150, 140)
                w:SetPoint("BOTTOMLEFT", 0, y)
                w:Show()
                w:Refresh()
                optionWidgets[#optionWidgets + 1] = w
                y = y + 32
            end
        end
        optionsBox:SetHeight(math.max(1, y))
        optionsNote:ClearAllPoints()
        optionsNote:SetPoint("BOTTOMLEFT", optionsBox, "BOTTOMLEFT", 0, y + 2)
        playerList:SetPoint("BOTTOMRIGHT", -34, 14 + y + (y > 0 and 18 or 0))
    end

    ---------------------------------------------------------------------------
    -- Guest view
    ---------------------------------------------------------------------------
    local guestCard = UI.Card(panel)
    guestCard:SetSize(420, 200)
    guestCard:SetPoint("TOP", 0, -96)
    local guestCrest = guestCard:CreateTexture(nil, "ARTWORK")
    guestCrest:SetSize(64, 64)
    guestCrest:SetPoint("TOP", 0, -18)
    local guestTitle = UI.Text(guestCard, "You're in!", { fancy = true, size = 26, ink = true, justify = "CENTER" })
    guestTitle:SetPoint("TOP", guestCrest, "BOTTOM", 0, -6)
    local guestText = UI.Text(guestCard, "", { ink = true, justify = "CENTER" })
    guestText:SetPoint("TOP", guestTitle, "BOTTOM", 0, -8)
    guestText:SetWidth(380)

    ---------------------------------------------------------------------------
    -- Buttons (bottom-right of the window)
    ---------------------------------------------------------------------------
    local actions = CreateFrame("Frame", nil, panel)
    actions:SetSize(1, 1)
    actions:SetPoint("BOTTOMRIGHT", UI.frame.actions, "BOTTOMRIGHT")
    local startButton = UI.Button(actions, "Start game!", 150, 36, function()
        local s = GG.Lobby.active
        if s then GG.Lobby:Start(s) end
    end, "primary")
    startButton:SetPoint("BOTTOMRIGHT")
    local leaveButton = UI.Button(actions, "Cancel", 110, 36, function()
        GG.Lobby:Leave(GG.Lobby.active)
    end, "danger")
    leaveButton:SetPoint("RIGHT", startButton, "LEFT", -8, 0)

    ---------------------------------------------------------------------------
    -- Refresh
    ---------------------------------------------------------------------------
    local function Refresh()
        local s = GG.Lobby.active
        if not s or s.status ~= "lobby" then return end
        local entry = s.catalog
        ribbon:SetText(entry.name)

        local isHost = s:IsHost()
        local tool = s.def and s.def.lobbyTool
        toolButton:SetShown(isHost and tool ~= nil)
        if tool then toolButton:SetText(tool.label) end
        announceButton:SetShown(isHost and s.open == true)
        inviteCard.heading:SetText(s.open and "1. Gather players" or "1. Invite players")
        inviteCard:SetShown(isHost)
        whoCard:SetShown(isHost)
        startButton:SetShown(isHost)
        guestCard:SetShown(not isHost)
        leaveButton:SetText(isHost and "Cancel" or "Leave")

        if not isHost then
            sub:SetText("")
            GG.Theme:SetCrest(guestCrest, s:GetFaction(s.host))
            local extra = ""
            local stake = GG.Lobby.Stake(s)
            if stake > 0 then extra = "\n\nGold stake: |cffa51d12" .. stake .. "g|r (ledger only, you trade it yourself)" end
            guestText:SetText("Waiting for |cff1f7a12" .. Util.ShortName(s.host) .. "|r to start " .. entry.name .. "." .. extra)
            UI:Say("Hang tight! The game pops up by itself as soon as " .. Util.ShortName(s.host) .. " starts it.")
            return
        end

        if optionsFor ~= s.id then
            BuildOptions(s)
        end
        local canEdit = GG.Lobby:CanEditOptions(s)
        for _, w in ipairs(optionWidgets) do
            w.button:SetEnabled(canEdit)
            w:Refresh()
        end
        if #optionWidgets > 0 then
            optionsNote:SetText(canEdit and "Game options (pick before inviting):" or "Game options (locked once invites went out):")
        else
            optionsNote:SetText("")
        end

        local ready = GG.Lobby.CountAccepted(s) + 1
        if entry.min == entry.max then
            sub:SetText(("%d of %d players ready"):format(ready, entry.max))
        else
            sub:SetText(("%d ready (need at least %d)"):format(ready, entry.min))
        end
        startButton:SetEnabled(GG.Lobby:CanStart(s))

        local members = Util.GroupMembers()
        groupList:SetItems(members)
        emptyGroup:SetShown(#members == 0)

        local items = { { label = Util.ShortName(s.host) .. " (you, host)", faction = s:GetFaction(s.host),
            status = UI.InkGreen("Ready!"), icon = UI.ICON_READY } }
        local waitingOn, missing
        for _, name in ipairs(s.inviteOrder) do
            local info = s.invites[name]
            local st = STATUS[info.status]
            local text = st.text
            if info.status == "declined" and info.reason and info.reason ~= "declined" then
                text = DECLINE_REASON[info.reason] or text
            end
            local color = (info.status == "accepted" and UI.InkGreen) or ((info.status == "declined" or info.status == "noaddon") and UI.InkRed) or UI.InkGrey
            items[#items + 1] = {
                label = Util.ShortName(name),
                faction = info.status == "accepted" and s:GetFaction(name) or nil,
                status = color(text),
                icon = st.icon,
            }
            if info.status == "sent" or info.status == "pending" then waitingOn = waitingOn or name end
            if info.status == "noaddon" then missing = missing or name end
        end
        playerList:SetItems(items)

        -- Tell the host exactly what's next.
        if s.open and not s.announced and GG.Lobby.CountAccepted(s) == 0 then
            UI:Say("Press |cff1f7a12Announce to guild!|r and everyone with Goblin Games gets a popup to join.")
        elseif GG.Lobby:CanStart(s) then
            UI:Say("Enough players! Press |cff1f7a12Start game!|r whenever you're ready." ..
                (s.open and " Latecomers can still join later." or ""))
        elseif waitingOn then
            UI:Say("Waiting for " .. Util.ShortName(waitingOn) .. " to accept..." ..
                (entry.max == 2 and " The game starts the moment they do." or ""))
        elseif missing then
            UI:Say(Util.ShortName(missing) .. " doesn't have Goblin Games (or is offline). Tell 'em it's free on CurseForge!")
        else
            UI:Say("Step 1: invite someone! Press |cff1f7a12Invite|r next to a name, or type one in.")
        end
    end

    panel:SetScript("OnShow", Refresh)
    local listener = {}
    GG.RegisterCallback(listener, "SESSION_UPDATED", function() if panel:IsShown() then Refresh() end end)
    GG.RegisterCallback(listener, "SESSION_CREATED", function() if panel:IsShown() then Refresh() end end)
    GG:RegisterEvent("GROUP_ROSTER_UPDATE", function() if panel:IsShown() then Refresh() end end)
    return panel
end)
