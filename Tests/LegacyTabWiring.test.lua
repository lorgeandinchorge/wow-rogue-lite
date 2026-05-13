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

local function testMainFrameUsesSingleLegacyTab()
    local src = readFile("UI/MainFrame.lua")

    assertContains(src, 'local TABS = { "Run", "Achievements", "Legacy", "Rewards" }',
        "main tab order should combine account economy into Legacy")
    assertContains(src, 'Legacy = "Legacy"', "Legacy tab should have a visible label")
    assertContains(src, "ns.Tab_Legacy:Init(body)", "MainFrame should initialize the Legacy panel")
    assertNotContains(src, 'TAB_LABELS = {\n    Run = "Current Run",\n    Contributions =',
        "Contributions should not remain a separate top-level tab")
    assertNotContains(src, 'if ns.Tab_Tiers', "Tiers should not remain a separate top-level tab")
end

local function testTocLoadsLegacyPanel()
    local toc = readFile("WoWRoguelite.toc")

    assertContains(toc, "UI/Tab_Legacy.lua", "TOC should load the combined Legacy tab")
    assertNotContains(toc, "UI/Tab_Contributions.lua", "TOC should stop loading the old Contributions tab")
    assertNotContains(toc, "UI/Tab_Tiers.lua", "TOC should stop loading the old Tiers tab")
end

testMainFrameUsesSingleLegacyTab()
testTocLoadsLegacyPanel()

print("LegacyTabWiring.test.lua: ok")
