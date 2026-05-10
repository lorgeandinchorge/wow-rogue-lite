-- Core/Contributions.lua
-- Ledger-style accounting for addon-tracked contributions.
--
-- Every contribution creates an immutable receipt stored account-wide in
-- WRL_DB.contributionReceipts.  Per-character totals (rec.contributed) and
-- the lifetime total (WRL_DB.totalContributed) are still maintained so the
-- existing UI keeps working without having to re-sum the ledger every frame.
--
-- Why one account-wide array instead of per-character receipts:
--   * avoids double-storage (receipt knows its characterKey already)
--   * lets the UI slice by character OR show a global feed cheaply
--   * lines up with the shape AI_MANAGER_PROMPTS.md Step 3 sketches
--
-- Receipt shape (see AI_MANAGER_PROMPTS.md Step 3):
--   id                unique string, stable across reloads
--   characterKey      the run character key, e.g. "Name-Realm"
--   when              epoch seconds
--   amount            copper credited
--   source            "final_contribution" | "manual" | free-text
--   confidence        "verified" | "estimated" | "manual"
--   note              free-text diagnostic string
--   preMoney          optional snapshot of GetMoney() at death
--   postMoney         optional GetMoney() after mail send
--   estimatedBagValue optional vendor value at death
--   postEstimatedBagValue optional vendor value after mail send

local ADDON_NAME, ns = ...
local C = ns:NewModule("Contributions")

local MAX_HISTORY_PER_CHAR = 50

local CONFIDENCE = { verified = true, estimated = true, manual = true }

local function now() return time() end

-- Short, monotonically-unique receipt id.  We tag it with the sequence number
-- so two receipts in the same second still get distinct ids after reload.
local function rollId()
    WRL_DB._receiptSeq = (WRL_DB._receiptSeq or 0) + 1
    return string.format("r%d-%d", now(), WRL_DB._receiptSeq)
end

local function ensureStorage()
    WRL_DB.contributionReceipts = WRL_DB.contributionReceipts or {}
end

-- One-shot: back-fill receipts from pre-receipt rec.history so lifetime
-- ledgers aren't empty on upgrade.  Guarded by WRL_DB._receiptsMigrated so we
-- don't duplicate on every login.
function C:_MigrateLegacyHistoryOnce()
    if WRL_DB._receiptsMigrated then return end
    ensureStorage()
    for key, rec in pairs(WRL_DB.characters or {}) do
        if type(rec.history) == "table" then
            for _, h in ipairs(rec.history) do
                if h and (h.copper or 0) > 0 and not h.receiptId then
                    local receipt = {
                        id           = rollId(),
                        characterKey = rec.key or key,
                        when         = h.when or 0,
                        amount       = h.copper or 0,
                        source       = h.source or "legacy",
                        confidence   = "estimated",
                        note         = "migrated from pre-receipt history",
                    }
                    table.insert(WRL_DB.contributionReceipts, receipt)
                    h.receiptId  = receipt.id
                    h.confidence = receipt.confidence
                end
            end
        end
    end
    WRL_DB._receiptsMigrated = true
end

function C:Init()
    ensureStorage()
    self:_MigrateLegacyHistoryOnce()
end

-- ── Accessors ─────────────────────────────────────────────────────────────

function C:All()
    ensureStorage()
    return WRL_DB.contributionReceipts
end

