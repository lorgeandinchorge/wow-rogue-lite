local addonEnabled = false

local function resetHarness(savedTheme)
    WRL_DB = {
        settings = savedTheme and { uiTheme = savedTheme } or {},
        characters = {},
    }

    _G.GetAddOnInfo = function(name)
        if name == "GW2_UI" then
            return "GW2 UI"
        end
        return nil
    end
    _G.GetAddOnEnableState = function(_, name)
        if name == "GW2_UI" and addonEnabled then
            return 2
        end
        return 0
    end
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

    local messages = {}
    local ns = {
        Database = { GetCurrentCharacter = function() return nil end },
        Debug = function() end,
        Print = function(_, msg, ...)
            if select("#", ...) > 0 then msg = msg:format(...) end
            messages[#messages + 1] = msg
        end,
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    assert(loadfile("Core/Settings.lua"))("WoWRoguelite", ns)
    ns.Settings:Init()
    assert(loadfile("UI/Theme.lua"))("WoWRoguelite", ns)
    ns.Theme:Init()
    return ns, messages
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function testClassicIsDefault()
    addonEnabled = false
    local ns = resetHarness()

    assertEqual(ns.Settings:Get("uiTheme"), "classic", "settings default theme")
    assertEqual(ns.Theme:GetSelectedThemeId(), "classic", "selected theme defaults to classic")
    assertEqual(ns.Theme:GetActiveThemeId(), "classic", "active theme defaults to classic")
end

local function testGw2CannotBeSelectedWhenUnavailable()
    addonEnabled = false
    local ns = resetHarness()

    local ok, reason = ns.Theme:SetTheme("gw2")

    assertEqual(ok, false, "gw2 theme selection fails when GW2_UI is unavailable")
    assertEqual(reason, "gw2_unavailable", "failure reason reports missing GW2_UI")
    assertEqual(ns.Settings:Get("uiTheme"), "classic", "stored setting remains unchanged")
end

local function testUnknownThemeIsRejected()
    addonEnabled = false
    local ns = resetHarness()

    local ok, reason = ns.Theme:SetTheme("neon")

    assertEqual(ok, false, "unknown theme selection fails")
    assertEqual(reason, "unknown", "unknown theme returns unknown reason")
    assertEqual(ns.Settings:Get("uiTheme"), "classic", "stored setting remains unchanged after unknown theme")
end

local function testSavedGw2FallsBackToDarkWhenUnavailable()
    addonEnabled = false
    local ns = resetHarness("gw2")

    assertEqual(ns.Theme:GetSelectedThemeId(), "gw2", "saved gw2 preference is preserved")
    assertEqual(ns.Theme:GetActiveThemeId(), "dark", "missing gw2 addon falls back to dark palette")
end

local function testGw2CanBeSelectedWhenAvailable()
    addonEnabled = true
    local ns = resetHarness()

    local ok, reason = ns.Theme:SetTheme("gw2")

    assertEqual(ok, true, "gw2 theme selection succeeds when GW2_UI is enabled")
    assertEqual(reason, nil, "successful theme selection has no failure reason")
    assertEqual(ns.Settings:Get("uiTheme"), "gw2", "stored setting changes to gw2")
    assertEqual(ns.Theme:GetActiveThemeId(), "gw2", "active theme is gw2")
end

local function testRefreshAvailabilityReappliesSavedGw2AfterAddonAppears()
    addonEnabled = false
    local ns = resetHarness("gw2")

    assertEqual(ns.Theme:GetActiveThemeId(), "dark", "saved gw2 starts on fallback when addon is unavailable")

    addonEnabled = true
    ns.Theme:RefreshAvailability()

    assertEqual(ns.Theme:GetSelectedThemeId(), "gw2", "saved gw2 preference remains selected")
    assertEqual(ns.Theme:GetActiveThemeId(), "gw2", "refresh reapplies gw2 once addon appears")
end

testClassicIsDefault()
testGw2CannotBeSelectedWhenUnavailable()
testUnknownThemeIsRejected()
testSavedGw2FallsBackToDarkWhenUnavailable()
testGw2CanBeSelectedWhenAvailable()
testRefreshAvailabilityReappliesSavedGw2AfterAddonAppears()

print("ThemeSelection.test.lua: ok")
