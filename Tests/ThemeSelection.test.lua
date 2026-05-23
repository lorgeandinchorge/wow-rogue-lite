local addonEnabled = false
local addonId = "GW2_UI"
local addonTitle = "GW2 UI"
local useCAddOns = false
local cAddOnsEnableStateOrder = "addonFirst"

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
            GetAddOnEnableState = function(first, second)
                local name = cAddOnsEnableStateOrder == "playerFirst" and second or first
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
    cAddOnsEnableStateOrder = "addonFirst"
    addonEnabled = true
    addonId = "GW2_UI"
    addonTitle = "|cffffedbaGW2 UI|r"
    local ns = resetHarness()

    local ok = ns.Theme:SetTheme("gw2")

    assertEqual(ok, true, "gw2 theme selection succeeds through C_AddOns")
    assertEqual(ns.Theme:HasGW2UI(), true, "HasGW2UI uses C_AddOns when globals are absent")
end

local function testGw2DetectedThroughCAddOnsPlayerFirstEnableState()
    useCAddOns = true
    cAddOnsEnableStateOrder = "playerFirst"
    addonEnabled = true
    addonId = "GW2_UI_TBC"
    addonTitle = "|cffffedbaGW2 UI|r |cFF888888TBC|r"
    local ns = resetHarness("gw2")

    assertEqual(ns.Theme:HasGW2UI(), true, "HasGW2UI tolerates player-first C_AddOns enable state")
    assertEqual(ns.Theme:GetActiveThemeId(), "gw2", "saved gw2 activates on first init when player-first C_AddOns reports enabled")
end

local function testRefreshAvailabilityReappliesSavedGw2AfterAddonAppears()
    useCAddOns = false
    cAddOnsEnableStateOrder = "addonFirst"
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

local function testSetThemeRefreshesVisibleUi()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()
    local refreshed = false
    ns.MainFrame = {
        RefreshTheme = function()
            refreshed = true
        end,
    }

    local ok = ns.Theme:SetTheme("dark")

    assertEqual(ok, true, "dark theme selection succeeds")
    assertEqual(refreshed, true, "theme selection refreshes visible UI")
end

local function testDefaultFontProfile()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    assertEqual(ns.Settings:Get("fontProfile"), "default", "settings default font profile")
    assertEqual(ns.Theme:GetSelectedFontProfileId(), "default", "selected font profile defaults to default")
    assertEqual(ns.Theme:FontProfileLabel("readable"), "Readable Sans", "font profile labels are exposed")
end

local function testFontProfileCanBeSelected()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()
    local refreshed = false
    ns.MainFrame = {
        RefreshTheme = function()
            refreshed = true
        end,
    }

    local ok, reason = ns.Theme:SetFontProfile("large")

    assertEqual(ok, true, "large font profile selection succeeds")
    assertEqual(reason, nil, "successful font profile selection has no failure reason")
    assertEqual(ns.Settings:Get("fontProfile"), "large", "stored font profile changes")
    assertEqual(ns.Theme:GetSelectedFontProfileId(), "large", "selected font profile changes")
    assertEqual(refreshed, true, "font profile selection refreshes visible UI")
end

local function testUnknownFontProfileIsRejected()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local ok, reason = ns.Theme:SetFontProfile("tiny")

    assertEqual(ok, false, "unknown font profile selection fails")
    assertEqual(reason, "unknown", "unknown font profile returns unknown reason")
    assertEqual(ns.Settings:Get("fontProfile"), "default", "stored font profile remains unchanged after unknown profile")
end

local function testGrahamThemeCanBeSelected()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local ok, reason = ns.Theme:SetTheme("grant")

    assertEqual(ok, true, "graham theme selection succeeds")
    assertEqual(reason, nil, "successful graham selection has no failure reason")
    assertEqual(ns.Settings:Get("uiTheme"), "grant", "stored setting changes to grant")
    assertEqual(ns.Theme:GetActiveThemeId(), "grant", "active theme is grant")
    assertEqual(ns.Theme:ThemeLabel("grant"), "Graham", "grant theme has Graham display label")
    assertEqual(ns.Theme.c.gold[1], 0.486, "graham primary accent uses jewel purple")
    assertEqual(ns.Theme.c.green[2], 0.659, "graham secondary success uses jewel green")
end

