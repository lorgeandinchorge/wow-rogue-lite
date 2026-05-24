local currentMoney = 0
local currentBagValue = 0
local currentGearValue = 0

local function resetHarness()
    WRL_DB = {
        _receiptSeq = 0,
        contributionReceipts = {},
        totalContributed = 0,
        characters = {
            ["Runner-Realm"] = {
                key = "Runner-Realm",
                contributed = 0,
                history = {},
                deathSnapshot = {
                    at = 100,
                    preMoney = 1000,
                    estimatedBagValue = 500,
                    estimatedGearValue = 0,
                    totalLiquid = 1500,
                    maximumPotential = 1500,
                    bagItems = {
                        { link = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r", count = 4, copper = 40, sellPrice = 10 },
                    },
                    gearItems = {
                        { link = "|cff9d9d9d|Hitem:25::::::::|h[Worn Shortsword]|h|r", count = 1, copper = 70, sellPrice = 70 },
                    },
                    credited = false,
                },
                _pendingContribution = 1500,
            },
        },
    }

    currentMoney = 250
    currentBagValue = 500
    currentGearValue = 0

    _G.time = function() return 12345 end
    _G.GetMoney = function() return currentMoney end

    local ns = {
        Achievements = nil,
        Database = {},
        Vendor = {},
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns.Database:GetCharacter(key)
        return WRL_DB.characters[key]
    end

    function ns.Vendor:FullCharacterSnapshot()
        return {
            money = currentMoney,
            bagValue = currentBagValue,
            gearValue = currentGearValue,
            bagItems = {},
            gearItems = {},
        }
    end

    function ns.Vendor:BagsSnapshot()
        return currentBagValue
    end

    function ns.Vendor:EquipmentSnapshot()
        return currentGearValue
    end

    local chunk = assert(loadfile("Core/Contributions.lua"))
    chunk("WoWRoguelite", ns)
    return ns.Contributions
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function testUnsentBagValueIsNotCredited()
    local contributions = resetHarness()

    currentMoney = 250
    currentBagValue = 500
    local receipt = contributions:CreditFinalDeath("Runner-Realm")

    assertEqual(receipt.amount, 750, "credits only money delta when bag value is unchanged")
    assertEqual(WRL_DB.totalContributed, 750, "lifetime total matches tightened credit")
end

local function testBagValueDeltaIsCredited()
    local contributions = resetHarness()

    currentMoney = 250
    currentBagValue = 200
    local receipt = contributions:CreditFinalDeath("Runner-Realm")

    assertEqual(receipt.amount, 1050, "credits money delta plus removed bag value")
    assertEqual(receipt.postEstimatedBagValue, 200, "receipt records post-mail bag value")
end

local function testFinalDeathReceiptPreservesCapturedItemValues()
    local contributions = resetHarness()

    currentMoney = 250
    currentBagValue = 200
    currentGearValue = 0
    local receipt = contributions:CreditFinalDeath("Runner-Realm")

    assertEqual(receipt.bagItems[1].link, "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r", "receipt preserves captured bag item link")
    assertEqual(receipt.bagItems[1].copper, 40, "receipt preserves captured bag item vendor value")
    assertEqual(receipt.gearItems[1].link, "|cff9d9d9d|Hitem:25::::::::|h[Worn Shortsword]|h|r", "receipt preserves captured gear item link")
    assertEqual(receipt.gearItems[1].copper, 70, "receipt preserves captured gear item vendor value")
end

local function testSoldGearValueCanBeCreditedUpToMaximumPotential()
    local contributions = resetHarness()
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.deathSnapshot.estimatedGearValue = 700
    rec.deathSnapshot.maximumPotential = 2200

    currentMoney = 0
    currentBagValue = 0
    currentGearValue = 700
    local receipt = contributions:CreditFinalDeath("Runner-Realm")

    assertEqual(receipt.amount, 1500, "credits money and bag value when gear is not sold")

    contributions = resetHarness()
    rec = WRL_DB.characters["Runner-Realm"]
    rec.deathSnapshot.estimatedGearValue = 700
    rec.deathSnapshot.maximumPotential = 2200
    currentBagValue = 0
    currentGearValue = 0
    currentMoney = 0

    receipt = contributions:CreditFinalDeath("Runner-Realm")

    assertEqual(receipt.amount, 2200, "sold gear proceeds can credit up to maximum potential")
end

local function testSnapshotDeathSubtractsMailPostageFromMaximumPotential()
    local contributions = resetHarness()
    currentMoney = 100
    currentBagValue = 20
    currentGearValue = 10

    local snap = contributions:SnapshotDeath("Runner-Realm")

    assertEqual(snap.preMoney, 100, "snapshot keeps gross carried money")
    assertEqual(snap.estimatedBagValue, 20, "snapshot keeps gross bag value")
    assertEqual(snap.estimatedGearValue, 10, "snapshot keeps gross gear value")
    assertEqual(snap.totalLiquid, 120, "snapshot keeps gross liquid value")
    assertEqual(snap.maximumPotential, 100, "maximum potential is net of 30c postage")
end

local function testSnapshotDeathDoesNotGoNegativeAfterPostage()
    local contributions = resetHarness()
    currentMoney = 10
    currentBagValue = 10
    currentGearValue = 5

    local snap = contributions:SnapshotDeath("Runner-Realm")

    assertEqual(snap.maximumPotential, 0, "maximum potential floors at zero after postage")
end

testUnsentBagValueIsNotCredited()
testBagValueDeltaIsCredited()
testFinalDeathReceiptPreservesCapturedItemValues()
testSoldGearValueCanBeCreditedUpToMaximumPotential()
testSnapshotDeathSubtractsMailPostageFromMaximumPotential()
testSnapshotDeathDoesNotGoNegativeAfterPostage()

print("ContributionsCredit.test.lua: ok")
