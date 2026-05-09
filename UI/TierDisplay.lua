-- UI/TierDisplay.lua
-- Display helpers for tier definitions. Does not mutate tier tables.
-- Money strings use ns.Tiers:FormatMoney (color-coded).
-- Reward contents are resolved via ns.Rewards:GetTierDisplayContents so that
-- this file does not depend on tier defs carrying items/gold/extraLives directly.

local ADDON_NAME, ns = ...
local TD = {}
ns.TierDisplay = TD

--- Return raw display contents { items, gold, extraLives } for a tier.
--- Falls back to empty contents if Rewards module is not yet loaded.
local function tierContents(tier)
    if ns.Rewards and tier then
        return ns.Rewards:GetTierDisplayContents(tier.id)
    end
    -- Backward-compat fallback: old-format tiers may still carry these fields.
    return {
        items      = tier and tier.items      or {},
        gold       = tier and tier.gold       or 0,
        extraLives = tier and tier.extraLives or 0,
    }
end

local function iconTag(texture, size)
    texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark"
    size = size or 13
    return ("|T%s:%d:%d:0:0|t"):format(texture, size, size)
end

local function itemIconTag(itemId)
    return iconTag((itemId and GetItemIcon(itemId)) or "Interface\\Icons\\INV_Misc_QuestionMark")
end

--- Tier 0 is the baseline starting tier (not framed as a bank "unlock" in the rewards UI).
function TD.IsBaselineTier(t)
    return t and t.id == 0
end

-- Flavor lines under current rank (UI-only; separate from tier blurbs in Core/Tiers.lua).
local CELEBRATION_BY_ID = {
    [0] = "Everyone starts somewhere.",
    [1] = "You've started building a legacy.",
    [2] = "Your rerolls come prepared.",
    [3] = "Your heirs inherit momentum.",
    [4] = "Your bloodline is immortal.",
}

function TD.CelebrationLineForTierId(id)
    return CELEBRATION_BY_ID[id] or ""
end

--- One-line summary for the tier ladder column (tier 0 stays minimal).
function TD.LadderRewardSummary(tier, T)
    if TD.IsBaselineTier(tier) then
        return "No rewards yet"
    end
    local c = tierContents(tier)
    local parts = {}
    if c.gold and c.gold > 0 then
        parts[#parts + 1] = T:FormatMoney(c.gold) .. " stipend"
    end
    for _, it in ipairs(c.items or {}) do
        parts[#parts + 1] = ("%dx %s"):format(it.qty, it.note or ("item:" .. it.id))
    end
    if c.extraLives and c.extraLives > 0 then
        parts[#parts + 1] = ("+%d life"):format(c.extraLives)
    end
    return table.concat(parts, ", ")
end

--- "Pill" lines for reward cards (+gold, +items, +lives). Omits zero gold and zero lives.
function TD.RewardPills(tier, T)
    local c = tierContents(tier)
    local out = {}
    if c.gold and c.gold > 0 then
        out[#out + 1] = ("%s +%s seed money"):format(iconTag("Interface\\Icons\\INV_Misc_Coin_01"), T:FormatMoney(c.gold))
    end
    if c.extraLives and c.extraLives > 0 then
        out[#out + 1] = ("%s +%d Extra Life"):format(iconTag("Interface\\Icons\\Spell_Holy_Resurrection"), c.extraLives)
    end
    for _, it in ipairs(c.items or {}) do
        local label = it.note or ("Item " .. tostring(it.id))
        out[#out + 1] = ("%s +%d %s"):format(itemIconTag(it.id), it.qty, label)
    end
    return out
end

local function firstItemMatching(contents, pred)
    if not contents then return nil end
    for _, it in ipairs(contents.items or {}) do
        if pred(it) then return it end
    end
    return nil
end

local function isBagItem(it)
    local n = (it.note or ""):lower()
    return n:find("bag") or n:find("pack")
end

local function isPotionItem(it)
    local n = (it.note or ""):lower()
    return n:find("potion") or n:find("healing")
end

--- Fun "upgrade" lines when comparing current vs next tier (for next-rank preview).
function TD.NextRankUpgradeLines(cur, nxt, T)
    local lines = {}
    if not cur or not nxt then return lines end

    local cCur = tierContents(cur)
    local cNxt = tierContents(nxt)

    if (cNxt.gold or 0) > (cCur.gold or 0) then
        local delta = cNxt.gold - cCur.gold
        lines[#lines + 1] = ("%s Bigger stipend: +%s over your current rank"):format(
            iconTag("Interface\\Icons\\INV_Misc_Coin_01"),
            T:FormatMoney(delta))
    end

    if (cNxt.extraLives or 0) > (cCur.extraLives or 0) then
        lines[#lines + 1] = ("%s Extra life unlocks for new runs!"):format(
            iconTag("Interface\\Icons\\Spell_Holy_Resurrection"))
    end

    local bagCur = firstItemMatching(cCur, isBagItem)
    local bagNxt = firstItemMatching(cNxt, isBagItem)
    if bagNxt then
        if bagCur and (bagCur.id ~= bagNxt.id or (bagCur.note or "") ~= (bagNxt.note or "")) then
            lines[#lines + 1] = ("%s Better bags: %s -> %s"):format(
                itemIconTag(bagNxt.id),
                bagCur.note or ("item " .. bagCur.id),
                bagNxt.note or ("item " .. bagNxt.id))
        elseif not bagCur then
            lines[#lines + 1] = ("%s Bag unlock: %s"):format(
                itemIconTag(bagNxt.id),
                bagNxt.note or ("item " .. bagNxt.id))
        end
    end

    local potCur = firstItemMatching(cCur, isPotionItem)
    local potNxt = firstItemMatching(cNxt, isPotionItem)
    if potNxt then
        if potCur and (potCur.id ~= potNxt.id or (potCur.note or "") ~= (potNxt.note or "")) then
            lines[#lines + 1] = ("%s Better potions: %s -> %s"):format(
                itemIconTag(potNxt.id),
                potCur.note or ("item " .. potCur.id),
                potNxt.note or ("item " .. potNxt.id))
        elseif not potCur then
            lines[#lines + 1] = ("%s Potion unlock: %s"):format(
                itemIconTag(potNxt.id),
                potNxt.note or ("item " .. potNxt.id))
        end
    end

    return lines
end
