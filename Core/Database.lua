-- Core/Database.lua
-- Owns the SavedVariables schema. Two saved vars:
--   WRL_DB       (SavedVariables) - shared across the account.
--                Holds bank char, per-character records, totals, requests queue.
--   WRL_CharDB   (SavedVariablesPerCharacter) - this character's UI prefs and cache.
--
-- Schema is versioned. Migrations bump WRL_DB.schema and rewrite fields as needed.

local ADDON_NAME, ns = ...
local D = ns:NewModule("Database")

local SCHEMA_VERSION = 14

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
        contributionMail     = {}, -- contribution mail outbox/inbox reconciliation; owned by Core/Death.lua
        fulfillmentReceipts  = {}, -- account-wide fulfillment audit; owned by Core/Requests.lua
        settings             = {}, -- account-wide settings; owned by Core/Settings.lua
        memorials            = {}, -- [uid] = memorial entry; owned by Core/Death.lua
        achievements         = {}, -- [achievementId] = { when, characterKey }; owned by Core/Achievements.lua
        legacyUnlocks        = {}, -- [storage|stipend|fate] = purchased rank count
        legacySpent          = 0,  -- copper spent from lifetime contribution budget
        accounts             = {}, -- [accountId] = { id, label, createdAt }
        accountLinks         = {}, -- [Character-Realm] = accountId
        resaleReceipts       = {}, -- account-wide resale sale ledger; owned by Core/BankResale.lua
        loanReceipts         = {}, -- account-wide loan borrow/repayment ledger; owned by Core/Loans.lua
        resaleSimStock       = {}, -- temporary simulated resale stock for local testing
        bankLedgerClearedAt  = 0,  -- visibility cutoff for the Recent Ledger UI
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
        playerGuid     = UnitGUID and UnitGUID("player") or nil,
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
    WRL_CharDB.ui = WRL_CharDB.ui or { x = nil, y = nil, lastTab = "Legacy" }
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
        if WRL_DB.schema < 11 then
            WRL_DB.contributionMail = WRL_DB.contributionMail or {}
        end
        if WRL_DB.schema < 12 then
            WRL_DB.accounts = WRL_DB.accounts or {}
            WRL_DB.accountLinks = WRL_DB.accountLinks or {}
        end
        if WRL_DB.schema < 13 then
            WRL_DB.resaleReceipts = WRL_DB.resaleReceipts or {}
            WRL_DB.resaleSimStock = WRL_DB.resaleSimStock or {}
        end
        if WRL_DB.schema < 14 then
            WRL_DB.loanReceipts = WRL_DB.loanReceipts or {}
        end
        WRL_DB.schema = SCHEMA_VERSION
    end

    WRL_DB.achievements = WRL_DB.achievements or {}
    WRL_DB.resaleReceipts = WRL_DB.resaleReceipts or {}
    WRL_DB.loanReceipts = WRL_DB.loanReceipts or {}
    WRL_DB.resaleSimStock = WRL_DB.resaleSimStock or {}
    WRL_DB.accounts = WRL_DB.accounts or {}
    WRL_DB.accountLinks = WRL_DB.accountLinks or {}
    self:EnsureDefaultAccount()
    WRL_DB.contributionMail = WRL_DB.contributionMail or {}
    WRL_DB.contributionMail.outbox = WRL_DB.contributionMail.outbox or {}
    WRL_DB.contributionMail.inbox = WRL_DB.contributionMail.inbox or {}
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
        if not WRL_DB.accountLinks[rec.key or storageKey] then
            WRL_DB.accountLinks[rec.key or storageKey] = "acct-local"
        end
    end

    self:EnsureCharacter(ns:UnitKey())
end

