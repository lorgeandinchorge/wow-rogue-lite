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
local instanceType = nil
local deathScreenShows = {}    -- captured ns.DeathScreen:Show invocations
local createdButtons = {}
local scheduledTimers = {}

local function resetHarness(opts)
    opts = opts or {}
    popupShown = {}
    printed = {}
    registeredEvents = {}
    mailFields = {}
    inboxHeaders = opts.inboxHeaders or {}
    deathScreenShows = {}
    createdButtons = {}
    scheduledTimers = {}
    currentDead = opts.currentDead
    if currentDead == nil then currentDead = true end
    currentMoney = opts.currentMoney or 12345
    hasDeadOrGhostApi = opts.hasDeadOrGhostApi
    if hasDeadOrGhostApi == nil then hasDeadOrGhostApi = true end
    unitIsDead = opts.unitIsDead or false
    unitIsGhost = opts.unitIsGhost or false
    instanceType = opts.instanceType

    WRL_DB = {
        bankCharacter = "Bank-Realm",
        settings = opts.settings or {},
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
    _G.IsInInstance = function()
        return instanceType ~= nil, instanceType
    end
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
    _G.CreateFrame = function(frameType, name, parent, template)
        local frame = {
            frameType = frameType,
            name = name,
            parent = parent,
            template = template,
            RegisterEvent = function() end,
            SetScript     = function(self, script, handler)
                if script == "OnClick" then self.onClick = handler end
            end,
            SetText       = function(self, value) self.text = value end,
            SetSize       = function(self, width, height) self.width = width; self.height = height end,
            SetPoint      = function(self, ...) self.point = { ... } end,
            SetParent     = function(self, value) self.parent = value end,
            SetFrameStrata = function(self, value) self.frameStrata = value end,
            SetFrameLevel = function(self, value) self.frameLevel = value end,
            ClearAllPoints = function(self) self.pointsCleared = true end,
            HookScript    = function(self, script, handler) self.hooks = self.hooks or {}; self.hooks[script] = handler end,
            Show          = function(self) self.shown = true end,
            Hide          = function(self) self.shown = false end,
            IsShown       = function(self) return self.shown end,
        }
        if frameType == "Button" then createdButtons[#createdButtons + 1] = frame end
        return frame
    end
    _G.UIParent = {}
    _G.C_Timer = {
        After = function(_, cb)
            scheduledTimers[#scheduledTimers + 1] = cb
        end,
    }
    _G.MailFrame = {
        shown = true,
        IsShown = function(self) return self.shown end,
        HookScript = function(self, script, handler) self.hooks = self.hooks or {}; self.hooks[script] = handler end,
    }
    _G.MailFrameTab2 = { Click = function() mailFields.clickedSendTab = true end }
    _G.SendMailNameEditBox = { SetText = function(_, value) mailFields.name = value end }
    _G.SendMailSubjectEditBox = { SetText = function(_, value) mailFields.subject = value end }
    _G.SendMailBodyEditBox = { SetText = function(_, value) mailFields.body = value end }
    _G.SendMailMoney = {}
    _G.SendMailMoneyGold = {
        SetNumber = function(_, value) mailFields.gold = value end,
        SetText = function(_, value) mailFields.goldText = value end,
        GetNumber = function() return mailFields.gold end,
        GetText = function() return mailFields.goldText end,
    }
    _G.SendMailMoneySilver = {
        SetNumber = function(_, value) mailFields.silver = value end,
        SetText = function(_, value) mailFields.silverText = value end,
        GetNumber = function() return mailFields.silver end,
        GetText = function() return mailFields.silverText end,
    }
    _G.SendMailMoneyCopper = {
        SetNumber = function(_, value) mailFields.copper = value end,
        SetText = function(_, value) mailFields.copperText = value end,
        GetNumber = function() return mailFields.copper end,
        GetText = function() return mailFields.copperText end,
    }
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
            maximumPotential = math.max(0, currentMoney + 2000 + 3000 - 30),
            bagItems = {
                { link = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r", count = 4, copper = 40, sellPrice = 10 },
            },
            gearItems = {
                { link = "|cff9d9d9d|Hitem:25::::::::|h[Worn Shortsword]|h|r", count = 1, copper = 70, sellPrice = 70 },
            },
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
    function ns.Contributions:CreditFinalDeath(key)
        local rec = WRL_DB.characters[key]
        local snap = rec and rec.deathSnapshot
        if not snap or snap.credited then return nil end
        local amount = math.min(snap.maximumPotential or snap.totalLiquid or 0,
            math.max(0, (snap.preMoney or 0) - currentMoney))
        snap.credited = true
        if amount <= 0 then return nil end
        return self:Record(key, amount, "final_contribution", {
            confidence = "estimated",
            note = "legacy delta estimate",
        })
    end

    function ns.Tiers:FormatMoney(copper)
        return tostring(copper) .. "c"
    end
    function ns.Settings:Get(pathOrKey, default)
        local tbl = WRL_DB.settings or {}
        for segment in tostring(pathOrKey or ""):gmatch("[^%.]+") do
            if type(tbl) ~= "table" then return default end
            tbl = tbl[segment]
        end
        if tbl == nil then return default end
        return tbl
    end
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

local function assertNotContains(haystack, needle, message)
    if haystack and haystack:find(needle, 1, true) then
        error(string.format("%s: expected %q not to contain %q", message, tostring(haystack), needle), 2)
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
        maximumPotential = 17315,
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
    assertContains(text, "Expected final contribution", "popup shows expected contribution label")
    assertContains(text, "Go to a mailbox", "popup lists mailbox step")
    assertContains(text, "Sell vendorable bags and gear", "popup explains currency-only preparation")
    assertNotContains(text, "drag", "popup no longer asks the player to drag items")
end

local function testDeathPopupShowsCapturedItemVendorValues()
    local ns = resetHarness({ currentDead = false })
    local rec = WRL_DB.characters["Runner-Realm"]

    local text = popupShown[1] and popupShown[1].args[1] or ""
    assertContains(text, "Captured bag value:", "popup names captured bag item values")
    assertContains(text, "x4 |cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r - 40c vendor",
        "popup lists bag stack vendor value")
    assertContains(text, "Captured gear value:", "popup names captured gear item values")
    assertContains(text, "x1 |cff9d9d9d|Hitem:25::::::::|h[Worn Shortsword]|h|r - 70c vendor",
        "popup lists gear vendor value")
    assertEqual(rec.status, "dead_pending_contribution",
        "item value reporting does not change death state")
    assert(ns ~= nil, "harness returns namespace")
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

local function testRetirePopupCancelKeepsContributionPending()
    resetHarness({ currentDead = false })
    local rec = WRL_DB.characters["Runner-Realm"]

    StaticPopupDialogs["WRL_RETIRE_CONFIRM"].OnCancel()

    assertEqual(rec.status, "dead_pending_contribution",
        "canceling retire popup defers contribution instead of skipping it")
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
        maximumPotential = 17315,
    }

    ns.Death:OpenMailToBank()
    registeredEvents.MAIL_SHOW()

    assertEqual(mailFields.clickedSendTab, true,
        "contribution mail switches to send tab")
    assertEqual(mailFields.name, "Bank",
        "contribution mail fills same-realm bank recipient")
    assertEqual(mailFields.money, 12315,
        "contribution mail leaves 30c for postage")
    assertContains(mailFields.subject, "WRL-CONTRIB:",
        "contribution mail uses importable subject prefix")
    assertContains(mailFields.body, "WRL-CONTRIB-ID:",
        "contribution mail body stores durable contribution id")
    assertContains(mailFields.body, "Runner-Realm",
        "contribution mail body stores source character")
    assertContains(mailFields.body, "Expected final contribution:",
        "contribution mail body records expected currency-only target")
    assertContains(mailFields.body, "Attached copper: 12315c",
        "contribution mail body records exact attached currency")
    assert(WRL_DB.contributionMail.outbox ~= nil,
        "contribution mail creates outbox ledger")
end

local function testContributionMailUsesExpectedContributionWhenEnoughCurrencyRemains()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1, currentMoney = 150000 })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "dead_pending_contribution"
    rec.deathSnapshot = {
        preMoney = 150000,
        estimatedBagValue = 0,
        estimatedGearValue = 0,
        totalLiquid = 150000,
        maximumPotential = 100000,
    }

    ns.Death:OpenMailToBank()
    registeredEvents.MAIL_SHOW()

    assertEqual(mailFields.money, 100000,
        "combined money frame receives expected final contribution")
    assertEqual(mailFields.gold, 10,
        "mail gold field receives expected gold")
    assertEqual(mailFields.silver, 0,
        "mail silver field receives expected silver")
    assertEqual(mailFields.copper, 0,
        "mail copper field receives expected copper")
    assertContains(mailFields.body, "Attached copper: 100000c",
        "mail body records exact automatic contribution amount")
end

local function testContributionMailLeavesPostageWhenCurrencyIsBelowExpected()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1, currentMoney = 25 })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "dead_pending_contribution"
    rec.deathSnapshot = {
        preMoney = 25,
        estimatedBagValue = 0,
        estimatedGearValue = 0,
        totalLiquid = 25,
        maximumPotential = 1000,
    }

    ns.Death:OpenMailToBank()
    registeredEvents.MAIL_SHOW()

    assertEqual(mailFields.money, 0,
        "less than postage leaves zero attached")
    assertEqual(mailFields.gold, 0,
        "zero attach fills zero gold")
    assertEqual(mailFields.silver, 0,
        "zero attach fills zero silver")
    assertEqual(mailFields.copper, 0,
        "zero attach fills zero copper")
    assertContains(mailFields.body, "Attached copper: 0c",
        "mail body records zero attached amount")
