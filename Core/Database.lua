-- Core/Database.lua
-- Owns the SavedVariables schema. Two saved vars:
--   WRL_DB       (SavedVariables) - shared across the account.
--                Holds bank char, per-character records, totals, requests queue.
--   WRL_CharDB   (SavedVariablesPerCharacter) - this character's UI prefs and cache.
--
-- Schema is versioned. Migrations bump WRL_DB.schema and rewrite fields as needed.

local ADDON_NAME, ns = ...
local D = ns:NewModule("Database")

local SCHEMA_VERSION = 10

local function normalizeCharacterKey(key)
    if not key or key == "" then return nil end
    key = tostring(key):gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then return nil end

    local name, realm = key:match("^([^%-]+)%-(.+)$")
    if not name then
        name = key
        realm = GetRealmName and GetRealmName() or ""
    end

    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    realm = (realm or ""):gsub("%s+", "")
    if name == "" then return nil end
    if realm == "" then
        local fallbackRealm = GetRealmName and GetRealmName() or ""
        realm = fallbackRealm:gsub("%s+", "")
    end
    if realm == "" then
        return name
    end
    return name .. "-" .. realm
end

-- Default skeleton. Any field missing on an older DB is lazy-filled in Init().
local function defaults()
    return {
        schema = SCHEMA_VERSION,
        debug = false,
        bankCharacter = nil,     -- "Name-Realm" of the bank toon
        totalContributed = 0,    -- copper, lifetime across all retired chars
        characters = {},         -- [key] = { ... }  see newCharRecord()
        requests = {},           -- incoming requests queue (bank-side ops)
        tiers = nil,             -- filled by Tiers:Init() from constants
        favorites = {},          -- [uid] = true; account-wide starred characters
        contributionReceipts = {}, -- account-wide ledger; owned by Core/Contributions.lua
        fulfillmentReceipts  = {}, -- account-wide fulfillment audit; owned by Core/Requests.lua
        settings             = {}, -- account-wide settings; owned by Core/Settings.lua
        memorials            = {}, -- [uid] = memorial entry; owned by Core/Death.lua
        achievements         = {}, -- [achievementId] = { when, characterKey }; owned by Core/Achievements.lua
        legacyUnlocks        = {}, -- [storage|stipend|fate] = purchased rank count
        legacySpent          = 0,  -- copper spent from lifetime contribution budget
    }
end

-- Per-character record. We keep a deathLog as an audit trail; contributions are
-- kept as a cumulative copper integer (cheap to chart / compare to thresholds).
--
-- Identity fields added for character-replacement tracking:
--   uid        — stable unique ID: "Name-Realm#createdAt".  Never changes.
--   generation — increments each time a new character is rolled with the same
--                Name-Realm (i.e. the player deleted the old one and re-created).
--   isArchived — true when this record was displaced by a newer-generation char.
--                Archived records are stored at key "Name-Realm#createdAt" rather
--                than the plain "Name-Realm" key so the current char keeps the
--                primary slot.
local function newCharRecord(key)
    local level = UnitLevel("player") or 1
    local _, class = UnitClass("player")
    local ts = time()
    return {
        key            = key,
        uid            = key .. "#" .. tostring(ts),
        generation     = 1,
        isArchived     = false,
        class          = class or "UNKNOWN",
        race           = select(2, UnitRace("player")) or "UNKNOWN",
        levelAtCreate  = level,
        levelCurrent   = level,
        createdAt      = ts,
        status         = "fresh",    -- "fresh"|"active"|"dead_pending_contribution"|"retired"
        contributed    = 0,          -- copper this character has sent to the bank
        livesRemaining = 1,          -- future: higher tiers grant +1
        retiredAt      = nil,
        deathLog       = {},         -- { { when, level, zone, subzone } }
        claimedTiers     = {},         -- [tierId] = { when, requestId, fulfilledBy, method }
        runSettings      = {},         -- per-run setting overrides; owned by Core/Settings.lua
        ruleLog          = {},         -- rule event log; owned by Core/Rules.lua
        visitedInstances = {},         -- [slug] = firstVisitTimestamp; for no_dungeon_repeats
        boons            = {},         -- [boonId] = { selectedAt }
        burdens          = {},         -- [burdenId] = { selectedAt }
    }
