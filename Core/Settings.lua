-- Core/Settings.lua
-- Owns account-wide addon settings, profile selection, and rule toggles.
--
-- Storage layout:
--   WRL_DB.settings          (SavedVariables) - account-wide defaults and
--                            active profile.  All helper functions read/write here.
--
--   rec.runSettings          – per-character run overrides stored inside the
--                            character record (WRL_DB.characters[key]).  Reserved for
--                            future per-run behavioural overrides; not yet surfaced in
--                            UI.  Schema migration ensures the field exists on every
--                            record, including those created before this module.
--
-- Profiles are configuration shortcuts. They write values into WRL_DB.settings
-- and do not create separate logic paths anywhere in the addon.  Applying a preset
-- profile and then changing an individual toggle sets the profile to "custom" —
-- that transition is the caller's responsibility (enforced by the future Rules UI).

local ADDON_NAME, ns = ...
local S = ns:NewModule("Settings")

-- ── Account-wide defaults ────────────────────────────────────────────────────

local SETTINGS_DEFAULTS = {
    profile             = "casual_roguelite",
    allowBankRewards    = true,    -- allow the bank to send starter rewards at all
    announceDeaths      = "local", -- "off" | "local" | "party" | "guild"  (final death only)
    announceSoftDeaths  = false,   -- also print a local notice on soft deaths (extra lives remain)
    multiplayerEnabled  = true,    -- auto co-op awareness in party/raid groups
    multiplayerGuildDiscovery = true, -- lightweight WRL presence pings in guild
    ignoreDungeonDeaths = false,   -- when true, party-instance deaths do not count for WRL
    ignoreBattlegroundDeaths = false, -- when true, battleground deaths do not count for WRL
    deathSound          = "dark_souls", -- "off" | "random" | one of Death:DeathSoundOptions()
    uiTheme             = "classic",
    fontProfile         = "default",
    rules               = {},      -- [ruleId] = bool; absent key → rule uses its own default
    -- Reward bundle modifier settings (applied by Core/Rewards.lua: ApplyRewardModifiers).
    rewards             = {
        disableGoldRewards  = false,  -- strip gold from all reward bundles
        disableExtraLives   = false,  -- strip extra lives from all reward bundles
        bagsOnly            = false,  -- only include bag items; strips gold, lives, and potions
        allowPotionRewards  = true,   -- set false to strip potion items from bundles
    },
    pricing             = {
        resaleSource        = "auto", -- "auto" | "tsm_dbmarket" | "local_fallback"
    },
}

-- ── Profile definitions ──────────────────────────────────────────────────────
-- Each profile is a flat table of setting overrides.  The "rules" sub-table maps
-- rule IDs to their enabled state for this profile.  Keys not listed in a profile
-- are left unchanged when the profile is applied, so adding new settings later
-- is backward-compatible without touching profile definitions.

local PROFILES = {
    casual_roguelite = {
        allowBankRewards  = true,
        announceDeaths    = "local",
        rules = {
            no_auction_house    = false,
            no_mail_except_bank = false,
            no_trade_except_bank = false,
            no_grouping         = false,
            no_dungeon_repeats  = false,
            white_green_only    = false,
        },
    },

    banked_hardcore = {
        allowBankRewards  = true,
        announceDeaths    = "party",
        rules = {
            no_auction_house    = false,
            no_mail_except_bank = true,
            no_trade_except_bank = true,
            no_grouping         = false,
            no_dungeon_repeats  = true,
            white_green_only    = false,
        },
    },

    solo_self_found = {
        allowBankRewards  = false,
        announceDeaths    = "local",
        rules = {
            no_auction_house    = true,
            no_mail_except_bank = true,
            no_trade_except_bank = true,
            no_grouping         = true,
            no_dungeon_repeats  = false,
            white_green_only    = false,
        },
    },

    ironman = {
        allowBankRewards  = false,
        announceDeaths    = "party",
        rules = {
            no_auction_house    = true,
            no_mail_except_bank = true,
            no_trade_except_bank = true,
            no_grouping         = true,
            no_dungeon_repeats  = true,
            white_green_only    = false,
        },
    },

    -- "custom" carries no overrides.  Applying it is a safe no-op that just stamps
    -- the profile name; it exists so callers always have a valid profile ID after
    -- the user diverges from a preset by toggling an individual rule.
    custom = {},
}

