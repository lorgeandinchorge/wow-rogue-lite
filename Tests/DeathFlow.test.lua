local mockTime = 200   -- tests set this to control time(); reset inside resetHarness

local popupShown = {}
local printed = {}
local currentDead = true
local currentMoney = 12345
local registeredEvents = {}
local mailFields = {}
local inboxHeaders = {}
local hasDeadOrGhostApi = true
local unitIsDead = false
local unitIsGhost = false
local deathScreenShows = {}    -- captured ns.DeathScreen:Show invocations

local function resetHarness(opts)
    opts = opts or {}
    popupShown = {}
    printed = {}
    registeredEvents = {}
    mailFields = {}
    inboxHeaders = opts.inboxHeaders or {}
    deathScreenShows = {}
    currentDead = opts.currentDead
    if currentDead == nil then currentDead = true end
    currentMoney = opts.currentMoney or 12345
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
        contributionReceipts = {},
        contributionMail = {},
        totalContributed = 0,
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
        local dialog = StaticPopupDialogs[name]
        if dialog and dialog.text then
            string.format(dialog.text, ...)
        end
    end
    _G.CreateFrame = function(_frameType)
        return {
            RegisterEvent = function() end,
            SetScript     = function() end,
        }
    end
    _G.MailFrame = { IsShown = function() return true end }
    _G.MailFrameTab2 = { Click = function() mailFields.clickedSendTab = true end }
    _G.SendMailNameEditBox = { SetText = function(_, value) mailFields.name = value end }
    _G.SendMailSubjectEditBox = { SetText = function(_, value) mailFields.subject = value end }
    _G.SendMailBodyEditBox = { SetText = function(_, value) mailFields.body = value end }
    _G.SendMailMoney = {}
    _G.SendMailMoneyGold = { SetNumber = function(_, value) mailFields.gold = value end, SetText = function(_, value) mailFields.goldText = value end }
    _G.SendMailMoneySilver = { SetNumber = function(_, value) mailFields.silver = value end, SetText = function(_, value) mailFields.silverText = value end }
    _G.SendMailMoneyCopper = { SetNumber = function(_, value) mailFields.copper = value end, SetText = function(_, value) mailFields.copperText = value end }
    _G.MoneyInputFrame_SetCopper = function(_, value) mailFields.money = value end
    _G.GetInboxNumItems = function() return #inboxHeaders end
    _G.GetInboxHeaderInfo = function(index)
        local h = inboxHeaders[index] or {}
        return h.packageIcon, h.stationeryIcon, h.sender, h.subject, h.money, h.CODAmount,
            h.daysLeft, h.itemCount, h.wasRead, h.wasReturned, h.textCreated
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

    function ns.Database:IsBankCharacter() return opts.isBank or false end
    function ns.Database:GetCurrentCharacter() return WRL_DB.characters["Runner-Realm"] end
    function ns.Database:GetCharacter(key) return WRL_DB.characters[key] end
    function ns.Database:TotalContributed() return WRL_DB.totalContributed or 0 end
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
    function ns.Contributions:Record(characterKey, amount, source, info)
        local rec = WRL_DB.characters[characterKey]
        if not rec then return nil end
        local receipt = {
            id = "test-receipt-" .. tostring(#(WRL_DB.contributionReceipts or {}) + 1),
            characterKey = characterKey,
            amount = amount,
            source = source,
            note = info and info.note or "",
            confidence = info and info.confidence or "estimated",
        }
        WRL_DB.contributionReceipts = WRL_DB.contributionReceipts or {}
        WRL_DB.contributionReceipts[#WRL_DB.contributionReceipts + 1] = receipt
        rec.contributed = (rec.contributed or 0) + amount
        WRL_DB.totalContributed = (WRL_DB.totalContributed or 0) + amount
        return receipt
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
    resetHarness({ currentDead = false })

    local text = popupShown[1] and popupShown[1].args[1] or ""
    assertContains(text, "YOU DIED", "popup headline is explicit")
    assertContains(text, "NEXT STEPS FOR WOW ROGUE LITE", "popup explains this is the next-step flow")
    assertContains(text, "Maximum possible contribution", "popup shows max contribution label")
    assertContains(text, "Go to a mailbox", "popup lists mailbox step")
    assertContains(text, "sell vendorable bags/gear", "popup explains max-value path")
end

local function testFinalDeathPopupUsesSingleFormattedMessageArgument()
    resetHarness({ currentDead = false })

    local popup = popupShown[1]
    assert(popup ~= nil, "final death popup was shown")
    assertEqual(popup.name, "WRL_RETIRE_CONFIRM", "final death popup name")
    assertEqual(StaticPopupDialogs["WRL_RETIRE_CONFIRM"].text, "%s",
        "retire confirmation popup template accepts exactly one formatted message")
    assertEqual(#popup.args, 1, "final death popup passes one formatted body argument")
    assertContains(popup.args[1], "Runner-Realm", "formatted popup includes character key")
    assertContains(popup.args[1], "Current money: 12345c", "formatted popup includes current money")
    assertContains(popup.args[1], "Bank-Realm", "formatted popup includes bank character")
end

local function testFinalDeathPopupWarnsWhenContributionCannotCoverPostage()
    resetHarness({ currentDead = false })
    local popup = popupShown[1]

    assert(popup ~= nil, "final death popup was shown")
    assert(not popup.args[1]:find("less than the 30c postage", 1, true),
        "normal contribution does not show postage warning")

    resetHarness({ currentDead = false })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "dead_pending_contribution"
    rec.deathSnapshot = {
        preMoney = 10,
        estimatedBagValue = 0,
        estimatedGearValue = 0,
        totalLiquid = 10,
        maximumPotential = 10,
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
    popupShown = {}

    registeredEvents.PLAYER_ENTERING_WORLD()

    assertContains(popupShown[1].args[1], "less than the 30c postage",
        "tiny final contribution warns about postage")
end

local function testContributionMailFillCreatesDurableMailRecordAndBody()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1 })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "dead_pending_contribution"
    rec.deathSnapshot = {
        preMoney = 12345,
        estimatedBagValue = 2000,
        estimatedGearValue = 3000,
        totalLiquid = 14345,
        maximumPotential = 17345,
    }

    ns.Death:OpenMailToBank()
    registeredEvents.MAIL_SHOW()

    assertEqual(popupShown[#popupShown].name, "WRL_CONTRIBUTION_AMOUNT",
        "opening mailbox asks player to confirm contribution amount")

    StaticPopupDialogs["WRL_CONTRIBUTION_AMOUNT"].OnAccept({
        editBox = { GetText = function() return "1g 23s 45c" end },
    })

    assertEqual(mailFields.clickedSendTab, true,
        "contribution mail switches to send tab")
    assertEqual(mailFields.name, "Bank",
        "contribution mail fills same-realm bank recipient")
    assertEqual(mailFields.money, 12345,
        "contribution mail fills current copper amount")
    assertContains(mailFields.subject, "WRL-CONTRIB:",
        "contribution mail uses importable subject prefix")
    assertContains(mailFields.body, "WRL-CONTRIB-ID:",
        "contribution mail body stores durable contribution id")
    assertContains(mailFields.body, "Runner-Realm",
        "contribution mail body stores source character")
    assert(WRL_DB.contributionMail.outbox ~= nil,
        "contribution mail creates outbox ledger")
end

local function testContributionMailUsesConfirmedGoldSilverCopperAmount()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1, currentMoney = 150000 })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "dead_pending_contribution"
    rec.deathSnapshot = {
        preMoney = 150000,
        estimatedBagValue = 0,
        estimatedGearValue = 0,
        totalLiquid = 150000,
        maximumPotential = 150000,
    }

    ns.Death:OpenMailToBank()
    registeredEvents.MAIL_SHOW()
    StaticPopupDialogs["WRL_CONTRIBUTION_AMOUNT"].OnAccept({
        editBox = { GetText = function() return "2g 3s 4c" end },
    })

    assertEqual(mailFields.money, 20304,
        "combined money frame receives confirmed copper")
    assertEqual(mailFields.gold, 2,
        "mail gold field receives confirmed gold")
    assertEqual(mailFields.silver, 3,
        "mail silver field receives confirmed silver")
    assertEqual(mailFields.copper, 4,
        "mail copper field receives confirmed copper")
    assertContains(mailFields.body, "Attached copper: 20304c",
        "mail body records exact confirmed contribution amount")
end

local function testContributionMailAllowsExplicitZeroCopper()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1, currentMoney = 150000 })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "dead_pending_contribution"
    rec.deathSnapshot = {
        preMoney = 150000,
        estimatedBagValue = 0,
        estimatedGearValue = 0,
        totalLiquid = 150000,
        maximumPotential = 150000,
    }

    ns.Death:OpenMailToBank()
    registeredEvents.MAIL_SHOW()
    StaticPopupDialogs["WRL_CONTRIBUTION_AMOUNT"].OnAccept({
        editBox = { GetText = function() return "0g 0s 0c" end },
    })

    assertEqual(mailFields.money, 0,
        "explicit zero contribution does not fall back to suggested amount")
    assertEqual(mailFields.gold, 0,
        "explicit zero fills zero gold")
    assertEqual(mailFields.silver, 0,
        "explicit zero fills zero silver")
    assertEqual(mailFields.copper, 0,
        "explicit zero fills zero copper")
