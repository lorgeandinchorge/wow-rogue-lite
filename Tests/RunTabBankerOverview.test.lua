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

    assertContains(left[1], "You're the banker", "banker overview starts with banker identity")
    assertContains(left[2], "Bank character", "banker overview names the role")
    assertContains(left[3], "Total lifetime contributed: 123456c", "banker overview includes lifetime contributions")
    assertContains(left[4], "Available legacy budget: 100000c", "banker overview includes available budget")
    assertContains(left[5], "Pending requests: 2", "banker overview counts pending requests")

    assertEqual(right[1], "|cffc0a060Your responsibilities|r", "right pane has responsibilities heading")
    assertContains(right[2], "Fulfill pending requests", "responsibilities include request fulfillment")
    assertContains(right[3], "Mail starter rewards", "responsibilities include mailing rewards")
    assertContains(right[4], "Hold contributed gold", "responsibilities include bank storage")
    assertContains(right[5], "Track legacy progression", "responsibilities include legacy progression")
    assertContains(right[6], "Banker deaths do not retire", "responsibilities explain banker death exemption")
end

testBankerOverviewReplacesRunSnapshotCopy()

print("RunTabBankerOverview.test.lua: ok")
