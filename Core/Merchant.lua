-- Core/Merchant.lua
-- Merchant-frame helper for final-death liquidation. The destructive sell
-- action is gated to dead_pending_contribution and requires player confirm.

local ADDON_NAME, ns = ...
local M = ns:NewModule("Merchant")

local EQUIPMENT_SLOTS = {
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19,
}

local function merchantOpen()
    return MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()
end

local function formatMoney(copper)
    if ns.Tiers and ns.Tiers.FormatMoney then
        return ns.Tiers:FormatMoney(copper or 0)
    end
    return tostring(copper or 0) .. "c"
end

local function currentRecord()
    return ns.Database and ns.Database.GetCurrentCharacter and ns.Database:GetCurrentCharacter()
end

local function currentState(rec)
    if ns.Run and ns.Run.GetState then return ns.Run:GetState(rec) end
    return rec and rec.status or nil
end

local function isBankCharacter()
    return ns.Database and ns.Database.IsBankCharacter and ns.Database:IsBankCharacter()
end

local function useContainerItem(bag, slot)
    if UseContainerItem then
        UseContainerItem(bag, slot)
        return true
    end
    if C_Container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(bag, slot)
        return true
    end
    return false
end

local function clearCursor()
    if ClearCursor then ClearCursor() end
end

function M:Init()
    self:_EnsureButton()

    if ns.On then
        ns:On("MERCHANT_SHOW", function() self:UpdateButton() end)
        ns:On("MERCHANT_CLOSED", function() self:UpdateButton() end)
        ns:On("BAG_UPDATE", function() self:UpdateButton() end)
        ns:On("PLAYER_EQUIPMENT_CHANGED", function() self:UpdateButton() end)
    end
end

function M:_EnsureButton()
    if self.button or not CreateFrame or not MerchantFrame then return end

    local button = CreateFrame("Button", "WoWRogueliteMerchantSellButton", MerchantFrame, "UIPanelButtonTemplate")
    if button.SetText then button:SetText("WRL: Sell Final Run") end
    if button.SetSize then button:SetSize(142, 22) end
    if button.SetPoint then button:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -32, -42) end
    if button.SetScript then
        button:SetScript("OnClick", function() M:PromptFinalRunSell() end)
    end
    self.button = button
    self:UpdateButton()
end

function M:UpdateButton()
    if not self.button then self:_EnsureButton() end
    if not self.button then return end
    if self:ShouldShowSellButton() then
        if self.button.Show then self.button:Show() end
    else
        if self.button.Hide then self.button:Hide() end
    end
end

function M:IsPendingFinalContribution()
    local rec = currentRecord()
    if not rec then return false end
    if isBankCharacter() then return false end
    return currentState(rec) == "dead_pending_contribution"
end

