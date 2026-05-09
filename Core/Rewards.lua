-- Core/Rewards.lua
-- Owns reward bundle definitions and helpers for building, filtering, and
-- modifying reward bundles.  Tiers.lua references bundle IDs; this module
-- resolves those IDs into actual item/gold/life contents.
--
-- Bundle settings (WRL_DB.settings.rewards):
--   disableGoldRewards  (bool) – zero out gold in all bundles
--   disableExtraLives   (bool) – zero out extra lives in all bundles
--   bagsOnly            (bool) – strip everything except bag items
--   allowPotionRewards  (bool) – default true; set false to strip potions
--
-- Item IDs (BC-era):
--   Linen Bag           = 4496   (6-slot)
--   Small Silk Pack     = 4245   (10-slot)
--   Mageweave Bag       = 10050  (12-slot)
--   Runecloth Bag       = 14046  (14-slot)
--   Netherweave Bag     = 21841  (16-slot)
--   Lesser Healing Pot  = 858
--   Healing Potion      = 929
--   Superior Healing Pot= 3928
--   Super Healing Potion= 22829
--
-- Gold amounts are in copper (1g = 10000).

local ADDON_NAME, ns = ...
local Rewards = ns:NewModule("Rewards")

local function g(gold)   return gold * 10000 end
local function s(silver) return silver * 100  end

-- ── Canonical bundle definitions ──────────────────────────────────────────────
-- Each bundle captures the reward contents that were previously embedded
-- directly in the tier definition.  Tiers now carry only a bundleIds list.

local BUNDLE_DEFS = {
    {
        id = "storage_1",
        items = {
            { id = 4496, qty = 2, note = "Linen Bag (6-slot)" },
        },
        gold = 0,
        extraLives = 0,
    },
    {
        id = "storage_2",
        items = {
            { id = 4245, qty = 2, note = "Small Silk Pack (10-slot)" },
        },
        gold = 0,
        extraLives = 0,
    },
    {
        id = "storage_3",
        items = {
            { id = 10050, qty = 2, note = "Mageweave Bag (12-slot)" },
        },
        gold = 0,
        extraLives = 0,
    },
    {
        id = "storage_4",
        items = {
            { id = 14046, qty = 2, note = "Runecloth Bag (14-slot)" },
        },
        gold = 0,
        extraLives = 0,
    },
    {
        id = "storage_5",
        items = {
            { id = 21841, qty = 2, note = "Netherweave Bag (16-slot)" },
        },
        gold = 0,
        extraLives = 0,
    },
    {
        id = "storage_6",
        items = {
            { id = 21841, qty = 4, note = "Netherweave Bag (16-slot)" },
        },
        gold = 0,
        extraLives = 0,
    },
    {
        id = "stipend_1",
        items = {},
        gold = g(3),
        extraLives = 0,
    },
    {
        id = "stipend_2",
        items = {},
        gold = g(10),
        extraLives = 0,
    },
    {
        id = "stipend_3",
        items = {},
        gold = g(25),
        extraLives = 0,
    },
    {
        id = "stipend_4",
        items = {},
        gold = g(75),
        extraLives = 0,
    },
    {
        id = "stipend_5",
        items = {},
        gold = g(250),
        extraLives = 0,
    },
    {
        id = "stipend_6",
        items = {},
        gold = g(750),
        extraLives = 0,
    },
    {
        id = "fate_1",
        items = {},
        gold = 0,
        extraLives = 1,
    },
    {
        id = "fate_2",
        items = {},
        gold = 0,
        extraLives = 1,
    },
    {
        id = "tier_1_base",
        items = {
            { id = 4496, qty = 2, note = "Linen Bag (6-slot)" },
        },
        gold      = s(50),
        extraLives = 0,
    },
    {
        id = "tier_2_base",
        items = {
            { id = 4245, qty = 2, note = "Small Silk Pack (10-slot)" },
            { id = 858,  qty = 5, note = "Lesser Healing Potion" },
        },
        gold      = g(1),
        extraLives = 0,
    },
    {
        id = "tier_3_base",
        items = {
            { id = 10050, qty = 2, note = "Mageweave Bag (12-slot)" },
            { id = 929,   qty = 5, note = "Healing Potion" },
        },
        gold      = g(8),
        extraLives = 0,
    },
    {
        id = "tier_4_base",
        items = {
            { id = 14046, qty = 2, note = "Runecloth Bag (14-slot)" },
            { id = 3928,  qty = 5, note = "Superior Healing Potion" },
        },
        gold      = g(60),
        extraLives = 0,
    },
    {
        id = "tier_5_base",
        items = {
            { id = 21841, qty = 2, note = "Netherweave Bag (16-slot)" },
            { id = 22829, qty = 5, note = "Super Healing Potion" },
        },
        gold      = g(500),
        extraLives = 1,
    },
}

local bundleById = {}
for _, b in ipairs(BUNDLE_DEFS) do bundleById[b.id] = b end

-- Fallback tier→bundle mapping used when a tier def lacks a bundleIds field.
-- Keeps older saved-variable data working after a migration delay.
local TIER_BUNDLE_FALLBACK = {
    [0] = {},
    [1] = { "tier_1_base" },
    [2] = { "tier_2_base" },
    [3] = { "tier_3_base" },
    [4] = { "tier_4_base" },
    [5] = { "tier_5_base" },
}

-- ── Item classifiers (used by ApplyRewardModifiers) ───────────────────────────

local function isPotionItem(it)
    local n = (it.note or ""):lower()
    return n:find("potion") ~= nil or n:find("healing") ~= nil
end

