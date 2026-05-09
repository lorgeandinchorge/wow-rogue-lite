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
    assertEqual(bundle.gold, 30000, "stipend rank 1 grants 3g")
    assertEqual(bundle.extraLives, 1, "fate rank 1 grants one life")
    assertEqual(#bundle.items, 2, "storage ranks merge two bag item types")
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
testResetUnlocksRefundsBudget()
testFateMilestonesUseRankThreeAndSixCosts()

print("LegacyUnlocks.test.lua: ok")
