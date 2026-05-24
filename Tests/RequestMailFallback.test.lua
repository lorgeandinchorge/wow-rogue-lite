local function resetHarness()
    WRL_DB = {
        requests = {},
        characters = {},
    }
    WRL_CharDB = {
        outgoing = {},
    }

    _G.time = function() return 12345 end
    _G.math.random = function() return 4321 end
    _G.MailFrame = nil
    _G.MailFrameTab2 = nil
    _G.SendMailNameEditBox = nil
    _G.SendMailSubjectEditBox = nil
    _G.SendMailBodyEditBox = nil
    _G.SendMailBodyScrollFrame = nil
    _G.SendMailFrame = nil
    _G.C_Timer = nil
    _G.NUM_BAG_SLOTS = nil
    _G.GetContainerNumSlots = nil
    _G.GetContainerItemInfo = nil
    _G.C_Container = nil

    local prints = {}
    local ns = {
        Database = {},
        Debug = function() end,
        Print = function(_, msg, ...)
            if select("#", ...) > 0 then
                prints[#prints + 1] = string.format(msg, ...)
            else
                prints[#prints + 1] = msg
            end
        end,
        On = function() end,
        _prints = prints,
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns:UnitKey()
        return "Runner-Realm"
    end

function ns.Database:IsBankCharacter()
    return false
end

function ns.Database:AccountIdForCharacter()
    return nil
end

    assert(loadfile("Core/Vendor.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/Pricing.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/Requests.lua"))("WoWRoguelite", ns)
    return ns
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function testMailFallbackSubjectUsesRewardCsv()
    local ns = resetHarness()

    local subject = ns.Requests:MailFallbackSubject({ 201, 101, 301 })

    assertEqual(subject, "WRL-REQ: 101,201,301", "mail fallback subject sorts reward IDs")
end

local function testOutgoingRequestKeepsMailFallbackSubject()
    local ns = resetHarness()

    local id = ns.Requests:EnqueueOutgoing("Bank-Realm", { 301, 101 }, "")

    assertEqual(WRL_CharDB.outgoing[1].id, id, "outgoing request is stored")
    assertEqual(WRL_CharDB.outgoing[1].mailSubject, "WRL-REQ: 101,301", "outgoing request stores fallback subject")
end

local function testMailFallbackBodyNamesRequesterAndRewards()
    local ns = resetHarness()

    local body = ns.Requests:MailFallbackBody("Bank-Realm", { 301, 101 }, "")

    if not body:find("Requester: Runner%-Realm") then
        error("mail fallback body includes requester")
    end
    if not body:find("Rewards: 101, 301") then
        error("mail fallback body includes sorted rewards")
    end
end

local function testBeginMailFallbackPrefillsMailbox()
    local ns = resetHarness()
    local fields = {}
    MailFrame = { IsShown = function() return true end }
    MailFrameTab2 = { Click = function() fields.clickedSendTab = true end }
    SendMailNameEditBox = { SetText = function(_, value) fields.name = value end }
    SendMailSubjectEditBox = { SetText = function(_, value) fields.subject = value end }
    SendMailBodyEditBox = { SetText = function(_, value) fields.body = value end }

    local ok = ns.Requests:BeginMailFallback("Bank-Realm", { 301, 101 }, "")

    assertEqual(ok, true, "mail fallback starts when mailbox is open")
    assertEqual(fields.clickedSendTab, true, "mail fallback switches to send tab")
    assertEqual(fields.name, "Bank", "mail fallback uses same-realm bank recipient")
    assertEqual(fields.subject, "WRL-REQ: 101,301", "mail fallback pre-fills import subject")
    if not fields.body or not fields.body:find("Requester: Runner%-Realm") then
        error("mail fallback pre-fills request body")
    end
end

local function testFulfillmentMailUsesBankerFlavorAndRewardDetails()
    local ns = resetHarness()
    ns.Tiers = { FormatMoney = function(_, copper) return tostring(copper) .. "c" end }
    ns.Rewards = {
        BuildRewardForTierIds = function()
            return { gold = 1234, extraLives = 1, items = { { id = 101, qty = 2, note = "linen bag" } } }
        end,
    }

    local req = { from = "Runner-Realm", tierIds = { 201, 101 } }
    local subject = ns.Requests:FulfillmentMailSubject(req)
    local body = ns.Requests:FulfillmentMailBody(req)

    assertEqual(subject, "Roguelite bank release", "fulfillment mail has banker release subject")
    if not body:find("Withdrawal approved", 1, true) then
        error("fulfillment mail opens with banker flavor")
    end
    if not body:find("Rewards: 101, 201", 1, true) then
        error("fulfillment mail preserves sorted reward details")
    end
    if not body:find("Gold released: 1234c", 1, true) then
        error("fulfillment mail preserves gold details")
    end
    if not body:find("Here are the items you requested", 1, true) then
        error("fulfillment mail introduces requested items in character")
    end
    if not body:find("- 2x item:101 (linen bag)", 1, true) then
        error("fulfillment mail lists requested item details")
    end
    if not body:find("Please try not to make the paperwork look heroic.", 1, true) then
        error("fulfillment mail includes dry banker snark")
    end
end

local function testBeginMailFulfillmentPrefillsBankDeskMailAndMarksGathering()
    local ns = resetHarness()
    ns.Tiers = { FormatMoney = function(_, copper) return tostring(copper) .. "c" end }
    ns.Rewards = {
        BuildRewardForTierIds = function()
            return { gold = 1200, extraLives = 0, items = { { id = 101, qty = 2, note = "thread" } } }
        end,
    }
    ns.Container = {
        GetNumSlots = function() return 0 end,
        GetItemInfo = function() return nil end,
    }
    WRL_DB.requests[1] = { id = "req-1", from = "Graham-Realm", tierIds = { 101 }, status = "pending" }

    local fields = {}
    MailFrame = { IsShown = function() return true end }
    MailFrameTab2 = { Click = function() fields.clickedSendTab = true end }
    SendMailNameEditBox = { SetText = function(_, value) fields.name = value end }
    SendMailSubjectEditBox = { SetText = function(_, value) fields.subject = value end }
    SendMailBodyEditBox = { SetText = function(_, value) fields.body = value end }
    SendMailMoney = {}
    MoneyInputFrame_SetCopper = function(frame, copper)
        fields.moneyFrame = frame
        fields.copper = copper
    end

    local ok = ns.Requests:BeginMailFulfillment("req-1")

    assertEqual(ok, true, "bank desk mail prep reports success")
    assertEqual(fields.clickedSendTab, true, "mail prep switches to send tab")
    assertEqual(fields.name, "Graham", "mail prep strips same-realm recipient")
    assertEqual(fields.subject, "Roguelite bank release", "mail prep fills banker subject")
    assertEqual(fields.copper, 1200, "mail prep fills requested gold")
    assertEqual(WRL_DB.requests[1].status, "gathering", "mail prep marks request as preparing")
    assertEqual(WRL_DB.requests[1]._fulfillmentMethod, "mail", "mail prep stores fulfillment method")
end

local function testBeginMailFulfillmentRetriesBodyAfterSendTabSwitch()
    local ns = resetHarness()
    ns.Tiers = { FormatMoney = function(_, copper) return tostring(copper) .. "c" end }
    ns.Rewards = {
        BuildRewardForTierIds = function()
            return { gold = 0, extraLives = 0, items = { { id = 101, qty = 1, note = "pouch" } } }
        end,
    }
    ns.Container = {
        GetNumSlots = function() return 0 end,
        GetItemInfo = function() return nil end,
    }
    WRL_DB.requests[1] = { id = "req-1", from = "Tester-Realm", tierIds = { 101 }, status = "pending" }

    local delayed = nil
    local fields = {}
    MailFrame = { IsShown = function() return true end }
    MailFrameTab2 = { Click = function() fields.clickedSendTab = true end }
    SendMailNameEditBox = { SetText = function(_, value) fields.name = value end }
    SendMailSubjectEditBox = { SetText = function(_, value) fields.subject = value end }
    SendMailBodyEditBox = nil
    C_Timer = {
        After = function(_, callback)
            delayed = callback
        end,
    }

    local ok = ns.Requests:BeginMailFulfillment("req-1")
    SendMailBodyEditBox = { SetText = function(_, value) fields.body = value end }
    delayed()

    assertEqual(ok, true, "mail prep still succeeds when body field appears after tab switch")
    if not fields.body or not fields.body:find("Here are the items you requested", 1, true) then
        error("mail prep retries body text after send tab switch")
    end
end

local function testFulfillmentMailAndChatUseAvailableMissingChecklist()
    local ns = resetHarness()
    ns.Tiers = { FormatMoney = function(_, copper) return tostring(copper) .. "c" end }
    ns.Rewards = {
        BuildRewardForTierIds = function()
            return {
                gold = 1200,
                extraLives = 0,
                items = {
                    { id = 101, qty = 2, note = "thread" },
                    { id = 202, qty = 3, note = "potion" },
                },
            }
        end,
    }
    ns.Container = {
        GetNumSlots = function() return 2 end,
        GetItemInfo = function(_, bag, slot)
            if bag == 0 and slot == 1 then return { itemID = 101, count = 1 } end
            if bag == 0 and slot == 2 then return { itemID = 202, count = 3 } end
            return nil
        end,
    }
    _G.GetMoney = function() return 500 end
    WRL_DB.requests[1] = { id = "req-1", from = "Graham-Realm", tierIds = { 101 }, status = "pending" }

    local fields = {}
    MailFrame = { IsShown = function() return true end }
    MailFrameTab2 = { Click = function() fields.clickedSendTab = true end }
    SendMailNameEditBox = { SetText = function(_, value) fields.name = value end }
    SendMailSubjectEditBox = { SetText = function(_, value) fields.subject = value end }
    SendMailBodyEditBox = { SetText = function(_, value) fields.body = value end }
    SendMailMoney = {}
    MoneyInputFrame_SetCopper = function(_, copper) fields.copper = copper end

    local ok = ns.Requests:BeginMailFulfillment("req-1")

    assertEqual(ok, true, "mail prep succeeds")
    if not fields.body or not fields.body:find("Item checklist", 1, true) then
        error("fulfillment mail body includes an item checklist")
    end
    if not fields.body:find("item:101 (thread): available 1 / requested 2 / missing 1", 1, true) then
        error("fulfillment mail body lists missing item availability")
    end
    if not fields.body:find("item:202 (potion): available 3 / requested 3 / ready", 1, true) then
        error("fulfillment mail body lists ready item availability")
    end

    local joined = table.concat(ns._prints, "\n")
    if not joined:find("Checklist for Graham%-Realm", 1, false) then
        error("chat feedback starts a request checklist")
    end
    if not joined:find("item:101 %(thread%): available 1 / requested 2 / missing 1") then
        error("chat feedback includes missing item counts")
    end
    if not joined:find("item:202 %(potion%): available 3 / requested 3 / ready") then
        error("chat feedback includes ready item counts")
    end
    if not joined:find("Gold: available 500c / requested 1200c / missing 700c") then
        error("chat feedback includes gold availability counts")
    end
end

local function testReadinessIncludesOptionalPricingAndTailorHints()
    local ns = resetHarness()
    ns.Tiers = { FormatMoney = function(_, copper) return tostring(copper) .. "c" end }
    ns.Rewards = {
        BuildRewardForTierIds = function()
            return {
                gold = 0,
                extraLives = 0,
                items = {
                    { id = 4496, qty = 1, note = "small brown pouch" },
                    { id = 202, qty = 2, note = "training stone" },
                },
            }
        end,
    }
    ns.Container = {
        GetNumSlots = function() return 0 end,
        GetItemInfo = function() return nil end,
    }
    _G.GetMoney = function() return 0 end
    _G.GetItemInfo = function(itemId)
        if tonumber(itemId) == 4496 then return "Small Brown Pouch" end
        if tonumber(itemId) == 202 then return "Training Stone" end
    end
    _G.TSM_API = {
        GetCustomPriceValue = function(source, itemString)
            if source == "DBMarket" and itemString == "i:4496" then return 1234 end
        end,
    }
    WRL_DB.requests[1] = { id = "req-1", from = "Graham-Realm", tierIds = { 101 }, status = "pending" }

    local readiness = ns.Requests:FulfillmentReadiness(WRL_DB.requests[1])
    assertEqual(readiness.items[1].marketCopper, 1234, "readiness stores optional TSM market value")
    assertEqual(readiness.items[1].marketLabel, "TSM DBMarket", "readiness labels TSM market source")
    assertEqual(readiness.items[1].craftHint, "tailor-made", "known starter bag gets tailor hint")
    assertEqual(readiness.items[2].marketCopper, nil, "missing TSM values stay optional")

    local lines = table.concat(ns.Requests:ReadinessItemLines(readiness, { prefix = "" }), "\n")
    if not lines:find("Small Brown Pouch %(small brown pouch%): available 0 / requested 1 / missing 1 %(tailor%-made; TSM DBMarket 1234c%)") then
        error("readiness item lines should include tailor and TSM hints")
    end
    if not lines:find("Training Stone %(training stone%): available 0 / requested 2 / missing 2") then
        error("readiness item lines should keep normal items readable")
    end
end

local function testRequestInventoryScansUseCContainerFallback()
    local ns = resetHarness()
    NUM_BAG_SLOTS = 0
    C_Container = {
        GetContainerNumSlots = function(bag)
            return bag == 0 and 2 or 0
        end,
        GetContainerItemInfo = function(bag, slot)
            if bag == 0 and slot == 1 then
                return {
                    stackCount = 3,
                    hyperlink = "|cffffffff|Hitem:101::::::::|h[Test Cloth]|h|r",
                    itemID = 101,
                }
            elseif bag == 0 and slot == 2 then
                return {
                    quantity = 1,
                    itemLink = "|cffffffff|Hitem:202::::::::|h[Test Stone]|h|r",
                }
            end
        end,
    }

    assertEqual(ns.Requests:CountItemInBags(101), 3,
        "request inventory count uses C_Container table result")
    assertEqual(ns.Requests:CountItemInBags(202), 1,
        "request inventory count parses item id from C_Container link")

    local bag, slot, count = ns.Requests:FindItemInBags(101)
    assertEqual(bag, 0, "request inventory find returns C_Container bag")
    assertEqual(slot, 1, "request inventory find returns C_Container slot")
    assertEqual(count, 3, "request inventory find returns C_Container stack count")
end

testMailFallbackSubjectUsesRewardCsv()
testOutgoingRequestKeepsMailFallbackSubject()
testMailFallbackBodyNamesRequesterAndRewards()
testBeginMailFallbackPrefillsMailbox()
testFulfillmentMailUsesBankerFlavorAndRewardDetails()
testBeginMailFulfillmentPrefillsBankDeskMailAndMarksGathering()
testBeginMailFulfillmentRetriesBodyAfterSendTabSwitch()
testFulfillmentMailAndChatUseAvailableMissingChecklist()
testReadinessIncludesOptionalPricingAndTailorHints()
testRequestInventoryScansUseCContainerFallback()

print("RequestMailFallback.test.lua: ok")
