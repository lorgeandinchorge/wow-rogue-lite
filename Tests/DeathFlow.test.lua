local popupShown = {}
local printed = {}
local currentDead = true
local currentMoney = 12345
local registeredEvents = {}
local hasDeadOrGhostApi = true
local unitIsDead = false
local unitIsGhost = false

local function resetHarness(opts)
    opts = opts or {}
    popupShown = {}
    printed = {}
    registeredEvents = {}
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

    _G.time = function() return 200 end
    _G.UnitLevel = function() return 12 end
    _G.GetRealZoneText = function() return "Westfall" end
    _G.GetSubZoneText = function() return "Moonbrook" end
    _G.GetMoney = function() return currentMoney end
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
        local module = {}
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

    function ns.Database:IsBankCharacter() return false end
    function ns.Database:GetCurrentCharacter() return WRL_DB.characters["Runner-Realm"] end
    function ns.Database:GetCharacter(key) return WRL_DB.characters[key] end
    function ns.Database:RecordDeathEntry(key, level, zone)
        local rec = self:GetCharacter(key)
        rec.retiredAt = rec.retiredAt or time()
        rec.levelCurrent = level
        rec.deathLog[#rec.deathLog + 1] = { when = time(), level = level, zone = zone }
    end
    function ns.Database:HasMemorial() return false end
    function ns.Database:SaveMemorial(entry) WRL_DB.memorials[entry.uid] = entry end
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

    function ns.Tiers:FormatMoney(copper)
        return tostring(copper) .. "c"
    end
    function ns.Settings:Get() return "off" end
    function ns.Settings:GetProfile() return "default" end
    function ns.Rules:TaintCount() return 0 end

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

local function testAlreadyDeadCharacterTriggersFinalDeathPopup()
    local ns = resetHarness()

    ns.Death:ReconcileCurrentDeath("login")

    local rec = WRL_DB.characters["Runner-Realm"]
    assertEqual(rec.status, "dead_pending_contribution", "already-dead run enters contribution-pending state")
    assertEqual(rec.stateReason, "final_death_login", "state reason records missed-death reconciliation")
    assertEqual(#rec.deathLog, 1, "final death records one death entry")
    assertEqual(#popupShown, 1, "final death popup is shown")
    assertEqual(popupShown[1].name, "WRL_RETIRE_CONFIRM", "final death uses retire confirmation popup")
end

local function testDuplicateAlreadyDeadCheckDoesNotDuplicateDeath()
    local ns = resetHarness()

    ns.Death:ReconcileCurrentDeath("login")
    ns.Death:ReconcileCurrentDeath("player_alive")

    local rec = WRL_DB.characters["Runner-Realm"]
    assertEqual(#rec.deathLog, 1, "duplicate reconciliation does not add another death")
    assertEqual(#popupShown, 1, "duplicate reconciliation does not show another popup")
end

local function testAlreadyGhostedCharacterUsesClassicApiFallback()
    resetHarness({
        hasDeadOrGhostApi = false,
        unitIsGhost = true,
    })

    local rec = WRL_DB.characters["Runner-Realm"]
    assertEqual(rec.status, "dead_pending_contribution", "ghost fallback detects an already-dead run")
    assertEqual(#popupShown, 1, "ghost fallback shows final death popup")
end

local function testEnteringWorldRechecksAlreadyDeadCharacter()
    resetHarness({ currentDead = false, livesRemaining = 1 })
    local rec = WRL_DB.characters["Runner-Realm"]

    currentDead = true
    registeredEvents.PLAYER_ENTERING_WORLD()

    assertEqual(rec.status, "dead_pending_contribution", "entering world catches dead state after login")
    assertEqual(rec.stateReason, "final_death_entering_world", "entering world records missed-death reason")
    assertEqual(#popupShown, 1, "entering world shows final death popup")
end

local function testOutOfLivesActiveCharacterFinalizesOnLoginEvenWhenAlive()
    resetHarness({ currentDead = false })

    local rec = WRL_DB.characters["Runner-Realm"]
    assertEqual(rec.status, "dead_pending_contribution", "active out-of-lives run finalizes even when corpse state was missed")
    assertEqual(rec.stateReason, "final_death_login_out_of_lives", "out-of-lives login path records reason")
    assertEqual(#popupShown, 1, "out-of-lives login path shows final death popup")
end

local function testOutOfLivesActiveCharacterFinalizesOnReviveEvent()
    resetHarness({ currentDead = false, livesRemaining = 1 })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "active"
    rec.livesRemaining = 0
    rec.stateReason = nil
    rec.deathLog = {}
    rec.deathSnapshot = nil
    popupShown = {}

    registeredEvents.PLAYER_ALIVE()

    assertEqual(rec.status, "dead_pending_contribution", "revive event catches active out-of-lives run")
    assertEqual(rec.stateReason, "final_death_player_alive_out_of_lives", "revive event records out-of-lives reason")
    assertEqual(#popupShown, 1, "revive event shows final death popup")
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

testAlreadyDeadCharacterTriggersFinalDeathPopup()
testDuplicateAlreadyDeadCheckDoesNotDuplicateDeath()
testAlreadyGhostedCharacterUsesClassicApiFallback()
testEnteringWorldRechecksAlreadyDeadCharacter()
testOutOfLivesActiveCharacterFinalizesOnLoginEvenWhenAlive()
testOutOfLivesActiveCharacterFinalizesOnReviveEvent()
testDeathPopupExplainsNextStepsAndMaximumPotential()

print("DeathFlow.test.lua: ok")
