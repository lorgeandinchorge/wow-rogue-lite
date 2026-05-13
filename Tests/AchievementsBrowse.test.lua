local function resetHarness()
    WRL_DB = {
        achievements = {
            reach_level_10 = { when = 200, characterKey = "Newer-Realm" },
            first_final_death = { when = 100, characterKey = "Older-Realm" },
            first_legend_tier_unlock = { when = 150, characterKey = "Secret-Realm" },
        },
        totalContributed = 0,
    }

    local ns = {
        Database = {},
        Tiers = {},
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns:UnitKey() return "Runner-Realm" end
    function ns.Database:GetAchievements() return WRL_DB.achievements end
    function ns.Database:GetAchievement(id) return WRL_DB.achievements[id] end
    function ns.Database:HasAchievement(id) return WRL_DB.achievements[id] ~= nil end

    assert(loadfile("Core/Achievements.lua"))("WoWRoguelite", ns)
    return ns
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertTrue(value, message)
    if not value then error(message .. ": expected truthy value", 2) end
end

local function testBrowseModelCountsVisibleAndSortsEarnedNewestFirst()
    local ns = resetHarness()

    local browse = ns.Achievements:Browse()

    assertEqual(browse.earnedCount, 3, "earned count uses achievement ledger")
    assertEqual(browse.visibleCount, 9, "visible count includes earned hidden achievements")
    assertEqual(browse.earned[1].id, "reach_level_10", "newest earned achievement appears first")
    assertEqual(browse.earned[2].id, "first_legend_tier_unlock", "earned hidden achievement appears after newer visible earned")
    assertEqual(browse.earned[3].id, "first_final_death", "oldest earned achievement appears last")
    assertEqual(browse.earned[1].characterKey, "Newer-Realm", "earned row keeps earning character")
    assertEqual(browse.earned[1].when, 200, "earned row keeps earned timestamp")
end

local function testBrowseModelKeepsLockedHiddenAchievementsOut()
    local ns = resetHarness()
    WRL_DB.achievements.first_legend_tier_unlock = nil

    local browse = ns.Achievements:Browse()

    assertEqual(browse.earnedCount, 2, "earned count updates after removing hidden achievement")
    assertEqual(browse.visibleCount, 8, "locked hidden achievement does not count as visible")
    for _, row in ipairs(browse.locked) do
        assertTrue(row.id ~= "first_legend_tier_unlock", "locked hidden achievement is not listed")
        assertTrue(row.requirement and row.requirement ~= "", "locked visible rows expose a requirement")
    end
end

testBrowseModelCountsVisibleAndSortsEarnedNewestFirst()
testBrowseModelKeepsLockedHiddenAchievementsOut()

print("AchievementsBrowse.test.lua: ok")