end

function D:Init()
    WRL_DB = WRL_DB or {}
    WRL_CharDB = WRL_CharDB or {}
    WRL_CharDB.ui = WRL_CharDB.ui or { x = nil, y = nil, lastTab = "Contributions" }
    WRL_CharDB.outgoing = WRL_CharDB.outgoing or {}

    -- Merge defaults into existing DB (preserves saved fields).
    local d = defaults()
    for k, v in pairs(d) do
        if WRL_DB[k] == nil then WRL_DB[k] = v end
    end

    if WRL_DB.schema < SCHEMA_VERSION then
        if WRL_DB.schema < 2 then
            -- Rebalance tier thresholds/gold for Classic economy; repull defaults from Tiers.lua.
            WRL_DB.tiers = nil
        end
        if WRL_DB.schema < 3 then
            -- Introduce the receipt ledger.  Empty array; Contributions:Init()
            -- will back-fill from any existing rec.history the first time it
            -- runs on this account.
            WRL_DB.contributionReceipts = WRL_DB.contributionReceipts or {}
        end
        if WRL_DB.schema < 4 then
            WRL_DB.fulfillmentReceipts = WRL_DB.fulfillmentReceipts or {}
        end
        if WRL_DB.schema < 5 then
            -- Introduce account-wide settings table.  Core/Settings:Init() will
            -- populate defaults and validate the profile on the same login.
            WRL_DB.settings = WRL_DB.settings or {}
        end
        if WRL_DB.schema < 6 then
            -- Introduce per-character ruleLog and visitedInstances for Core/Rules.lua.
            for _, rec in pairs(WRL_DB.characters or {}) do
                rec.ruleLog          = rec.ruleLog          or {}
                rec.visitedInstances = rec.visitedInstances or {}
            end
        end
        if WRL_DB.schema < 7 then
            -- Introduce account-wide memorials table for Core/Death.lua (Step 11).
            WRL_DB.memorials = WRL_DB.memorials or {}
        end
        if WRL_DB.schema < 8 then
            -- Introduce per-character boon/burden selections (Step 12).
            for _, rec in pairs(WRL_DB.characters or {}) do
                rec.boons = rec.boons or {}
                rec.burdens = rec.burdens or {}
            end
        end
        if WRL_DB.schema < 9 then
            -- Introduce account-wide achievements ledger (Step 14).
            WRL_DB.achievements = WRL_DB.achievements or {}
        end
        if WRL_DB.schema < 10 then
            -- Introduce spendable legacy unlock tracks. Existing contribution
            -- totals stay intact and become available budget for fresh choices.
            WRL_DB.legacyUnlocks = WRL_DB.legacyUnlocks or {}
            WRL_DB.legacySpent = WRL_DB.legacySpent or 0
        end
        WRL_DB.schema = SCHEMA_VERSION
    end

    WRL_DB.achievements = WRL_DB.achievements or {}
    WRL_DB.legacyUnlocks = WRL_DB.legacyUnlocks or {}
    WRL_DB.legacySpent = math.max(0, math.floor(WRL_DB.legacySpent or 0))

    -- Lazy-migrate existing character records that predate the uid/generation
    -- fields.  Safe to run every login; no-ops on already-migrated records.
    for storageKey, rec in pairs(WRL_DB.characters or {}) do
        -- uid: if the storage key already contains "#" it IS an archive key,
        -- use it directly; otherwise build from base key + createdAt.
        if not rec.uid then
            if storageKey:find("#", 1, true) then
                rec.uid = storageKey
            else
                rec.uid = storageKey .. "#" .. tostring(rec.createdAt or 0)
            end
        end
        if rec.generation == nil then rec.generation = 1 end
        if rec.isArchived == nil then
            -- A storage key that contains "#" means it was already archived
            -- (manually or by a previous addon version); mark it accordingly.
            rec.isArchived = storageKey:find("#", 1, true) and true or false
        end
        if rec.claimedTiers     == nil then rec.claimedTiers     = {} end
        if rec.runSettings      == nil then rec.runSettings      = {} end
        if rec.ruleLog          == nil then rec.ruleLog          = {} end
        if rec.visitedInstances == nil then rec.visitedInstances = {} end
        if rec.boons            == nil then rec.boons            = {} end
        if rec.burdens          == nil then rec.burdens          = {} end
    end

    self:EnsureCharacter(ns:UnitKey())
