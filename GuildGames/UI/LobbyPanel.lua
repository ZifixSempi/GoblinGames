--[[----------------------------------------------------------------------------
  GuildGames/UI/LobbyPanel.lua

  The lobby before a game starts.
    Host:  invite group members, your target, or anyone by name; see who has
           accepted; start the game.
    Guest: "waiting for the host" and a Leave button.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI
local Util = GG.Util

local STATUS_TEXT = {
    sent     = function() return UI.Grey("Invited...") end,
    pending  = function() return UI.Gold("Deciding") end,
    accepted = function() return UI.Green("Accepted") end,
    declined = function(info) return UI.Red(info.reason == "declined" and "Declined" or ("Declined (" .. (info.reason or "?") .. ")")) end,
    noaddon  = function() return UI.Red("No addon / offline") end,
}

UI:RegisterPanel("lobby", "Lobby", function(container)
    local panel = CreateFrame("Frame", nil, container)

    local heading = UI.Label(panel, "", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 4, 0)
    local sub = UI.Label(panel, "", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)

    ---------------------------------------------------------------------------
    -- Host: left column = people you can invite
    ---------------------------------------------------------------------------
    local left = UI.Panel(panel, "tile")
    left:SetPoint("TOPLEFT", 0, -46)
    left:SetPoint("BOTTOMLEFT", 0, 40)
    left:SetWidth(260)

    local leftTitle = UI.Label(left, "Your group", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", 10, -8)

    local nameBox
    local function InviteName(name)
        local s = GG.Lobby.active
        if not s or not name or name:trim() == "" then return end
        local ok, err = GG.Lobby:Invite(s, name:trim())
        if not ok and err then GG:Print(err) end
        if nameBox then nameBox:SetText("") end
    end

    local groupList = UI.ScrollList(left, 24,
        function(parent)
            local row = CreateFrame("Frame", nil, parent)
            row.name = UI.Label(row, "")
            row.name:SetPoint("LEFT", 4, 0)
            row.button = UI.Button(row, "Invite", 60, 20, function(self) InviteName(self:GetParent().player) end)
            row.button:SetPoint("RIGHT", -4, 0)
            return row
        end,
        function(row, name)
            row.player = name
            row.name:SetText(Util.ShortName(name))
        end)
    groupList:SetPoint("TOPLEFT", 8, -28)
    groupList:SetPoint("BOTTOMRIGHT", -28, 64)

    local emptyGroup = UI.Label(left, UI.Grey("You're not in a group.\nInvite by name below."), "GameFontHighlightSmall")
    emptyGroup:SetPoint("TOPLEFT", 12, -32)

    nameBox = UI.EditBox(left, 150, InviteName)
    nameBox:SetPoint("BOTTOMLEFT", 16, 38)
    local nameButton = UI.Button(left, "Invite", 70, 20, function() InviteName(nameBox:GetText()) end)
    nameButton:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)

    local targetButton = UI.Button(left, "Invite target", 120, 20, function()
        local name = Util.UnitFullName("target")
        if name then InviteName(name) else GG:Print("Target a player first.") end
    end)
    targetButton:SetPoint("BOTTOMLEFT", 10, 10)

    ---------------------------------------------------------------------------
    -- Host: right column = invited players and their answers
    ---------------------------------------------------------------------------
    local right = UI.Panel(panel, "tile")
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 40)

    local rightTitle = UI.Label(right, "Players", "GameFontNormal")
    rightTitle:SetPoint("TOPLEFT", 10, -8)

    local playerList = UI.ScrollList(right, 22,
        function(parent)
            local row = CreateFrame("Frame", nil, parent)
            row.crest = row:CreateTexture(nil, "ARTWORK")
            row.crest:SetSize(18, 18)
            row.crest:SetPoint("LEFT", 2, 0)
            row.name = UI.Label(row, "")
            row.name:SetPoint("LEFT", row.crest, "RIGHT", 6, 0)
            row.status = UI.Label(row, "", "GameFontHighlightSmall")
            row.status:SetPoint("RIGHT", -4, 0)
            return row
        end,
        function(row, item)
            GG.Theme:SetCrest(row.crest, item.faction)
            row.crest:SetShown(item.faction ~= nil)
            row.name:SetText(item.label)
            row.status:SetText(item.status)
        end)
    playerList:SetPoint("TOPLEFT", 8, -28)
    playerList:SetPoint("BOTTOMRIGHT", -28, 8)

    ---------------------------------------------------------------------------
    -- Guest view
    ---------------------------------------------------------------------------
    local waiting = UI.Label(panel, "", "GameFontHighlight")
    waiting:SetPoint("CENTER", 0, 20)
    waiting:SetJustifyH("CENTER")

    ---------------------------------------------------------------------------
    -- Bottom buttons
    ---------------------------------------------------------------------------
    local startButton = UI.Button(panel, "Start game", 120, 26, function()
        local s = GG.Lobby.active
        if s then GG.Lobby:Start(s) end
    end)
    startButton:SetPoint("BOTTOMRIGHT", 0, 4)

    local leaveButton = UI.Button(panel, "Cancel", 100, 26, function()
        GG.Lobby:Leave(GG.Lobby.active)
    end)
    leaveButton:SetPoint("RIGHT", startButton, "LEFT", -8, 0)

    ---------------------------------------------------------------------------
    -- Refresh
    ---------------------------------------------------------------------------
    local function Refresh()
        local s = GG.Lobby.active
        if not s or s.status ~= "lobby" then return end
        local entry = s.catalog
        heading:SetText(GG.Theme:TitleText(entry.name))

        local isHost = s:IsHost()
        left:SetShown(isHost)
        right:SetShown(isHost)
        startButton:SetShown(isHost)
        waiting:SetShown(not isHost)
        leaveButton:SetText(isHost and "Cancel" or "Leave")

        if not isHost then
            sub:SetText("")
            waiting:SetText("Joined " .. Util.ShortName(s.host) .. "'s " .. entry.name .. " game.\n\n" .. UI.Grey("Waiting for the host to start..."))
            return
        end

        local accepted = GG.Lobby.CountAccepted(s) + 1
        sub:SetText(UI.Grey(("%d of %d-%d players ready"):format(accepted, entry.min, entry.max)))
        startButton:SetEnabled(GG.Lobby:CanStart(s))

        local members = Util.GroupMembers()
        groupList:SetItems(members)
        emptyGroup:SetShown(#members == 0)

        local items = { { label = Util.ShortName(s.host) .. UI.Grey(" (host)"), faction = s:GetFaction(s.host), status = UI.Green("Ready") } }
        for _, name in ipairs(s.inviteOrder) do
            local info = s.invites[name]
            items[#items + 1] = {
                label = Util.ShortName(name),
                faction = info.status == "accepted" and s:GetFaction(name) or nil,
                status = STATUS_TEXT[info.status](info),
            }
        end
        playerList:SetItems(items)
    end

    panel:SetScript("OnShow", Refresh)
    local listener = {}
    GG.RegisterCallback(listener, "SESSION_UPDATED", function() if panel:IsShown() then Refresh() end end)
    GG.RegisterCallback(listener, "SESSION_CREATED", function() if panel:IsShown() then Refresh() end end)
    GG:RegisterEvent("GROUP_ROSTER_UPDATE", function() if panel:IsShown() then Refresh() end end)
    return panel
end)