local function testIsabellaThemeCanBeSelected()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local ok, reason = ns.Theme:SetTheme("isabella")

    assertEqual(ok, true, "isabella theme selection succeeds")
    assertEqual(reason, nil, "successful isabella selection has no failure reason")
    assertEqual(ns.Settings:Get("uiTheme"), "isabella", "stored setting changes to isabella")
    assertEqual(ns.Theme:GetActiveThemeId(), "isabella", "active theme is isabella")
    assertEqual(ns.Theme:ThemeLabel("isabella"), "Isabella", "isabella theme has display label")
    assertEqual(ns.Theme.c.gold[1], 0.851, "isabella primary accent uses jewel pink")
    assertEqual(ns.Theme.c.green[2], 0.714, "isabella secondary success uses jewel teal")
end

local function testHavokThemeCanBeSelected()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local ok, reason = ns.Theme:SetTheme("havok")

    assertEqual(ok, true, "havok theme selection succeeds")
    assertEqual(reason, nil, "successful havok selection has no failure reason")
    assertEqual(ns.Settings:Get("uiTheme"), "havok", "stored setting changes to havok")
    assertEqual(ns.Theme:GetActiveThemeId(), "havok", "active theme is havok")
    assertEqual(ns.Theme:ThemeLabel("havok"), "Havok", "havok theme has display label")
    assertEqual(ns.Theme.c.bg0[1], 0.012, "havok uses black surface red channel")
    assertEqual(ns.Theme.c.gold[3], 1.000, "havok accent uses electric blue")
end

local function testRabidThemeCanBeSelected()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local ok, reason = ns.Theme:SetTheme("rabid")

    assertEqual(ok, true, "rabid theme selection succeeds")
    assertEqual(reason, nil, "successful rabid selection has no failure reason")
    assertEqual(ns.Settings:Get("uiTheme"), "rabid", "stored setting changes to rabid")
    assertEqual(ns.Theme:GetActiveThemeId(), "rabid", "active theme is rabid")
    assertEqual(ns.Theme:ThemeLabel("rabid"), "Rabid", "rabid theme has display label")
    assertEqual(ns.Theme.c.bg0[3], 0.180, "rabid uses a stronger blue base")
    assertEqual(ns.Theme.c.gold[1], 0.400, "rabid accent keeps a cooler blue-purple red channel")
    assertEqual(ns.Theme.c.fg[1], 0.875, "rabid primary text shifts toward readable purple")
    assertEqual(ns.Theme.c.fg2[3], 0.940, "rabid secondary text stays bright enough on blue")
end

local function testPersonalThemesAppearInThemeListOrder()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local list = ns.Theme:ThemeList()

    assertEqual(list[4].id, "havok", "havok appears after gw2 in theme list")
    assertEqual(list[4].available, true, "havok is always available")
    assertEqual(list[5].id, "rabid", "rabid appears after havok in theme list")
    assertEqual(list[5].available, true, "rabid is always available")
    assertEqual(list[6].id, "grant", "grant appears after rabid in theme list")
    assertEqual(list[6].available, true, "grant is always available")
    assertEqual(list[7].id, "isabella", "isabella appears after grant in theme list")
    assertEqual(list[7].available, true, "isabella is always available")
end

local function testThemeCommandTextUsesThemeOrder()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    assertEqual(ns.Theme:ThemeUsageText(), "classic | dark | gw2 | havok | rabid | grant | isabella", "theme usage text follows theme order")
    assertEqual(ns.Theme:ThemeSentenceText(), "classic, dark, gw2, havok, rabid, grant, or isabella", "theme sentence text follows theme order")
end

local function testClassicPaletteUsesBetterBagsStyleDefault()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    assertEqual(ns.Theme:GetActiveThemeId(), "classic", "classic remains the default active theme")
    assertEqual(ns.Theme.c.bg0[1], 0.135, "classic default uses a warmer Blizzard panel base")
    assertEqual(ns.Theme.c.headerBg[1], 0.240, "classic default has a BetterBags-style panel header")
    assertEqual(ns.Theme.c.gold[1], 1.000, "classic default uses brighter Blizzard title gold")
end

local function testDarkPaletteUsesPreviousClassicDarkDefault()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local ok = ns.Theme:SetTheme("dark")

    assertEqual(ok, true, "dark theme can be selected")
    assertEqual(ns.Theme.c.bg0[1], 0.045, "dark inherits the previous default bg0 red channel")
    assertEqual(ns.Theme.c.headerBg[1], 0.105, "dark inherits the previous default header token")
    assertEqual(ns.Theme.c.gold[1], 0.780, "dark inherits the previous default restrained gold")