end

local function testPrepareContributionMailCanBeReopenedWhenMailboxIsAlreadyOpen()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1, currentMoney = 5000 })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "dead_pending_contribution"
    rec.deathSnapshot = {
        preMoney = 5000,
        estimatedBagValue = 0,
        estimatedGearValue = 0,
        totalLiquid = 5000,
        maximumPotential = 4970,
    }

    local ok = ns.Death:PrepareContributionMail()

    assertEqual(ok, true, "recovery action fills contribution when mailbox is open")
    assertEqual(mailFields.money, 4970,
        "recovery action fills expected contribution")
end

local function testMailboxContributionButtonShowsWhenMailboxOpen()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1 })
    ns.Death:Init()

    assert(ns.Death.contributionButton ~= nil,
        "mailbox contribution button is created during Death init")

    registeredEvents.MAIL_SHOW()

    assertEqual(ns.Death.contributionButton:IsShown(), true,
        "mailbox contribution button is visible when mailbox is open")
    assertEqual(ns.Death.contributionButton.text, "WRL: Contribute",
        "mailbox contribution button has expected label")
    assertEqual(ns.Death.contributionButton.width, 112,
        "mailbox contribution button is compact enough for the header")
    assertEqual(ns.Death.contributionButton.point[1], "TOPLEFT",
        "mailbox contribution button anchors in the mail header strip")
    assertEqual(ns.Death.contributionButton.point[3], "TOPLEFT",
        "mailbox contribution button uses the mail header as anchor reference")
    assertEqual(ns.Death.contributionButton.point[4], 56,
        "mailbox contribution button sits in the top-left header after the mail icon")
    assertEqual(ns.Death.contributionButton.point[5], -1,
        "mailbox contribution button sits near the top edge of the header strip")
