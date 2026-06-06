local function resetHarness()
    WRL_DB = {
        bankCharacter = "Bank-Realm",
        settings = {
            profile = "casual_roguelite",
            multiplayerEnabled = true,
            multiplayerGuildDiscovery = true,
            rules = {
                no_auction_house = false,
                no_dungeon_repeats = false,
            },
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
        Rules = {},
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

    function ns.Settings:GetProfile()
        return WRL_DB.settings.profile
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

    function ns.Rules:Definitions()
        return {
            { id = "no_auction_house" },
            { id = "no_dungeon_repeats" },
        }
    end

    function ns.Rules:IsEnabled(ruleId)
        return WRL_DB.settings.rules and WRL_DB.settings.rules[ruleId] == true
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

local function r2Payload(overrides)
    local row = {
        schema = "R2",
        key = "Friend-Realm",
        version = "0.4.1c",
        class = "PRIEST",
        level = "31",
        lives = "3",
        state = "active",
        profile = "casual_roguelite",
        rules = "r0-0000",
        bank = "1",
        finalDeath = "0",
    }
    for k, v in pairs(overrides or {}) do row[k] = tostring(v) end
    return table.concat({
        row.schema,
        row.key,
        row.version,
        row.class,
        row.level,
        row.lives,
        row.state,
        row.profile,
        row.rules,
        row.bank,
        row.finalDeath,
    }, "^")
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
    assertEqual(sent[1].payload, "R2^Runner-Realm^0.4.1c^MAGE^24^2^active^casual_roguelite^r0-0000^1^0", "hello payload")
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
    assertEqual(rows[1].readiness, "Unknown", "legacy state readiness")
    assertEqual(rows[1].readinessReason, "older client", "legacy readiness reason")

    setNow(1101)
    rows = ns.Multiplayer:RosterRows()

    assertEqual(#rows, 0, "stale roster entry expires")
end

local function testMatchingR2PeerIsReady()
    local ns = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:Receive("STATE", r2Payload(), "PARTY", "Friend-Realm")
    local rows = ns.Multiplayer:RosterRows()

    assertEqual(rows[1].readiness, "Ready", "matching R2 peer is ready")
    assertEqual(rows[1].readinessReason, "aligned", "matching R2 reason")
end

local function testVersionMismatchWarns()
    local ns = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:Receive("STATE", r2Payload({ version = "0.4.0" }), "PARTY", "Friend-Realm")
    local rows = ns.Multiplayer:RosterRows()

    assertEqual(rows[1].readiness, "Warning", "version mismatch warns")
    assertEqual(rows[1].readinessReason, "version mismatch", "version mismatch reason")
end

local function testProfileMismatchWarns()
    local ns = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:Receive("STATE", r2Payload({ profile = "banked_hardcore" }), "PARTY", "Friend-Realm")
    local rows = ns.Multiplayer:RosterRows()

    assertEqual(rows[1].readiness, "Warning", "profile mismatch warns")
    assertEqual(rows[1].readinessReason, "different profile", "profile mismatch reason")
end

local function testRulesMismatchWarns()
    local ns = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:Receive("STATE", r2Payload({ rules = "r1-1234" }), "PARTY", "Friend-Realm")
    local rows = ns.Multiplayer:RosterRows()

    assertEqual(rows[1].readiness, "Warning", "rules mismatch warns")
    assertEqual(rows[1].readinessReason, "different rules", "rules mismatch reason")
end

local function testMissingBankWarns()
    local ns = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:Receive("STATE", r2Payload({ bank = "0" }), "PARTY", "Friend-Realm")
    local rows = ns.Multiplayer:RosterRows()

    assertEqual(rows[1].readiness, "Warning", "missing bank warns")
    assertEqual(rows[1].readinessReason, "no bank set", "missing bank reason")
end

local function testFinalDeathWarns()
    local ns = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:Receive("STATE", r2Payload({ state = "dead_pending_contribution", lives = "0", finalDeath = "1" }), "PARTY", "Friend-Realm")
    local rows = ns.Multiplayer:RosterRows()

    assertEqual(rows[1].readiness, "Warning", "final death warns")
    assertEqual(rows[1].readinessReason, "final death pending", "final death reason")
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
    assertContains(joined, "Unknown - older client", "dashboard includes legacy readiness")
    assertContains(joined, "final death", "dashboard includes readable event kind")
end

local function testDashboardLinesShowReadyPeerCompactly()
    local ns = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:Receive("STATE", r2Payload(), "PARTY", "Friend-Realm")
    local joined = table.concat(ns.Multiplayer:DashboardLines(), "\n")

    assertContains(joined, "Friend lvl 31", "dashboard keeps compact peer row")
    assertContains(joined, "Ready - aligned", "dashboard includes ready status")
end

local function testDashboardLinesNameAuditEvents()
    local ns = resetHarness()
    ns.Multiplayer:Init()

    ns.Multiplayer:Receive("EVENT", "evt-3^Friend-Realm^request_created^31^3^active^Rewards 101, 201", "PARTY", "Friend-Realm")
    ns.Multiplayer:Receive("EVENT", "evt-4^Friend-Realm^bank_fulfilled^31^3^active^Rewards 101, 201", "PARTY", "Friend-Realm")
    ns.Multiplayer:Receive("EVENT", "evt-5^Friend-Realm^contribution_completed^31^3^retired^105c", "PARTY", "Friend-Realm")
    local joined = table.concat(ns.Multiplayer:DashboardLines(), "\n")

    assertContains(joined, "request created", "dashboard labels request audit event")
    assertContains(joined, "bank fulfilled", "dashboard labels bank fulfillment audit event")
    assertContains(joined, "contribution completed", "dashboard labels contribution audit event")
end

testInitRegistersMultiplayerOps()
testGroupHelloBroadcastUsesCompactRunSummary()
testGuildDiscoverySendsLightweightHello()
testStateBroadcastsAreThrottled()
testIncomingStateUpdatesRosterAndExpiresWhenStale()
testMatchingR2PeerIsReady()
testVersionMismatchWarns()
testProfileMismatchWarns()
testRulesMismatchWarns()
testMissingBankWarns()
testFinalDeathWarns()
testHelloAndByeCreateLocalJoinLeaveFeed()
testDuplicateEventsAreIgnored()
testDashboardLinesSummarizeRosterAndEvents()
testDashboardLinesShowReadyPeerCompactly()
testDashboardLinesNameAuditEvents()

print("Multiplayer.test.lua: ok")
