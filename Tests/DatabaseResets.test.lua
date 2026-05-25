local function resetHarness()
    WRL_DB = {
        characters = {
            ["Runner-Realm"] = {
                key = "Runner-Realm",
                contributed = 25000,
            },
            ["Other-Realm"] = {
                key = "Other-Realm",
                contributed = 12500,
            },
        },
        achievements = {
            reach_level_10 = { when = 10, characterKey = "Runner-Realm" },
        },
        legacyUnlocks = {
            storage = 2,
            stipend = 1,
        },
        legacySpent = 130000,
        totalContributed = 37500,
        contributionReceipts = {
            { id = "c1", amount = 25000 },
        },
        fulfillmentReceipts = {
            { id = "f1" },
        },
        resaleReceipts = {
            { id = "r1", amount = 5000 },
        },
        loanReceipts = {
            { id = "l1", amount = 10000 },
        },
        memorials = {
            ["Runner-Realm#1"] = { characterKey = "Runner-Realm" },
        },
        requests = {
            { id = "req1" },
        },
        settings = {
            uiTheme = "classic",
        },
    }

    local ns = {}
    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end
    function ns:UnitKey() return "Runner-Realm" end
    function ns:Debug() end
    function ns:Print() end

    _G.GetRealmName = function() return "Realm" end
    _G.UnitLevel = function() return 20 end
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    _G.UnitRace = function() return "Human", "Human" end
    _G.UnitGUID = function() return "Player-1" end
    _G.time = function() return 12345 end

    assert(loadfile("Core/Database.lua"))("WoWRoguelite", ns)
    return ns.Database
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertNil(value, message)
    if value ~= nil then error(message .. ": expected nil", 2) end
end

local function assertTrue(value, message)
    if not value then error(message .. ": expected truthy value", 2) end
end

local function testResetAchievementsOnlyClearsAchievementLedger()
    local db = resetHarness()

    db:ResetAchievements()

    assertEqual(next(WRL_DB.achievements), nil, "achievement ledger cleared")
    assertEqual(WRL_DB.totalContributed, 37500, "contribution total retained")
    assertEqual(#WRL_DB.contributionReceipts, 1, "contribution receipts retained")
    assertEqual(WRL_DB.legacyUnlocks.storage, 2, "legacy unlocks retained")
    assertTrue(WRL_DB.memorials["Runner-Realm#1"], "memorials retained")
end

local function testResetLegacyProgressionKeepsEconomyLedger()
    local db = resetHarness()

    db:ResetLegacyProgression()

    assertEqual(next(WRL_DB.legacyUnlocks), nil, "legacy unlocks cleared")
    assertEqual(WRL_DB.legacySpent, 0, "legacy spend cleared")
    assertEqual(WRL_DB.totalContributed, 37500, "contribution total retained")
    assertEqual(#WRL_DB.contributionReceipts, 1, "contribution receipts retained")
    assertTrue(WRL_DB.achievements.reach_level_10, "achievements retained")
end

local function testResetLedgerEconomyClearsReceiptsTotalsAndDependentLegacy()
    local db = resetHarness()

    db:ResetLedgerEconomy()

    assertEqual(WRL_DB.totalContributed, 0, "total contribution cleared")
    assertEqual(#WRL_DB.contributionReceipts, 0, "contribution receipts cleared")
    assertEqual(#WRL_DB.fulfillmentReceipts, 0, "fulfillment receipts cleared")
    assertEqual(#WRL_DB.resaleReceipts, 0, "resale receipts cleared")
    assertEqual(#WRL_DB.loanReceipts, 0, "loan receipts cleared")
    assertEqual(WRL_DB.characters["Runner-Realm"].contributed, 0, "runner contribution total cleared")
    assertEqual(WRL_DB.characters["Other-Realm"].contributed, 0, "other contribution total cleared")
    assertEqual(next(WRL_DB.legacyUnlocks), nil, "dependent legacy unlocks cleared")
    assertEqual(WRL_DB.legacySpent, 0, "dependent legacy spend cleared")
    assertTrue(WRL_DB.achievements.reach_level_10, "achievements retained")
    assertTrue(WRL_DB.memorials["Runner-Realm#1"], "memorials retained")
    assertEqual(#WRL_DB.requests, 1, "requests retained")
    assertEqual(WRL_DB.settings.uiTheme, "classic", "settings retained")
end

testResetAchievementsOnlyClearsAchievementLedger()
testResetLegacyProgressionKeepsEconomyLedger()
testResetLedgerEconomyClearsReceiptsTotalsAndDependentLegacy()

print("DatabaseResets.test.lua: ok")