-- Called on login for every char. Idempotent.
-- Also detects when a player has deleted and re-created a character with the
-- same Name-Realm but a different class: the old record is archived under a
-- unique key ("Name-Realm#createdAt") and a fresh record takes the primary slot.
function D:EnsureCharacter(key)
    if not key then return end
    WRL_DB.accounts = WRL_DB.accounts or {}
    WRL_DB.accountLinks = WRL_DB.accountLinks or {}
    self:EnsureDefaultAccount()
    local rec = WRL_DB.characters[key]
    local _, currentClass = UnitClass("player")
    currentClass = currentClass or ""
    local currentGuid = UnitGUID and UnitGUID("player") or nil

    -- ── Replacement detection ───────────────────────────────────────────────
    -- If there's a live record but the stored identity no longer matches the
    -- logged-in player, the character was deleted and re-created with the same
    -- name.  GUID catches same-name/same-class rerolls after this version; class
    -- mismatch preserves the older fallback for pre-GUID records.
    local guidChanged = rec and rec.playerGuid and currentGuid and rec.playerGuid ~= currentGuid
    local classChanged = rec and currentClass ~= "" and rec.class ~= currentClass
    if rec and (guidChanged or classChanged) then
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
        if not rec.playerGuid then rec.playerGuid = currentGuid end
        if rec.generation == nil then rec.generation = 1 end
        if rec.isArchived == nil then rec.isArchived = false end
        if rec.claimedTiers     == nil then rec.claimedTiers     = {} end
        if rec.runSettings      == nil then rec.runSettings      = {} end
        if rec.ruleLog          == nil then rec.ruleLog          = {} end
        if rec.visitedInstances == nil then rec.visitedInstances = {} end
        if rec.boons            == nil then rec.boons            = {} end
        if rec.burdens          == nil then rec.burdens          = {} end
    end
    if rec.key and not WRL_DB.accountLinks[rec.key] then
        WRL_DB.accountLinks[rec.key] = "acct-local"
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
function D:RecordDeathEntry(key, atLevel, zone, ctx)
    local rec = self:GetCharacter(key); if not rec then return end
    local now = time()
    rec.retiredAt    = rec.retiredAt or now   -- preserve if already set
    rec.levelCurrent = atLevel or rec.levelCurrent
    local entry = {
        when    = now,
        level   = atLevel or rec.levelCurrent,
        zone    = zone or (GetRealZoneText() or ""),
        subzone = GetSubZoneText() or "",
    }
    -- Optional death context from D:GetDeathContextSnapshot().
    -- All fields are nil when not captured, so old entries remain valid.
    if ctx then
        entry.sourceName        = ctx.sourceName
        entry.sourceGuid        = ctx.sourceGuid
        entry.environmentalType = ctx.environmentalType
        entry.mapID             = ctx.mapID
        entry.instanceName      = ctx.instanceName
        entry.instanceID        = ctx.instanceID
        entry.positionX         = ctx.positionX
        entry.positionY         = ctx.positionY
        entry.lastWords         = ctx.lastWords
    end
    table.insert(rec.deathLog, entry)
end

-- Convenience accessors -----------------------------------------------------

function D:TotalContributed() return WRL_DB.totalContributed or 0 end

-- Account grouping ---------------------------------------------------------
-- These helpers deliberately use manual, stable account labels.  WoW does not
-- expose a reliable cross-player Battle.net account identity for addon data.