end

-- Called on login for every char. Idempotent.
-- Also detects when a player has deleted and re-created a character with the
-- same Name-Realm but a different class: the old record is archived under a
-- unique key ("Name-Realm#createdAt") and a fresh record takes the primary slot.
function D:EnsureCharacter(key)
    if not key then return end
    local rec = WRL_DB.characters[key]
    local _, currentClass = UnitClass("player")
    currentClass = currentClass or ""

    -- ── Replacement detection ───────────────────────────────────────────────
    -- If there's a live record but the class doesn't match the logged-in player,
    -- the character must have been deleted and a new one rolled with the same name.
    if rec and currentClass ~= "" and rec.class ~= currentClass then
        local archiveKey = key .. "#" .. tostring(rec.createdAt or 0)
        if not WRL_DB.characters[archiveKey] then
            rec.isArchived = true
            WRL_DB.characters[archiveKey] = rec
            ns:Print("New character on slot %s (was %s, now %s). Previous record archived.",
                key, rec.class, currentClass)
        end
        WRL_DB.characters[key] = nil
        rec = nil
    end

    if not rec then
        -- Count how many previous generations exist for this name.
        local maxGen = 0
        for _, r in pairs(WRL_DB.characters) do
            if r.key == key and (r.generation or 1) > maxGen then
                maxGen = r.generation or 1
            end
        end

        rec = newCharRecord(key)
        rec.generation = maxGen + 1
        WRL_DB.characters[key] = rec
        ns:Debug("Registered new char %s (gen %d)", key, rec.generation)
    else
        -- Keep cached level fresh. Class/race never change.
        rec.levelCurrent = UnitLevel("player") or rec.levelCurrent
        -- Lazy-add uid for records that predate this feature.
        if not rec.uid then
            rec.uid = key .. "#" .. tostring(rec.createdAt or 0)
        end
        if rec.generation == nil then rec.generation = 1 end
        if rec.isArchived == nil then rec.isArchived = false end
        if rec.claimedTiers     == nil then rec.claimedTiers     = {} end
        if rec.runSettings      == nil then rec.runSettings      = {} end
        if rec.ruleLog          == nil then rec.ruleLog          = {} end
        if rec.visitedInstances == nil then rec.visitedInstances = {} end
        if rec.boons            == nil then rec.boons            = {} end
        if rec.burdens          == nil then rec.burdens          = {} end
    end
    return rec
end

function D:GetCharacter(key)
    return WRL_DB.characters[key]
end

function D:GetCurrentCharacter()
    return self:GetCharacter(ns:UnitKey())
end

function D:IsBankCharacter(key)
    key = key or ns:UnitKey()
    return WRL_DB.bankCharacter and WRL_DB.bankCharacter == key
end

