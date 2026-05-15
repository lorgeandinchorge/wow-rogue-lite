local function readFile(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s:gsub("\r\n", "\n")
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

local function testMainFrameUsesSingleRewardsTab()
    local src = readFile("UI/MainFrame.lua")

    assertContains(src, 'local TABS = { "Run", "Achievements", "Legacy", "Rewards" }',
        "main tab order should combine New Run and Requests into Rewards")
    assertContains(src, 'Rewards = "Rewards"', "Rewards tab should have a visible label")
    assertContains(src, "ns.Tab_Rewards:Init(body)", "MainFrame should initialize the Rewards panel")
    assertNotContains(src, 'Requests = "Requests"', "Requests should not remain a top-level tab")
    assertNotContains(src, 'NewRun = "New Run"', "New Run should not remain a top-level tab")
end

local function testTocLoadsRewardsPanel()
    local toc = readFile("WoWRoguelite.toc")

    assertContains(toc, "UI/Tab_Rewards.lua", "TOC should load the combined Rewards tab")
    assertNotContains(toc, "UI/Tab_Requests.lua", "TOC should stop loading the old Requests tab")
    assertNotContains(toc, "UI/Tab_NewRun.lua", "TOC should stop loading the old New Run tab")
end

local function testBankWorkflowHidesRunWorkflow()
    local src = readFile("UI/Tab_Rewards.lua")

    assertContains(src, "function Tab:HideRunWorkflow()", "Rewards tab should have a helper that hides run-only controls")
    assertContains(src, "self:HideRunWorkflow()\n        self:RefreshBankWorkflow()",
        "bank characters should hide run controls before showing bank fulfillment")
end

local function testRequestsNotifyRewardsTab()
    local src = readFile("Core/Requests.lua")

    assertContains(src, 'ns.MainFrame:Notify("Rewards")',
        "incoming reward requests should highlight the combined Rewards tab")
    assertNotContains(src, 'ns.MainFrame:Notify("requests")',
        "incoming reward requests should not target the removed lowercase requests tab")
end

testMainFrameUsesSingleRewardsTab()
testTocLoadsRewardsPanel()
testBankWorkflowHidesRunWorkflow()
testRequestsNotifyRewardsTab()

print("RewardsTabWiring.test.lua: ok")