end

local function testBankInboxContributionMailCreditsAttachedCopperOnce()
    local mailId = "Runner-Realm#100-200"
    resetHarness({
        currentDead = false,
        livesRemaining = 1,
        isBank = true,
        inboxHeaders = {
            { sender = "Runner", subject = "WRL-CONTRIB: " .. mailId, money = 4321, itemCount = 0 },
        },
    })
    WRL_DB.contributionMail = {
        outbox = {
            [mailId] = {
                id = mailId,
                characterKey = "Runner-Realm",
                uid = "Runner-Realm#100",
                estimated = 14345,
                status = "sent",
            },
        },
        inbox = {},
    }

    registeredEvents.MAIL_SHOW()
    registeredEvents.MAIL_SHOW()

    local rec = WRL_DB.characters["Runner-Realm"]
    assertEqual(rec.contributed, 4321,
        "bank inbox scan credits attached contribution copper")
    assertEqual(WRL_DB.totalContributed, 4321,
        "bank inbox scan updates lifetime contribution")
    assertEqual(#WRL_DB.contributionReceipts, 1,
        "bank inbox scan does not double-credit the same contribution mail")
    assertEqual(WRL_DB.contributionMail.outbox[mailId].status, "received",
        "bank inbox scan marks contribution mail received")
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
testFinalDeathPopupUsesSingleFormattedMessageArgument()
testFinalDeathPopupWarnsWhenContributionCannotCoverPostage()
testContributionMailFillCreatesDurableMailRecordAndBody()
testContributionMailUsesConfirmedGoldSilverCopperAmount()
testContributionMailAllowsExplicitZeroCopper()
testBankInboxContributionMailCreditsAttachedCopperOnce()
testCombatDamageSourceCapturedBeforeDeath()
testEnvironmentalDamageSourceCapturedBeforeDeath()
testFinalDeathMemorialIncludesSourceContext()
testDuplicatePlayerDeadDoesNotConsumeTwoSoftDeathLives()
testStaleLastAttackerIsIgnoredAfterTimeout()
testMissingMapAPIsDoNotBreakDeathHandling()

print("DeathFlow.test.lua: ok")