end

local function testGw2PaletteUsesHeroicSurfaceTokens()
    useCAddOns = false
    addonEnabled = true
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local ok = ns.Theme:SetTheme("gw2")

    assertEqual(ok, true, "gw2 theme can be selected")
    assertEqual(ns.Theme.c.headerBg[1], 0.270, "gw2 header has warm red channel")
    assertEqual(ns.Theme.c.headerBg[2], 0.120, "gw2 header has restrained green channel")
    assertEqual(ns.Theme.c.gold[1], 0.850, "gw2 uses stronger metallic gold")
end

local function testClassicThemeUsesBlizzardTextureSkin()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    assertEqual(ns.Theme:SurfaceTexture("frame"), "Interface\\DialogFrame\\UI-DialogBox-Background", "classic frame uses Blizzard dialog background texture")
    assertEqual(ns.Theme:SurfaceTexture("header"), "Interface\\DialogFrame\\UI-DialogBox-Header", "classic header uses Blizzard dialog header texture")
    assertEqual(ns.Theme:SurfaceTexture("button"), "Interface\\Buttons\\UI-Panel-Button-Up", "classic buttons use Blizzard panel button texture")
end

local function testDarkThemeRemainsFlatTextureSkin()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local ok = ns.Theme:SetTheme("dark")

    assertEqual(ok, true, "dark theme can be selected")
    assertEqual(ns.Theme:SurfaceTexture("frame"), nil, "dark frame stays flat")
    assertEqual(ns.Theme:SurfaceTexture("button"), nil, "dark buttons stay flat")
end

local function testGw2ThemeUsesGw2UiTextureSkinWhenActive()
    useCAddOns = false
    addonEnabled = true
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local ok = ns.Theme:SetTheme("gw2")

    assertEqual(ok, true, "gw2 theme can be selected")
    assertEqual(ns.Theme:SurfaceTexture("frame"), "Interface\\AddOns\\GW2_UI\\Textures\\bag\\bagbg.png", "gw2 frame uses GW2_UI bag body texture")
    assertEqual(ns.Theme:SurfaceTexture("header"), "Interface\\AddOns\\GW2_UI\\Textures\\bag\\bagheader.png", "gw2 header uses GW2_UI bag header texture")
    assertEqual(ns.Theme:SurfaceTexture("footer"), "Interface\\AddOns\\GW2_UI\\Textures\\bag\\bagfooter.png", "gw2 footer exposes GW2_UI bag footer texture")
end

local function testGw2ThemeUsesActiveFlavorTextureRoot()
    useCAddOns = false
    addonEnabled = true
    addonId = "GW2_UI_TBC"
    addonTitle = "|cffffedbaGW2 UI|r |cFF888888TBC|r"
    local ns = resetHarness()

    local ok = ns.Theme:SetTheme("gw2")

    assertEqual(ok, true, "gw2 theme can be selected for TBC flavor")
    assertEqual(ns.Theme:SurfaceTexture("frame"), "Interface\\AddOns\\GW2_UI_TBC\\Textures\\bag\\bagbg.png", "gw2 frame uses active flavor folder")
    assertEqual(ns.Theme:SurfaceTexture("panel"), "Interface\\AddOns\\GW2_UI_TBC\\Textures\\addonSkins\\backdrop.png", "gw2 panel uses active flavor addonSkins texture")
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
testGw2DetectedThroughCAddOnsPlayerFirstEnableState()
testRefreshAvailabilityReappliesSavedGw2AfterAddonAppears()
testSetThemeRefreshesVisibleUi()
testDefaultFontProfile()
testFontProfileCanBeSelected()
testUnknownFontProfileIsRejected()
testGrahamThemeCanBeSelected()
testIsabellaThemeCanBeSelected()
testHavokThemeCanBeSelected()
testRabidThemeCanBeSelected()
testPersonalThemesAppearInThemeListOrder()
testThemeCommandTextUsesThemeOrder()
testClassicPaletteUsesBetterBagsStyleDefault()
testDarkPaletteUsesPreviousClassicDarkDefault()
testGw2PaletteUsesHeroicSurfaceTokens()
testClassicThemeUsesBlizzardTextureSkin()
testDarkThemeRemainsFlatTextureSkin()
testGw2ThemeUsesGw2UiTextureSkinWhenActive()
testGw2ThemeUsesActiveFlavorTextureRoot()

print("ThemeSelection.test.lua: ok")
