local addonEnabled = false
local addonId = "GW2_UI"
local addonTitle = "GW2 UI"
local useCAddOns = false

local function resetHarness(savedTheme)
    WRL_DB = {
        settings = savedTheme and { uiTheme = savedTheme } or {},
        characters = {},
    }

    _G.C_AddOns = nil
    _G.GetAddOnInfo = function(name)
        if name == addonId or name == 1 then
            return addonId, addonTitle, nil, true, nil
        end
        if type(name) == "string" then
            return name, nil, nil, false, "MISSING"
        end
        return nil, nil, nil, false, "MISSING"
    end
    _G.GetAddOnEnableState = function(_, name)
        if name == addonId and addonEnabled then
            return 2
        end
        return 0
    end
    _G.GetNumAddOns = function()
        return 1
    end
    if useCAddOns then
        _G.C_AddOns = {
            GetAddOnInfo = _G.GetAddOnInfo,
            GetAddOnEnableState = function(name)
                if name == addonId and addonEnabled then
                    return 2
                end
                return 0
            end,
            GetNumAddOns = _G.GetNumAddOns,
        }
        _G.GetAddOnInfo = nil
        _G.GetAddOnEnableState = nil
        _G.GetNumAddOns = nil
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
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    assertEqual(ns.Settings:Get("uiTheme"), "classic", "settings default theme")
    assertEqual(ns.Theme:GetSelectedThemeId(), "classic", "selected theme defaults to classic")
    assertEqual(ns.Theme:GetActiveThemeId(), "classic", "active theme defaults to classic")
end

local function testGw2CannotBeSelectedWhenUnavailable()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local ok, reason = ns.Theme:SetTheme("gw2")

    assertEqual(ok, false, "gw2 theme selection fails when GW2_UI is unavailable")
    assertEqual(reason, "gw2_unavailable", "failure reason reports missing GW2_UI")
    assertEqual(ns.Settings:Get("uiTheme"), "classic", "stored setting remains unchanged")
end

local function testUnknownThemeIsRejected()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local ok, reason = ns.Theme:SetTheme("neon")

    assertEqual(ok, false, "unknown theme selection fails")
    assertEqual(reason, "unknown", "unknown theme returns unknown reason")
    assertEqual(ns.Settings:Get("uiTheme"), "classic", "stored setting remains unchanged after unknown theme")
end

local function testSavedGw2FallsBackToDarkWhenUnavailable()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness("gw2")

    assertEqual(ns.Theme:GetSelectedThemeId(), "gw2", "saved gw2 preference is preserved")
    assertEqual(ns.Theme:GetActiveThemeId(), "dark", "missing gw2 addon falls back to dark palette")
end

local function testGw2CanBeSelectedWhenAvailable()
    useCAddOns = false
    addonEnabled = true
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local ok, reason = ns.Theme:SetTheme("gw2")

    assertEqual(ok, true, "gw2 theme selection succeeds when GW2_UI is enabled")
    assertEqual(reason, nil, "successful theme selection has no failure reason")
    assertEqual(ns.Settings:Get("uiTheme"), "gw2", "stored setting changes to gw2")
    assertEqual(ns.Theme:GetActiveThemeId(), "gw2", "active theme is gw2")
end

local function testGw2TbcCanBeSelectedWhenAvailable()
    useCAddOns = false
    addonEnabled = true
    addonId = "GW2_UI_TBC"
    addonTitle = "|cffffedbaGW2 UI|r |cFF888888TBC|r"
    local ns = resetHarness()

    local ok, reason = ns.Theme:SetTheme("gw2")

    assertEqual(ok, true, "gw2 theme selection succeeds when GW2 UI TBC is enabled")
    assertEqual(reason, nil, "successful TBC theme selection has no failure reason")
    assertEqual(ns.Settings:Get("uiTheme"), "gw2", "stored setting changes to gw2 for TBC")
    assertEqual(ns.Theme:GetActiveThemeId(), "gw2", "active theme is gw2 for TBC")
    assertEqual(ns.Theme:HasGW2UI(), true, "HasGW2UI recognizes TBC flavor")
end

local function testGw2VanillaCanBeSelectedWhenAvailable()
    useCAddOns = false
    addonEnabled = true
    addonId = "GW2_UI_Vanilla"
    addonTitle = "|cffffedbaGW2 UI|r |cFF888888Era|r"
    local ns = resetHarness()

    local ok, reason = ns.Theme:SetTheme("gw2")

    assertEqual(ok, true, "gw2 theme selection succeeds when GW2 UI Vanilla is enabled")
    assertEqual(reason, nil, "successful Vanilla theme selection has no failure reason")
    assertEqual(ns.Theme:HasGW2UI(), true, "HasGW2UI recognizes Vanilla flavor")
end

local function testGw2MistsCanBeSelectedWhenAvailable()
    useCAddOns = false
    addonEnabled = true
    addonId = "GW2_UI_Mists"
    addonTitle = "|cffffedbaGW2 UI|r |cFF888888Mists|r"
    local ns = resetHarness()

    local ok = ns.Theme:SetTheme("gw2")

    assertEqual(ok, true, "gw2 theme selection succeeds when GW2 UI Mists is enabled")
    assertEqual(ns.Theme:HasGW2UI(), true, "HasGW2UI recognizes Mists flavor")
end

local function testGw2WrathCanBeSelectedWhenAvailable()
    useCAddOns = false
    addonEnabled = true
    addonId = "GW2_UI_Wrath"
    addonTitle = "|cffffedbaGW2 UI|r |cFF888888Wrath|r"
    local ns = resetHarness()

    local ok = ns.Theme:SetTheme("gw2")

    assertEqual(ok, true, "gw2 theme selection succeeds when GW2 UI Wrath is enabled")
    assertEqual(ns.Theme:HasGW2UI(), true, "HasGW2UI recognizes Wrath flavor")
end

local function testGw2DetectedThroughCAddOns()
    useCAddOns = true
    addonEnabled = true
    addonId = "GW2_UI"
    addonTitle = "|cffffedbaGW2 UI|r"
    local ns = resetHarness()

    local ok = ns.Theme:SetTheme("gw2")

    assertEqual(ok, true, "gw2 theme selection succeeds through C_AddOns")
    assertEqual(ns.Theme:HasGW2UI(), true, "HasGW2UI uses C_AddOns when globals are absent")
end

local function testRefreshAvailabilityReappliesSavedGw2AfterAddonAppears()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
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
testGw2TbcCanBeSelectedWhenAvailable()
testGw2VanillaCanBeSelectedWhenAvailable()
testGw2MistsCanBeSelectedWhenAvailable()
testGw2WrathCanBeSelectedWhenAvailable()
testGw2DetectedThroughCAddOns()
testRefreshAvailabilityReappliesSavedGw2AfterAddonAppears()

print("ThemeSelection.test.lua: ok")
