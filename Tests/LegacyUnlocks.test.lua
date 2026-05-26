local function resetHarness()
    WRL_DB = {
        schema = 10,
        totalContributed = 0,
        legacyUnlocks = nil,
        legacySpent = nil,
        settings = {},
        characters = {},
    }

    _G.time = function() return 12345 end
    _G.GetRealmName = function() return "Realm" end
    _G.UnitName = function() return "Runner", nil end
    _G.UnitLevel = function() return 1 end
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    _G.UnitRace = function() return "Human", "HUMAN" end

    local ns = {
        Database = {},
        Debug = function() end,
        Print = function() end,
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns:UnitKey()
        return "Runner-Realm"
    end

    assert(loadfile("Core/Database.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/LegacyUnlocks.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/Rewards.lua"))("WoWRoguelite", ns)

    ns.Database:Init()
    ns.LegacyUnlocks:Init()
    return ns
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message .. ": expected truthy value", 2)
    end
end

local function assertFalse(value, message)
    if value then
        error(message .. ": expected falsey value", 2)
    end
end

local function testDefaultsStartUnspent()
    local ns = resetHarness()

    assertEqual(ns.LegacyUnlocks:GetRank("storage"), 0, "storage starts locked")
    assertEqual(ns.LegacyUnlocks:GetRank("stipend"), 0, "stipend starts locked")
    assertEqual(ns.LegacyUnlocks:GetRank("alchemy"), 0, "alchemy starts locked")
    assertEqual(ns.LegacyUnlocks:GetRank("fate"), 0, "fate starts locked")
    assertEqual(ns.LegacyUnlocks:Spent(), 0, "legacy spent starts at zero")
    assertEqual(ns.LegacyUnlocks:AvailableBudget(), 0, "available budget starts at zero")
end

local function testUnlockSpendsBudgetAndRequiresSequentialRanks()
    local ns = resetHarness()
    WRL_DB.totalContributed = 130000

    local ok, reason = ns.LegacyUnlocks:Unlock("storage")
    assertTrue(ok, "storage rank 1 unlock succeeds")
    assertEqual(reason, nil, "storage rank 1 has no failure reason")
    assertEqual(ns.LegacyUnlocks:GetRank("storage"), 1, "storage rank increments to one")
    assertEqual(ns.LegacyUnlocks:Spent(), 30000, "rank 1 cost is spent")
    assertEqual(ns.LegacyUnlocks:AvailableBudget(), 100000, "remaining budget is total minus spent")

    ok = ns.LegacyUnlocks:Unlock("storage")
    assertTrue(ok, "storage rank 2 unlock succeeds")
    assertEqual(ns.LegacyUnlocks:GetRank("storage"), 2, "storage rank increments to two")
    assertEqual(ns.LegacyUnlocks:Spent(), 130000, "rank 1 and 2 costs are cumulative")
    assertEqual(ns.LegacyUnlocks:AvailableBudget(), 0, "all contributed budget is spent")

    ok, reason = ns.LegacyUnlocks:Unlock("stipend")
    assertFalse(ok, "stipend rank 1 cannot unlock without available budget")
    assertEqual(reason, "insufficient_budget", "overspend failure reason")
end

local function testCanGoBackToAnotherTrackWhenBudgetArrives()
    local ns = resetHarness()
    WRL_DB.totalContributed = 160000

    assertTrue(ns.LegacyUnlocks:Unlock("storage"), "storage rank 1 unlocks")
    assertTrue(ns.LegacyUnlocks:Unlock("storage"), "storage rank 2 unlocks")
    assertTrue(ns.LegacyUnlocks:Unlock("stipend"), "stipend rank 1 unlocks after more budget")

    assertEqual(ns.LegacyUnlocks:GetRank("storage"), 2, "storage remains rank two")
    assertEqual(ns.LegacyUnlocks:GetRank("stipend"), 1, "stipend rank one unlocks independently")
    assertEqual(ns.LegacyUnlocks:Spent(), 160000, "spent includes both tracks")
end

