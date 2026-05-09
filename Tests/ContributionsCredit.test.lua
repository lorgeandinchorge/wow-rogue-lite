local currentMoney = 0
local currentBagValue = 0

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
                    totalLiquid = 1500,
                    credited = false,
                },
                _pendingContribution = 1500,
            },
        },
    }

    currentMoney = 250
    currentBagValue = 500

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

    function ns.Vendor:BagsSnapshot()
        return currentBagValue
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

testUnsentBagValueIsNotCredited()
testBagValueDeltaIsCredited()

print("ContributionsCredit.test.lua: ok")