function D:SetBankCharacter(key)
    key = normalizeCharacterKey(key)
    if not key then
        ns:Print("Provide a bank character name, for example |cffffff00/wrl setbank Mybank-Realm|r.")
        return
    end
    -- If a different bank is already set, confirm with a chat message; we don't
    -- wipe their data, we just reassign the bank role.
    local prior = WRL_DB.bankCharacter
    WRL_DB.bankCharacter = key
    if prior and prior ~= key then
        ns:Print("Bank reassigned from %s to %s. Previous contributions retained.", prior, key)
    else
        ns:Print("Bank set to %s.", key)
    end
end

-- Contribution intake.
--
-- Delegates to Core/Contributions.lua so every credit produces a ledger
-- receipt with a confidence tag.  A minimal inline fallback is kept so
-- early boot (before Contributions:Init) still updates totals instead of
-- silently dropping the call.
--
-- `info` is an optional table forwarded to Contributions:Record; see that
-- module's header for recognised fields (confidence/note/preMoney/...).
function D:AddContribution(key, copper, source, info)
    if ns.Contributions and ns.Contributions.Record then
        return ns.Contributions:Record(key, copper, source, info)
    end

    -- Fallback: Contributions module not yet loaded.  Keep totals coherent.
    local rec = self:GetCharacter(key); if not rec then return end
    copper = math.max(0, math.floor(copper or 0))
    rec.contributed = rec.contributed + copper
    WRL_DB.totalContributed = (WRL_DB.totalContributed or 0) + copper

    rec.history = rec.history or {}
    table.insert(rec.history, { when = time(), copper = copper, source = source or "" })
    -- Cap history to last 50 entries per char; charts don't need more.
    while #rec.history > 50 do table.remove(rec.history, 1) end
end

-- Called by Death.lua when the player's run ends for good.
-- Legacy path: sets status directly to "retired".
-- Prefer Run:SetState + Database:RecordDeathEntry in new code.
function D:RetireCharacter(key, atLevel, zone)
    local rec = self:GetCharacter(key); if not rec then return end
    rec.status    = "retired"
    rec.retiredAt = time()
    self:RecordDeathEntry(key, atLevel, zone)
end

-- Record a death-log entry and update levelCurrent + retiredAt without
-- changing the run state.  Called by Death.lua on final death so that
-- Run:SetState can own the state transition independently.
function D:RecordDeathEntry(key, atLevel, zone)
    local rec = self:GetCharacter(key); if not rec then return end
    local now = time()
    rec.retiredAt    = rec.retiredAt or now   -- preserve if already set
    rec.levelCurrent = atLevel or rec.levelCurrent
    table.insert(rec.deathLog, {
        when    = now,
        level   = atLevel or rec.levelCurrent,
        zone    = zone or (GetRealZoneText() or ""),
        subzone = GetSubZoneText() or "",
    })
end

-- Convenience accessors -----------------------------------------------------

function D:TotalContributed() return WRL_DB.totalContributed or 0 end