-- Ordered list for UI iteration.
local PROFILE_ORDER = {
    "casual_roguelite",
    "banked_hardcore",
    "solo_self_found",
    "ironman",
    "custom",
}

local PROFILE_DISPLAY_NAMES = {
    casual_roguelite = "Casual Roguelite",
    banked_hardcore  = "Banked Hardcore",
    solo_self_found  = "Solo Self Found",
    ironman          = "Ironman",
    custom           = "Custom",
}

-- ── Internal path resolution ─────────────────────────────────────────────────
-- Supports dot-notation paths ("rules.no_auction_house") and plain keys
-- ("allowBankRewards").  Returns the parent table and the final key, or
-- (nil, nil) when WRL_DB.settings is not yet available.
-- Intermediate tables are created on demand so Set() never errors on a missing
-- sub-table.

local function resolvePath(pathOrKey)
    local settings = WRL_DB and WRL_DB.settings
    if not settings then return nil, nil end

    -- Split on dots.
    local parts = {}
    for segment in tostring(pathOrKey):gmatch("[^%.]+") do
        parts[#parts + 1] = segment
    end

    local tbl = settings
    for i = 1, #parts - 1 do
        local seg = parts[i]
        if type(tbl[seg]) ~= "table" then
            tbl[seg] = {}
        end
        tbl = tbl[seg]
    end
    return tbl, parts[#parts]
end

-- ── Public API ───────────────────────────────────────────────────────────────

--- Read a setting by dot-path or plain key.
--- Returns `default` when the stored value is nil.
function S:Get(pathOrKey, default)
    local tbl, key = resolvePath(pathOrKey)
    if not tbl or not key then return default end
    local v = tbl[key]
    if v == nil then return default end
    return v
end

--- Write a setting by dot-path or plain key.
--- Creates any missing intermediate tables automatically.
function S:Set(pathOrKey, value)
    local tbl, key = resolvePath(pathOrKey)
    if not tbl or not key then
        ns:Debug("Settings:Set – could not resolve path '%s'", tostring(pathOrKey))
        return
    end
    tbl[key] = value
    ns:Debug("Settings: set '%s' = %s", pathOrKey, tostring(value))
end

--- Return whether a rule is currently enabled (defaults to false if not set).
function S:GetRuleEnabled(ruleId)
    return self:Get("rules." .. tostring(ruleId), false)
end

--- Enable or disable a named rule.
function S:SetRuleEnabled(ruleId, enabled)
    self:Set("rules." .. tostring(ruleId), enabled == true)
end

--- Return the current profile ID string.
function S:GetProfile()
    if WRL_DB and WRL_DB.settings then
        return WRL_DB.settings.profile or SETTINGS_DEFAULTS.profile
    end
    return SETTINGS_DEFAULTS.profile
end

--- Apply a profile by ID.  Overwrites account-wide settings with the profile's
--- values and stamps the profile name.  Returns true on success.
---
--- Applying "custom" is a no-op for settings values; it just records the name.
--- Applying an unknown ID prints a warning and returns false.
function S:ApplyProfile(profileId)
    local profile = PROFILES[profileId]
    if not profile then
        ns:Print(
            "Settings: unknown profile '%s'. Valid profiles: %s.",
            tostring(profileId),
            table.concat(PROFILE_ORDER, ", ")
        )
        return false
    end

    local settings = WRL_DB.settings
    settings.profile = profileId

    -- Apply top-level keys (the "rules" sub-table is handled separately below).
    for k, v in pairs(profile) do
        if k ~= "rules" then
            settings[k] = v
        end
    end

    -- Apply rule overrides.  Only write keys the profile explicitly defines;
    -- rule IDs absent from the profile definition keep their current values.
    if profile.rules then
        settings.rules = settings.rules or {}
        for ruleId, enabled in pairs(profile.rules) do
            settings.rules[ruleId] = enabled
        end
    end

    ns:Debug("Settings: applied profile '%s'", profileId)
    return true
end

-- ── Metadata helpers (for future UI) ────────────────────────────────────────

--- Ordered list of valid profile IDs.
function S:ProfileList()
    return PROFILE_ORDER
end

--- Human-readable display name for a profile ID.
function S:ProfileDisplayName(profileId)
    return PROFILE_DISPLAY_NAMES[profileId] or profileId
end

--- Returns a shallow copy of a profile's setting overrides.  Useful for UI
--- preview without mutating live settings.
function S:ProfilePreview(profileId)
    local profile = PROFILES[profileId]
    if not profile then return nil end
    local copy = {}
    for k, v in pairs(profile) do
        if k ~= "rules" then copy[k] = v end
    end
    copy.rules = {}
    if profile.rules then
        for ruleId, enabled in pairs(profile.rules) do
            copy.rules[ruleId] = enabled
        end
    end
    return copy
end

-- ── Per-character run settings accessor ─────────────────────────────────────
-- rec.runSettings is reserved for future per-run behavioural overrides.
-- These helpers provide a consistent interface so callers don't reach into
-- character records directly.

--- Return a per-character run setting.  Falls back to the account-wide value.
function S:GetRunSetting(key, default)
    local rec = ns.Database and ns.Database:GetCurrentCharacter()
    if rec and rec.runSettings and rec.runSettings[key] ~= nil then
        return rec.runSettings[key]
    end
    return self:Get(key, default)
end

--- Write a per-character run setting.
function S:SetRunSetting(key, value)
    local rec = ns.Database and ns.Database:GetCurrentCharacter()
    if not rec then
        ns:Debug("Settings:SetRunSetting – no current character record")
        return
    end
    rec.runSettings = rec.runSettings or {}
    rec.runSettings[key] = value
    ns:Debug("Settings: run-setting '%s' = %s", tostring(key), tostring(value))
end

-- ── Initialisation ───────────────────────────────────────────────────────────

function S:Init()
    -- Ensure WRL_DB.settings exists.  Database:Init() has already guaranteed
    -- WRL_DB itself exists (and the schema<5 migration has added the key).
    WRL_DB.settings = WRL_DB.settings or {}
    local settings = WRL_DB.settings

    -- Merge top-level defaults for any key absent in the stored settings.
    -- This handles both new installs and existing installs that gain new keys.
    -- Sub-tables (rules, rewards, pricing) are handled separately below.
    for k, v in pairs(SETTINGS_DEFAULTS) do
        if k ~= "rules" and k ~= "rewards" and k ~= "pricing" and settings[k] == nil then
            settings[k] = v
        end
    end

    -- Ensure the rules sub-table exists.
    settings.rules = settings.rules or {}

    -- Ensure the rewards sub-table exists and all keys have defaults.
    -- New keys added to SETTINGS_DEFAULTS.rewards are merged into existing installs.
    settings.rewards = settings.rewards or {}
    for k, v in pairs(SETTINGS_DEFAULTS.rewards) do
        if settings.rewards[k] == nil then
            settings.rewards[k] = v
        end
    end

    settings.pricing = settings.pricing or {}
    for k, v in pairs(SETTINGS_DEFAULTS.pricing) do
        if settings.pricing[k] == nil then
            settings.pricing[k] = v
        end
    end
    if ns.Pricing and ns.Pricing.NormalizeResaleSource then
        settings.pricing.resaleSource = ns.Pricing:NormalizeResaleSource(settings.pricing.resaleSource)
    elseif settings.pricing.resaleSource ~= "tsm_dbmarket" and settings.pricing.resaleSource ~= "local_fallback" then
        settings.pricing.resaleSource = "auto"
    end

    -- Validate profile; reset to default if the stored value is unrecognised
    -- (e.g. from a future addon version that gets rolled back).
    if not PROFILES[settings.profile] then
        ns:Debug("Settings: unrecognised profile '%s'; resetting to '%s'.",
            tostring(settings.profile), SETTINGS_DEFAULTS.profile)
        settings.profile = SETTINGS_DEFAULTS.profile
    end

    -- Lazy-migrate existing character records to ensure rec.runSettings exists.
    -- The per-char field was introduced in schema v5; older records won't have it.
    -- Database:Init() also sets this in newCharRecord() for brand-new records, so
    -- this loop only touches old records.
    for _, rec in pairs(WRL_DB.characters or {}) do
        if rec.runSettings == nil then
            rec.runSettings = {}
        end
    end

    ns:Debug("Settings: ready (profile=%s, allowBankRewards=%s, announceDeaths=%s, announceSoftDeaths=%s)",
        tostring(settings.profile),
        tostring(settings.allowBankRewards),
        tostring(settings.announceDeaths),
        tostring(settings.announceSoftDeaths))
end
