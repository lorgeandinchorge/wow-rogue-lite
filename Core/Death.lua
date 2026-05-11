-- Core/Death.lua
-- Hardcore-style death handling.
--
-- State transitions managed here (via ns.Run:SetState):
--   final death  → dead_pending_contribution
--   mail sent    → retired  (contribution credited)
--   "Not Now"    → retired  (contribution skipped)
--
-- Soft deaths (livesRemaining > 0) do not change run state and do not create
-- memorials.  A local notice is printed only when announceSoftDeaths = true.
--
-- ── Flow ─────────────────────────────────────────────────────────────────────
--
-- PLAYER_DEAD only does the bookkeeping (snapshot money/loot, write memorial,
-- transition state, announce).  No UI is shown while the player is corpse-
-- running.  The bookkeeping leaves rec.deathSnapshot + the memorial entry on
-- disk so a UI reload mid-corpse-run does not lose anything.
--
-- PLAYER_UNGHOST / PLAYER_ALIVE present the death screen the moment the player
-- is alive again (corpse run completed, or spirit-healer revival).  The death
-- screen is the new ns.DeathScreen overlay; its Continue button chains into
-- the existing WRL_RETIRE_CONFIRM popup so the contribution mail flow remains.
--
-- PLAYER_ENTERING_WORLD reconciles the run on login: if the character is
-- dead/ghosted but the run state is still active, we run the bookkeeping
-- pass.  If the character is alive but the state is dead_pending_contribution
-- (e.g. they alt-F4'd after dying and reloaded later), we re-present the death
-- screen until the player acknowledges it.
--
-- On a final death a memorial entry is written to WRL_DB.memorials (keyed by
-- character uid) exactly once.  Memorials carry an `acknowledged` flag set
-- when the player clicks Continue on the death screen — this prevents the
-- screen from re-popping every login forever.
--
-- We deliberately do NOT attempt to "lock" the character out of play — we just
-- stop crediting any further contributions from a retired char.

local ADDON_NAME, ns = ...
local D = ns:NewModule("Death")

-- ── Death-context state ───────────────────────────────────────────────────────
-- Populated by COMBAT_LOG_EVENT_UNFILTERED and CHAT_MSG_* handlers.
-- Snapshot is captured on final death, then reset.
local CTX_STALE_SEC = 30  -- ignore last attacker if their hit was >30 s ago
local D_ctx = {
    lastAttackSourceName        = nil,
    lastAttackSourceGuid        = nil,
    lastDamageEvent             = nil,   -- subevent: "SWING_DAMAGE", etc.
    lastEnvironmentalDamageType = nil,   -- "Falling", "Drowning", "Fire", etc.
    lastAttackTime              = nil,
    lastPlayerChatText          = nil,
    lastPlayerChatChannel       = nil,
    lastPlayerChatTime          = nil,
}
-- Soft-death cycle guard: set true when a soft death consumes a life,
-- reset to false on PLAYER_ALIVE / PLAYER_UNGHOST.
-- Prevents one corpse-state from burning multiple extra lives if
-- PLAYER_DEAD fires more than once before the revive event.
local deathCycleOpen = false

-- ── Helpers ──────────────────────────────────────────────────────────────────

-- Return a six-character hex colour for a WoW class name (e.g. "WARRIOR").
-- Falls back to a warm gold if RAID_CLASS_COLORS is unavailable.
local function classHex(class)
    local cc = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if cc then
        return string.format("%02x%02x%02x",
            math.floor((cc.r or 1) * 255),
            math.floor((cc.g or 1) * 255),
            math.floor((cc.b or 1) * 255))
    end
    return "ffd100"
end

-- Capitalise the first letter of an all-caps string ("WARRIOR" → "Warrior").
local function titleCase(s)
    if not s or s == "" then return s end
    return s:sub(1, 1):upper() .. s:sub(2):lower()
end

-- ── Death-context capture ────────────────────────────────────────────────────

local function playerGuid()
    return UnitGUID and UnitGUID("player") or nil
end

-- Called from a dedicated frame for COMBAT_LOG_EVENT_UNFILTERED.
-- In TBC Classic, combat log args are passed directly to OnEvent rather
-- than via CombatLogGetCurrentEventInfo(), so we receive them as varargs.
-- Only tracks damage sub-events where the destination is the player.
function D:OnCombatLogEvent(timestamp, subevent, _hiddenArg,
                             srcGUID, srcName, _srcFlags, _srcRaidFlags,
                             dstGUID, _dstName, _dstFlags, _dstRaidFlags, ...)
    local myGuid = playerGuid()
    if myGuid and dstGUID ~= myGuid then return end

    if subevent == "ENVIRONMENTAL_DAMAGE" then
        -- args after destRaidFlags: environmentalType, amount, ...
        local envType = select(1, ...)
        D_ctx.lastEnvironmentalDamageType = envType
        D_ctx.lastAttackSourceName        = nil
        D_ctx.lastAttackSourceGuid        = nil
        D_ctx.lastDamageEvent             = subevent
        D_ctx.lastAttackTime              = timestamp or time()
    elseif subevent == "SWING_DAMAGE"
        or subevent == "SPELL_DAMAGE"
        or subevent == "SPELL_PERIODIC_DAMAGE"
        or subevent == "RANGE_DAMAGE" then
        -- Only track hostile sources, not self-inflicted damage.
        if srcGUID and srcGUID ~= (myGuid or "") then
            D_ctx.lastAttackSourceName        = srcName
            D_ctx.lastAttackSourceGuid        = srcGUID
            D_ctx.lastDamageEvent             = subevent
            D_ctx.lastEnvironmentalDamageType = nil
            D_ctx.lastAttackTime              = timestamp or time()
        end
    end
end

-- Called when the player sends a chat message.
-- `channel` is "SAY", "PARTY", or "GUILD".
function D:OnPlayerChat(channel, text)
    D_ctx.lastPlayerChatText    = text
    D_ctx.lastPlayerChatChannel = channel
    D_ctx.lastPlayerChatTime    = time()
end

-- Returns a snapshot of current context, silently filtering stale attackers.
-- Called immediately before recording a final death.
function D:GetDeathContextSnapshot()
    local now  = time()
    local snap = {}
    local age  = D_ctx.lastAttackTime and (now - D_ctx.lastAttackTime) or math.huge
    if age <= CTX_STALE_SEC then
        snap.sourceName        = D_ctx.lastAttackSourceName
        snap.sourceGuid        = D_ctx.lastAttackSourceGuid
        snap.environmentalType = D_ctx.lastEnvironmentalDamageType
    end
    snap.lastWords   = D_ctx.lastPlayerChatText
    snap.lastChannel = D_ctx.lastPlayerChatChannel

    -- Map / position (degrade gracefully if APIs unavailable in Classic).
    if C_Map and C_Map.GetBestMapForUnit then
        snap.mapID = C_Map.GetBestMapForUnit("player")
    end
    if GetInstanceInfo then
        snap.instanceName = (select(1, GetInstanceInfo()))
        snap.instanceID   = (select(8, GetInstanceInfo()))
    end
    if UnitPosition then
        local y, x = UnitPosition("player")
        snap.positionX = x
        snap.positionY = y
    end
    return snap
end

-- Clears context state after a final death is fully recorded.
function D:ResetDeathContext()
    for k in pairs(D_ctx) do D_ctx[k] = nil end
    deathCycleOpen = false
end

-- ── Announcement ─────────────────────────────────────────────────────────────

-- Send a tasteful death announcement for `memorial` to the channel configured
-- in the announceDeaths setting.  Falls back to local when the target channel
-- is unavailable (not in a party / not in a guild).
function D:AnnounceMemorial(memorial)
    local dest = ns.Settings and ns.Settings:Get("announceDeaths", "local") or "local"
    if dest == "off" then return end

    local name  = (memorial.characterKey or ""):match("^([^%-]+)") or memorial.characterKey
    local hex   = classHex(memorial.class)
    local class = titleCase(memorial.class or "Unknown")
    local race  = memorial.race or "Unknown"
    local level = memorial.level or 0
    local zone  = (memorial.zone ~= "" and memorial.zone) or "Unknown Zone"

    -- Terse, flavourful one-liner.  Include cause of death when available.
    local cause = memorial.sourceName
        or (memorial.environmentalType and titleCase(memorial.environmentalType))
        or nil
    local msg
    if cause then
        msg = string.format(
            "[Roguelite] |cff%s%s|r the %s %s (lvl %d) has fallen in %s to %s. Their run is over.",
            hex, name, race, class, level, zone, cause)
    else
        msg = string.format(
            "[Roguelite] |cff%s%s|r the %s %s (lvl %d) has fallen in %s. Their run is over.",
            hex, name, race, class, level, zone)
    end

    if dest == "local" then
        ns:Print(msg)
    elseif dest == "party" then
        local inParty = GetNumPartyMembers and GetNumPartyMembers() or 0
        if inParty > 0 then
            SendChatMessage(msg, "PARTY")
        else
            ns:Print(msg)
        end
    elseif dest == "guild" then
        if IsInGuild and IsInGuild() then
            SendChatMessage(msg, "GUILD")
        else
            ns:Print(msg)
        end
    end
end

local RETIRE_SUBJECT = "Roguelite: final contribution"

function D:Init()
    ns:On("PLAYER_DEAD",       function() self:OnPlayerDead() end)
    ns:On("PLAYER_ENTERING_WORLD", function()
        self:ReconcileCurrentDeath("entering_world")
        -- ReconcileCurrentDeath above only handles the "missed-the-death-event"
        -- case.  If the player is alive at login but the run is already in
        -- dead_pending_contribution state (they alt-F4'd after dying, or
        -- released to graveyard between sessions), surface the death screen
        -- as a reminder.
        self:TryPresentPendingDeathScreen("entering_world")
    end)
    ns:On("PLAYER_FLAGS_CHANGED", function(unit)
        if unit == "player" then self:ReconcileCurrentDeath("flags_changed") end
    end)
    ns:On("PLAYER_UNGHOST",    function() self:OnRevive() end)
    ns:On("PLAYER_ALIVE",      function() self:OnRevive() end)
    ns:On("MAIL_SHOW",         function() self:OnMailShow() end)
    ns:On("MAIL_SEND_SUCCESS", function() self:OnMailSent() end)

    -- Combat-log context capture uses a dedicated frame because ns:On() does
    -- not forward event arguments to callbacks.
    local ctxFrame = CreateFrame("Frame")
    ctxFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    ctxFrame:SetScript("OnEvent", function(_, _event, ...)
        D:OnCombatLogEvent(...)
    end)

    -- Last-words capture: filter to our own messages by comparing the author
    -- arg to UnitName("player").
    local function onChatMsg(channel)
        return function(text, author)
            if author == (UnitName and UnitName("player") or "") then
                D:OnPlayerChat(channel, text)
            end
        end
    end
    ns:On("CHAT_MSG_SAY",   onChatMsg("SAY"))
    ns:On("CHAT_MSG_PARTY", onChatMsg("PARTY"))
    ns:On("CHAT_MSG_GUILD", onChatMsg("GUILD"))

    -- StaticPopup definitions (singletons so we register once).
    StaticPopupDialogs["WRL_RETIRE_CONFIRM"] = {
        text = "YOU DIED. WE'RE SORRY, BUT YOUR NEXT STEPS FOR WOW ROGUE LITE ARE...\n\n" ..
               "|cffc0a060%s|r is retired. This character can no longer contribute after this final handoff.\n\n" ..
               "Current money: %s\n" ..
               "Bag vendor value: %s\n" ..
               "Equipped gear vendor value: %s\n" ..
               "Maximum possible contribution: %s\n\n" ..
               "1. Go to a mailbox.\n" ..
               "2. The addon will pre-fill mail to your bank (|cffffd700%s|r).\n" ..
               "3. Send carried gold and eligible items you choose to contribute.\n" ..
               "4. To reach the maximum, sell vendorable bags/gear first, then mail the gold.\n" ..
               "5. After mail sends, the addon records the contribution and retires the run.",
        button1  = "Pre-Fill Mail",
        button2  = "Not Now",
        OnAccept = function() ns.Death:OpenMailToBank() end,
        -- "Not Now" skips the contribution and finalises the retirement.
        OnCancel = function()
            local key = ns:UnitKey()
            if key then ns.Run:SetState(key, "retired", "skipped_contribution") end
        end,
        timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    }
    StaticPopupDialogs["WRL_DEATH_SOFT"] = {
        text    = "You died.\n\n|cffc0a060%d|r %s remaining.\n(Contributions only recorded on final death.)",
        button1 = "OK",
        timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    }

    self:ReconcileCurrentDeath("login")
    -- Login is the moment to surface a missed/un-acknowledged death screen too.
    self:TryPresentPendingDeathScreen("login")
end

function D:_IsEndedState(state)
    return state == "retired" or state == "archived" or state == "dead_pending_contribution"
end

function D:_IsPlayerDeadOrGhost()
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return true end
    if UnitIsDead and UnitIsDead("player") then return true end
    if UnitIsGhost and UnitIsGhost("player") then return true end
    return false
end

function D:_ShowFinalDeathPopup(rec, snap)
    snap = snap or {}
    local bank = WRL_DB.bankCharacter or "(no bank set)"
    local money = snap.preMoney or 0
    local bagValue = snap.estimatedBagValue or 0
    local gearValue = snap.estimatedGearValue or 0
    local maxPotential = snap.maximumPotential or (money + bagValue + gearValue)
    StaticPopup_Show(
        "WRL_RETIRE_CONFIRM",
        rec.key,
        ns.Tiers:FormatMoney(money),
        ns.Tiers:FormatMoney(bagValue),
        ns.Tiers:FormatMoney(gearValue),
        ns.Tiers:FormatMoney(maxPotential),
        bank
    )
end

-- Look up the most recent memorial belonging to this character record by uid.
function D:_GetMemorialForRec(rec)
    if not rec or not rec.uid then return nil end
    if not WRL_DB or not WRL_DB.memorials then return nil end
    return WRL_DB.memorials[rec.uid]
end

function D:_GetDeathSnapshotForRec(rec)
    if not rec then return {} end
    return (ns.Contributions and ns.Contributions.GetDeathSnapshot
            and ns.Contributions:GetDeathSnapshot(rec.key))
        or rec.deathSnapshot
        or {}
end

function D:_ShowPendingRetirePopup(rec)
    if not rec then return false end
    if ns.Run:GetState(rec) ~= "dead_pending_contribution" then return false end
    self:_ShowFinalDeathPopup(rec, self:_GetDeathSnapshotForRec(rec))
    return true
end

-- Show the death-screen overlay (if the module is available) for the given
-- record.  When the player clicks Continue, the existing retire popup is
-- shown so the mail/skip flow proceeds as before.  Idempotent — if the screen
-- is already visible or the memorial has already been acknowledged, no-op.
function D:_PresentDeathScreen(rec, reason)
    if not rec then return false end
    local memorial = self:_GetMemorialForRec(rec)
    if not memorial then return false end
    if memorial.acknowledged then return false end

    -- Resolve the snapshot used to populate the retire popup.
    local snap = self:_GetDeathSnapshotForRec(rec)

    -- Continue handler: mark acknowledged + chain into the retire popup.
    local function onContinue()
        if ns.Database and ns.Database.AcknowledgeMemorial then
            ns.Database:AcknowledgeMemorial(memorial.uid)
        else
            memorial.acknowledged = true
        end
        D:_ShowFinalDeathPopup(rec, snap)
    end

    if ns.DeathScreen and ns.DeathScreen.Show then
        ns.DeathScreen:Show(memorial, snap, rec, onContinue)
        ns:Debug("Death screen presented (reason=%s)", tostring(reason))
        return true
    else
        -- DeathScreen module unavailable (early boot or stripped build).
        -- Fall back to the retire popup directly so the player still gets
        -- the contribution flow.
        if ns.Database and ns.Database.AcknowledgeMemorial then
            ns.Database:AcknowledgeMemorial(memorial.uid)
        else
            memorial.acknowledged = true
        end
        self:_ShowFinalDeathPopup(rec, snap)
        return true
    end
end

-- Shown on revive and on login.  Only fires when:
--   * the run is in dead_pending_contribution,
--   * the player is currently alive (not corpse-running),
--   * a memorial exists and has not been acknowledged.
function D:TryPresentPendingDeathScreen(reason)
    local rec = ns.Database and ns.Database:GetCurrentCharacter()
    if not rec then return false end
    if ns.Run:GetState(rec) ~= "dead_pending_contribution" then return false end
    if self:_IsPlayerDeadOrGhost() then return false end

    local memorial = self:_GetMemorialForRec(rec)
    if memorial and memorial.acknowledged then
        return self:_ShowPendingRetirePopup(rec)
    end

    return self:_PresentDeathScreen(rec, reason)
end

function D:ProcessCurrentDeath(reason)
    -- Bank characters have no roguelite death logic.
    if ns.Database:IsBankCharacter() then return end

    local rec = ns.Database:GetCurrentCharacter(); if not rec then return end

    -- Guard against duplicate PLAYER_DEAD or re-firing on already-ended runs.
    local state = ns.Run:GetState(rec)
    if self:_IsEndedState(state) then return end

    if rec.livesRemaining == nil then rec.livesRemaining = 1 end

    -- Soft-death cycle guard: if PLAYER_DEAD fires more than once before
    -- PLAYER_ALIVE in the same corpse-state, do not consume another life.
    if deathCycleOpen and (rec.livesRemaining or 0) > 0 then return end

    if rec.livesRemaining > 0 then
        rec.livesRemaining = rec.livesRemaining - 1
    end
    if rec.livesRemaining >= 1 then
        deathCycleOpen = true   -- mark this corpse-cycle as consuming a life
        if ns.Achievements and ns.Achievements.OnExtraLifeUsed then
            ns.Achievements:OnExtraLifeUsed(ns:UnitKey(), rec)
        end
        -- Soft death: extra lives remain.  Announce locally only when the
        -- announceSoftDeaths setting is explicitly enabled (default: off).
        if ns.Settings and ns.Settings:Get("announceSoftDeaths", false) then
            local charName = rec.key:match("^([^%-]+)") or rec.key
            ns:Print("|cffffff00[Roguelite]|r %s died but has %d %s remaining.",
                charName, rec.livesRemaining,
                rec.livesRemaining == 1 and "life" or "lives")
        end
        StaticPopup_Show("WRL_DEATH_SOFT", rec.livesRemaining, rec.livesRemaining == 1 and "life" or "lives")
        return
    end

    -- ── Final death: bookkeeping only.  No UI is shown here. ────────────────
    -- The death screen + retire popup are presented when the player is alive
    -- again (PLAYER_UNGHOST / PLAYER_ALIVE), or on the next login if the
    -- player logs out before reviving.
    --
    -- Contributions:SnapshotDeath captures preMoney + bag vendor value + total
    -- onto rec.deathSnapshot so the later mail-credit step can diff against it.
    -- It also mirrors rec._pendingContribution for any legacy callers.
    local key  = ns:UnitKey()
    local snap = ns.Contributions:SnapshotDeath(key)
    local totalLiquid = snap and snap.totalLiquid or 0

    -- Transition to dead_pending_contribution BEFORE recording the death log
    -- so the state is consistent if anything inspects it during the log write.
    local stateReason = reason and ("final_death_" .. tostring(reason)) or "final_death"
    ns.Run:SetState(key, "dead_pending_contribution", stateReason)
    -- Capture context snapshot before recording (will be reset after memorial).
    local deathCtx = self:GetDeathContextSnapshot()
    ns.Database:RecordDeathEntry(key, UnitLevel("player"), GetRealZoneText(), deathCtx)
    if ns.Achievements and ns.Achievements.OnFinalDeath then
        ns.Achievements:OnFinalDeath(key, rec)
    end

    -- ── Memorial (Step 11) ─────────────────────────────────────────────────
    -- Guard by uid so repeated PLAYER_DEAD firings never create a second entry
    -- for this character generation, while same-name rerolls still get their
    -- own memorials.
    if not ns.Database:HasMemorialUID(rec.uid) then
        local memorial = {
            uid                  = rec.uid,    -- storage key; see Database:SaveMemorial
            characterKey         = key,
            class                = rec.class,
            race                 = rec.race,
            level                = UnitLevel("player") or rec.levelCurrent,
            zone                 = (GetRealZoneText  and GetRealZoneText())  or "",
            subzone              = (GetSubZoneText   and GetSubZoneText())   or "",
            timestamp            = time(),
            runState             = "dead_pending_contribution",
            activeProfile        = ns.Settings and ns.Settings:GetProfile() or "unknown",
            taintCount           = ns.Rules   and ns.Rules:TaintCount(key)  or 0,
            contributionEstimate = totalLiquid,
            -- claimedRewards: flat list of tier IDs claimed by this character.
            claimedRewards       = ns.Database:ClaimedTierIds(key),
            -- livesUsed: deathLog now includes the current death entry (added
            -- by RecordDeathEntry above), so #deathLog equals total lives used.
            livesUsed            = #(rec.deathLog or {}),
            -- acknowledged: set when the player clicks Continue on the death
            -- screen.  Until then, every login re-presents the death screen.
            acknowledged         = false,
            -- Death context (all fields optional; nil when not captured).
            sourceName           = deathCtx.sourceName,
            sourceGuid           = deathCtx.sourceGuid,
            environmentalType    = deathCtx.environmentalType,
            lastWords            = deathCtx.lastWords,
            mapID                = deathCtx.mapID,
            instanceName         = deathCtx.instanceName,
            positionX            = deathCtx.positionX,
            positionY            = deathCtx.positionY,
        }
        ns.Database:SaveMemorial(memorial)
        self:AnnounceMemorial(memorial)
        self:ResetDeathContext()   -- clear context state after memorial is written
    end

    -- Friendly chat hint while the player is still corpse-running.  The death
    -- screen + mail popup will appear the moment they're alive again.
    ns:Print("|cffff6060Your run has ended.|r Return to your corpse to continue.")
    return true
end

function D:ReconcileCurrentDeath(reason)
    local rec = ns.Database:GetCurrentCharacter(); if not rec then return false end
    local state = ns.Run:GetState(rec)
    if self:_IsEndedState(state) then return false end

    if self:_IsPlayerDeadOrGhost() then
        return self:ProcessCurrentDeath(reason or "reconcile")
    end

    if (rec.livesRemaining or 1) < 1 then
        return self:ProcessCurrentDeath((reason or "reconcile") .. "_out_of_lives")
    end

    return false
end

function D:OnPlayerDead()
    return self:ProcessCurrentDeath(nil)
end

function D:OnRevive()
    deathCycleOpen = false   -- reset soft-death cycle guard on successful revive
    self:ReconcileCurrentDeath("player_alive")

    local rec = ns.Database:GetCurrentCharacter(); if not rec then return end
    local state = ns.Run:GetState(rec)
    if state == "dead_pending_contribution" then
        -- Player has just returned to their corpse (or accepted the spirit
        -- healer res).  Present the death screen then retire popup chain.
        self:TryPresentPendingDeathScreen("revive")
    elseif state == "retired" then
        ns:Print("|cffff6060This character is retired.|r Further play will not be credited to the bank.")
    end
end

function D:OpenMailToBank()
    if not WRL_DB.bankCharacter then
        ns:Print("No bank character set. Use /wrl setbank Name-Realm first.")
        return
    end
    ns:Print("Walk to a mailbox; the send form will pre-fill for %s.", WRL_DB.bankCharacter)
    self._awaitingMailbox = true
end

function D:OnMailShow()
    if not self._awaitingMailbox then return end
    self._awaitingMailbox = false

    local rec = ns.Database:GetCurrentCharacter(); if not rec then return end
    if MailFrameTab2 and MailFrameTab2.Click then MailFrameTab2:Click() end

    local bank  = WRL_DB.bankCharacter
    local short = bank and (bank:match("^([^-]+)") or bank)
    if SendMailNameEditBox and short then SendMailNameEditBox:SetText(short) end
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(RETIRE_SUBJECT) end
    if SendMailBodyEditBox then
        SendMailBodyEditBox:SetText(string.format(
            "Final run: %s (lvl %d).\nAttach bag contents + fill money. Press Send.",
            rec.key, rec.levelCurrent or 0))
    end
    if MoneyInputFrame_SetCopper and SendMailMoney then
        MoneyInputFrame_SetCopper(SendMailMoney, GetMoney() or 0)
    end
end

function D:OnMailSent()
    local rec = ns.Database:GetCurrentCharacter(); if not rec then return end
    if ns.Run:GetState(rec) ~= "dead_pending_contribution" then return end

    local key     = ns:UnitKey()
    local snap    = ns.Contributions:GetDeathSnapshot(key)
    local receipt = ns.Contributions:CreditFinalDeath(key)

    if not snap then
        ns.Run:SetState(key, "retired", "mail_sent_no_snapshot")
        return
    end

    ns.Run:SetState(key, "retired", "contribution_credited")

    if receipt then
        ns:Print("|cffc0a060+%s|r contributed to the bank (est.). Total lifetime: %s",
            ns.Tiers:FormatMoney(receipt.amount),
            ns.Tiers:FormatMoney(ns.Database:TotalContributed()))
    else
        ns:Print("|cffc0a060Run retired.|r No new contribution detected since death snapshot.")
    end
end
