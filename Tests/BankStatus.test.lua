local function resetHarness(isBankCharacter)
    WRL_DB = { bankCharacter = "Bank-Realm" }

    _G.GuildRoster = function() end
    _G.GetNumGuildMembers = function() return 1 end
    _G.GetGuildRosterInfo = function()
        return "Bank", nil, nil, nil, nil, nil, nil, nil, false
    end
    _G.GetNumFriends = function() return 0 end

    local ns = {
        Database = {},
        On = function() end,
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns.Database:IsBankCharacter()
        return isBankCharacter == true
    end

    assert(loadfile("Core/BankStatus.lua"))("WoWRoguelite", ns)
    return ns
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function testConfiguredBankIsNotSelfOnRunCharacter()
    local ns = resetHarness(false)

    local status, label = ns.BankStatus:Status("Bank-Realm")

    assertEqual(status, "offline", "configured bank uses roster status on run character")
    assertEqual(label, "Offline (guild)", "configured bank shows guild offline label")
end

local function testConfiguredBankIsSelfOnBankCharacter()
    local ns = resetHarness(true)

    local status, label = ns.BankStatus:Status("Bank-Realm")

    assertEqual(status, "self", "configured bank is self on bank character")
    assertEqual(label, "This character", "self bank label")
end

testConfiguredBankIsNotSelfOnRunCharacter()
testConfiguredBankIsSelfOnBankCharacter()

print("BankStatus.test.lua: ok")