end

local function testMailboxContributionButtonClickPreparesMail()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1 })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "dead_pending_contribution"
    rec.deathSnapshot = {
        preMoney = 12345,
        estimatedBagValue = 0,
        estimatedGearValue = 0,
        totalLiquid = 12345,
        maximumPotential = 12315,
    }
    ns.Death:Init()
    registeredEvents.MAIL_SHOW()

    ns.Death.contributionButton.onClick()

    assertEqual(mailFields.name, "Bank",
        "mailbox contribution button fills contribution recipient")
end

local function testMailShowRetriesWhenMailFrameAppearsAfterEvent()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1 })
    _G.MailFrame = nil
    ns.Death.contributionButton = nil

    ns.Death:UpdateContributionButton()
    assertEqual(ns.Death.contributionButton, nil,
        "mail contribution button is not created before MailFrame exists")
    assert(#scheduledTimers > 0,
        "mail contribution button schedules a retry when MailFrame is missing")

    _G.MailFrame = {
        IsShown = function() return true end,
        GetFrameLevel = function() return 9 end,
    }
    scheduledTimers[1]()

    assert(ns.Death.contributionButton ~= nil,
        "mail contribution button is created by deferred retry after MailFrame appears")
    assertEqual(ns.Death.contributionButton:IsShown(), true,
        "deferred mail contribution button is shown when mailbox is open")
    assertEqual(ns.Death.contributionButton.parent, UIParent,
        "mail contribution button is parented to UIParent so MailFrame refreshes cannot hide it")
    assertEqual(ns.Death.contributionButton.frameStrata, "DIALOG",
        "mail contribution button is raised above mailbox internals")
    assertEqual(ns.Death.contributionButton.frameLevel, 29,
        "mail contribution button is raised relative to MailFrame")
end

