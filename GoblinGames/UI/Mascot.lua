--[[----------------------------------------------------------------------------
  GoblinGames/UI/Mascot.lua

  The hint bubble in the bottom-left corner of the window. It tells you what
  to do on every screen, so nobody has to guess what a button is for.

  Panels call UI:Say("text") when they show or when something changes.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI

local bubble, lastSaid

--- The hint bubble in the bottom-left corner of the window. (There used to be
--- a goblin mascot here; Zifix preferred no goblin pictures, so it's just the
--- bubble now.)
function UI:BuildMascot(window)
    bubble = UI.Bubble(window)
    bubble:SetPoint("BOTTOMLEFT", 28, 22)
    bubble:SetSize(440, 58)
    bubble:SetFrameLevel(window:GetFrameLevel() + 30)
    bubble.tail:Hide()
    UI.AddPopIn(bubble)
end

--- Show a hint. `quip` lines are temporary: after a few seconds the bubble
--- goes back to the panel's instructions.
function UI:Say(text, quip)
    if not bubble then return end
    if not quip then self.instruction = text end
    lastSaid = text
    bubble.text:SetText(text)
    bubble.popIn:Play()
    if quip then
        local said = text
        C_Timer.After(5, function()
            if lastSaid == said and UI.instruction then
                bubble.text:SetText(UI.instruction)
                lastSaid = UI.instruction
            end
        end)
    end
end
