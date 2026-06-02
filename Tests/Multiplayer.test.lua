local function resetHarness()
    WRL_DB = {
        settings = {
            multiplayerEnabled = true,
            multiplayerGuildDiscovery = true,
        },
        characters = {
            ["Runner-Realm"] = {
                key = "Runner-Realm",
                class = "MAGE",
                levelCurrent = 24,
                livesRemaining = 2,
                status = "active",
            },
        },
    }

    local sent = {}
    local events = {}
    local now = 1000

    _G.time = function() return now end
    _G.UnitName = function() return "Runner", "Realm" end
    _G.GetRealmName = function() return "Realm" end
    _G.UnitClass = function() return "Mage", "MAGE" end
    _G.UnitLevel = function() return 24 end
    _G.GetNumRaidMembers = function() return 0 end
    _G.GetNumPartyMembers = function() return 2 end
    _G.IsInGuild = function() return true end

    local ns = {
        version = "0.4.1c",
        Database = {},
        Run = {},
        Settings = {},
        Comm = {},
        MainFrame = {
            RefreshCurrentTab = function() events.refreshTab = (events.refreshTab or 0) + 1 end,
            RefreshHeader = function() events.refreshHeader = (events.refreshHeader or 0) + 1 end,
        },
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns:UnitKey() return "Runner-Realm" end
    function ns:Debug() end
    function ns:On(event, cb)
        events[event] = cb
    end

    function ns.Settings:Get(key, fallback)
        local v = WRL_DB.settings[key]
        if v == nil then return fallback end
        return v
    end

    function ns.Database:GetCurrentCharacter()
        return WRL_DB.characters["Runner-Realm"]
    end

    function ns.Database:GetCharacter(key)
        return WRL_DB.characters[key]
    end

    function ns.Run:GetState(rec)
        return rec and rec.status or "unknown"
    end

    function ns.Comm:RegisterOpHandler(op, cb)
        self.handlers = self.handlers or {}
        self.handlers[op] = cb
    end

    function ns.Comm:SendGroup(op, payload)
        sent[#sent + 1] = { channel = "PARTY", op = op, payload = payload }
        return true
    end

    function ns.Comm:SendGuild(op, payload)
        sent[#sent + 1] = { channel = "GUILD", op = op, payload = payload }
        return true
    end

    assert(loadfile("Core/Multiplayer.lua"))("WoWRoguelite", ns)
    return ns, sent, events, function(value) if value then now = value end return now end
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertContains(text, needle, message)
    if not tostring(text):find(needle, 1, true) then
        error(string.format("%s: expected '%s' to contain '%s'", message, tostring(text), tostring(needle)), 2)
    end
end

local function testInitRegistersMultiplayerOps()
    local ns = resetHarness()

    ns.Multiplayer:Init()

    assertEqual(type(ns.Comm.handlers.HELLO), "function", "HELLO handler registered")
    assertEqual(type(ns.Comm.handlers.STATE), "function", "STATE handler registered")
    assertEqual(type(ns.Comm.handlers.EVENT), "function", "EVENT handler registered")
    assertEqual(type(ns.Comm.handlers.BYE), "function", "BYE handler registered")
end

local function testGroupHelloBroadcastUsesCompactRunSummary()
    local ns, sent = resetHarness()
    ns.Multiplayer:Init()

    local ok = ns.Multiplayer:BroadcastHello()

    assertEqual(ok, true, "hello broadcast succeeds")
    assertEqual(sent[1].channel, "PARTY", "hello uses group channel")
    assertEqual(sent[1].op, "HELLO", "hello op")
    assertEqual(sent[1].payload, "Runner-Realm^0.4.1c^MAGE^24^2^active", "hello payload")
end

local function testGuildDiscoverySendsLightweightHello()
    local ns, sent = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:BroadcastGuildHello()

    assertEqual(sent[1].channel, "GUILD", "guild discovery channel")
    assertEqual(sent[1].op, "HELLO", "guild discovery op")
    assertContains(sent[1].payload, "Runner-Realm", "guild discovery payload includes identity")
end

local function testStateBroadcastsAreThrottled()
    local ns, sent, _, setNow = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:BroadcastState()
    ns.Multiplayer:BroadcastState()
    setNow(1003)
    ns.Multiplayer:BroadcastState()

    assertEqual(#sent, 2, "state broadcasts are throttled by send bucket")
end

local function testIncomingStateUpdatesRosterAndExpiresWhenStale()
    local ns, _, _, setNow = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:Receive("STATE", "Friend-Realm^0.4.1c^WARRIOR^19^1^active", "PARTY", "Friend-Realm")
    local rows = ns.Multiplayer:RosterRows()

    assertEqual(#rows, 1, "fresh state appears in roster")
    assertEqual(rows[1].key, "Friend-Realm", "roster key")
    assertEqual(rows[1].level, 19, "roster level")
    assertEqual(rows[1].lives, 1, "roster lives")

    setNow(1101)
    rows = ns.Multiplayer:RosterRows()

    assertEqual(#rows, 0, "stale roster entry expires")
end

local function testHelloAndByeCreateLocalJoinLeaveFeed()
    local ns = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:Receive("HELLO", "Friend-Realm^0.4.1c^PRIEST^31^3^active", "PARTY", "Friend-Realm")
    ns.Multiplayer:Receive("BYE", "Friend-Realm", "PARTY", "Friend-Realm")
    local feed = ns.Multiplayer:EventRows()

    assertEqual(feed[1].kind, "leave", "bye creates leave event")
    assertEqual(feed[2].kind, "join", "first hello creates join event")
end

local function testDuplicateEventsAreIgnored()
    local ns = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:Receive("EVENT", "evt-1^Friend-Realm^soft_death^19^1^active^Murloc", "PARTY", "Friend-Realm")
    ns.Multiplayer:Receive("EVENT", "evt-1^Friend-Realm^soft_death^19^1^active^Murloc", "PARTY", "Friend-Realm")
    local feed = ns.Multiplayer:EventRows()

    assertEqual(#feed, 1, "duplicate event suppressed")
    assertEqual(feed[1].kind, "soft_death", "event kind")
    assertEqual(feed[1].detail, "Murloc", "event detail")
end

local function testDashboardLinesSummarizeRosterAndEvents()
    local ns = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:Receive("STATE", "Friend-Realm^0.4.1c^PRIEST^31^3^active", "PARTY", "Friend-Realm")
    ns.Multiplayer:Receive("EVENT", "evt-2^Friend-Realm^final_death^31^0^dead_pending_contribution^Wailing Caverns", "PARTY", "Friend-Realm")
    local lines = ns.Multiplayer:DashboardLines()
    local joined = table.concat(lines, "\n")

    assertContains(joined, "Co-op Run", "dashboard has co-op heading")
    assertContains(joined, "Friend", "dashboard includes short player name")
    assertContains(joined, "lvl 31", "dashboard includes level")
    assertContains(joined, "final death", "dashboard includes readable event kind")
end

testInitRegistersMultiplayerOps()
testGroupHelloBroadcastUsesCompactRunSummary()
testGuildDiscoverySendsLightweightHello()
testStateBroadcastsAreThrottled()
testIncomingStateUpdatesRosterAndExpiresWhenStale()
testHelloAndByeCreateLocalJoinLeaveFeed()
testDuplicateEventsAreIgnored()
testDashboardLinesSummarizeRosterAndEvents()

print("Multiplayer.test.lua: ok")
