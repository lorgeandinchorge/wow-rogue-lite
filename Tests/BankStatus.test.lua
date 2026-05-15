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
        Debug = function() end,
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

local function resetUnknownHarness(clockTime)
    WRL_DB = { bankCharacter = "Bank-Realm" }

    _G.GuildRoster = function() end
    _G.GetNumGuildMembers = function() return 0 end
    _G.GetNumFriends = function() return 0 end
    _G.time = function() return clockTime end

    local ns = {
        Database = {},
        Debug = function() end,
        On = function() end,
        Comm = {
            sentPing = nil,
            SendPresencePing = function(self, bankKey)
                self.sentPing = bankKey
                return true
            end,
        },
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns.Database:IsBankCharacter()
        return false
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

local function testAddonPresenceMarksUnknownBankOnline()
    local ns = resetUnknownHarness(120)

    ns.BankStatus:MarkSeen("Bank-Realm", 100)
    local status, label, source = ns.BankStatus:Status("Bank-Realm")

    assertEqual(status, "online", "fresh addon presence marks bank online")
    assertEqual(label, "Online", "fresh addon presence label")
    assertEqual(source, "addon", "fresh addon presence source")
end

local function testStaleAddonPresenceFallsBackToUnknownWithoutChatPing()
    local ns = resetUnknownHarness(200)

    ns.BankStatus:MarkSeen("Bank-Realm", 100)
    local status, label = ns.BankStatus:Status("Bank-Realm")

    assertEqual(status, "unknown", "stale addon presence falls back to unknown")
    assertEqual(label, "Unknown", "stale addon presence label")
    assertEqual(ns.Comm.sentPing, nil, "unknown bank is not auto-pinged from status refresh")
end

local function testNotifyChangedSkipsMainFrameRefreshBeforeFrameExists()
    local ns = resetUnknownHarness(120)
    local refreshes = 0
    ns.MainFrame = {
        RefreshHeader = function()
            refreshes = refreshes + 1
        end,
        RefreshCurrentTab = function()
            refreshes = refreshes + 1
        end,
    }

    ns.BankStatus:NotifyChanged()

    assertEqual(refreshes, 0, "bank status does not refresh UI before main frame exists")
end

testConfiguredBankIsNotSelfOnRunCharacter()
testConfiguredBankIsSelfOnBankCharacter()
testAddonPresenceMarksUnknownBankOnline()
testStaleAddonPresenceFallsBackToUnknownWithoutChatPing()
testNotifyChangedSkipsMainFrameRefreshBeforeFrameExists()

print("BankStatus.test.lua: ok")
