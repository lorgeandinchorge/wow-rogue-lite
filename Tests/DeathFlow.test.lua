local mockTime = 200   -- tests set this to control time(); reset inside resetHarness

local popupShown = {}
local printed = {}
local currentDead = true
local currentMoney = 12345
local registeredEvents = {}
local hasDeadOrGhostApi = true
local unitIsDead = false
local unitIsGhost = false
local deathScreenShows = {}    -- captured ns.DeathScreen:Show invocations

local function resetHarness(opts)
    opts = opts or {}
    popupShown = {}
    printed = {}
    registeredEvents = {}
    deathScreenShows = {}
    currentDead = opts.currentDead
    if currentDead == nil then currentDead = true end
    currentMoney = 12345
    hasDeadOrGhostApi = opts.hasDeadOrGhostApi
    if hasDeadOrGhostApi == nil then hasDeadOrGhostApi = true end
    unitIsDead = opts.unitIsDead or false
    unitIsGhost = opts.unitIsGhost or false

    WRL_DB = {
        bankCharacter = "Bank-Realm",
        characters = {
            ["Runner-Realm"] = {
                key = "Runner-Realm",
                uid = "Runner-Realm#100",
                status = "active",
                class = "WARRIOR",
                race = "HUMAN",
                levelCurrent = 12,
                livesRemaining = opts.livesRemaining or 0,
                deathLog = {},
                claimedTiers = {},
            },
        },
        memorials = {},
    }

    mockTime = 200
    _G.time = function() return mockTime end
    _G.UnitLevel = function() return 12 end
    _G.GetRealZoneText = function() return "Westfall" end
    _G.GetSubZoneText = function() return "Moonbrook" end
    _G.GetMoney = function() return currentMoney end
    _G.UnitGUID   = function(unit) return unit == "player" and "Player-1-00000001" or nil end
    _G.UnitName   = function(unit) return unit == "player" and "Runner" or nil end
    _G.UnitPosition  = function() return nil end   -- no position by default
    _G.GetInstanceInfo = function() return nil end
    _G.C_Map      = nil   -- no map API by default
    if hasDeadOrGhostApi then
        _G.UnitIsDeadOrGhost = function() return currentDead end
    else
        _G.UnitIsDeadOrGhost = nil
    end
    _G.UnitIsDead = function() return unitIsDead end
    _G.UnitIsGhost = function() return unitIsGhost end
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(name, ...)
        popupShown[#popupShown + 1] = { name = name, args = { ... } }
    end
    _G.CreateFrame = function(_frameType)
        return {
            RegisterEvent = function() end,
            SetScript     = function() end,
        }
    end

    local ns = {
        Database = {},
        Run = {},
        Contributions = {},
        Tiers = {},
        Settings = {},
        Rules = {},
        Achievements = nil,
    }

    function ns:NewModule(name)
        local module = self[name] or {}
        self[name] = module
        return module
    end

    function ns:On(event, cb)
        registeredEvents[event] = cb
    end
    function ns:UnitKey() return "Runner-Realm" end
    function ns:Print(msg, ...)
        if select("#", ...) > 0 then msg = msg:format(...) end
        printed[#printed + 1] = msg
    end
    function ns:Debug() end

    function ns.Database:IsBankCharacter() return false end
    function ns.Database:GetCurrentCharacter() return WRL_DB.characters["Runner-Realm"] end
    function ns.Database:GetCharacter(key) return WRL_DB.characters[key] end
    function ns.Database:RecordDeathEntry(key, level, zone, ctx)
        local rec = self:GetCharacter(key)
        rec.retiredAt = rec.retiredAt or time()
        rec.levelCurrent = level
        rec.deathLog[#rec.deathLog + 1] = { when = time(), level = level, zone = zone, ctx = ctx }
    end
    function ns.Database:HasMemorial(key)
        for _, m in pairs(WRL_DB.memorials) do
            if m and m.characterKey == key then return true end
        end
        return false
    end
    function ns.Database:GetMemorialByUID(uid)
        return uid and WRL_DB.memorials[uid] or nil
    end
    function ns.Database:HasMemorialUID(uid)
        return self:GetMemorialByUID(uid) ~= nil
    end
    function ns.Database:SaveMemorial(entry) WRL_DB.memorials[entry.uid] = entry end
    function ns.Database:AcknowledgeMemorial(uid)
        local m = WRL_DB.memorials[uid]
        if m then
            m.acknowledged = true
            m.acknowledgedAt = time()
        end
    end
    function ns.Database:ClaimedTierIds() return {} end

    function ns.Run:GetState(rec) return rec.status end
    function ns.Run:SetState(key, state, reason)
        local rec = WRL_DB.characters[key]
        rec.status = state
        rec.stateReason = reason
        return true
    end

    function ns.Contributions:SnapshotDeath(key)
        local rec = WRL_DB.characters[key]
        rec.deathSnapshot = {
            preMoney = currentMoney,
            estimatedBagValue = 2000,
            estimatedGearValue = 3000,
            totalLiquid = currentMoney + 2000,
            maximumPotential = currentMoney + 2000 + 3000,
        }
        return rec.deathSnapshot
    end
    function ns.Contributions:GetDeathSnapshot(key)
        local rec = WRL_DB.characters[key]
        return rec and rec.deathSnapshot or nil
    end

    function ns.Tiers:FormatMoney(copper)
        return tostring(copper) .. "c"
    end
    function ns.Settings:Get() return "off" end
    function ns.Settings:GetProfile() return "default" end
    function ns.Rules:TaintCount() return 0 end

    -- Stub the DeathScreen module: capture every Show invocation.  The
    -- stubbed Show fires the onContinue callback synchronously so the
    -- existing assertions for the retire popup still apply on the revive
    -- path.
    ns.DeathScreen = {
        Show = function(_, memorial, snap, rec, onContinue)
            deathScreenShows[#deathScreenShows + 1] = {
                memorial = memorial,
                snap = snap,
                rec = rec,
            }
            if type(onContinue) == "function" then onContinue() end
        end,
        Hide   = function() end,
        IsShown = function() return false end,
    }

    assert(loadfile("Core/Death.lua"))("WoWRoguelite", ns)
    ns.Death:Init()
    return ns
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertContains(haystack, needle, message)
    if not haystack or not haystack:find(needle, 1, true) then
        error(string.format("%s: expected %q to contain %q", message, tostring(haystack), needle), 2)
    end
end

-- ── Tests ────────────────────────────────────────────────────────────────────
-- Note: in the new flow the death screen + retire popup show on REVIVE, not
-- on PLAYER_DEAD.  The test harness's stubbed DeathScreen:Show fires
-- onContinue synchronously, so any test that previously asserted the retire
-- popup appears does so via the same revive path used in production.

local function testAlreadyDeadAtLoginSnapshotsButDoesNotShowDeathScreen()
    -- currentDead=true at login → reconcile takes the corpse path, runs
    -- bookkeeping, but does NOT show the death screen yet.
    resetHarness()

    local rec = WRL_DB.characters["Runner-Realm"]
    assertEqual(rec.status, "dead_pending_contribution",
        "already-dead run enters contribution-pending state")
    assertEqual(rec.stateReason, "final_death_login",
        "state reason records missed-death reconciliation")
    assertEqual(#rec.deathLog, 1, "final death records one death entry")
    assertEqual(#deathScreenShows, 0,
        "death screen is NOT shown while still corpse-running")
    assertEqual(#popupShown, 0,
        "retire popup is NOT shown while still corpse-running")
end

local function testReviveAfterAlreadyDeadShowsDeathScreenAndRetirePopup()
    -- Player was dead at login, then becomes alive (corpse run completes).
    local ns = resetHarness()

    currentDead = false
    registeredEvents.PLAYER_ALIVE()

    assertEqual(#deathScreenShows, 1,
        "death screen presented on revive after already-dead login")
    local memorial = WRL_DB.memorials["Runner-Realm#100"]
    assert(memorial ~= nil, "memorial exists after final death")
    assertEqual(memorial.acknowledged, true,
        "death screen Continue marks memorial acknowledged")
    assertEqual(#popupShown, 1, "retire popup is shown after death-screen continue")
    assertEqual(popupShown[1].name, "WRL_RETIRE_CONFIRM",
        "death-screen continue chains into retire confirmation popup")
end

local function testEnteringWorldAlivePresentsDeathScreenIfPending()
    -- Set up a player who logged in alive but the run is already in
    -- dead_pending_contribution state with an un-acknowledged memorial
    -- (e.g. they alt-F4'd after dying in a previous session).
    resetHarness({ currentDead = false, livesRemaining = 1 })
    -- Pre-existing death state from a prior session:
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "dead_pending_contribution"
    rec.livesRemaining = 0
    WRL_DB.memorials["Runner-Realm#100"] = {
        uid = "Runner-Realm#100",
        characterKey = "Runner-Realm",
        class = "WARRIOR",
        race = "HUMAN",
        level = 12,
        zone = "Westfall",
        livesUsed = 1,
        acknowledged = false,
    }
    deathScreenShows = {}
    popupShown = {}

    registeredEvents.PLAYER_ENTERING_WORLD()

    assertEqual(#deathScreenShows, 1,
        "PLAYER_ENTERING_WORLD presents death screen for un-acknowledged memorial")
    assertEqual(WRL_DB.memorials["Runner-Realm#100"].acknowledged, true,
        "memorial flagged acknowledged after death-screen Continue")
end

local function testAcknowledgedMemorialDoesNotRePopOnLogin()
    resetHarness({ currentDead = false })
    -- After first-login flow: revive → screen shown + acknowledged.
    currentDead = false
    registeredEvents.PLAYER_ALIVE()
    assertEqual(#deathScreenShows, 1, "first revive shows death screen once")

    -- Simulate a second PLAYER_ENTERING_WORLD (e.g. /reload, zone change).
    deathScreenShows = {}
    popupShown = {}
    registeredEvents.PLAYER_ENTERING_WORLD()

    assertEqual(#deathScreenShows, 0,
        "acknowledged memorial does NOT re-pop the death screen")
    assertEqual(#popupShown, 1,
        "acknowledged pending run still re-prompts the retire flow")
    assertEqual(popupShown[1].name, "WRL_RETIRE_CONFIRM",
        "acknowledged pending run reopens retire confirmation popup")
end

local function testSameNameNewGenerationCreatesOwnMemorial()
    resetHarness({ currentDead = false, livesRemaining = 1 })
    local rec = WRL_DB.characters["Runner-Realm"]

    WRL_DB.memorials["Runner-Realm#old"] = {
        uid = "Runner-Realm#old",
        characterKey = "Runner-Realm",
        class = "WARRIOR",
        race = "HUMAN",
        level = 8,
        zone = "Elwynn Forest",
        acknowledged = true,
    }

    currentDead = true
    registeredEvents.PLAYER_DEAD()

    assert(WRL_DB.memorials[rec.uid] ~= nil,
        "same-name reroll must create a memorial for the current uid")
    assertEqual(WRL_DB.memorials[rec.uid].characterKey, "Runner-Realm",
        "current-generation memorial keeps the character key")
    assertEqual(rec.status, "dead_pending_contribution",
        "same-name reroll still enters pending contribution state")
end

local function testAcknowledgedPendingRunReopensRetirePopupOnLogin()
    resetHarness({ currentDead = false, livesRemaining = 1 })

    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "dead_pending_contribution"
    rec.livesRemaining = 0
    rec.deathSnapshot = {
        preMoney = 12345,
        estimatedBagValue = 2000,
        estimatedGearValue = 3000,
        totalLiquid = 14345,
        maximumPotential = 17345,
    }
    WRL_DB.memorials[rec.uid] = {
        uid = rec.uid,
        characterKey = rec.key,
        class = "WARRIOR",
        race = "HUMAN",
        level = 12,
        zone = "Westfall",
        acknowledged = true,
    }

    deathScreenShows = {}
    popupShown = {}

    registeredEvents.PLAYER_ENTERING_WORLD()

    assertEqual(#deathScreenShows, 0,
        "acknowledged memorial does not re-open death screen")
    assertEqual(#popupShown, 1,
        "pending acknowledged run re-opens retire popup")
    assertEqual(popupShown[1].name, "WRL_RETIRE_CONFIRM",
        "pending acknowledged run uses retire confirmation popup")
end

local function testAlreadyGhostedCharacterUsesClassicApiFallback()
    resetHarness({
        hasDeadOrGhostApi = false,
        unitIsGhost = true,
    })

    local rec = WRL_DB.characters["Runner-Realm"]
    assertEqual(rec.status, "dead_pending_contribution",
        "ghost fallback detects an already-dead run")
    assertEqual(#deathScreenShows, 0,
        "death screen is NOT shown to a corpse-running ghost")
end

local function testEnteringWorldRechecksAlreadyDeadCharacter()
    resetHarness({ currentDead = false, livesRemaining = 1 })
    local rec = WRL_DB.characters["Runner-Realm"]

    currentDead = true
    registeredEvents.PLAYER_ENTERING_WORLD()

    assertEqual(rec.status, "dead_pending_contribution",
        "entering world catches dead state after login")
    assertEqual(rec.stateReason, "final_death_entering_world",
        "entering world records missed-death reason")
    -- Player is corpse-running (currentDead=true), so no death screen yet.
    assertEqual(#deathScreenShows, 0,
        "still corpse-running → no death screen yet")
end

local function testOutOfLivesActiveCharacterFinalizesOnLoginEvenWhenAlive()
    resetHarness({ currentDead = false })

    local rec = WRL_DB.characters["Runner-Realm"]
    assertEqual(rec.status, "dead_pending_contribution",
        "active out-of-lives run finalizes even when corpse state was missed")
    assertEqual(rec.stateReason, "final_death_login_out_of_lives",
        "out-of-lives login path records reason")
    -- And — because the player is alive at login — the death screen is shown
    -- by the TryPresentPendingDeathScreen("login") call inside Death:Init.
    assertEqual(#deathScreenShows, 1,
        "out-of-lives login path presents death screen immediately")
    assertEqual(#popupShown, 1,
        "retire popup chained from death-screen continue")
end

local function testOutOfLivesActiveCharacterFinalizesOnReviveEvent()
    resetHarness({ currentDead = false, livesRemaining = 1 })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "active"
    rec.livesRemaining = 0
    rec.stateReason = nil
    rec.deathLog = {}
    rec.deathSnapshot = nil
    WRL_DB.memorials = {}
    popupShown = {}
    deathScreenShows = {}

    registeredEvents.PLAYER_ALIVE()

    assertEqual(rec.status, "dead_pending_contribution",
        "revive event catches active out-of-lives run")
    assertEqual(rec.stateReason, "final_death_player_alive_out_of_lives",
        "revive event records out-of-lives reason")
    assertEqual(#deathScreenShows, 1, "revive event shows death screen")
    assertEqual(#popupShown, 1, "death-screen continue surfaces retire popup")
end

local function testDeathPopupExplainsNextStepsAndMaximumPotential()
    resetHarness()

    local text = StaticPopupDialogs["WRL_RETIRE_CONFIRM"].text
    assertContains(text, "YOU DIED", "popup headline is explicit")
    assertContains(text, "NEXT STEPS FOR WOW ROGUE LITE", "popup explains this is the next-step flow")
    assertContains(text, "Maximum possible contribution", "popup shows max contribution label")
    assertContains(text, "Go to a mailbox", "popup lists mailbox step")
    assertContains(text, "sell vendorable bags/gear", "popup explains max-value path")
end

local function testCombatDamageSourceCapturedBeforeDeath()
    -- Player alive on login (currentDead=false), 1 life → first PLAYER_DEAD is final.
    mockTime = 200
    local ns = resetHarness({ currentDead = false, livesRemaining = 1 })

    -- Simulate a melee hit 5 seconds before death.
    mockTime = 195
    ns.Death:OnCombatLogEvent(
        195, "SWING_DAMAGE", nil,
        "Creature-0-3684-0-0001", "Defias Trapper", 0x10a48, 0,
        "Player-1-00000001", "Runner", 0x512, 0)

    mockTime = 200
    -- Player is currentDead=false here; firing PLAYER_DEAD just runs the
    -- bookkeeping pass (no death screen yet because they're "still dead").
    currentDead = true
    registeredEvents.PLAYER_DEAD()

    local memorial = WRL_DB.memorials["Runner-Realm#100"]
    assert(memorial ~= nil, "testCombatDamageSourceCapturedBeforeDeath: memorial created")
    assertEqual(memorial.sourceName, "Defias Trapper",
        "testCombatDamageSourceCapturedBeforeDeath: memorial.sourceName")
end

local function testEnvironmentalDamageSourceCapturedBeforeDeath()
    mockTime = 200
    local ns = resetHarness({ currentDead = false, livesRemaining = 1 })

    mockTime = 198
    ns.Death:OnCombatLogEvent(
        198, "ENVIRONMENTAL_DAMAGE", nil,
        nil, nil, 0, 0,
        "Player-1-00000001", "Runner", 0x512, 0,
        "Falling", 9999)

    mockTime = 200
    currentDead = true
    registeredEvents.PLAYER_DEAD()

    local memorial = WRL_DB.memorials["Runner-Realm#100"]
    assert(memorial ~= nil, "testEnvironmentalDamageSourceCapturedBeforeDeath: memorial created")
    assertEqual(memorial.environmentalType, "Falling",
        "testEnvironmentalDamageSourceCapturedBeforeDeath: environmentalType")
    assert(memorial.sourceName == nil,
        "testEnvironmentalDamageSourceCapturedBeforeDeath: no creature sourceName for env death")
end

local function testFinalDeathMemorialIncludesSourceContext()
    mockTime = 200
    local ns = resetHarness({ currentDead = false, livesRemaining = 1 })

    ns.Death:OnCombatLogEvent(
        199, "SWING_DAMAGE", nil,
        "Creature-0-0001", "Hogger", 0, 0,
        "Player-1-00000001", "Runner", 0, 0)

    mockTime = 200
    currentDead = true
    registeredEvents.PLAYER_DEAD()

    local memorial = WRL_DB.memorials["Runner-Realm#100"]
    assert(memorial ~= nil, "testFinalDeathMemorialIncludesSourceContext: memorial created")
    assertEqual(memorial.sourceName, "Hogger",
        "testFinalDeathMemorialIncludesSourceContext: memorial.sourceName")

    local rec = WRL_DB.characters["Runner-Realm"]
    assert(rec.deathLog[1] ~= nil, "testFinalDeathMemorialIncludesSourceContext: deathLog entry exists")
    assert(rec.deathLog[1].ctx ~= nil,
        "testFinalDeathMemorialIncludesSourceContext: deathLog entry carries ctx")
    assertEqual(rec.deathLog[1].ctx.sourceName, "Hogger",
        "testFinalDeathMemorialIncludesSourceContext: deathLog ctx.sourceName")
end

local function testDuplicatePlayerDeadDoesNotConsumeTwoSoftDeathLives()
    mockTime = 200
    local ns = resetHarness({ currentDead = false, livesRemaining = 2 })
    local rec = WRL_DB.characters["Runner-Realm"]
    assertEqual(rec.status, "active", "testDuplicateDeath: setup - character is active")

    registeredEvents.PLAYER_DEAD()
    registeredEvents.PLAYER_DEAD()

    assertEqual(rec.livesRemaining, 1,
        "testDuplicateDeath: only one life consumed by duplicate PLAYER_DEAD")
    assertEqual(rec.status, "active",
        "testDuplicateDeath: soft death does not end the run")
    assertEqual(#rec.deathLog, 0,
        "testDuplicateDeath: soft death writes no death log entry")
end

local function testStaleLastAttackerIsIgnoredAfterTimeout()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1 })

    mockTime = 100
    ns.Death:OnCombatLogEvent(
        100, "SWING_DAMAGE", nil,
        "Creature-0-0001", "Old Enemy", 0, 0,
        "Player-1-00000001", "Runner", 0, 0)

    mockTime = 135
    currentDead = true
    registeredEvents.PLAYER_DEAD()

    local memorial = WRL_DB.memorials["Runner-Realm#100"]
    assert(memorial ~= nil, "testStaleAttacker: memorial created")
    assert(memorial.sourceName == nil,
        "testStaleAttacker: stale attacker is excluded from memorial")
end

local function testMissingMapAPIsDoNotBreakDeathHandling()
    mockTime = 200
    local ns = resetHarness({ currentDead = false, livesRemaining = 1 })

    _G.C_Map         = nil
    _G.GetInstanceInfo = nil
    _G.UnitPosition  = nil

    currentDead = true
    registeredEvents.PLAYER_DEAD()

    local memorial = WRL_DB.memorials["Runner-Realm#100"]
    assert(memorial ~= nil, "testMissingMapAPIs: memorial created despite missing APIs")
    assert(memorial.mapID == nil,    "testMissingMapAPIs: mapID is nil")
    assert(memorial.positionX == nil, "testMissingMapAPIs: positionX is nil")
    assert(memorial.instanceName == nil, "testMissingMapAPIs: instanceName is nil")
end

testAlreadyDeadAtLoginSnapshotsButDoesNotShowDeathScreen()
testReviveAfterAlreadyDeadShowsDeathScreenAndRetirePopup()
testEnteringWorldAlivePresentsDeathScreenIfPending()
testAcknowledgedMemorialDoesNotRePopOnLogin()
testSameNameNewGenerationCreatesOwnMemorial()
testAcknowledgedPendingRunReopensRetirePopupOnLogin()
testAlreadyGhostedCharacterUsesClassicApiFallback()
testEnteringWorldRechecksAlreadyDeadCharacter()
testOutOfLivesActiveCharacterFinalizesOnLoginEvenWhenAlive()
testOutOfLivesActiveCharacterFinalizesOnReviveEvent()
testDeathPopupExplainsNextStepsAndMaximumPotential()
testCombatDamageSourceCapturedBeforeDeath()
testEnvironmentalDamageSourceCapturedBeforeDeath()
testFinalDeathMemorialIncludesSourceContext()
testDuplicatePlayerDeadDoesNotConsumeTwoSoftDeathLives()
testStaleLastAttackerIsIgnoredAfterTimeout()
testMissingMapAPIsDoNotBreakDeathHandling()

print("DeathFlow.test.lua: ok")
