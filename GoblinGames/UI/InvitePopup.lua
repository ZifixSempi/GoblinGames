--[[----------------------------------------------------------------------------
  GoblinGames/UI/InvitePopup.lua

  "Bob wants to play Tic-Tac-Toe!" A parchment note at the top of the screen,
  with the goblin peeking over it.

  Why not Blizzard's StaticPopup? StaticPopups are shared with the default UI
  (group invites, release spirit ...), and addons adding their own
  StaticPopupDialogs have caused taint in the past, so we use our own frame.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI
local Util = GG.Util

local popup

local function NextInvite()
    local first
    for _, invite in pairs(GG.Lobby.invites) do
        if not first or invite.expires < first.expires then first = invite end
    end
    return first
end

local function Build()
    popup = CreateFrame("Frame", "GoblinGamesInvitePopup", UIParent)
    popup:SetSize(380, 132)
    popup:SetPoint("TOP", 0, -150)
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    UI.NineSlice(popup, UI.MEDIA .. "Parchment", 128, 24, 18)

    -- The goblin peeks over the top edge.
    local head = popup:CreateTexture(nil, "OVERLAY")
    head:SetTexture(UI.MEDIA .. "GoblinHead")
    head:SetSize(112, 56)
    head:SetPoint("BOTTOM", popup, "TOP", 0, -14)
    UI.AddBob(head, 3, 0.8)

    popup.crest = popup:CreateTexture(nil, "ARTWORK")
    popup.crest:SetSize(44, 44)
    popup.crest:SetPoint("TOPLEFT", 18, -22)

    popup.text = UI.Text(popup, "", { fancy = true, size = 17, ink = true })
    popup.text:SetPoint("TOPLEFT", popup.crest, "TOPRIGHT", 10, -2)
    popup.text:SetWidth(290)

    popup.timer = UI.Text(popup, "", { ink = true, font = "GameFontHighlightSmall" })
    popup.timer:SetPoint("TOPLEFT", popup.text, "BOTTOMLEFT", 0, -4)
    popup.timer:SetTextColor(0.48, 0.38, 0.25)

    local accept = UI.Button(popup, "Let's play!", 150, 34, function()
        if popup.invite then GG.Lobby:AcceptInvite(popup.invite.id) end
    end, "primary")
    accept:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)

    local decline = UI.Button(popup, "Not now", 120, 34, function()
        if popup.invite then GG.Lobby:DeclineInvite(popup.invite.id, "declined") end
    end, "wood")
    decline:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 16)

    UI.AddPopIn(popup)
    popup:SetScript("OnUpdate", function(self)
        if self.invite then
            self.timer:SetText("Offer expires in " .. Util.FormatSeconds(self.invite.expires - GetTime()))
        end
    end)
end

local function Refresh()
    local invite = NextInvite()
    if not invite then
        if popup then popup:Hide(); popup.invite = nil end
        return
    end
    if not popup then Build() end
    local isNew = popup.invite ~= invite
    popup.invite = invite
    GG.Theme:SetCrest(popup.crest, invite.hostFaction)
    local entry = GG:GetCatalogEntry(invite.gameId)
    local stake = tonumber(invite.options and invite.options.stake) or 0
    local text = Util.ShortName(invite.host) .. " wants to play " .. entry.name .. "!"
    if stake > 0 then
        text = text .. "\n|cffa51d12Gold stake: " .. stake .. "g|r"
    end
    popup.text:SetText(text)
    popup:Show()
    if isNew then popup.popIn:Play() end
end

local listener = {}
GG.RegisterCallback(listener, "INVITE_RECEIVED", Refresh)
GG.RegisterCallback(listener, "INVITE_CLEARED", Refresh)