local function isBagItem(it)
    local n = (it.note or ""):lower()
    return n:find("bag") ~= nil or n:find("pack") ~= nil
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Return a bundle definition table by ID, or nil if unknown.
function Rewards:GetBundle(bundleId)
    return bundleById[bundleId]
end

--- Return a list of bundle defs (raw, unfiltered) for a given tier ID.
--- Reads tier.bundleIds from Tiers:Definitions() with a canonical fallback.
function Rewards:BundlesForTier(tierId)
    if ns.LegacyUnlocks and ns.LegacyUnlocks.NodeById and ns.LegacyUnlocks:NodeById(tierId) then
        local out = {}
        for _, bid in ipairs(ns.LegacyUnlocks:BundleIdsForNodeIds({ tierId })) do
            local b = bundleById[bid]
            if b then out[#out + 1] = b end
        end
        return out
    end

    local defs = ns.Tiers and ns.Tiers:Definitions()
    if defs then
        for _, t in ipairs(defs) do
            if t.id == tierId then
                if type(t.bundleIds) == "table" then
                    local out = {}
                    for _, bid in ipairs(t.bundleIds) do
                        local b = bundleById[bid]
                        if b then out[#out + 1] = b end
                    end
                    return out
                end
                break
            end
        end
    end
    -- Fallback: canonical mapping for tiers that predate this refactor.
    local ids = TIER_BUNDLE_FALLBACK[tierId] or {}
    local out = {}
    for _, bid in ipairs(ids) do
        local b = bundleById[bid]
        if b then out[#out + 1] = b end
    end
    return out
end

--- Merge a list of bundle defs into a single { items, gold, extraLives } table.
--- Items with the same ID are combined by summing quantities.
function Rewards:MergeBundles(bundles)
    local byId     = {}
    local gold      = 0
    local extraLives = 0
    for _, b in ipairs(bundles or {}) do
        gold      = gold      + (b.gold      or 0)
        extraLives = extraLives + (b.extraLives or 0)
        for _, it in ipairs(b.items or {}) do
            local cur = byId[it.id]
            if cur then
                cur.qty = cur.qty + (it.qty or 1)
            else
                byId[it.id] = { id = it.id, qty = it.qty or 1, note = it.note }
            end
        end
    end
    local flat = {}
    for _, v in pairs(byId) do flat[#flat + 1] = v end
    table.sort(flat, function(a, b) return a.id < b.id end)
    return { items = flat, gold = gold, extraLives = extraLives }
end

--- Return the raw merged display contents for a single tier (no modifier filtering).
--- Used by UI helpers that want the unfiltered canonical contents for display.
function Rewards:GetTierDisplayContents(tierId)
    return self:MergeBundles(self:BundlesForTier(tierId))
end

--- Build the full merged reward bundle for a set of tier IDs.
--- Applies reward-modifier settings and boon modifiers for charKey.
--- charKey may be nil (boon application is then skipped).
function Rewards:BuildRewardForTierIds(tierIds, charKey)
    local allBundles = {}
    for _, tierId in ipairs(tierIds or {}) do
        for _, b in ipairs(self:BundlesForTier(tierId)) do
            allBundles[#allBundles + 1] = b
        end
    end
    local bundle = self:MergeBundles(allBundles)
    self:ApplyRewardModifiers(bundle, charKey)
    return bundle
end

--- Apply settings-based filters and boon/burden modifiers to a bundle in-place.
---
--- Settings are read from WRL_DB.settings.rewards; the optional `opts` table
--- can supply per-call overrides using the same key names:
---   disableGoldRewards  (bool)
---   disableExtraLives   (bool)
---   bagsOnly            (bool)
---   allowPotionRewards  (bool, default true → current behavior includes potions)
---
--- Boon modifiers are applied last via ns.Boons:ApplyToBundle if charKey is set.
--- This is the single central hook for all boon/burden reward modifications.
function Rewards:ApplyRewardModifiers(bundle, charKey, opts)
    if not bundle then return end

    -- Resolve effective settings: saved defaults → caller opts override.
    local saved        = (WRL_DB and WRL_DB.settings and WRL_DB.settings.rewards) or {}
    local disableGold  = (opts and opts.disableGoldRewards  ~= nil) and opts.disableGoldRewards  or saved.disableGoldRewards  or false
    local disableLives = (opts and opts.disableExtraLives    ~= nil) and opts.disableExtraLives    or saved.disableExtraLives    or false
    local bagsOnly     = (opts and opts.bagsOnly             ~= nil) and opts.bagsOnly             or saved.bagsOnly             or false
    local allowPotions
    if opts and opts.allowPotionRewards ~= nil then
        allowPotions = opts.allowPotionRewards
    elseif saved.allowPotionRewards ~= nil then
        allowPotions = saved.allowPotionRewards
    else
        allowPotions = true   -- default: preserve existing behavior (potions included)
    end

    if bagsOnly then
        -- bagsOnly trumps all other filters.
        local filtered = {}
        for _, it in ipairs(bundle.items or {}) do
            if isBagItem(it) then filtered[#filtered + 1] = it end
        end
        bundle.items      = filtered
        bundle.gold       = 0
        bundle.extraLives = 0
    else
        if disableGold  then bundle.gold       = 0 end
        if disableLives then bundle.extraLives  = 0 end
        if not allowPotions then
            local filtered = {}
            for _, it in ipairs(bundle.items or {}) do
                if not isPotionItem(it) then filtered[#filtered + 1] = it end
            end
            bundle.items = filtered
        end
    end

    -- Boon/burden reward modifiers – single central application point.
    if ns.Boons and charKey then
        ns.Boons:ApplyToBundle(bundle, charKey)
    end
end
