local function resetHarness()
    WRL_DB = {
        bankCharacter = "Bank-Realm",
        totalContributed = 123456,
        legacySpent = 23456,
        requests = {
            { status = "pending" },
            { status = "gathering" },
            { status = "fulfilled" },
        },
    }
    WRL_CharDB = {}

    _G.GetRealmName = function() return "Realm" end
    _G.GetMoney = function() return 0 end

    local ns = {
        Database = {},
        LegacyUnlocks = {},
        Run = {},
        Tiers = {},
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns:UnitKey() return "Bank-Realm" end
    function ns.Database:IsBankCharacter() return true end
    function ns.LegacyUnlocks:AvailableBudget() return 100000 end
    function ns.Run:GetState(rec) return rec and rec.status or "unknown" end
    function ns.Tiers:FormatMoney(copper) return tostring(copper) .. "c" end

    assert(loadfile("UI/Tab_Run.lua"))("WoWRoguelite", ns)
    return ns.Tab_Run
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertContains(line, needle, message)
    if not line or not line:find(needle, 1, true) then
        error(string.format("%s: expected %q to contain %q", message, tostring(line), needle), 2)
    end
end

local function testBankerOverviewReplacesRunSnapshotCopy()
    local tab = resetHarness()

    local left, right = tab:_BuildBankerOverviewLines("Bank-Realm")

    assertContains(left[1], "Name:", "banker overview starts with character identity")
    assertContains(left[4], "Realm: Realm", "banker overview includes realm")
    assertContains(left[5], "bank infrastructure", "banker overview names the bank run state")
    assertContains(left[6], "Lives remaining: n/a", "banker overview avoids runner life accounting")

    assertEqual(right[1], "|cffc0a060Character status|r", "right pane has character status heading")
    assertContains(right[2], "legacy bank", "status identifies bank character")
    assertContains(right[3], "do not run roguelite lives", "status avoids runner-only affordances")
    assertContains(right[4], "do not retire", "status explains banker death exemption")
    assertEqual(right[6], "|cffc0a060Estimated contribution|r", "right pane includes contribution heading")
    assertContains(right[11], "Recent taint/warning entries: none", "right pane includes warning summary")
end

local function testContributionActionOnlyShowsForPendingContributionRuns()
    local tab = resetHarness()

    assertEqual(tab:_ShouldShowContributionAction({ status = "dead_pending_contribution" }), true,
        "pending final contribution shows recovery action")
    assertEqual(tab:_ShouldShowContributionAction({ status = "active" }), false,
        "active runs do not show contribution recovery action")
    assertEqual(tab:_ShouldShowContributionAction({ status = "retired" }), false,
        "fully retired runs do not show contribution recovery action")
end

testBankerOverviewReplacesRunSnapshotCopy()
testContributionActionOnlyShowsForPendingContributionRuns()

print("RunTabBankerOverview.test.lua: ok")
