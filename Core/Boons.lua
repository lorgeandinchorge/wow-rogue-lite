-- Core/Boons.lua
-- Run modifier definitions + persistence helpers for boons and burdens.
-- Boons modify reward bundles through Requests:Bundle().
-- Burdens map to existing rules by enabling rule toggles.

local ADDON_NAME, ns = ...
local Boons = ns:NewModule("Boons")

local BOON_DEFS = {
    {
        id = "extra_starter_bag",
        name = "Extra Starter Bag",
        description = "Adds one extra starter bag to each requested rank bundle.",
        livesBonus = 0,
        goldBonus = 0,
        extraItems = {
            { id = 4496, qty = 1, note = "Small Brown Pouch (6-slot bag)" },
        },
    },
    {
        id = "potion_cache",
        name = "Potion Cache",
        description = "Adds minor health potions to each requested rank bundle.",
        livesBonus = 0,
        goldBonus = 0,
        extraItems = {
            { id = 118, qty = 5, note = "Minor Healing Potion" },
        },
    },
    {
        id = "profession_stipend",
        name = "Profession Stipend",
        description = "Adds 50 silver to each requested rank bundle.",
        livesBonus = 0,
        goldBonus = 5000,
        extraItems = {},
    },
    {
        id = "one_extra_life",
        name = "One Extra Life",
        description = "Adds one extra life to requested rank bundles.",
        livesBonus = 1,
        goldBonus = 0,
        extraItems = {},
    },
}

local BURDEN_DEFS = {
    {
        id = "no_auction_house",
        name = "No Auction House",
        description = "Auction House use is prohibited for this run.",
        ruleId = "no_auction_house",
    },
    {
        id = "no_non_bank_trade",
        name = "No Non-Bank Trade",
        description = "Only trading with your registered bank character is allowed.",
        ruleId = "no_trade_except_bank",
    },
    {
        id = "no_grouping",
        name = "No Grouping",
        description = "Grouping with other players is prohibited.",
        ruleId = "no_grouping",
    },
    {
        id = "no_dungeon_repeats",
        name = "No Dungeon Repeats",
        description = "Re-entering the same dungeon is prohibited.",
        ruleId = "no_dungeon_repeats",
    },
    {
        id = "white_green_only",
        name = "White/Green Gear Only",
        description = "Only white or green quality gear may be worn.",
        ruleId = "white_green_only",
    },
}

local boonById = {}
for _, def in ipairs(BOON_DEFS) do
    boonById[def.id] = def
end

local burdenById = {}
for _, def in ipairs(BURDEN_DEFS) do
    burdenById[def.id] = def
end

function Boons:BoonDefs()
    return BOON_DEFS
end

function Boons:BurdenDefs()
    return BURDEN_DEFS
end

function Boons:GetBoonDef(boonId)
    return boonById[boonId]
end

function Boons:GetBurdenDef(burdenId)
    return burdenById[burdenId]
end

function Boons:IsLocked(charKey)
    if ns.Database and ns.Database:IsBankCharacter(charKey) then
        return true
    end

    charKey = charKey or ns:UnitKey()
    local rec = ns.Database and ns.Database:GetCharacter(charKey)
    if not rec then return true end
    if next(rec.claimedTiers or {}) then return true end

    local state = ns.Run and ns.Run:GetState(rec) or rec.status
    return state == "dead_pending_contribution" or state == "retired" or state == "archived"
end

function Boons:HasBoon(charKey, boonId)
    local rec = ns.Database and ns.Database:GetCharacter(charKey or ns:UnitKey())
    if not rec or not rec.boons then return false end
    return rec.boons[boonId] ~= nil
end

function Boons:HasBurden(charKey, burdenId)
    local rec = ns.Database and ns.Database:GetCharacter(charKey or ns:UnitKey())
    if not rec or not rec.burdens then return false end
    return rec.burdens[burdenId] ~= nil
end

function Boons:SetBoons(charKey, boonIdList)
    charKey = charKey or ns:UnitKey()
    if self:IsLocked(charKey) then return false end
    local rec = ns.Database and ns.Database:GetCharacter(charKey)
    if not rec then return false end
    rec.boons = {}
    for _, boonId in ipairs(boonIdList or {}) do
        if boonById[boonId] then
            rec.boons[boonId] = { selectedAt = time() }
        end
    end
    return true
end

function Boons:SetBurdens(charKey, burdenIdList)
    charKey = charKey or ns:UnitKey()
    if self:IsLocked(charKey) then return false end
    local rec = ns.Database and ns.Database:GetCharacter(charKey)
    if not rec then return false end
    rec.burdens = {}
    for _, burdenId in ipairs(burdenIdList or {}) do
        if burdenById[burdenId] then
            rec.burdens[burdenId] = { selectedAt = time() }
        end
    end
    self:ApplyBurdenRules(charKey)
    return true
end

function Boons:ApplyToBundle(bundle, charKey)
    if not charKey or not bundle then return end
    local rec = ns.Database and ns.Database:GetCharacter(charKey)
    if not rec or not rec.boons then return end

    bundle.items = bundle.items or {}
    for boonId in pairs(rec.boons) do
        local def = boonById[boonId]
        if def then
            if (def.livesBonus or 0) > 0 then
                bundle.extraLives = (bundle.extraLives or 0) + def.livesBonus
            end
            if (def.goldBonus or 0) > 0 then
                bundle.gold = (bundle.gold or 0) + def.goldBonus
            end
            for _, it in ipairs(def.extraItems or {}) do
                local found = false
                for _, existing in ipairs(bundle.items) do
                    if existing.id == it.id then
                        existing.qty = (existing.qty or 0) + (it.qty or 0)
                        found = true
                        break
                    end
                end
                if not found then
                    bundle.items[#bundle.items + 1] = {
                        id = it.id,
                        qty = it.qty or 1,
                        note = it.note,
                    }
                end
            end
        end
    end
end

function Boons:ApplyBurdenRules(charKey)
    charKey = charKey or ns:UnitKey()
    local rec = ns.Database and ns.Database:GetCharacter(charKey)
    if not rec or not rec.burdens then return end
    if not (ns.Settings and ns.Settings.SetRuleEnabled) then return end

    for burdenId in pairs(rec.burdens) do
        local def = burdenById[burdenId]
        if def and def.ruleId then
            ns.Settings:SetRuleEnabled(def.ruleId, true)
        end
    end
end

function Boons:Init()
    local key = ns:UnitKey()
    if key then
        self:ApplyBurdenRules(key)
    end
end