local function testMailShowRefreshesAfterFrameBecomesShown()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1 })
    local mailOpen = false
    _G.MailFrame = {
        IsShown = function() return mailOpen end,
        GetFrameLevel = function() return 6 end,
    }
    ns.Death.contributionButton = nil
    ns.Death:_EnsureContributionButton()

    registeredEvents.MAIL_SHOW()
    assertEqual(ns.Death.contributionButton:IsShown(), false,
        "first mail-show pass can still see MailFrame as hidden")
    assert(#scheduledTimers > 0,
        "MAIL_SHOW schedules a follow-up refresh for the visible frame")

    mailOpen = true
    scheduledTimers[#scheduledTimers]()

    assertEqual(ns.Death.contributionButton:IsShown(), true,
        "follow-up mail-show refresh shows button once mailbox is visible")
end

local function testMailboxContributionButtonHidesWhenMailFrameHides()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1 })
    registeredEvents.MAIL_SHOW()

    assertEqual(ns.Death.contributionButton:IsShown(), true,
        "setup shows mailbox contribution button")
    assert(MailFrame.hooks and MailFrame.hooks.OnHide,
        "mail contribution button hooks MailFrame OnHide")

    MailFrame.shown = false
    MailFrame.hooks.OnHide()

    assertEqual(ns.Death.contributionButton:IsShown(), false,
        "mailbox contribution button hides with MailFrame")
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

local function testMailSendCreditsPreparedCopperInsteadOfWalletDelta()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1, currentMoney = 135 })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "dead_pending_contribution"
    rec.deathSnapshot = {
        preMoney = 135,
        estimatedBagValue = 0,
        estimatedGearValue = 0,
        totalLiquid = 135,
        maximumPotential = 105,
    }

    ns.Death:PrepareContributionMail()
    assertEqual(mailFields.money, 105, "setup attaches 105c and reserves 30c")

    currentMoney = 46
    registeredEvents.MAIL_SEND_SUCCESS()

    local receipt = WRL_DB.contributionReceipts[1]
    assert(receipt ~= nil, "mail send creates contribution receipt")
    assertEqual(receipt.amount, 105,
        "mail send credits the prepared attached copper, not wallet delta")
    assertEqual(receipt.source, "final_contribution_mail",
        "prepared mail credit is recorded as mail contribution")
    assertEqual(rec.status, "retired", "mail send retires the run")
end

local function testMailSendFallbackCountsGoldSilverAndCopperFields()
    local ns = resetHarness({ currentDead = false, livesRemaining = 1, currentMoney = 141 })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "dead_pending_contribution"
    rec.deathSnapshot = {
        preMoney = 141,
        estimatedBagValue = 0,
        estimatedGearValue = 0,
        totalLiquid = 141,
        maximumPotential = 111,
    }

    ns.Death:PrepareContributionMail()
    assertEqual(mailFields.silver, 1, "setup fills silver field")
    assertEqual(mailFields.copper, 11, "setup fills copper field")

    WRL_DB.contributionMail.outbox = {}
    rec._pendingContributionMailId = nil
    currentMoney = 130
    registeredEvents.MAIL_SEND_SUCCESS()

    local receipt = WRL_DB.contributionReceipts[1]
    assert(receipt ~= nil, "mail send creates fallback contribution receipt")
    assertEqual(receipt.amount, 111,
        "mail send fallback credits gold+silver+copper fields, not only copper")
    assertEqual(receipt.source, "final_contribution_mail",
        "field readback is recorded as mail contribution")
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

local function testCombatLogGetCurrentEventInfoSourceCapturedBeforeDeath()
    mockTime = 200
    local ns = resetHarness({ currentDead = false, livesRemaining = 1 })

    mockTime = 199
    _G.CombatLogGetCurrentEventInfo = function()
        return 199, "SPELL_DAMAGE", nil,
            "Creature-0-0002", "Murloc Tidehunter", 0, 0,
            "Player-1-00000001", "Runner", 0, 0,
            133, "Fireball", 4, 999
    end

    ns.Death:OnCombatLogEvent()
    _G.CombatLogGetCurrentEventInfo = nil

    mockTime = 200
    currentDead = true
    registeredEvents.PLAYER_DEAD()

    local memorial = WRL_DB.memorials["Runner-Realm#100"]
    assert(memorial ~= nil, "testCombatLogGetCurrentEventInfoSourceCapturedBeforeDeath: memorial created")
    assertEqual(memorial.sourceName, "Murloc Tidehunter",
        "testCombatLogGetCurrentEventInfoSourceCapturedBeforeDeath: memorial.sourceName")
