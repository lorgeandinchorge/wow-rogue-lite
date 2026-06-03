local function resetHarness()
    WRL_DB = {
        bankCharacter = "Bank-Realm",
        resaleReceipts = {},
        settings = {
            pricing = {
                resaleSource = "local_fallback",
            },
        },
    }
    WRL_CharDB = {}
    NUM_BAG_SLOTS = 0

    _G.time = function() return 24680 end
    _G.GetRealmName = function() return "Realm" end
    _G.MailFrame = nil
    _G.MailFrameTab2 = nil
    _G.SendMailNameEditBox = nil
    _G.SendMailSubjectEditBox = nil
    _G.SendMailBodyEditBox = nil
    _G.SendMailMoney = nil
    _G.SendMailCOD = nil
    _G.SendMailCODMoney = nil
    _G.MoneyInputFrame_SetCopper = nil
    _G.TSM_API = nil
    _G.GetItemInfo = function(itemId)
        if itemId == 723 then
            return "Goretusk Liver", nil, nil, nil, nil, nil, nil, nil, nil, nil, 12
        elseif itemId == 769 then
            return "Chunk of Boar Meat", nil, nil, nil, nil, nil, nil, nil, nil, nil, 1
        elseif itemId == 2589 then
            return "Linen Cloth", nil, nil, nil, nil, nil, nil, nil, nil, nil, 0
        elseif itemId == 99999 then
            return "Vendor Trash", nil, nil, nil, nil, nil, nil, nil, nil, nil, 100
        end
        return nil
    end

    local ns = {
        Database = {},
        MainFrame = {},
        Print = function() end,
        Settings = {},
        Tiers = { FormatMoney = function(_, copper) return tostring(copper or 0) .. "c" end },
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns:UnitKey()
        return "Bank-Realm"
    end

    function ns.Settings:Get(path, default)
        if path == "pricing.resaleSource" then
            return WRL_DB.settings.pricing.resaleSource or default
        end
        return default
    end

    local refreshed = 0
    function ns.MainFrame:RefreshCurrentTab()
        refreshed = refreshed + 1
    end
    function ns.MainFrame:RefreshCount()
        return refreshed
    end

    assert(loadfile("Core/Vendor.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/Pricing.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/BankResale.lua"))("WoWRoguelite", ns)
    return ns
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function testCatalogRecognizesQuestGoods()
    local ns = resetHarness()

    assertEqual(ns.BankResale:IsCatalogItem(769), true, "catalog includes Chunk of Boar Meat")
    assertEqual(ns.BankResale:IsCatalogItem(723), true, "catalog includes Goretusk Liver")
    assertEqual(ns.BankResale:IsCatalogItem(99999), false, "catalog ignores non-curated junk")
end

local function testPriceUsesVendorDoubleOrFallbackMinimum()
    local ns = resetHarness()

    assertEqual(ns.BankResale:PriceForItem(723), 50, "fallback beats low vendor price")
    assertEqual(ns.BankResale:PriceForItem(769), 25, "boar meat uses catalog fallback when vendor price is tiny")

    _G.GetItemInfo = function(itemId)
        if itemId == 723 then
            return "Goretusk Liver", nil, nil, nil, nil, nil, nil, nil, nil, nil, 40
        end
        return nil
    end
    assertEqual(ns.BankResale:PriceForItem(723), 80, "vendor price doubled wins when higher")
end

local function testPriceUsesFallbackWhenGetItemInfoIsUncached()
    local ns = resetHarness()
    _G.GetItemInfo = function() return nil end

    assertEqual(ns.BankResale:PriceForItem(769), 25, "uncached item info uses catalog fallback without crashing")
end

local function testAutoPricingUsesTSMWithSourceMetadata()
    local ns = resetHarness()
    WRL_DB.settings.pricing.resaleSource = "auto"
    _G.TSM_API = {
        GetCustomPriceValue = function(source, itemString)
            if source == "DBMarket" and itemString == "i:769" then return 333 end
        end,
    }

    local price, reason, detail = ns.BankResale:PriceForItem(769)

    assertEqual(reason, nil, "TSM resale price has no error")
    assertEqual(price, 333, "auto resale pricing prefers TSM")
    assertEqual(detail.sourceId, "tsm_dbmarket", "price detail records TSM source id")
    assertEqual(detail.sourceLabel, "TSM DBMarket", "price detail records TSM label")
end

local function testInventoryRowsAggregateCatalogStacks()
    local ns = resetHarness()
    ns.Container = {
        GetNumSlots = function(_, bag)
            if bag == 0 then return 4 end
            if bag == -1 then return 1 end
            return 0
        end,
        GetItemInfo = function(_, bag, slot)
            if bag == 0 and slot == 1 then return { itemID = 769, count = 2, itemLink = "item:769" } end
            if bag == 0 and slot == 2 then return { itemID = 723, count = 1, itemLink = "item:723" } end
            if bag == 0 and slot == 3 then return { itemID = 769, count = 3, itemLink = "item:769" } end
            if bag == 0 and slot == 4 then return { itemID = 99999, count = 9, itemLink = "item:99999" } end
            if bag == -1 and slot == 1 then return { itemID = 723, count = 4, itemLink = "item:723" } end
            return nil
        end,
    }
    _G.BankFrame = { IsShown = function() return true end }

    local rows = ns.BankResale:InventoryRows()

    assertEqual(#rows, 2, "inventory rows only include catalog items")
    assertEqual(rows[1].itemId, 769, "rows sort by item name")
    assertEqual(rows[1].count, 5, "matching stacks aggregate")
    assertEqual(rows[1].priceEach, 25, "row includes fallback price")
    assertEqual(rows[1].priceSource, "catalog_fallback", "row includes fallback source id")
    assertEqual(rows[1].priceLabel, "catalog fallback", "row includes fallback source label")
    assertEqual(rows[1].totalCopper, 125, "row includes total value")
    assertEqual(rows[2].itemId, 723, "second catalog item included")
    assertEqual(rows[2].count, 5, "visible bank slots aggregate with carried bags")
end

local function testDismissInventoryStockHidesVisibleCatalogRowUntilCountIncreases()
    local ns = resetHarness()
    local boarCount = 5
    ns.Container = {
        GetNumSlots = function(_, bag)
            if bag == 0 then return 1 end
            return 0
        end,
        GetItemInfo = function(_, bag, slot)
            if bag == 0 and slot == 1 then return { itemID = 769, count = boarCount, itemLink = "item:769" } end
            return nil
        end,
    }

    local ok, reason = ns.BankResale:DismissInventoryStock(769, boarCount)
    local hiddenRows = ns.BankResale:InventoryRows()
    boarCount = 7
    local newRows = ns.BankResale:InventoryRows()

    assertEqual(ok, true, "dismissing visible resale stock succeeds")
    assertEqual(reason, nil, "dismissing visible resale stock has no error")
    assertEqual(#hiddenRows, 0, "dismissed inventory stock no longer redraws the same row")
    assertEqual(#newRows, 1, "newly added stock can still appear after dismissal")
    assertEqual(newRows[1].itemId, 769, "new stock keeps the dismissed item id")
    assertEqual(newRows[1].count, 2, "only stock above the dismissed count is shown")
end

local function testSimulatedStockAppearsInInventoryRows()
    local ns = resetHarness()

    local ok, reason = ns.BankResale:SimulateStock({
        { itemId = 769, qty = 4 },
        { itemId = 723, qty = 2 },
    })
    local badOk, badReason = ns.BankResale:SimulateStock({
        { itemId = 99999, qty = 3 },
    })
    local rows = ns.BankResale:InventoryRows()

    assertEqual(ok, true, "simulated catalog stock is accepted")
    assertEqual(reason, nil, "simulated catalog stock has no error")
    assertEqual(badOk, false, "non-catalog simulated stock is rejected")
    assertEqual(badReason, "not_catalog", "non-catalog simulation returns catalog error")
    assertEqual(#rows, 2, "simulated inventory rows include accepted catalog stock")
    assertEqual(rows[1].itemId, 769, "simulated boar meat row is present")
    assertEqual(rows[1].count, 4, "simulated boar meat quantity is used")
    assertEqual(rows[1].simulated, true, "simulated rows are flagged")
    assertEqual(rows[2].itemId, 723, "simulated liver row is present")

    ns.BankResale:ClearSimulatedStock()
    assertEqual(#ns.BankResale:InventoryRows(), 0, "clearing simulated stock removes rows")
end

local function testRemoveSimulatedStockRemovesOneItemLine()
    local ns = resetHarness()

    ns.BankResale:SimulateStock({
        { itemId = 769, qty = 4 },
        { itemId = 723, qty = 2 },
    })
    local ok, reason = ns.BankResale:RemoveSimulatedStock(769)
    local rows = ns.BankResale:InventoryRows()

    assertEqual(ok, true, "removing simulated stock succeeds")
    assertEqual(reason, nil, "removing simulated stock has no error")
    assertEqual(#rows, 1, "removing one simulated item leaves other rows")
    assertEqual(rows[1].itemId, 723, "remaining simulated row is preserved")
end

local function testRecordSaleStoresReceipt()
    local ns = resetHarness()

    local receipt, reason = ns.BankResale:RecordSale(769, 2, "Tester-Realm")

    assertEqual(reason, nil, "sale records without error")
    assertEqual(receipt.itemId, 769, "receipt stores item ID")
    assertEqual(receipt.itemName, "Chunk of Boar Meat", "receipt stores item name")
    assertEqual(receipt.qty, 2, "receipt stores quantity")
    assertEqual(receipt.priceEach, 25, "receipt stores current price")
    assertEqual(receipt.priceSource, "catalog_fallback", "receipt stores price source id")
    assertEqual(receipt.priceLabel, "catalog fallback", "receipt stores price source label")
    assertEqual(receipt.totalCopper, 50, "receipt stores total copper")
    assertEqual(receipt.buyer, "Tester-Realm", "receipt stores buyer")
    assertEqual(receipt.seller, "Bank-Realm", "receipt stores seller")
    assertEqual(WRL_DB.resaleReceipts[1], receipt, "receipt is appended to saved data")
    assertEqual(ns.MainFrame:RefreshCount(), 1, "recording sale refreshes dashboard")
end

local function testRecordSaleConsumesSimulatedStock()
    local ns = resetHarness()

    ns.BankResale:SimulateStock({
        { itemId = 769, qty = 4 },
        { itemId = 723, qty = 2 },
    }, "Tester-Realm")
    local beforeRefresh = ns.MainFrame:RefreshCount()

    ns.BankResale:RecordSale(769, 4, "Tester-Realm")
    local rows = ns.BankResale:InventoryRows()

    assertEqual(#rows, 1, "recording the full simulated order removes its line")
    assertEqual(rows[1].itemId, 723, "other simulated resale lines remain")
    assertEqual(ns.MainFrame:RefreshCount() - beforeRefresh, 1, "recording sale refreshes dashboard once")
end

local function testPrepareCODMailPrefillsDraftWithoutReceipt()
    local ns = resetHarness()
    local fields = {}
    _G.MailFrame = { IsShown = function() return true end }
    _G.MailFrameTab2 = { Click = function() fields.clickedSendTab = true end }
    _G.SendMailNameEditBox = { SetText = function(_, value) fields.name = value end }
    _G.SendMailSubjectEditBox = { SetText = function(_, value) fields.subject = value end }
    _G.SendMailBodyEditBox = { SetText = function(_, value) fields.body = value end }
    _G.SendMailMoney = {}
    _G.SendMailCOD = {}
    _G.MoneyInputFrame_SetCopper = function(frame, copper)
        if frame == _G.SendMailCOD then
            fields.cod = copper
        elseif frame == _G.SendMailMoney then
            fields.money = copper
        end
    end

    local draft, reason = ns.BankResale:PrepareCODMail(769, 2, "Tester-Realm")

    assertEqual(reason, nil, "cod prep reports no error")
    assertEqual(fields.clickedSendTab, true, "cod prep switches to send tab")
    assertEqual(fields.name, "Tester", "cod prep strips same-realm recipient")
    assertEqual(fields.subject, "Roguelite resale desk", "cod prep fills resale subject")
    assertEqual(fields.cod, 50, "cod prep fills total COD amount")
    assertEqual(fields.money, 0, "cod prep clears outgoing money field")
    assertEqual(draft.itemId, 769, "draft stores item ID")
    assertEqual(draft.qty, 2, "draft stores quantity")
    assertEqual(draft.totalCopper, 50, "draft stores total copper")
    assertEqual(draft.priceSource, "catalog_fallback", "draft stores price source id")
    assertEqual(draft.priceLabel, "catalog fallback", "draft stores price source label")
    assertEqual(ns.BankResale.pendingCOD, draft, "draft is kept as transient pending COD")
    assertEqual(#WRL_DB.resaleReceipts, 0, "cod prep does not record a sale receipt")
    if not fields.body or not fields.body:find("Chunk of Boar Meat", 1, true) then
        error("cod prep body should name the resale item")
    end
    if not fields.body:find("Price source: catalog fallback", 1, true) then
        error("cod prep body should include price source")
    end
end

local function testPrepareCODMailValidation()
    local ns = resetHarness()
    _G.MailFrame = { IsShown = function() return true end }

    local missingBuyer, missingBuyerReason = ns.BankResale:PrepareCODMail(769, 1, "")
    local badQty, badQtyReason = ns.BankResale:PrepareCODMail(769, 0, "Tester-Realm")
    local badItem, badItemReason = ns.BankResale:PrepareCODMail(99999, 1, "Tester-Realm")
    _G.MailFrame = { IsShown = function() return false end }
    local noMailbox, noMailboxReason = ns.BankResale:PrepareCODMail(769, 1, "Tester-Realm")

    assertEqual(missingBuyer, nil, "missing buyer rejects draft")
    assertEqual(missingBuyerReason, "missing_buyer", "missing buyer reason is explicit")
    assertEqual(badQty, nil, "bad quantity rejects draft")
    assertEqual(badQtyReason, "bad_qty", "bad quantity reason is explicit")
    assertEqual(badItem, nil, "non-catalog item rejects draft")
    assertEqual(badItemReason, "not_catalog", "non-catalog reason is explicit")
    assertEqual(noMailbox, nil, "closed mailbox rejects draft")
    assertEqual(noMailboxReason, "mailbox_closed", "closed mailbox reason is explicit")
end

local function testStrictTSMBlocksCODAndSaleWhenPriceMissing()
    local ns = resetHarness()
    WRL_DB.settings.pricing.resaleSource = "tsm_dbmarket"
    _G.MailFrame = { IsShown = function() return true end }
    _G.SendMailCOD = {}
    _G.MoneyInputFrame_SetCopper = function() end

    local receipt, saleReason = ns.BankResale:RecordSale(769, 1, "Tester-Realm")
    local draft, mailReason = ns.BankResale:PrepareCODMail(769, 1, "Tester-Realm")

    assertEqual(receipt, nil, "strict TSM mode blocks sale receipt without a price")
    assertEqual(saleReason, "no_price", "strict TSM sale failure is explicit")
    assertEqual(draft, nil, "strict TSM mode blocks COD without a price")
    assertEqual(mailReason, "no_price", "strict TSM COD failure is explicit")
end

testCatalogRecognizesQuestGoods()
testPriceUsesVendorDoubleOrFallbackMinimum()
testPriceUsesFallbackWhenGetItemInfoIsUncached()
testAutoPricingUsesTSMWithSourceMetadata()
testInventoryRowsAggregateCatalogStacks()
testDismissInventoryStockHidesVisibleCatalogRowUntilCountIncreases()
testSimulatedStockAppearsInInventoryRows()
testRemoveSimulatedStockRemovesOneItemLine()
testRecordSaleStoresReceipt()
testRecordSaleConsumesSimulatedStock()
testPrepareCODMailPrefillsDraftWithoutReceipt()
testPrepareCODMailValidation()
testStrictTSMBlocksCODAndSaleWhenPriceMissing()

print("BankResale.test.lua: ok")
