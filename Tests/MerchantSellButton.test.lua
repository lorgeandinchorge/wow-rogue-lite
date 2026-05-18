local bagItems = {}
local inventoryLinks = {}
local sellPrices = {}
local currentMoney = 2500
local isBank = false
local merchantOpen = true
local soldBagItems = {}
local soldInventorySlots = {}
local popupShown = {}
local printed = {}
local scheduledTimers = {}
local registeredEvents = {}

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function resetHarness(opts)
    opts = opts or {}
    bagItems = {
        [0] = {
            [1] = { count = 2, link = "|cffffffff|Hitem:300::::::::|h[Linen Cloth]|h|r", hasNoValue = false },
            [2] = { count = 1, link = "|cffffffff|Hitem:400::::::::|h[Quest Thing]|h|r", hasNoValue = true },
            [3] = { count = 1, link = "|cffffffff|Hitem:500::::::::|h[Unknown Relic]|h|r", hasNoValue = false },
            [4] = { count = 1, link = "|cffffffff|Hitem:600::::::::|h[Locked Buckle]|h|r", hasNoValue = false, locked = true },
        },
    }
    inventoryLinks = {
        [1] = "|cff9d9d9d|Hitem:100::::::::|h[Old Hat]|h|r",
        [16] = "|cff1eff00|Hitem:200::::::::|h[Green Axe]|h|r",
    }
    sellPrices = {
        ["|cff9d9d9d|Hitem:100::::::::|h[Old Hat]|h|r"] = 25,
        ["|cff1eff00|Hitem:200::::::::|h[Green Axe]|h|r"] = 500,
        ["|cffffffff|Hitem:300::::::::|h[Linen Cloth]|h|r"] = 3,
        ["|cffffffff|Hitem:600::::::::|h[Locked Buckle]|h|r"] = 10,
    }
    currentMoney = opts.currentMoney or 2500
    isBank = opts.isBank or false
    merchantOpen = opts.merchantOpen
    if merchantOpen == nil then merchantOpen = true end
    soldBagItems = {}
    soldInventorySlots = {}
    popupShown = {}
    printed = {}
    scheduledTimers = {}
    registeredEvents = {}

    _G.NUM_BAG_SLOTS = 0
    _G.GetMoney = function() return currentMoney end
    _G.GetContainerNumSlots = function(bag)
        local slots = bagItems[bag]
        if not slots then return 0 end
        local max = 0
        for slot in pairs(slots) do if slot > max then max = slot end end
        return max
    end
    _G.GetContainerItemInfo = function(bag, slot)
        local item = bagItems[bag] and bagItems[bag][slot]
        if not item then return nil end
        return nil, item.count, item.locked, nil, nil, nil, item.link, nil, item.hasNoValue
    end
    _G.GetInventoryItemLink = function(_, slot) return inventoryLinks[slot] end
    _G.GetItemInfo = function(link)
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, sellPrices[link] or 0
    end
    _G.UseContainerItem = function(bag, slot)
        soldBagItems[#soldBagItems + 1] = { bag = bag, slot = slot }
    end
    _G.PickupInventoryItem = function(slot)
        soldInventorySlots[#soldInventorySlots + 1] = slot
    end
    _G.SellCursorItem = function() end
    _G.ClearCursor = function() end
    _G.UIParent = {}           -- needed so _EnsureConfirmFrame() can create the dialog
    _G.MerchantFrame = {
        IsShown = function() return merchantOpen end,
    }
    _G.C_Timer = {
        After = function(delay, cb)
            scheduledTimers[#scheduledTimers + 1] = { delay = delay, cb = cb }
        end,
    }
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(name, ...)
        popupShown[#popupShown + 1] = { name = name, args = { ... } }
    end
    _G.CreateFrame = function(frameType, name, parent, template)
        return {
            frameType = frameType,
            name = name,
            parent = parent,
            template = template,
            SetText = function() end,
            SetSize = function() end,
            SetPoint = function() end,
            SetScript = function() end,
            SetParent = function(self, value) self.parent = value end,
            SetFrameStrata = function(self, value) self.frameStrata = value end,
            SetFrameLevel = function(self, value) self.frameLevel = value end,
            ClearAllPoints = function(self) self.pointsCleared = true end,
            Show = function(self) self.shown = true end,
            Hide = function(self) self.shown = false end,
            IsShown = function(self) return self.shown end,
        }
    end

    local ns = {
        Database = {},
        Run = {},
        Tiers = {},
    }
    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end
    function ns:Print(msg, ...)
        if select("#", ...) > 0 then msg = msg:format(...) end
        printed[#printed + 1] = msg
    end
    function ns:On(event, cb)
        registeredEvents[event] = cb
    end
    function ns.Database:GetCurrentCharacter()
        return {
            key = "Runner-Realm",
            status = opts.state or "dead_pending_contribution",
            deathSnapshot = {
                estimatedBagValue = 6,
                estimatedGearValue = 525,
                maximumPotential = 3001,
            },
        }
    end
    function ns.Database:IsBankCharacter()
        return isBank
    end
    function ns.Run:GetState(rec)
        if rec and rec.isArchived then return "archived" end
        return rec and rec.status or "active"
    end
    function ns.Tiers:FormatMoney(copper)
        return tostring(copper or 0) .. "c"
    end

    assert(loadfile("Core/Vendor.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/Merchant.lua"))("WoWRoguelite", ns)
    return ns
end

local function testSellButtonVisibleWheneverMerchantIsOpen()
    local ns = resetHarness()

    assertEqual(ns.Merchant:ShouldShowSellButton(), true,
        "pending dead run at merchant can see sell button")

    ns = resetHarness({ state = "active" })
    assertEqual(ns.Merchant:ShouldShowSellButton(), true,
        "active runs can see sell button at merchant")

    ns = resetHarness({ state = "retired" })
    assertEqual(ns.Merchant:ShouldShowSellButton(), true,
        "retired runs can see sell button at merchant")

    ns = resetHarness({ state = "dead_pending_contribution", isBank = true })
    assertEqual(ns.Merchant:ShouldShowSellButton(), true,
        "bank characters can see sell button at merchant")

    ns = resetHarness({ state = "dead_pending_contribution", merchantOpen = false })
    assertEqual(ns.Merchant:ShouldShowSellButton(), false,
        "button is hidden when merchant frame is closed")
end

local function testBuildSellPlanIncludesBagsAndEquippedGear()
    local ns = resetHarness()

    local plan = ns.Merchant:BuildFinalRunSellPlan()

    assertEqual(#plan.bags, 1, "sell plan includes one vendorable unlocked bag item")
    assertEqual(plan.bags[1].bag, 0, "bag sell entry records bag")
    assertEqual(plan.bags[1].slot, 1, "bag sell entry records slot")
    assertEqual(plan.bagValue, 6, "bag sell value includes stack count")
    assertEqual(#plan.gear, 2, "sell plan includes vendorable equipped gear")
    assertEqual(plan.gearValue, 525, "gear sell value includes equipped items")
    assertEqual(#plan.skipped, 3, "sell plan records no-value, unknown-price, and locked skips")
end

local function testConfirmAndSellExecutesPlanButKeepsContributionPending()
    local ns = resetHarness()

    local sold = ns.Merchant:SellFinalRunItems()

    assertEqual(sold, true, "sale executor reports items were sold")
    assertEqual(#soldBagItems, 1, "sale executor sells bag item")
    assertEqual(soldBagItems[1].bag, 0, "sale executor uses bag id")
    assertEqual(soldBagItems[1].slot, 1, "sale executor uses bag slot")
    assertEqual(#soldInventorySlots, 2, "sale executor sells equipped gear")
    assertEqual(ns.Run:GetState(ns.Database:GetCurrentCharacter()), "dead_pending_contribution",
        "sale does not retire the run")
end

local function testSellFinalRunItemsNoLongerRequiresPendingDeath()
    local ns = resetHarness({ state = "active" })

    local sold = ns.Merchant:SellFinalRunItems()

    assertEqual(sold, true, "sale executor can sell from the always-visible merchant button")
    assertEqual(#soldBagItems, 1, "sale executor sells bag item without pending death")
    assertEqual(#soldInventorySlots, 2, "sale executor sells equipped gear without pending death")
end

local function testMerchantShowCreatesButtonWhenMerchantFrameLoadsLate()
    _G.MerchantFrame = nil
    local ns = resetHarness()
    _G.MerchantFrame = nil
    ns.Merchant.button = nil

    ns.Merchant:Init()
    assertEqual(ns.Merchant.button, nil,
        "merchant button is not created before MerchantFrame exists")

    _G.MerchantFrame = {
        IsShown = function() return true end,
    }
    ns.Merchant:UpdateButton()

    assert(ns.Merchant.button ~= nil,
        "merchant button is created after MerchantFrame becomes available")
    assertEqual(ns.Merchant.button:IsShown(), true,
        "late-created merchant button is shown for pending dead run")
end

local function testMerchantShowRetriesWhenMerchantFrameAppearsAfterEvent()
    local ns = resetHarness()
    _G.MerchantFrame = nil
    ns.Merchant.button = nil

    ns.Merchant:UpdateButton()
    assertEqual(ns.Merchant.button, nil,
        "merchant button is not created before MerchantFrame exists")
    assert(#scheduledTimers > 0,
        "merchant button schedules a retry when MerchantFrame is missing")

    _G.MerchantFrame = {
        IsShown = function() return true end,
        GetFrameLevel = function() return 7 end,
    }
    scheduledTimers[1].cb()

    assert(ns.Merchant.button ~= nil,
        "merchant button is created by deferred retry after MerchantFrame appears")
    assertEqual(ns.Merchant.button:IsShown(), true,
        "deferred merchant button is shown when merchant is open")
    assertEqual(ns.Merchant.button.parent, UIParent,
        "merchant button is parented to UIParent so MerchantFrame refreshes cannot hide it")
    assertEqual(ns.Merchant.button.frameStrata, "DIALOG",
        "merchant button is raised above merchant internals")
    assertEqual(ns.Merchant.button.frameLevel, 27,
        "merchant button is raised relative to MerchantFrame")
end

local function testMerchantShowRefreshesAfterFrameBecomesShown()
    local ns = resetHarness({ merchantOpen = false })
    ns.Merchant:Init()
    assert(registeredEvents.MERCHANT_SHOW ~= nil,
        "merchant module registers MERCHANT_SHOW")

    registeredEvents.MERCHANT_SHOW()
    assertEqual(ns.Merchant.button:IsShown(), false,
        "first merchant-show pass can still see MerchantFrame as hidden")
    assert(#scheduledTimers > 0,
        "MERCHANT_SHOW schedules a follow-up refresh for the visible frame")

    merchantOpen = true
    scheduledTimers[#scheduledTimers].cb()

    assertEqual(ns.Merchant.button:IsShown(), true,
        "follow-up merchant-show refresh shows button once vendor window is visible")
end

-- ── New tests covering the item-cache race fix ───────────────────────────────

-- Before the fix, ShouldShowSellButton() called BuildFinalRunSellPlan(), which
-- calls GetItemInfo().  When MERCHANT_SHOW fires the cache is cold, so every
-- item reports a zero sell price and the plan appears empty → button hidden.
-- After the fix the button is visible whenever state + merchant are right,
-- regardless of whether item prices are cached.
local function testSellButtonVisibleWithColdItemCache()
    local ns = resetHarness()
    -- Simulate cold cache: GetItemInfo returns 0 for every link.
    _G.GetItemInfo = function(_link) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 0 end

    -- Confirm the precondition: plan is genuinely empty with cold cache.
    local plan = ns.Merchant:BuildFinalRunSellPlan()
    assertEqual(#plan.bags + #plan.gear, 0,
        "cold-cache precondition: plan has no items")

    -- The button must still be shown (state = dead_pending_contribution, merchant open).
    assertEqual(ns.Merchant:ShouldShowSellButton(), true,
        "button is visible for pending dead run at merchant even with cold item cache")
end

-- When PromptFinalRunSell() is called with a cold cache it should print a
-- friendly WRL message and return false rather than silently doing nothing.
local function testPromptFinalRunSellPrintsMessageWhenNothingVendorable()
    local ns = resetHarness()
    _G.GetItemInfo = function(_link) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 0 end

    local ok = ns.Merchant:PromptFinalRunSell()
    assertEqual(ok, false, "PromptFinalRunSell returns false when no vendorable items found")

    local found = false
    for _, msg in ipairs(printed) do
        if msg:find("vendorable", 1, true) then found = true; break end
    end
    assert(found, "PromptFinalRunSell prints a 'no vendorable items' message to chat")
end

-- The button can be visible when the cache is cold, but PromptFinalRunSell()
-- should succeed once the cache warms between button-show and the click.
-- This confirms the plan is built at action time, not at button-visibility time.
local function testPromptFinalRunSellBuildsAtActionTime()
    local ns = resetHarness()

    -- Cold cache: button is shown but plan is empty.
    _G.GetItemInfo = function(_link) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 0 end
    assertEqual(ns.Merchant:ShouldShowSellButton(), true, "button shown with cold cache")

    -- Cache warms before the player clicks.
    _G.GetItemInfo = function(link)
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, sellPrices[link] or 0
    end

    -- PromptFinalRunSell now finds items and either shows the confirm frame
    -- (if UIParent is available) or falls through to SellFinalRunItems().
    -- Either way it must return true.
    local ok = ns.Merchant:PromptFinalRunSell()
    assertEqual(ok, true, "PromptFinalRunSell succeeds when item cache warms before click")
end

-- Calling via slash command (/wrl sellfinal) when no merchant is open should
-- print a clear instructional message, not crash or silently fail.
local function testPromptFinalRunSellPrintsClearMessageOutsideMerchant()
    local ns = resetHarness({ merchantOpen = false })

    local ok = ns.Merchant:PromptFinalRunSell()
    assertEqual(ok, false, "PromptFinalRunSell returns false when merchant not open")

    local found = false
    for _, msg in ipairs(printed) do
        if msg:find("Open a vendor", 1, true) then found = true; break end
    end
    assert(found, "PromptFinalRunSell prints 'Open a vendor' when merchant is closed")
end

testSellButtonVisibleWheneverMerchantIsOpen()
testBuildSellPlanIncludesBagsAndEquippedGear()
testConfirmAndSellExecutesPlanButKeepsContributionPending()
testSellFinalRunItemsNoLongerRequiresPendingDeath()
testMerchantShowCreatesButtonWhenMerchantFrameLoadsLate()
testMerchantShowRetriesWhenMerchantFrameAppearsAfterEvent()
testMerchantShowRefreshesAfterFrameBecomesShown()
testSellButtonVisibleWithColdItemCache()
testPromptFinalRunSellPrintsMessageWhenNothingVendorable()
testPromptFinalRunSellBuildsAtActionTime()
testPromptFinalRunSellPrintsClearMessageOutsideMerchant()

print("MerchantSellButton.test.lua: ok")