-- Shallow-copied slice so callers can sort/filter without mutating the ledger.
function C:ForCharacter(characterKey)
    ensureStorage()
    local out = {}
    for _, r in ipairs(WRL_DB.contributionReceipts) do
        if r.characterKey == characterKey then out[#out+1] = r end
    end
    return out
end

function C:GetReceipt(id)
    if not id then return nil end
    ensureStorage()
    for _, r in ipairs(WRL_DB.contributionReceipts) do
        if r.id == id then return r end
    end
    return nil
end

-- ── Core ledger write ─────────────────────────────────────────────────────
-- Creates a receipt and updates rec.contributed + WRL_DB.totalContributed and
-- mirrors the entry into rec.history for existing UI.
--
-- `info` is optional; recognised fields: confidence, note, preMoney,
-- postMoney, estimatedBagValue, postEstimatedBagValue. Unknown confidences
-- fall back to "estimated".
function C:Record(characterKey, amount, source, info)
    local rec = ns.Database:GetCharacter(characterKey); if not rec then return nil end
    amount = math.max(0, math.floor(amount or 0))
    info = info or {}

    ensureStorage()

    local confidence = info.confidence
    if not (confidence and CONFIDENCE[confidence]) then confidence = "estimated" end

    local receipt = {
        id                = rollId(),
        characterKey      = characterKey,
        when              = now(),
        amount            = amount,
        source            = source or "",
        confidence        = confidence,
        note              = info.note or "",
        preMoney          = info.preMoney,
        postMoney         = info.postMoney,
        estimatedBagValue = info.estimatedBagValue,
        postEstimatedBagValue = info.postEstimatedBagValue,
    }
    table.insert(WRL_DB.contributionReceipts, receipt)

    -- Per-character and account totals stay in sync with the ledger.
    rec.contributed         = (rec.contributed or 0) + amount
    WRL_DB.totalContributed = (WRL_DB.totalContributed or 0) + amount

    -- Mirror into rec.history for backward-compatible UI feeds.
    rec.history = rec.history or {}
    table.insert(rec.history, {
        when       = receipt.when,
        copper     = receipt.amount,
        source     = receipt.source,
        confidence = receipt.confidence,
        receiptId  = receipt.id,
    })
    while #rec.history > MAX_HISTORY_PER_CHAR do
        table.remove(rec.history, 1)
    end

    if ns.Achievements and ns.Achievements.OnContribution then
        ns.Achievements:OnContribution(characterKey, receipt)
    end

    return receipt
end

-- ── Final-death snapshot / credit flow ────────────────────────────────────
-- Two-step because the mail send happens some time after the death: we
-- snapshot the "contributable" value at death, then credit once the mail
-- goes through (or skip on "Not Now").

-- Capture the liquid-value snapshot when the player hits final death.  Stored
-- on the character record so it survives reload.  Returns the snapshot table.
function C:SnapshotDeath(characterKey)
    local rec = ns.Database:GetCharacter(characterKey); if not rec then return nil end

    local money = GetMoney and GetMoney() or 0
    local bagCopper = 0
    local gearCopper = 0
    local bagItems = {}
    local gearItems = {}
    if ns.Vendor and ns.Vendor.FullCharacterSnapshot then
        local full = ns.Vendor:FullCharacterSnapshot()
        money = full.money or money
        bagCopper = full.bagValue or 0
        gearCopper = full.gearValue or 0
        bagItems = full.bagItems or {}
        gearItems = full.gearItems or {}
    elseif ns.Vendor and ns.Vendor.BagsSnapshot then
        bagCopper, bagItems = ns.Vendor:BagsSnapshot()
        bagCopper = bagCopper or 0
        bagItems = bagItems or {}
    end

    local snap = {
        at                = now(),
        preMoney          = money,
        estimatedBagValue = bagCopper,
        estimatedGearValue = gearCopper,
        totalLiquid       = money + bagCopper,
        maximumPotential  = money + bagCopper + gearCopper,
        bagItems          = bagItems,
        gearItems         = gearItems,
        credited          = false,
    }
    rec.deathSnapshot = snap
    -- Legacy mirror so old code paths that read _pendingContribution stay OK.
    rec._pendingContribution = snap.totalLiquid
    return snap
end

function C:GetDeathSnapshot(characterKey)
    local rec = ns.Database:GetCharacter(characterKey); if not rec then return nil end
    return rec.deathSnapshot
end

-- Credit the final-death contribution exactly once.  Idempotent: repeated
-- calls after success return nil.
--
-- Returns the receipt on credit, or nil if nothing was credited (either no
-- snapshot exists or it's already been credited).
--
-- Amount derivation:
--   moneySent  = max(0, snap.preMoney - GetMoney())       -- how much copper left the wallet
--   bagSentEst = max(0, snap.estimatedBagValue - currentBagValue)
--   amount     = min(snap.totalLiquid, moneySent + bagSentEst)
--
-- We still mark item value as estimated, but unchanged bag value is no longer
-- credited just because it existed at death.
function C:CreditFinalDeath(characterKey, opts)
    local rec = ns.Database:GetCharacter(characterKey); if not rec then return nil end
    opts = opts or {}

    local snap = rec.deathSnapshot
    if not snap or snap.credited then
        return nil
    end

    local postMoney = GetMoney and GetMoney() or 0
    local moneyDelta = math.max(0, (snap.preMoney or 0) - postMoney)
    local bagEst = snap.estimatedBagValue or 0
    local postBagEst
    if ns.Vendor and ns.Vendor.BagsSnapshot then
        postBagEst = select(1, ns.Vendor:BagsSnapshot()) or 0
    end
    local bagDelta
    if postBagEst ~= nil then
        bagDelta = math.max(0, bagEst - postBagEst)
    else
        bagDelta = bagEst
    end
    local total = snap.totalLiquid or ((snap.preMoney or 0) + bagEst)

    -- Cap at the snapshot total so we never over-credit the recorded estimate.
    local amount = math.min(total, moneyDelta + bagDelta)

    -- If nothing plausibly moved, mark the snapshot consumed without a receipt
    -- so we don't repeatedly try to credit on future MAIL_SEND_SUCCESS events.
    if amount <= 0 and not opts.forceZero then
        snap.credited   = true
        snap.creditedAt = now()
        rec.deathSnapshot        = snap
        rec._pendingContribution = nil
        return nil
    end

    local note = opts.note or string.format(
        "final death credit: moneyDelta=%d bagDelta=%d preBagEst=%d postBagEst=%s cap=%d",
        moneyDelta, bagDelta, bagEst, tostring(postBagEst), total
    )
    local receipt = self:Record(characterKey, amount, opts.source or "final_contribution", {
        confidence        = "estimated",
        note              = note,
        preMoney          = snap.preMoney,
        postMoney         = postMoney,
        estimatedBagValue = snap.estimatedBagValue,
        postEstimatedBagValue = postBagEst,
    })

    -- Mark the snapshot consumed; second calls short-circuit at the top.
    snap.credited   = true
    snap.creditedAt = now()
    snap.creditedId = receipt and receipt.id or nil
    rec.deathSnapshot        = snap
    rec._pendingContribution = nil
    return receipt
end

-- Manual contribution entry (player records a value the addon can't verify).
-- Always logs as "manual" confidence.  Useful when mail went out without a
-- snapshot, or for reconciling offline contributions.
function C:RecordManual(characterKey, amount, note)
    return self:Record(characterKey, amount, "manual", {
        confidence = "manual",
        note       = note or "player-entered contribution",
    })
end
