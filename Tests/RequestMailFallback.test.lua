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
    _G.NUM_BAG_SLOTS = nil
    _G.GetContainerNumSlots = nil
    _G.GetContainerItemInfo = nil
    _G.C_Container = nil

    local ns = {
        Database = {},
        Debug = function() end,
        Print = function() end,
        On = function() end,
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

    assert(loadfile("Core/Vendor.lua"))("WoWRoguelite", ns)
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
testRequestInventoryScansUseCContainerFallback()

print("RequestMailFallback.test.lua: ok")