local function testActiveNodeIdsAndRewardsReflectUnlockedTracks()
    local ns = resetHarness()
    WRL_DB.totalContributed = 2000000

    assertTrue(ns.LegacyUnlocks:Unlock("storage"), "storage rank 1 unlocks")
    assertTrue(ns.LegacyUnlocks:Unlock("storage"), "storage rank 2 unlocks")
    assertTrue(ns.LegacyUnlocks:Unlock("stipend"), "stipend rank 1 unlocks")
    assertTrue(ns.LegacyUnlocks:Unlock("fate"), "fate rank 1 unlocks")

    local nodeIds = ns.LegacyUnlocks:ActiveNodeIds()
    assertEqual(#nodeIds, 4, "four active nodes")
    assertEqual(nodeIds[1], 101, "storage node 1 first")
    assertEqual(nodeIds[2], 102, "storage node 2 second")
    assertEqual(nodeIds[3], 201, "stipend node 1 third")
    assertEqual(nodeIds[4], 301, "fate node 1 fourth")

    local bundle = ns.Rewards:BuildRewardForTierIds(nodeIds, "Runner-Realm")
    assertEqual(bundle.gold, 10000, "stipend rank 1 grants 1g")
    assertEqual(bundle.extraLives, 1, "fate rank 1 grants one life")
    assertEqual(#bundle.items, 2, "storage ranks merge two bag item types")
end

local function testStipendBundlesMatchLegacyPassValues()
    local ns = resetHarness()
    local expected = {
        stipend_1 = 10000,
        stipend_2 = 50000,
        stipend_3 = 100000,
        stipend_4 = 250000,
        stipend_5 = 1000000,
        stipend_6 = 3500000,
    }

    for bundleId, expectedGold in pairs(expected) do
        local bundle = ns.Rewards:GetBundle(bundleId)
        assertEqual(bundle.gold, expectedGold, bundleId .. " gold matches 0.4 stipend values")
        assertEqual(#bundle.items, 0, bundleId .. " remains gold-only")
        assertEqual(bundle.extraLives, 0, bundleId .. " does not grant lives")
    end
end

local function testAlchemistsTableUnlocksPotionRanks()
    local ns = resetHarness()
    WRL_DB.totalContributed = 130000

    local track = ns.LegacyUnlocks:TrackDef("alchemy")
    assertTrue(track, "alchemy track exists")
    assertEqual(track.name, "Alchemist's Table", "alchemy track has user-facing name")
    assertEqual(ns.LegacyUnlocks:MaxRank("alchemy"), 6, "alchemy has six ranks")

    assertTrue(ns.LegacyUnlocks:Unlock("alchemy"), "alchemy rank 1 unlocks")
    assertTrue(ns.LegacyUnlocks:Unlock("alchemy"), "alchemy rank 2 unlocks")
    assertEqual(ns.LegacyUnlocks:GetRank("alchemy"), 2, "alchemy rank increments independently")
    assertEqual(ns.LegacyUnlocks:Spent(), 130000, "alchemy uses the standard rank cost ladder")

    local nodeIds = ns.LegacyUnlocks:ActiveNodeIds()
    assertEqual(nodeIds[1], 401, "alchemy rank 1 node is active")
    assertEqual(nodeIds[2], 402, "alchemy rank 2 node is active")

    local bundle = ns.Rewards:BuildRewardForTierIds(nodeIds, "Runner-Realm")
    assertEqual(#bundle.items, 2, "two potion types are merged from two ranks")
    assertEqual(bundle.items[1].id, 118, "rank 1 grants Minor Healing Potion")
    assertEqual(bundle.items[1].qty, 2, "rank 1 grants two potions")
    assertEqual(bundle.items[2].id, 858, "rank 2 grants Lesser Healing Potion")
    assertEqual(bundle.items[2].qty, 2, "rank 2 grants two potions")
    assertEqual(bundle.gold, 0, "alchemy grants no gold")
    assertEqual(bundle.extraLives, 0, "alchemy grants no lives")
end

local function testAlchemistsTableBundlesUsePotionProgression()
    local ns = resetHarness()
    local expected = {
        { id = "alchemy_1", itemId = 118,   note = "Minor Healing Potion" },
        { id = "alchemy_2", itemId = 858,   note = "Lesser Healing Potion" },
        { id = "alchemy_3", itemId = 929,   note = "Healing Potion" },
        { id = "alchemy_4", itemId = 1710,  note = "Greater Healing Potion" },
        { id = "alchemy_5", itemId = 3928,  note = "Superior Healing Potion" },
        { id = "alchemy_6", itemId = 22829, note = "Super Healing Potion" },
    }

    for _, spec in ipairs(expected) do
        local bundle = ns.Rewards:GetBundle(spec.id)
        assertEqual(#bundle.items, 1, spec.id .. " has one potion item")
        assertEqual(bundle.items[1].id, spec.itemId, spec.id .. " item id matches potion ladder")
        assertEqual(bundle.items[1].qty, 2, spec.id .. " grants two potions")
        assertEqual(bundle.items[1].note, spec.note, spec.id .. " note names the potion")
        assertEqual(bundle.gold, 0, spec.id .. " grants no gold")
        assertEqual(bundle.extraLives, 0, spec.id .. " grants no lives")
    end
end

local function testResetUnlocksRefundsBudget()
    local ns = resetHarness()
    WRL_DB.totalContributed = 130000

    assertTrue(ns.LegacyUnlocks:Unlock("storage"), "storage rank 1 unlocks")
    assertTrue(ns.LegacyUnlocks:Unlock("storage"), "storage rank 2 unlocks")
    ns.LegacyUnlocks:ResetUnlocks()

    assertEqual(ns.LegacyUnlocks:GetRank("storage"), 0, "storage reset")
    assertEqual(ns.LegacyUnlocks:Spent(), 0, "spent reset")
    assertEqual(ns.LegacyUnlocks:AvailableBudget(), 130000, "budget becomes available again")
end

local function testFateMilestonesUseRankThreeAndSixCosts()
    local ns = resetHarness()
    local fate = ns.LegacyUnlocks:TrackDef("fate")

    assertEqual(fate.nodes[1].milestone, 3, "first fate node displays at tier three")
    assertEqual(fate.nodes[1].cost, 250000, "first fate node costs 25g")
    assertEqual(fate.nodes[2].milestone, 6, "second fate node displays at tier six")
    assertEqual(fate.nodes[2].cost, 7500000, "second fate node costs 750g")
end

testDefaultsStartUnspent()
testUnlockSpendsBudgetAndRequiresSequentialRanks()
testCanGoBackToAnotherTrackWhenBudgetArrives()
testActiveNodeIdsAndRewardsReflectUnlockedTracks()
testStipendBundlesMatchLegacyPassValues()
testAlchemistsTableUnlocksPotionRanks()
testAlchemistsTableBundlesUsePotionProgression()
testResetUnlocksRefundsBudget()
testFateMilestonesUseRankThreeAndSixCosts()

print("LegacyUnlocks.test.lua: ok")