local function accountSlug(label)
    label = tostring(label or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    label = label:gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    if label == "" then label = "account" end
    return label
end

function D:EnsureDefaultAccount()
    WRL_DB.accounts = WRL_DB.accounts or {}
    WRL_DB.accountLinks = WRL_DB.accountLinks or {}
    if not WRL_DB.accounts["acct-local"] then
        WRL_DB.accounts["acct-local"] = {
            id = "acct-local",
            label = "Local Account",
            createdAt = time and time() or 0,
        }
    end
    return WRL_DB.accounts["acct-local"]
end

function D:CreateAccount(label)
    self:EnsureDefaultAccount()
    label = tostring(label or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if label == "" then label = "Account" end

    for _, account in pairs(WRL_DB.accounts or {}) do
        if account.label == label then return account end
    end

    local base = "acct-" .. accountSlug(label)
    local id = base
    local i = 2
    while WRL_DB.accounts[id] do
        id = base .. "-" .. tostring(i)
        i = i + 1
    end

    local account = { id = id, label = label, createdAt = time and time() or 0 }
    WRL_DB.accounts[id] = account
    return account
end

function D:LinkCharacterToAccount(characterKey, accountId)
    if not characterKey or characterKey == "" then return nil end
    self:EnsureDefaultAccount()
    if not accountId or not WRL_DB.accounts[accountId] then
        accountId = "acct-local"
    end
    WRL_DB.accountLinks[characterKey] = accountId
    return WRL_DB.accounts[accountId]
end

function D:AccountIdForCharacter(characterKey)
    self:EnsureDefaultAccount()
    if not characterKey or characterKey == "" then return nil end
    return WRL_DB.accountLinks and WRL_DB.accountLinks[characterKey] or nil
end

function D:AccountForCharacter(characterKey)
    local accountId = self:AccountIdForCharacter(characterKey)
    if not accountId then return nil end
    return WRL_DB.accounts and WRL_DB.accounts[accountId] or nil
end

function D:AccountLabel(accountId)
    local account = accountId and WRL_DB.accounts and WRL_DB.accounts[accountId]
    return account and account.label or "Unassigned"
end

function D:AccountLabelForCharacter(characterKey)
    local account = self:AccountForCharacter(characterKey)
    return account and account.label or "Unassigned"
end

function D:RenameAccount(accountId, label)
    self:EnsureDefaultAccount()
    local account = accountId and WRL_DB.accounts and WRL_DB.accounts[accountId]
    if not account then return nil end
    label = tostring(label or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if label == "" then return account end
    account.label = label
    return account
end

function D:AssignCharacterToAccountLabel(characterKey, label)
    if not characterKey or characterKey == "" then return nil end
    local account = self:CreateAccount(label)
    self:LinkCharacterToAccount(characterKey, account.id)
    for _, receipt in ipairs(WRL_DB.contributionReceipts or {}) do
        if receipt.characterKey == characterKey then
            receipt.accountId = account.id
        end
    end
    for _, receipt in ipairs(WRL_DB.fulfillmentReceipts or {}) do
        if receipt.requester == characterKey then
            receipt.accountId = account.id
        end
    end
    for _, receipt in ipairs(WRL_DB.loanReceipts or {}) do
        if receipt.characterKey == characterKey then
            receipt.accountId = account.id
        end
    end
    return account
end

function D:AccountContributionRows()
    self:EnsureDefaultAccount()
    local grouped = {}
    local total = 0

    for _, receipt in ipairs(WRL_DB.contributionReceipts or {}) do
        local amount = math.max(0, math.floor(receipt.amount or receipt.copper or 0))
        if amount > 0 then
            total = total + amount
            local accountId = self:AccountIdForCharacter(receipt.characterKey) or receipt.accountId or "unassigned"
            local row = grouped[accountId]
            if not row then
                row = {
                    accountId = accountId,
                    label = accountId == "unassigned" and "Unassigned" or self:AccountLabel(accountId),
                    total = 0,
                    charactersByKey = {},
                    characters = {},
                }
                grouped[accountId] = row
            end
            row.total = row.total + amount
            local characterKey = receipt.characterKey or "Unknown"
            local character = row.charactersByKey[characterKey]
            if not character then
                character = { characterKey = characterKey, total = 0 }
                row.charactersByKey[characterKey] = character
                row.characters[#row.characters + 1] = character
            end
            character.total = character.total + amount
        end
    end

    local rows = {}
    for _, row in pairs(grouped) do
        row.percent = total > 0 and ((row.total / total) * 100) or 0
        row.charactersByKey = nil
        table.sort(row.characters, function(a, b)
            if (a.total or 0) == (b.total or 0) then
                return tostring(a.characterKey) < tostring(b.characterKey)
            end
            return (a.total or 0) > (b.total or 0)
        end)
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b)
        if (a.total or 0) == (b.total or 0) then
            return tostring(a.label) < tostring(b.label)
        end
        return (a.total or 0) > (b.total or 0)
    end)
    return rows
end

function D:CharacterContributionRows()
    local grouped = {}
    local total = 0

    for _, receipt in ipairs(WRL_DB.contributionReceipts or {}) do
        local amount = math.max(0, math.floor(receipt.amount or receipt.copper or 0))
        if amount > 0 then
            total = total + amount
            local characterKey = receipt.characterKey or "Unknown"
            local row = grouped[characterKey]
            if not row then
                local rec = WRL_DB.characters and WRL_DB.characters[characterKey] or nil
                row = {
                    characterKey = characterKey,
                    generation = rec and (rec.generation or 1) or 1,
                    level = rec and (rec.levelCurrent or rec.levelAtCreate) or "?",
                    total = 0,
                }
                grouped[characterKey] = row
            end
            row.total = row.total + amount
        end
    end

    local rows = {}
    for _, row in pairs(grouped) do
        row.percent = total > 0 and ((row.total / total) * 100) or 0
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b)
        if (a.total or 0) == (b.total or 0) then
            return tostring(a.characterKey) < tostring(b.characterKey)
        end
        return (a.total or 0) > (b.total or 0)
    end)
    return rows