function M:BuildFinalRunSellPlan()
    local plan = {
        bags = {},
        gear = {},
        skipped = {},
        bagValue = 0,
        gearValue = 0,
        totalValue = 0,
    }

    local vendor = ns.Vendor
    local container = ns.Container
    if not vendor or not container then return plan end

    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots = container.GetNumSlots and container:GetNumSlots(bag) or 0
        for slot = 1, slots do
            local info = container.GetItemInfo and container:GetItemInfo(bag, slot)
            if info and info.link then
                if info.locked then
                    plan.skipped[#plan.skipped + 1] = { kind = "bag", bag = bag, slot = slot, link = info.link, reason = "locked" }
                elseif info.hasNoValue then
                    plan.skipped[#plan.skipped + 1] = { kind = "bag", bag = bag, slot = slot, link = info.link, reason = "no_value" }
                else
                    local copper = vendor:StackValue(info.link, info.count or 1)
                    if copper > 0 then
                        plan.bags[#plan.bags + 1] = {
                            bag = bag,
                            slot = slot,
                            link = info.link,
                            count = info.count or 1,
                            sellPrice = copper / (info.count or 1),
                            copper = copper,
                        }
                        plan.bagValue = plan.bagValue + copper
                    else
                        plan.skipped[#plan.skipped + 1] = { kind = "bag", bag = bag, slot = slot, link = info.link, reason = "unknown_price" }
                    end
                end
            end
        end
    end

    for _, slot in ipairs(EQUIPMENT_SLOTS) do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        if link then
            local copper = vendor:StackValue(link, 1)
            if copper > 0 then
                plan.gear[#plan.gear + 1] = {
                    slot = slot,
                    link = link,
                    count = 1,
                    sellPrice = copper,
                    copper = copper,
                }
                plan.gearValue = plan.gearValue + copper
            else
                plan.skipped[#plan.skipped + 1] = { kind = "gear", slot = slot, link = link, reason = "unknown_price" }
            end
        end
    end

    plan.totalValue = plan.bagValue + plan.gearValue
    return plan
end

function M:ShouldShowSellButton()
    if not merchantOpen() then return false end
    if not self:IsPendingFinalContribution() then return false end

    local plan = self:BuildFinalRunSellPlan()
    return (#plan.bags + #plan.gear) > 0
end

function M:_ConfirmationText(plan)
    local money = GetMoney and (GetMoney() or 0) or 0
    local expected = money + (plan and plan.totalValue or 0)
    if ns.Vendor and ns.Vendor.NetAfterPostage then
        expected = ns.Vendor:NetAfterPostage(expected)
    end

    return string.format(
        "Sell all vendorable inventory items and equipped gear for this dead run?\n\n" ..
        "Current money: %s\n" ..
        "Bag vendor value: %s\n" ..
        "Equipped gear vendor value: %s\n" ..
        "Expected contribution after postage: %s\n\n" ..
        "This will automatically sell equipped gear. The run will stay pending until you mail the currency to your bank.",
        formatMoney(money),
        formatMoney(plan and plan.bagValue or 0),
        formatMoney(plan and plan.gearValue or 0),
        formatMoney(expected)
    )
end

function M:_EnsureConfirmFrame()
    if self.confirmFrame or not CreateFrame or not UIParent then return self.confirmFrame end

    local frame = CreateFrame("Frame", "WoWRogueliteMerchantSellConfirm", UIParent)
    if frame.SetFrameStrata then frame:SetFrameStrata("DIALOG") end
    if frame.SetSize then frame:SetSize(430, 250) end
    if frame.SetPoint then frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
    if frame.EnableMouse then frame:EnableMouse(true) end
    if frame.Hide then frame:Hide() end

    if frame.CreateTexture then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(frame)
        bg:SetColorTexture(0.04, 0.035, 0.03, 0.96)
        frame._bg = bg

        local border = frame:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        border:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        border:SetHeight(2)
        border:SetColorTexture(0.78, 0.18, 0.18, 0.95)
        frame._border = border
    end

    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local text
    if frame.CreateFontString then
        text = frame:CreateFontString(nil, "OVERLAY")
        text:SetFont(font, 13, "")
        text:SetTextColor(0.92, 0.86, 0.76, 1)
        text:SetJustifyH("LEFT")
        text:SetJustifyV("TOP")
        text:SetWidth(380)
        text:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -24)
        frame._text = text
    end

    local sellButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    if sellButton.SetText then sellButton:SetText("Sell Final Run") end
    if sellButton.SetSize then sellButton:SetSize(130, 24) end
    if sellButton.SetPoint then sellButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 20) end
    if sellButton.SetScript then
        sellButton:SetScript("OnClick", function()
            if frame.Hide then frame:Hide() end
            M:SellFinalRunItems()
        end)
    end
    frame._sellButton = sellButton

    local cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    if cancelButton.SetText then cancelButton:SetText(CANCEL or "Cancel") end
    if cancelButton.SetSize then cancelButton:SetSize(100, 24) end
    if cancelButton.SetPoint then cancelButton:SetPoint("RIGHT", sellButton, "LEFT", -10, 0) end
    if cancelButton.SetScript then
        cancelButton:SetScript("OnClick", function()
            if frame.Hide then frame:Hide() end
        end)
    end
    frame._cancelButton = cancelButton

    self.confirmFrame = frame
    return frame
end

function M:PromptFinalRunSell()
    if not self:ShouldShowSellButton() then
        if ns.Print then ns:Print("No final-run vendor sale is available right now.") end
        self:UpdateButton()
        return false
    end

    local plan = self:BuildFinalRunSellPlan()
    self._pendingSellPlan = plan

    local frame = self:_EnsureConfirmFrame()
    if frame then
        if frame._text and frame._text.SetText then
            frame._text:SetText(self:_ConfirmationText(plan))
        end
        if frame.Show then frame:Show() end
        return true
    end

    return self:SellFinalRunItems()
end

function M:SellFinalRunItems()
    if not merchantOpen() then
        if ns.Print then ns:Print("Final-run sale stopped because the merchant is closed.") end
        return false
    end
    if not self:IsPendingFinalContribution() then
        if ns.Print then ns:Print("No final contribution is pending for this character.") end
        return false
    end

    local plan = self:BuildFinalRunSellPlan()
    if (#plan.bags + #plan.gear) == 0 then
        if ns.Print then ns:Print("No vendorable final-run items were found.") end
        self:UpdateButton()
        return false
    end

    local soldBags = 0
    local soldGear = 0

    for _, item in ipairs(plan.bags) do
        if not merchantOpen() then break end
        if useContainerItem(item.bag, item.slot) then
            soldBags = soldBags + 1
        end
    end

    for _, item in ipairs(plan.gear) do
        if not merchantOpen() then break end
        if PickupInventoryItem and SellCursorItem then
            clearCursor()
            PickupInventoryItem(item.slot)
            SellCursorItem()
            clearCursor()
            soldGear = soldGear + 1
        end
    end

    if ns.Print then
        ns:Print("Sold final-run items: %d bag stacks, %d equipped items. Go to a mailbox and use /wrl contribute.",
            soldBags, soldGear)
        if #plan.skipped > 0 then
            ns:Print("Skipped %d item(s) with no value, unknown price, or locked state.", #plan.skipped)
        end
    end

    self._pendingSellPlan = nil
    self:UpdateButton()
    return (soldBags + soldGear) > 0
end