-- Returns every character record (current + archived) as a flat list.
-- Sorting is left to the caller so the UI can apply its own priority
-- (e.g. favorites first).
function D:RosterSortedByContribution()
    local list = {}
    for _, rec in pairs(WRL_DB.characters) do
        list[#list+1] = rec
    end
    table.sort(list, function(a, b) return (a.contributed or 0) > (b.contributed or 0) end)
    return list
end

-- ── Favorites ───────────────────────────────────────────────────────────────
-- Favorites are keyed by uid and stored account-wide in WRL_DB.favorites.

function D:IsFavorite(uid)
    return uid ~= nil
        and WRL_DB.favorites ~= nil
        and WRL_DB.favorites[uid] == true
end

function D:ToggleFavorite(uid)
    if not uid then return end
    WRL_DB.favorites = WRL_DB.favorites or {}
    if WRL_DB.favorites[uid] then
        WRL_DB.favorites[uid] = nil
    else
        WRL_DB.favorites[uid] = true
    end
end

-- ── Claim Tracking ──────────────────────────────────────────────────────────
-- Per-character claimed tier records. Stored in rec.claimedTiers keyed by
-- tierId for O(1) lookup.  Lazy-initialized so old records get the field on
-- first access without a separate migration pass.

function D:HasClaimedTier(characterKey, tierId)
    local rec = self:GetCharacter(characterKey)
    if not rec then return false end
    rec.claimedTiers = rec.claimedTiers or {}
    return rec.claimedTiers[tierId] ~= nil
end

function D:MarkTierClaimed(characterKey, tierId, claimInfo)
    local rec = self:GetCharacter(characterKey)
    if not rec then return end
    rec.claimedTiers = rec.claimedTiers or {}
    -- Only write once; first fulfillment wins.
    if not rec.claimedTiers[tierId] then
        rec.claimedTiers[tierId] = claimInfo or { when = time() }
    end
end

function D:ClaimedTierIds(characterKey)
    local rec = self:GetCharacter(characterKey)
    if not rec or not rec.claimedTiers then return {} end
    local ids = {}
    for id in pairs(rec.claimedTiers) do ids[#ids+1] = id end
    return ids
end

-- Account-wide setting from Core/Settings.lua: when false, claimed tiers cannot
-- be requested again unless the no_repeat_claims rule is disabled separately.
function D:AllowRepeatClaims()
    if ns.Settings and ns.Settings.Get then
        if ns.Settings:Get("allowRepeatClaims", false) == true then return true end
        if ns.Rules and ns.Rules.IsEnabled then
            return not ns.Rules:IsEnabled("no_repeat_claims")
        end
        if ns.Settings.GetRuleEnabled then
            return ns.Settings:GetRuleEnabled("no_repeat_claims") == false
        end
        return false
    end
    return WRL_DB.settings and WRL_DB.settings.allowRepeatClaims == true
end

-- Append a fulfillment receipt from Core/Requests.lua (bank-side audit trail).
function D:AppendFulfillmentReceipt(fulfillment)
    if not fulfillment then return end
    WRL_DB.fulfillmentReceipts = WRL_DB.fulfillmentReceipts or {}
    table.insert(WRL_DB.fulfillmentReceipts, fulfillment)
    while #WRL_DB.fulfillmentReceipts > 500 do
        table.remove(WRL_DB.fulfillmentReceipts, 1)
    end
end

-- ── Memorial helpers (Step 11) ───────────────────────────────────────────────
-- Achievement helpers (Step 14). Achievements are account-wide and keyed by
-- achievement id; earning is idempotent so login/backfill evaluation is safe.
function D:GetAchievements()
    WRL_DB.achievements = WRL_DB.achievements or {}
    return WRL_DB.achievements
end

function D:GetAchievement(id)
    if not id then return nil end
    return self:GetAchievements()[id]
end

function D:HasAchievement(id)
    return self:GetAchievement(id) ~= nil
end

function D:EarnAchievement(id, characterKey)
    if not id or self:HasAchievement(id) then return nil end
    local entry = {
        when = time(),
        characterKey = characterKey or ns:UnitKey(),
    }
    self:GetAchievements()[id] = entry
    return entry
end

-- Memorials are keyed by character uid so each generation of a name gets its
-- own memorial and old entries are never overwritten by a new character rolled
-- on the same slot.  The entry itself always carries characterKey as a field
-- so callers don't need to know the storage key.

--- Save a memorial entry.  `entry` must have a `uid` field.
--- Idempotent: a second write with the same uid overwrites the first.
function D:SaveMemorial(entry)
    if not entry or not entry.uid then return end
    WRL_DB.memorials = WRL_DB.memorials or {}
    WRL_DB.memorials[entry.uid] = entry
end

--- Returns true when any memorial exists for the given character key.
--- Looks up by the characterKey field stored inside each uid-keyed entry.
function D:HasMemorial(key)
    if not key or not WRL_DB or not WRL_DB.memorials then return false end
    for _, m in pairs(WRL_DB.memorials) do
        if m and m.characterKey == key then return true end
    end
    return false
end
