--[[----------------------------------------------------------------------------
  GoblinGames/UI/InvitePopup.lua

  The "X invites you to play Y" box at the top of the screen.

  Why not Blizzard's StaticPopup system? StaticPopups are shared with the
  default UI (group invites, release spirit ...). Addons that add their own
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
    popup = CreateFrame("Frame", "GoblinGamesInvitePopup", UIParent, UI.BACKDROP)
    GG.Theme:ApplyFrame(popup)
    popup:SetSize(340, 112)
    popup:SetPoint("TOP", 0, -140)
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)

    popup.crest = popup:CreateTexture(nil, "ARTWORK")
    popup.crest:SetSize(36, 36)
    popup.crest:SetPoint("TOPLEFT", 16, -14)

    popup.text = UI.Label(popup, "", "GameFontHighlight")
    popup.text:SetPoint("TOPLEFT", popup.crest, "TOPRIGHT", 10, -2)
    popup.text:SetWidth(260)

    popup.timer = UI.Label(popup, "", "GameFontHighlightSmall")
    popup.timer:SetPoint("TOPLEFT", popup.text, "BOTTOMLEFT", 0, -4)

    local accept = UI.Button(popup, "Accept", 110, 24, function()
        if popup.invite then GG.Lobby:AcceptInvite(popup.invite.id) end
    end)
    accept:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 14)

    local decline = UI.Button(popup, "Decline", 110, 24, function()
        if popup.invite then GG.Lobby:DeclineInvite(popup.invite.id, "declined") end
    end)
    decline:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 14)

    popup:SetScript("OnUpdate", function(self)
        if self.invite then
            self.timer:SetText(UI.Grey("Expires in " .. Util.FormatSeconds(self.invite.expires - GetTime())))
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
    popup.invite = invite
    GG.Theme:SetCrest(popup.crest, invite.hostFaction)
    local entry = GG:GetCatalogEntry(invite.gameId)
    popup.text:SetText(UI.Gold(Util.ShortName(invite.host)) .. " invites you to play " .. GG.Theme:TitleText(entry.name) .. ".")
    popup:Show()
end

local listener = {}
GG.RegisterCallback(listener, "INVITE_RECEIVED", Refresh)
GG.RegisterCallback(listener, "INVITE_CLEARED", Refresh)
