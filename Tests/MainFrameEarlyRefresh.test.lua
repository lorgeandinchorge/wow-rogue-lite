local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function resetHarness()
    WRL_DB = {
        bankCharacter = "Bank-Realm",
        totalContributed = 0,
    }

    local ns = {
        Database = {},
        Tiers = {},
        BankStatus = {},
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns:Debug() end
    function ns.Database:TotalContributed() return WRL_DB.totalContributed or 0 end
    function ns.Database:IsBankCharacter() return false end
    function ns.Tiers:FormatMoney(copper) return tostring(copper) .. "c" end
    function ns.BankStatus:Status() return "unknown", "Unknown" end

    assert(loadfile("UI/MainFrame.lua"))("WoWRoguelite", ns)
    return ns.MainFrame
end

local function testRefreshHeaderBeforeInitDoesNotError()
    local mainFrame = resetHarness()

    local ok, err = pcall(function()
        mainFrame:RefreshHeader()
        mainFrame:RefreshCurrentTab()
    end)

    assertEqual(ok, true, "early BankStatus refresh must not error: " .. tostring(err))
end

testRefreshHeaderBeforeInitDoesNotError()

print("MainFrameEarlyRefresh.test.lua: ok")
