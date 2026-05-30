local function resetHarness()
    WRL_DB = {
        settings = {},
        characters = {},
    }
    local ns = {
        Debug = function() end,
        Print = function() end,
    }
    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end
    assert(loadfile("Core/Settings.lua"))("WoWRoguelite", ns)
    return ns
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

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

local function testSettingsDefaultIncludesAutoResalePricing()
    local ns = resetHarness()

    ns.Settings:Init()

    assertEqual(ns.Settings:Get("pricing.resaleSource"), "auto", "resale pricing defaults to auto")
end

local function testSettingsDefaultIncludesDarkSoulsDeathSound()
    local ns = resetHarness()

    ns.Settings:Init()

    assertEqual(ns.Settings:Get("deathSound"), "dark_souls", "death sound defaults to Dark Souls")
end

local function testSettingsDefaultsDoNotIgnoreInstanceDeaths()
    local ns = resetHarness()

    ns.Settings:Init()

    assertEqual(ns.Settings:Get("ignoreDungeonDeaths"), false, "dungeon deaths count by default")
    assertEqual(ns.Settings:Get("ignoreBattlegroundDeaths"), false, "battleground deaths count by default")
end

local function testSettingsUINamesPricingControls()
    local src = readFile("UI/SettingsPopup.lua")

    assertContains(src, "Pricing", "Settings should include pricing section")
    assertContains(src, "Resale Desk pricing", "Settings should label resale pricing dropdown")
    assertContains(src, "WRL_SettingsResalePricingDropdown", "Settings should create resale pricing dropdown")
    assertContains(src, "pricing.resaleSource", "Settings should persist resale pricing preference")
end

local function testSettingsUINamesDeathSoundControls()
    local src = readFile("UI/SettingsPopup.lua")

    assertContains(src, "Death Sound", "Settings should include death sound section")
    assertContains(src, "WRL_SettingsDeathSoundDropdown", "Settings should create death sound dropdown")
    assertContains(src, "deathSound", "Settings should persist death sound preference")
    assertContains(src, "DeathSoundOptions", "Settings should use death module sound options")
end

local function testSettingsUINamesIgnoredInstanceDeathControls()
    local src = readFile("UI/SettingsPopup.lua")

    assertContains(src, "Ignore deaths in dungeons", "Settings should expose dungeon death ignore toggle")
    assertContains(src, "Ignore deaths in battlegrounds", "Settings should expose battleground death ignore toggle")
    assertContains(src, "ignoreDungeonDeaths", "Settings should persist dungeon death ignore preference")
    assertContains(src, "ignoreBattlegroundDeaths", "Settings should persist battleground death ignore preference")
end

testSettingsDefaultIncludesAutoResalePricing()
testSettingsDefaultIncludesDarkSoulsDeathSound()
testSettingsDefaultsDoNotIgnoreInstanceDeaths()
testSettingsUINamesPricingControls()
testSettingsUINamesIgnoredInstanceDeathControls()
testSettingsUINamesDeathSoundControls()

print("SettingsPricing.test.lua: ok")