end

function D:RecentBankLedgerRows(maxRows)
    maxRows = maxRows or 8
    local rows = {}
    local clearedAt = math.max(0, tonumber(WRL_DB.bankLedgerClearedAt) or 0)
    for _, r in ipairs(WRL_DB.contributionReceipts or {}) do
        if (r.when or 0) > clearedAt then
            local accountId = self:AccountIdForCharacter(r.characterKey) or r.accountId
            rows[#rows + 1] = {
                kind = "contribution",
                when = r.when or 0,
                characterKey = r.characterKey,
                accountId = accountId,
                accountLabel = self:AccountLabel(accountId),
                amount = r.amount or 0,
                source = r.source,
            }
        end
    end
    for _, f in ipairs(WRL_DB.fulfillmentReceipts or {}) do
        if (f.when or 0) > clearedAt then
            local accountId = self:AccountIdForCharacter(f.requester) or f.accountId
            rows[#rows + 1] = {
                kind = "fulfillment",
                when = f.when or 0,
                characterKey = f.requester,
                accountId = accountId,
                accountLabel = self:AccountLabel(accountId),
                amount = f.gold or 0,
                method = f.method,
            }
        end
    end
    for _, s in ipairs(WRL_DB.resaleReceipts or {}) do
        if (s.when or 0) > clearedAt then
            rows[#rows + 1] = {
                kind = "resale",
                when = s.when or 0,
                characterKey = s.buyer,
                accountId = self:AccountIdForCharacter(s.buyer),
                accountLabel = s.buyer and self:AccountLabel(self:AccountIdForCharacter(s.buyer)) or "Unassigned",
                amount = s.totalCopper or 0,
                itemName = s.itemName,
                qty = s.qty,
                priceLabel = s.priceLabel,
                priceShortLabel = s.priceShortLabel,
                priceSource = s.priceSource,
            }
        end
    end
    for _, loan in ipairs(WRL_DB.loanReceipts or {}) do
        if (loan.when or 0) > clearedAt then
            local accountId = self:AccountIdForCharacter(loan.characterKey) or loan.accountId
            rows[#rows + 1] = {
                kind = loan.kind == "repayment" and "loan_repayment" or "loan_borrow",
                when = loan.when or 0,
                characterKey = loan.characterKey,
                accountId = accountId,
                accountLabel = self:AccountLabel(accountId),
                amount = loan.amount or 0,
                source = loan.source,
            }
        end
    end
    table.sort(rows, function(a, b) return (a.when or 0) > (b.when or 0) end)
    while #rows > maxRows do table.remove(rows) end
    return rows
end

function D:ClearRecentBankLedger()
    WRL_DB.bankLedgerClearedAt = time and time() or 0
    return WRL_DB.bankLedgerClearedAt
end

