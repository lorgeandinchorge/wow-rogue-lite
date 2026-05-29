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

local function testLegacyPanelSupportsFourUnlockTracks()
    local src = readFile("UI/Tab_Legacy.lua")

    assertContains(src, "local TRACK_COLS = 4", "Legacy unlock tracks should line up side by side")
    assertContains(src, "buildTalentNode", "Legacy unlock ranks should render as talent-style nodes")
    assertContains(src, "buildTalentConnector", "Legacy unlock tracks should draw connector lines between nodes")
    assertContains(src, "TALENT_NODE_SIZE", "Legacy talent nodes should have a stable circular size")
    assertContains(src, "TRACK_ICON_TEX", "Legacy talent nodes should use track-specific icon textures")
    assertContains(src, "applyTalentIcon", "Legacy talent nodes should paint the track icon instead of rank text")
    assertContains(src, "Unlocks available: %d / %d", "Legacy tab should show a simple available unlock count")
    assertContains(src, "track._gridIndex", "Legacy tab should position tracks from their order")
end

local function testLegacyPanelShowsAvailableLegacyRewards()
    local src = readFile("UI/Tab_Legacy.lua")

    assertContains(src, "Available Legacy Rewards", "Legacy tab should include a reward summary section")
    assertContains(src, "refreshAvailableRewards", "Legacy tab should refresh merged active legacy rewards")
    assertContains(src, "ActiveNodeIds", "Available rewards should derive from active legacy unlock nodes")
    assertContains(src, "BuildRewardForTierIds", "Available rewards should use the canonical reward bundle builder")
end

local function testAvailableLegacyRewardsSitsAboveTalentBoard()
    local src = readFile("UI/Tab_Legacy.lua")

    assertContains(src, "local afterRewards = refreshAvailableRewards(self, 0)",
        "Available Legacy Rewards should refresh at the top of the Legacy page")
    assertContains(src, "local afterUnlocks = self:_RefreshUnlocks(afterRewards + 28)",
        "Talent board should render after the Available Legacy Rewards section")
end

testMainFrameUsesSingleLegacyTab()
testTocLoadsLegacyPanel()
testLegacyPanelSupportsFourUnlockTracks()
testLegacyPanelShowsAvailableLegacyRewards()
testAvailableLegacyRewardsSitsAboveTalentBoard()

print("LegacyTabWiring.test.lua: ok")
