local function resetHarness(state, totalContributed)
    WRL_DB = {
        achievements = {},
        totalContributed = totalContributed or 0,
        characters = {
            ["Runner-Realm"] = {
                key = "Runner-Realm",
                status = state or "active",
                levelCurrent = 20,
                ruleLog = {},
            },
        },
    }

    _G.time = function() return 12345 end

    local ns = {
        Database = {},
        Run = {},
        Tiers = {},
        printed = {},
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns:UnitKey() return "Runner-Realm" end
    function ns:Print(...) self.printed[#self.printed + 1] = string.format(...) end

    function ns.Database:GetCharacter(key) return WRL_DB.characters[key] end
    function ns.Database:GetAchievements() return WRL_DB.achievements end
    function ns.Database:GetAchievement(id) return WRL_DB.achievements[id] end
    function ns.Database:HasAchievement(id) return WRL_DB.achievements[id] ~= nil end
    function ns.Database:EarnAchievement(id, characterKey)
        if WRL_DB.achievements[id] then return nil end
        local entry = { when = time(), characterKey = characterKey }
        WRL_DB.achievements[id] = entry
        return entry
    end
    function ns.Database:IsBankCharacter() return false end

    function ns.Run:GetState(recOrKey)
        local rec = type(recOrKey) == "table" and recOrKey or WRL_DB.characters[recOrKey]
        if rec and rec.isArchived then return "archived" end
        return rec and rec.status or "active"
    end
    function ns.Run:IsPlayable(recOrKey)
        local stateValue = self:GetState(recOrKey)
        return stateValue == "fresh" or stateValue == "active"
    end

    function ns.Tiers:CurrentTier()
        return { id = 5 }
    end

    assert(loadfile("Core/Achievements.lua"))("WoWRoguelite", ns)
    return ns
end

local function assertNil(value, message)
    if value ~= nil then error(message .. ": expected nil", 2) end
end

local function assertTrue(value, message)
    if not value then error(message .. ": expected truthy value", 2) end
end

local function testPendingContributionCharacterCannotEarnLevelOrCleanPathAchievements()
    local ns = resetHarness("dead_pending_contribution")

    ns.Achievements:OnLevelUp(20)

    assertNil(WRL_DB.achievements.reach_level_10, "pending contribution run cannot earn level 10")
    assertNil(WRL_DB.achievements.reach_level_20, "pending contribution run cannot earn level 20")
    assertNil(WRL_DB.achievements.no_taint_to_level_20, "pending contribution run cannot earn clean path")
end

local function testRetiredCharacterCannotEarnBackfillAchievements()
    local ns = resetHarness("retired", 1000000)

    ns.Achievements:Evaluate("login", {
        key = "Runner-Realm",
        rec = WRL_DB.characters["Runner-Realm"],
    })

    assertNil(WRL_DB.achievements.reach_level_10, "retired run cannot earn login level backfill")
    assertNil(WRL_DB.achievements.contribute_10g_lifetime, "retired run cannot earn lifetime contribution backfill")
    assertNil(WRL_DB.achievements.contribute_100g_lifetime, "retired run cannot earn major patron backfill")
    assertNil(WRL_DB.achievements.first_legend_tier_unlock, "retired run cannot earn legend backfill")
end

local function testFinalDeathAchievementStillAwardsAfterRunStops()
    local ns = resetHarness("dead_pending_contribution")

    ns.Achievements:OnFinalDeath("Runner-Realm", WRL_DB.characters["Runner-Realm"])

    assertTrue(WRL_DB.achievements.first_final_death, "final death achievement still awards")
    assertNil(WRL_DB.achievements.reach_level_10, "final death event does not back-award level achievements")
end

local function testDeadContributionDoesNotEarnLifetimeAchievements()
    local ns = resetHarness("dead_pending_contribution", 1000000)

    ns.Achievements:OnContribution("Runner-Realm", { amount = 1000000 })

    assertNil(WRL_DB.achievements.contribute_10g_lifetime, "dead contribution cannot earn first tithe")
    assertNil(WRL_DB.achievements.contribute_100g_lifetime, "dead contribution cannot earn major patron")
    assertNil(WRL_DB.achievements.first_legend_tier_unlock, "dead contribution cannot earn legend tier")
end

local function testActiveContributionCanEarnLifetimeAchievements()
    local ns = resetHarness("active", 1000000)

    ns.Achievements:OnContribution("Runner-Realm", { amount = 1000000 })

    assertTrue(WRL_DB.achievements.contribute_10g_lifetime, "active contribution can earn first tithe")
    assertTrue(WRL_DB.achievements.contribute_100g_lifetime, "active contribution can earn major patron")
    assertTrue(WRL_DB.achievements.first_legend_tier_unlock, "active contribution can earn legend tier")
end

local function testLevelAchievementsReachEveryTenThroughSeventy()
    local ns = resetHarness("active")
    WRL_DB.characters["Runner-Realm"].levelCurrent = 70

    ns.Achievements:OnLevelUp(70)

    for level = 10, 70, 10 do
        assertTrue(WRL_DB.achievements["reach_level_" .. tostring(level)], "level " .. tostring(level) .. " achievement awards")
    end
end

local function testSoftDeathAwardsDeathDecadeAndCountAchievements()
    local ns = resetHarness("active")
    WRL_DB.characters["Runner-Realm"].levelCurrent = 27
    WRL_DB.characters["Runner-Realm"].deathCount = 1
    WRL_DB.deathCount = 1

    ns.Achievements:OnDeath("soft", "Runner-Realm", WRL_DB.characters["Runner-Realm"])

    assertTrue(WRL_DB.achievements.death_decade_20, "soft death in 20s awards death decade")
    assertTrue(WRL_DB.achievements.death_count_1, "first death count achievement awards")
    assertNil(WRL_DB.achievements.death_decade_30, "soft death in 20s does not award 30s death decade")
end

local function testDeathCountAchievementsUseRunDeathCounter()
    local ns = resetHarness("active")
    WRL_DB.characters["Runner-Realm"].levelCurrent = 44
    WRL_DB.deathCount = 50

    ns.Achievements:OnDeath("soft", "Runner-Realm", WRL_DB.characters["Runner-Realm"])

    assertTrue(WRL_DB.achievements.death_count_50, "50th death achievement awards")
    assertTrue(WRL_DB.achievements.death_decade_40, "death in 40s achievement awards")
    assertNil(WRL_DB.achievements.death_count_100, "100 deaths achievement waits for threshold")
end

testPendingContributionCharacterCannotEarnLevelOrCleanPathAchievements()
testRetiredCharacterCannotEarnBackfillAchievements()
testFinalDeathAchievementStillAwardsAfterRunStops()
testDeadContributionDoesNotEarnLifetimeAchievements()
testActiveContributionCanEarnLifetimeAchievements()
testLevelAchievementsReachEveryTenThroughSeventy()
testSoftDeathAwardsDeathDecadeAndCountAchievements()
testDeathCountAchievementsUseRunDeathCounter()

print("AchievementEligibility.test.lua: ok")