function D:AccountBankingSummaryRows()
    self:EnsureDefaultAccount()
    local rowsById = {}

    local function ensureRow(accountId)
        accountId = accountId or "unassigned"
        local row = rowsById[accountId]
        if not row then
            row = {
                accountId = accountId,
                label = accountId == "unassigned" and "Unassigned" or self:AccountLabel(accountId),
                contributedCopper = 0,
                borrowedCopper = 0,
                repaidCopper = 0,
                outstandingCopper = 0,
                capCopper = 0,
                availableCopper = 0,
                resaleCopper = 0,
                resaleCount = 0,
                fulfillmentCount = 0,
                charactersByKey = {},
                characters = {},
            }
            rowsById[accountId] = row
        end
        return row
    end

    local function rememberCharacter(row, characterKey)
        if not row or not characterKey or characterKey == "" then return end
        if not row.charactersByKey[characterKey] then
            row.charactersByKey[characterKey] = true
            row.characters[#row.characters + 1] = { characterKey = characterKey }
        end
    end

    for _, account in pairs(WRL_DB.accounts or {}) do
        ensureRow(account.id)
    end
    for _, receipt in ipairs(WRL_DB.contributionReceipts or {}) do
        local amount = math.max(0, math.floor(tonumber(receipt.amount or receipt.copper) or 0))
        local accountId = receipt.accountId or self:AccountIdForCharacter(receipt.characterKey)
        local row = ensureRow(accountId)
        row.contributedCopper = row.contributedCopper + amount
        rememberCharacter(row, receipt.characterKey)
    end
    for _, loan in ipairs(WRL_DB.loanReceipts or {}) do
        local amount = math.max(0, math.floor(tonumber(loan.amount) or 0))
        local accountId = loan.accountId or self:AccountIdForCharacter(loan.characterKey)
        local row = ensureRow(accountId)
        rememberCharacter(row, loan.characterKey)
        if loan.kind == "repayment" then
            row.repaidCopper = row.repaidCopper + amount
        else
            row.borrowedCopper = row.borrowedCopper + amount
        end
    end
    for _, resale in ipairs(WRL_DB.resaleReceipts or {}) do
        local accountId = self:AccountIdForCharacter(resale.buyer)
        local row = ensureRow(accountId)
        rememberCharacter(row, resale.buyer)
        row.resaleCopper = row.resaleCopper + math.max(0, math.floor(tonumber(resale.totalCopper) or 0))
        row.resaleCount = row.resaleCount + 1
    end
    for _, fulfillment in ipairs(WRL_DB.fulfillmentReceipts or {}) do
        local accountId = fulfillment.accountId or self:AccountIdForCharacter(fulfillment.requester)
        local row = ensureRow(accountId)
        row.fulfillmentCount = row.fulfillmentCount + 1
        rememberCharacter(row, fulfillment.requester)
    end

    local rows = {}
    for accountId, row in pairs(rowsById) do
        row.charactersByKey = nil
        table.sort(row.characters, function(a, b)
            return tostring(a.characterKey) < tostring(b.characterKey)
        end)
        row.isUnassigned = accountId == "unassigned"
        row.isLocalAccount = accountId == "acct-local"
        row.outstandingCopper = math.max(0, (row.borrowedCopper or 0) - (row.repaidCopper or 0))
        if ns.Loans and ns.Loans.BorrowCapForAccount then
            local cap = ns.Loans:BorrowCapForAccount(accountId)
            row.capCopper = cap.capCopper or 0
            row.availableCopper = cap.availableCopper or math.max(0, (row.capCopper or 0) - (row.outstandingCopper or 0))
            row.highestRank = cap.highestRank or 0
        end
        if row.contributedCopper > 0 or row.outstandingCopper > 0 or row.resaleCopper > 0 or row.fulfillmentCount > 0 then
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b)
        if (a.outstandingCopper or 0) ~= (b.outstandingCopper or 0) then
            return (a.outstandingCopper or 0) > (b.outstandingCopper or 0)
        end
        if (a.contributedCopper or 0) ~= (b.contributedCopper or 0) then
            return (a.contributedCopper or 0) > (b.contributedCopper or 0)
        end
        return tostring(a.label) < tostring(b.label)
    end)
    return rows
