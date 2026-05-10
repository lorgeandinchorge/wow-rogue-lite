local inventoryLinks = {}
local bagItems = {}
local sellPrices = {}
local currentMoney = 111

local function resetHarness()
    inventoryLinks = {
        [1] = "|cff9d9d9d|Hitem:100::::::::|h[Old Hat]|h|r",
        [16] = "|cff1eff00|Hitem:200::::::::|h[Green Axe]|h|r",
        [19] = nil,
    }
    bagItems = {
        [0] = {
            [1] = { count = 2, link = "|cffffffff|Hitem:300::::::::|h[Linen Cloth]|h|r", hasNoValue = false },
            [2] = { count = 1, link = "|cffffffff|Hitem:400::::::::|h[Quest Thing]|h|r", hasNoValue = true },
        },
    }
    sellPrices = {
        ["|cff9d9d9d|Hitem:100::::::::|h[Old Hat]|h|r"] = 25,
        ["|cff1eff00|Hitem:200::::::::|h[Green Axe]|h|r"] = 500,
        ["|cffffffff|Hitem:300::::::::|h[Linen Cloth]|h|r"] = 3,
    }
    currentMoney = 111

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
        return nil, item.count, nil, nil, nil, nil, item.link, nil, item.hasNoValue
    end
    _G.GetInventoryItemLink = function(_, slot) return inventoryLinks[slot] end
    _G.GetItemInfo = function(link)
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, sellPrices[link] or 0
    end

    local ns = {}
    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    assert(loadfile("Core/Vendor.lua"))("WoWRoguelite", ns)
    return ns.Vendor
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function testEquipmentSnapshotAddsVendorableGear()
    local vendor = resetHarness()

    local total, items = vendor:EquipmentSnapshot()

    assertEqual(total, 525, "equipment total includes all vendorable equipped gear")
    assertEqual(#items, 2, "equipment item list includes vendorable equipped gear")
    assertEqual(items[1].slot, 1, "equipment entries record inventory slot")
    assertEqual(items[2].slot, 16, "equipment scan includes weapon slot")
end

local function testFullCharacterSnapshotSeparatesMoneyBagsGearAndPotential()
    local vendor = resetHarness()

    local snap = vendor:FullCharacterSnapshot()

    assertEqual(snap.money, 111, "snapshot records current money")
    assertEqual(snap.bagValue, 6, "snapshot records bag vendor value")
    assertEqual(snap.gearValue, 525, "snapshot records equipped gear vendor value")
    assertEqual(snap.maximumPotential, 642, "maximum potential includes money, bags, and gear")
end

testEquipmentSnapshotAddsVendorableGear()
testFullCharacterSnapshotSeparatesMoneyBagsGearAndPotential()

print("VendorSnapshot.test.lua: ok")
