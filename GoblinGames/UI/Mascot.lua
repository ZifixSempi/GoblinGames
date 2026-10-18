--[[----------------------------------------------------------------------------
  GoblinGames/UI/Mascot.lua

  Grizzle, the goblin in the bottom-left corner of the window. He tells you
  what to do on every screen, so nobody has to guess what a button is for,
  and he has opinions. Click him for more.

  Panels call UI:Say("text") when they show or when something changes.
------------------------------------------------------------------------------]]

local _, GG = ...

local UI = GG.UI

local QUIPS = {
    "Psst. The Training Dummy cheats. Probably.",
    "Every game here is free. Suspicious, I know.",
    "I once lost a zeppelin at Tic-Tac-Toe. Long story.",
    "Time is money, friend! ...But this one's on the house.",
    "Win or lose, I still take a cut. Kidding! Mostly.",
    "Rumour has it Guild Bingo is next. Rumours are my business.",
    "In Deathroll, the house always wins. I am the house.",
    "Click me again. Go on. I dare ya.",
}

local mascot, bubble, lastSaid

function UI:BuildMascot(window)
    local holder = CreateFrame("Button", nil, window)
    holder:SetSize(128, 64)
    holder:SetPoint("BOTTOMLEFT", 22, 18)
    holder:SetFrameLevel(window:GetFrameLevel() + 30)
    local head = holder:CreateTexture(nil, "ARTWORK")
    head:SetTexture(UI.MEDIA .. "GoblinHead")
    head:SetAllPoints()
    UI.AddBob(head, 3, 1.1)
    UI.AddBounce(holder, 1.15)
    holder:SetScript("OnClick", function(self)
        self.bounce:Play()
        GG.Theme:PlaySound("click")
        local line
        repeat line = QUIPS[math.random(#QUIPS)] until line ~= lastSaid or #QUIPS < 2
        UI:Say(line, true)
    end)
    mascot = holder

    bubble = UI.Bubble(window)
    bubble:SetPoint("LEFT", holder, "RIGHT", 12, 4)
    bubble:SetSize(300, 62)
    bubble:SetFrameLevel(window:GetFrameLevel() + 30)
    UI.AddPopIn(bubble)
end

--- Make the goblin say something. `quip` lines are temporary: after a few
--- seconds he goes back to the panel's instructions.
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
