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

local function testRulesMoveOutOfMainTabs()
    local src = readFile("UI/MainFrame.lua")

    assertContains(src, 'local TABS = { "Run", "Achievements", "Legacy", "Rewards" }',
        "main tabs should no longer include Rules")
    assertNotContains(src, 'Rules = "Rules"', "Rules should not have a top-level tab label")
    assertNotContains(src, "ns.Tab_Rules:Init(body)", "MainFrame should not initialize the old Rules tab")
end

local function testSettingsOwnsRulesProfilesSurface()
    local src = readFile("UI/SettingsPopup.lua")

    assertContains(src, "Rules & Profiles", "Settings should include the rules/profile section")
    assertContains(src, "Recent Rule Log", "Settings should include the recent rule log section")
    assertContains(src, "ProfileDisplayName", "Settings should render existing profile presets")
    assertContains(src, "SetRuleEnabled", "Settings should own rule toggle editing")
    assertContains(src, "TaintCount", "Settings should show the per-character taint summary")
    assertContains(src, "RULE_ROW_H", "Settings should render rule rows with descriptions and severity")
end

local function testSettingsOwnsRunModifiersSurface()
    local src = readFile("UI/SettingsPopup.lua")

    assertContains(src, "Run Modifiers", "Settings should include a dedicated run modifier section")
    assertContains(src, "Boons", "Settings should label beneficial run modifiers")
    assertContains(src, "Burdens", "Settings should label restrictive run modifiers")
    assertContains(src, "BoonDefs", "Settings should render boon definitions")
    assertContains(src, "BurdenDefs", "Settings should render burden definitions")
    assertContains(src, "SetBoons", "Settings should persist selected boons")
    assertContains(src, "SetBurdens", "Settings should persist selected burdens")
end

local function testSettingsOwnsPricingSurface()
    local src = readFile("UI/SettingsPopup.lua")

    assertContains(src, "Pricing", "Settings should include a pricing section")
    assertContains(src, "Resale Desk pricing", "Settings should include resale pricing control")
    assertContains(src, "WRL_SettingsResalePricingDropdown", "Settings should expose a resale pricing dropdown")
    assertContains(src, "pricing.resaleSource", "Settings should persist resale pricing source")
end

local function testSettingsOwnsCoreResetSurface()
    local src = readFile("UI/SettingsPopup.lua")

    assertContains(src, "Options", "Settings should expose an Options selector")
    assertContains(src, "Resets", "Settings should expose a Resets selector")
    assertContains(src, "Reset Achievements", "Settings should label the achievement reset")
    assertContains(src, "Reset Legacy Progression", "Settings should label the legacy reset")
    assertContains(src, "Reset Ledger & Economy", "Settings should label the ledger reset")
    assertContains(src, "WRL_RESET_ACHIEVEMENTS_CONFIRM", "Settings should confirm achievement reset")
    assertContains(src, "WRL_RESET_LEGACY_CONFIRM", "Settings should confirm legacy reset")
    assertContains(src, "WRL_RESET_LEDGER_CONFIRM", "Settings should confirm ledger reset")
    assertContains(src, "ResetAchievements", "Settings reset handler should use the database helper")
    assertContains(src, "ResetLegacyProgression", "Settings reset handler should use the database helper")
    assertContains(src, "ResetLedgerEconomy", "Settings reset handler should use the database helper")
end

local function testSettingsOwnsIgnoredInstanceDeathToggles()
    local src = readFile("UI/SettingsPopup.lua")

    assertContains(src, "Ignore deaths in dungeons", "Settings should include dungeon death ignore toggle")
    assertContains(src, "Ignore deaths in battlegrounds", "Settings should include battleground death ignore toggle")
    assertContains(src, "ignoreDungeonDeaths", "Settings should write dungeon death ignore setting")
    assertContains(src, "ignoreBattlegroundDeaths", "Settings should write battleground death ignore setting")
end

local function testOldRulesTabNoLongerLoads()
    local toc = readFile("WoWRoguelite.toc")

    assertNotContains(toc, "UI/Tab_Rules.lua", "TOC should stop loading the old top-level Rules tab")
end

local function testInterfaceOptionsPointsRulesToSettings()
    local src = readFile("UI/AddonOptions.lua")

    assertContains(src, "gear Settings", "Interface options should point rule editing to Settings")
    assertNotContains(src, "/wrl > Rules", "Interface options should not reference the removed Rules tab")
end

testRulesMoveOutOfMainTabs()
testSettingsOwnsRulesProfilesSurface()
testSettingsOwnsRunModifiersSurface()
testSettingsOwnsPricingSurface()
testSettingsOwnsCoreResetSurface()
testSettingsOwnsIgnoredInstanceDeathToggles()
testOldRulesTabNoLongerLoads()
testInterfaceOptionsPointsRulesToSettings()

print("SettingsRulesWiring.test.lua: ok")
