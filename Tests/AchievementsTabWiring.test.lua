local function readFile(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function assertContains(haystack, needle, message)
    if not haystack:find(needle, 1, true) then
        error(("%s: expected to find %q"):format(message, needle), 2)
    end
end

local function assertNotContains(haystack, needle, message)
    if haystack:find(needle, 1, true) then
        error(("%s: did not expect to find %q"):format(message, needle), 2)
    end
end

local function testMainFrameRegistersAchievementsTab()
    local src = readFile("UI/MainFrame.lua")

    assertContains(src, 'local TABS = { "Run", "Achievements", "Legacy", "Rewards" }',
        "main tab order should include dedicated Achievements tab")
    assertContains(src, 'Achievements = "Achievements"', "Achievements tab should have a visible label")
    assertContains(src, "ns.Tab_Achievements:Init(body)", "MainFrame should initialize the Achievements panel")
end

local function testTocLoadsAchievementsPanel()
    local toc = readFile("WoWRoguelite.toc")

    assertContains(toc, "UI/Tab_Achievements.lua", "TOC should load the Achievements tab")
end

local function testCurrentRunOnlyPointsToAchievementsTab()
    local src = readFile("UI/Tab_Run.lua")

    assertContains(src, "open Achievements", "Current Run should keep a compact Achievements pointer")
    assertNotContains(src, "VisibleDefinitions", "Current Run should not browse achievement definitions")
    assertNotContains(src, "GetAchievements()", "Current Run should not browse the achievement ledger directly")
end

testMainFrameRegistersAchievementsTab()
testTocLoadsAchievementsPanel()
testCurrentRunOnlyPointsToAchievementsTab()

print("AchievementsTabWiring.test.lua: ok")