end

function D:BankerSummary()
    local pending, ready, missing = 0, 0, 0
    if ns.Requests and ns.Requests.PendingRequests then
        for _, req in ipairs(ns.Requests:PendingRequests()) do
            pending = pending + 1
            local ok, readiness = pcall(function() return ns.Requests:FulfillmentReadiness(req) end)
            if ok and readiness then
                if readiness.fulfillable then ready = ready + 1 end
                missing = missing + #(readiness.missingItems or {})
            end
        end
    end

    local outstanding = 0
    if ns.Loans and ns.Loans.AccountLoanRows then
        for _, row in ipairs(ns.Loans:AccountLoanRows()) do
            outstanding = outstanding + math.max(0, math.floor(tonumber(row.outstandingCopper) or 0))
        end
    end

    local resaleRows = 0
    if ns.BankResale and ns.BankResale.InventoryRows then
        resaleRows = #(ns.BankResale:InventoryRows() or {})
    end

    local ledgerRows = #(self:RecentBankLedgerRows(50) or {})
    local pricingStatus = "Pricing: local fallback available."
    if ns.Pricing and ns.Pricing.MarketValue then
        local value = ns.Pricing:MarketValue(769)
        pricingStatus = value and "Pricing: TSM DBMarket available." or "Pricing: TSM unavailable; using fallback labels when needed."
    end

    return {
        pendingRequests = pending,
        readyRequests = ready,
        missingItemLines = missing,
        resaleRows = resaleRows,
        outstandingLoanCopper = outstanding,
        recentLedgerRows = ledgerRows,
        pricingStatus = pricingStatus,
    }
end

function D:BankerSummaryLines()
    local summary = self:BankerSummary()
    local loanText = ns.Loans and ns.Loans.FormatGold and ns.Loans:FormatGold(summary.outstandingLoanCopper or 0)
        or tostring(summary.outstandingLoanCopper or 0)
    return {
        ("Requests: %d pending / %d ready"):format(summary.pendingRequests or 0, summary.readyRequests or 0),
        ("Missing item lines: %d"):format(summary.missingItemLines or 0),
        ("Resale rows: %d"):format(summary.resaleRows or 0),
        ("Outstanding loans: %s"):format(loanText),
        ("Recent ledger rows: %d"):format(summary.recentLedgerRows or 0),
        summary.pricingStatus or "Pricing: local fallback available.",
    }
end

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

function D:ResetAchievements()
    WRL_DB.achievements = {}
    return true
end

function D:ResetLegacyProgression()
    WRL_DB.legacyUnlocks = {}
    WRL_DB.legacySpent = 0
    return true
end

function D:ResetLedgerEconomy()
    WRL_DB.totalContributed = 0
    WRL_DB.contributionReceipts = {}
    WRL_DB.fulfillmentReceipts = {}
    WRL_DB.resaleReceipts = {}
    WRL_DB.loanReceipts = {}
    self:ResetLegacyProgression()

    for _, rec in pairs(WRL_DB.characters or {}) do
        if rec then
            rec.contributed = 0
        end
    end
    return true
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

--- Return the memorial stored for a specific character generation uid.
function D:GetMemorialByUID(uid)
    if not uid or not WRL_DB or not WRL_DB.memorials then return nil end
    return WRL_DB.memorials[uid]
end

--- Returns true when a memorial exists for a specific character generation uid.
function D:HasMemorialUID(uid)
    return self:GetMemorialByUID(uid) ~= nil
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

--- Mark a memorial as having been acknowledged on the death screen.
--- Once acknowledged the death screen will not re-pop on subsequent logins;
--- the retire popup mail/skip flow remains the only further prompt.
function D:AcknowledgeMemorial(uid)
    if not uid or not WRL_DB or not WRL_DB.memorials then return end
    local m = WRL_DB.memorials[uid]
    if not m then return end
    m.acknowledged   = true
    m.acknowledgedAt = time()
end