end

local function testCombatLogGetCurrentEventInfoEnvironmentalDeathCaptured()
    mockTime = 200
    local ns = resetHarness({ currentDead = false, livesRemaining = 1 })

    mockTime = 199
    _G.CombatLogGetCurrentEventInfo = function()
        return 199, "ENVIRONMENTAL_DAMAGE", nil,
            nil, nil, 0, 0,
            "Player-1-00000001", "Runner", 0, 0,
            "Drowning", 999
    end

    ns.Death:OnCombatLogEvent()
    _G.CombatLogGetCurrentEventInfo = nil

    mockTime = 200
    currentDead = true
    registeredEvents.PLAYER_DEAD()

    local memorial = WRL_DB.memorials["Runner-Realm#100"]
    assert(memorial ~= nil, "testCombatLogGetCurrentEventInfoEnvironmentalDeathCaptured: memorial created")
    assertEqual(memorial.environmentalType, "Drowning",
        "testCombatLogGetCurrentEventInfoEnvironmentalDeathCaptured: environmentalType")
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
    assertEqual(WRL_DB.deathCount, 1,
        "testDuplicateDeath: duplicate PLAYER_DEAD increments account death count once")
    assertEqual(rec.status, "active",
        "testDuplicateDeath: soft death does not end the run")
    assertEqual(#rec.deathLog, 0,
        "testDuplicateDeath: soft death writes no death log entry")
end

