-- UI/TierDisplay.lua
-- Compatibility helpers retained for older tier-based callers. The active
-- Tiers tab now uses Core/LegacyUnlocks.lua directly.

local ADDON_NAME, ns = ...
local TD = {}
ns.TierDisplay = TD

local function tierContents(tier)
    if ns.Rewards and tier then
        return ns.Rewards:GetTierDisplayContents(tier.id)
    end
    return {
        items = tier and tier.items or {},
        gold = tier and tier.gold or 0,
        extraLives = tier and tier.extraLives or 0,
    }
end

function TD.IsBaselineTier(t)
    return t and t.id == 0
end

function TD.CelebrationLineForTierId(id)
    local lines = {
        [0] = "Everyone starts somewhere.",
        [1] = "You've started building a legacy.",
        [2] = "Your rerolls come prepared.",
        [3] = "Your heirs inherit momentum.",
        [4] = "Your bloodline is immortal.",
    }
    return lines[id] or ""
end

function TD.LadderRewardSummary(tier, T)
    if TD.IsBaselineTier(tier) then return "No rewards yet" end
    local c = tierContents(tier)
    local parts = {}
    if c.gold and c.gold > 0 then
        parts[#parts + 1] = T:FormatMoney(c.gold) .. " stipend"
    end
    for _, it in ipairs(c.items or {}) do
        parts[#parts + 1] = ("%dx %s"):format(it.qty, it.note or ("item:" .. tostring(it.id)))
    end
    if c.extraLives and c.extraLives > 0 then
        parts[#parts + 1] = ("+%d life"):format(c.extraLives)
    end
    return table.concat(parts, ", ")
end

function TD.RewardPills(tier, T)
    local c = tierContents(tier)
    local out = {}
    if c.gold and c.gold > 0 then
        out[#out + 1] = "+ " .. T:FormatMoney(c.gold)
    end
    if c.extraLives and c.extraLives > 0 then
        out[#out + 1] = ("+%d Extra Life"):format(c.extraLives)
    end
    for _, it in ipairs(c.items or {}) do
        out[#out + 1] = ("+%d %s"):format(it.qty or 1, it.note or ("item:" .. tostring(it.id)))
    end
    return out
end

function TD.NextRankUpgradeLines(cur, nxt, T)
    local cCur = tierContents(cur)
    local cNxt = tierContents(nxt)
    local out = {}
    if (cNxt.gold or 0) > (cCur.gold or 0) then
        out[#out + 1] = "Bigger stipend: +" .. T:FormatMoney(cNxt.gold - (cCur.gold or 0))
    end
    if (cNxt.extraLives or 0) > (cCur.extraLives or 0) then
        out[#out + 1] = "Extra life unlocks for new runs."
    end
    for _, it in ipairs(cNxt.items or {}) do
        out[#out + 1] = ("Reward: %dx %s"):format(it.qty or 1, it.note or ("item:" .. tostring(it.id)))
    end
    return out
end
