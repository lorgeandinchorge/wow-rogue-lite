-- Core/Tiers.lua
-- Tier ladder: thresholds (in copper, lifetime contributed to the bank) unlock
-- reward bundles that a new run can request from the bank.
--
-- Tiers carry only identity data: id, name, threshold, blurb, and bundleIds.
-- Actual reward contents (items, gold, extra lives) live in Core/Rewards.lua.
-- The bundleIds list references bundle definitions owned by the Rewards module.
--
-- Gold thresholds are in copper (1g = 10000).

local ADDON_NAME, ns = ...
local T = ns:NewModule("Tiers")

local function g(gold) return gold * 10000 end

local function copyTierDef(t)
    local out = {}
    for k, v in pairs(t) do
        if k == "bundleIds" and type(v) == "table" then
            -- Deep-copy the bundle ID list (strings are value types, but keep
            -- the table so mutations on the copy don't affect TIER_DEFS).
            out.bundleIds = {}
            for i, bid in ipairs(v) do
                out.bundleIds[i] = bid
            end
        else
            out[k] = v
        end
    end
    return out
end

local TIER_DEFS = {
    {
        id = 0, name = "Barebones", threshold = 0,
        blurb    = "Fresh run. No starter rewards yet.",
        bundleIds = {},
    },
    {
        id = 1, name = "Survivalist", threshold = g(5),
        blurb    = "Your first bank unlock. A little space and a little seed money.",
        bundleIds = { "tier_1_base" },
    },
    {
        id = 2, name = "Adventurer", threshold = g(25),
        blurb    = "You've proven you can make coin. Better bags, basic potions.",
        bundleIds = { "tier_2_base" },
    },
    {
        id = 3, name = "Veteran", threshold = g(100),
        blurb    = "Mid-game ready. Enough for skills and basic needs.",
        bundleIds = { "tier_3_base" },
    },
    {
        id = 4, name = "Champion", threshold = g(400),
        blurb    = "You run deep. Large bags, strong pots, toward epic mount.",
        bundleIds = { "tier_4_base" },
    },
    {
        id = 5, name = "Legend", threshold = g(1200),
        blurb    = "Outland-ready. Extra life on next run, flying fund, top pots.",
        bundleIds = { "tier_5_base" },
    },
}

local function defaultDefsCopy()
    local out = {}
    for i, t in ipairs(TIER_DEFS) do
        out[i] = copyTierDef(t)
    end
    return out
end

-- Returns true when the saved tier table needs to be replaced with defaults.
-- Old format had items/gold/extraLives directly on tier defs; new format uses
-- bundleIds.  A missing bundleIds on the first tier reliably detects old data.
local function needsTierMigration(defs)
    if type(defs) ~= "table" or #defs == 0 then
        return true
    end

    local first = defs[1]
    if type(first) ~= "table" then
        return true
    end

    -- Name/threshold sanity check (catches badly-shaped or future-version data).
    if first.name ~= "Barebones" or (first.threshold or 0) ~= 0 then
        return true
    end

    -- Old format: no bundleIds field.  Triggers one-time migration.
    if first.bundleIds == nil then
        return true
    end

    return false
end

function T:Init()
    -- Store as SV so players can tweak/override later if they want.
    if needsTierMigration(WRL_DB.tiers) then
        WRL_DB.tiers = defaultDefsCopy()
    end
end

-- Always returns a non-empty array; UI must never get nil [1] from a bad SV.
function T:Definitions()
    local d = (WRL_DB and WRL_DB.tiers) or TIER_DEFS
    if needsTierMigration(d) then
        if WRL_DB then
            WRL_DB.tiers = defaultDefsCopy()
            return WRL_DB.tiers
        end
        return defaultDefsCopy()
    end
    return d
end

-- Highest tier whose threshold the lifetime total has crossed.
function T:CurrentTier(totalContributedCopper)
    local defs = self:Definitions()
    local cur = defs[1] or TIER_DEFS[1]
    for _, t in ipairs(defs) do
        if totalContributedCopper >= (t.threshold or 0) then cur = t end
    end
    return cur or TIER_DEFS[1]
end

-- Next tier (or nil if maxed).
function T:NextTier(totalContributedCopper)
    for _, t in ipairs(self:Definitions()) do
        if totalContributedCopper < t.threshold then return t end
    end
    return nil
end

-- All tiers the account has unlocked so far.
function T:UnlockedTiers(totalContributedCopper)
    local out = {}
    for _, t in ipairs(self:Definitions()) do
        if totalContributedCopper >= t.threshold then out[#out+1] = t end
    end
    return out
end

-- Progress 0..1 toward the next tier, for the UI progress bar.
function T:ProgressToNext(totalContributedCopper)
    local cur = self:CurrentTier(totalContributedCopper)
    local nxt = self:NextTier(totalContributedCopper)
    if not nxt then return 1.0, cur, nil end
    local span = nxt.threshold - (cur and cur.threshold or 0)
    if span <= 0 then return 0, cur, nxt end
    local have = totalContributedCopper - (cur and cur.threshold or 0)
    return math.max(0, math.min(1, have / span)), cur, nxt
end

-- Copper formatter: returns "12g 34s 56c" with color codes, short form.
function T:FormatMoney(copper)
    copper = math.max(0, math.floor(copper or 0))
    local gold   = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop    = copper % 100
    if gold > 0 then
        return string.format("|cffffd700%d|rg |cffc7c7cf%d|rs |cffeda55f%d|rc", gold, silver, cop)
    elseif silver > 0 then
        return string.format("|cffc7c7cf%d|rs |cffeda55f%d|rc", silver, cop)
    else
        return string.format("|cffeda55f%d|rc", cop)
    end
end