local function testDungeonDeathIgnoredWhenSettingEnabled()
    local ns = resetHarness({
        currentDead = false,
        livesRemaining = 1,
        instanceType = "party",
        settings = { ignoreDungeonDeaths = true },
    })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "active"
    rec.livesRemaining = 1
    rec.deathLog = {}
    WRL_DB.memorials = {}
    WRL_DB.deathCount = 0
    popupShown = {}
    deathScreenShows = {}

    registeredEvents.PLAYER_DEAD()

    assertEqual(rec.status, "active", "ignored dungeon death keeps run active")
    assertEqual(rec.livesRemaining, 1, "ignored dungeon death does not consume a life")
    assertEqual(WRL_DB.deathCount, 0, "ignored dungeon death does not increment account death count")
    assertEqual(#rec.deathLog, 0, "ignored dungeon death writes no death log")
    assertEqual(next(WRL_DB.memorials), nil, "ignored dungeon death creates no memorial")
    assertEqual(#popupShown, 0, "ignored dungeon death shows no popup")
    assertEqual(#deathScreenShows, 0, "ignored dungeon death shows no death screen")
    assertEqual(rec.ignoreDeathUntilAlive, true, "ignored dungeon death is suppressed until revive")
end

local function testBattlegroundDeathIgnoredWhenSettingEnabled()
    resetHarness({
        currentDead = false,
        livesRemaining = 1,
        instanceType = "pvp",
        settings = { ignoreBattlegroundDeaths = true },
    })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "active"
    rec.livesRemaining = 1
    rec.deathLog = {}
    WRL_DB.memorials = {}
    WRL_DB.deathCount = 0
    popupShown = {}
    deathScreenShows = {}

    registeredEvents.PLAYER_DEAD()

    assertEqual(rec.status, "active", "ignored battleground death keeps run active")
    assertEqual(rec.livesRemaining, 1, "ignored battleground death does not consume a life")
    assertEqual(WRL_DB.deathCount, 0, "ignored battleground death does not increment account death count")
    assertEqual(#rec.deathLog, 0, "ignored battleground death writes no death log")
    assertEqual(next(WRL_DB.memorials), nil, "ignored battleground death creates no memorial")
    assertEqual(#popupShown, 0, "ignored battleground death shows no popup")
    assertEqual(#deathScreenShows, 0, "ignored battleground death shows no death screen")
end

local function testDungeonDeathStillCountsWhenSettingDisabled()
    resetHarness({
        currentDead = false,
        livesRemaining = 1,
        instanceType = "party",
        settings = { ignoreDungeonDeaths = false },
    })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "active"
    rec.livesRemaining = 1
    rec.deathLog = {}
    WRL_DB.memorials = {}
    WRL_DB.deathCount = 0
    popupShown = {}
    deathScreenShows = {}

    registeredEvents.PLAYER_DEAD()

    assertEqual(rec.status, "dead_pending_contribution", "dungeon death counts when ignore setting is disabled")
    assertEqual(rec.livesRemaining, 0, "counted dungeon death consumes the final life")
    assertEqual(WRL_DB.deathCount, 1, "counted dungeon death increments account death count")
    assert(WRL_DB.memorials["Runner-Realm#100"] ~= nil, "counted dungeon death creates a memorial")
end

local function testIgnoredDeathRemainsIgnoredAfterLeavingInstanceWhileDead()
    resetHarness({
        currentDead = false,
        livesRemaining = 1,
        instanceType = "party",
        settings = { ignoreDungeonDeaths = true },
    })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "active"
    rec.livesRemaining = 1
    rec.deathLog = {}
    WRL_DB.memorials = {}
    WRL_DB.deathCount = 0

    currentDead = true
    registeredEvents.PLAYER_DEAD()
    instanceType = nil
    registeredEvents.PLAYER_ENTERING_WORLD()

    assertEqual(rec.status, "active", "ignored corpse state remains active after zoning while dead")
    assertEqual(rec.livesRemaining, 1, "ignored corpse state still does not consume a life")
    assertEqual(WRL_DB.deathCount, 0, "ignored corpse state still does not increment death count")
    assertEqual(#rec.deathLog, 0, "ignored corpse state still writes no death log")
end

local function testIgnoredDeathFlagClearsOnReviveAndLaterWorldDeathCounts()
    resetHarness({
        currentDead = false,
        livesRemaining = 1,
        instanceType = "party",
        settings = { ignoreDungeonDeaths = true },
    })
    local rec = WRL_DB.characters["Runner-Realm"]
    rec.status = "active"
    rec.livesRemaining = 1
    rec.deathLog = {}
    WRL_DB.memorials = {}
    WRL_DB.deathCount = 0

    currentDead = true
    registeredEvents.PLAYER_DEAD()
    assertEqual(rec.ignoreDeathUntilAlive, true, "ignored death flag is set while corpse-running")

    currentDead = false
    registeredEvents.PLAYER_ALIVE()
    assertEqual(rec.ignoreDeathUntilAlive, nil, "ignored death flag clears when alive")

    instanceType = nil
    registeredEvents.PLAYER_DEAD()

    assertEqual(rec.status, "dead_pending_contribution", "later world death counts after ignored flag clears")
    assertEqual(rec.livesRemaining, 0, "later world death consumes the final life")
    assertEqual(WRL_DB.deathCount, 1, "later world death increments death count")
    assert(WRL_DB.memorials["Runner-Realm#100"] ~= nil, "later world death creates a memorial")
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
testDeathPopupShowsCapturedItemVendorValues()
testFinalDeathPopupUsesSingleFormattedMessageArgument()
testFinalDeathPopupWarnsWhenContributionCannotCoverPostage()
testRetirePopupCancelKeepsContributionPending()
testContributionMailFillCreatesDurableMailRecordAndBody()
testContributionMailUsesExpectedContributionWhenEnoughCurrencyRemains()
testContributionMailLeavesPostageWhenCurrencyIsBelowExpected()
testPrepareContributionMailCanBeReopenedWhenMailboxIsAlreadyOpen()
testMailboxContributionButtonShowsWhenMailboxOpen()
testMailboxContributionButtonClickPreparesMail()
testMailShowRetriesWhenMailFrameAppearsAfterEvent()
testMailShowRefreshesAfterFrameBecomesShown()
testMailboxContributionButtonHidesWhenMailFrameHides()
testBankInboxContributionMailCreditsAttachedCopperOnce()
testMailSendCreditsPreparedCopperInsteadOfWalletDelta()
testMailSendFallbackCountsGoldSilverAndCopperFields()
testCombatDamageSourceCapturedBeforeDeath()
testEnvironmentalDamageSourceCapturedBeforeDeath()
testFinalDeathMemorialIncludesSourceContext()
testCombatLogGetCurrentEventInfoSourceCapturedBeforeDeath()
testCombatLogGetCurrentEventInfoEnvironmentalDeathCaptured()
testDuplicatePlayerDeadDoesNotConsumeTwoSoftDeathLives()
testDungeonDeathIgnoredWhenSettingEnabled()
testBattlegroundDeathIgnoredWhenSettingEnabled()
testDungeonDeathStillCountsWhenSettingDisabled()
testIgnoredDeathRemainsIgnoredAfterLeavingInstanceWhileDead()
testIgnoredDeathFlagClearsOnReviveAndLaterWorldDeathCounts()
testStaleLastAttackerIsIgnoredAfterTimeout()
testMissingMapAPIsDoNotBreakDeathHandling()

print("DeathFlow.test.lua: ok")
