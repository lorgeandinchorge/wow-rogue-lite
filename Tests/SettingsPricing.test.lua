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

local function testSettingsUINamesPricingControls()
    local src = readFile("UI/SettingsPopup.lua")

    assertContains(src, "Pricing", "Settings should include pricing section")
    assertContains(src, "Resale Desk pricing", "Settings should label resale pricing dropdown")
    assertContains(src, "WRL_SettingsResalePricingDropdown", "Settings should create resale pricing dropdown")
    assertContains(src, "pricing.resaleSource", "Settings should persist resale pricing preference")
end

testSettingsDefaultIncludesAutoResalePricing()
testSettingsUINamesPricingControls()

print("SettingsPricing.test.lua: ok")
