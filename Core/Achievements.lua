-- Core/Achievements.lua
-- Addon-only legacy achievements for account and run milestones.

local ADDON_NAME, ns = ...
local A = ns:NewModule("Achievements")

local function currentKey()
    return ns:UnitKey()
end

local function currentRec()
    local key = currentKey()
    return key and ns.Database:GetCharacter(key) or nil
end

local function hasTaint(rec)
    if not rec or type(rec.ruleLog) ~= "table" then return false end
    for _, e in ipairs(rec.ruleLog) do
        if e and e.result == "tainted" then return true end
    end
    return false
end

local function levelAtLeast(rec, n)
    return (rec and (rec.levelCurrent or rec.levelAtCreate or 1) or 1) >= n
end

local function isRunCharacterKey(key)
    if not key then return false end
    if not ns.Database or not ns.Database.IsBankCharacter then return true end
    return not ns.Database:IsBankCharacter(key)
end

local function lifetimeAtLeast(copper)
    return (WRL_DB and WRL_DB.totalContributed or 0) >= copper
end

local function legendTierUnlocked()
    if not ns.Tiers or not ns.Tiers.CurrentTier then return false end
    local cur = ns.Tiers:CurrentTier(WRL_DB and WRL_DB.totalContributed or 0)
    return cur and cur.id and cur.id >= 5
end

local function isPlayableRunContext(ctx)
    if not ctx then return false end
    local key = ctx.key or currentKey()
    local rec = ctx.rec or (key and ns.Database:GetCharacter(key)) or nil
    if not isRunCharacterKey(key) then return false end
    if ns.Run and ns.Run.IsPlayable then
        return ns.Run:IsPlayable(rec or key)
    end
    local state = rec and rec.status
    return state == nil or state == "fresh" or state == "active" or state == "alive"
end

local function canEvaluateDefinition(def, ctx)
    if not def or not ctx then return false end
    if ctx.event == "death_final" then
        return def.id == "first_final_death"
    end
    return isPlayableRunContext(ctx)
end

local ACHIEVEMENTS = {
    {
        id = "first_final_death",
        name = "First Bloodline Loss",
        description = "Suffer your first final death.",
        hidden = false,
        criteria = function(ctx)
            return ctx.event == "death_final"
        end,
    },
    {
        id = "reach_level_10",
        name = "Double Digits",
        description = "Reach level 10 on any run character.",
        hidden = false,
        criteria = function(ctx)
            local key = ctx.key or currentKey()
            local rec = ctx.rec or currentRec()
            return isRunCharacterKey(key) and levelAtLeast(rec, 10)
        end,
    },
    {
        id = "reach_level_20",
        name = "Seasoned Adventurer",
        description = "Reach level 20 on any run character.",
        hidden = false,
        criteria = function(ctx)
            local key = ctx.key or currentKey()
            local rec = ctx.rec or currentRec()
            return isRunCharacterKey(key) and levelAtLeast(rec, 20)
        end,
    },
    {
        id = "retire_above_level_30",
        name = "Veteran's Rest",
        description = "Retire a character at level 30 or above.",
        hidden = false,
        criteria = function(ctx)
            if ctx.event ~= "run_state_changed" or ctx.state ~= "retired" then return false end
            local key = ctx.key or currentKey()
            local rec = ctx.rec or currentRec()
            return isRunCharacterKey(key) and levelAtLeast(rec, 30)
        end,
    },
    {
        id = "contribute_10g_lifetime",
        name = "First Tithe",
        description = "Contribute at least 10g lifetime to your legacy bank.",
        hidden = false,
        criteria = function(ctx)
            if ctx.event ~= "contribution" then return false end
            return lifetimeAtLeast(100000)
        end,
    },
    {
        id = "contribute_100g_lifetime",
        name = "Major Patron",
        description = "Contribute at least 100g lifetime to your legacy bank.",
        hidden = false,
        criteria = function(ctx)
            if ctx.event ~= "contribution" then return false end
            return lifetimeAtLeast(1000000)
        end,
    },
    {
        id = "no_taint_to_level_20",
        name = "Clean Path",
        description = "Reach level 20 without recording any taint violations.",
        hidden = false,
        criteria = function(ctx)
            local key = ctx.key or currentKey()
            local rec = ctx.rec or currentRec()
            return isRunCharacterKey(key) and levelAtLeast(rec, 20) and not hasTaint(rec)
        end,
    },
    {
        id = "first_extra_life_used",
        name = "Second Wind",
        description = "Use an extra life for the first time.",
        hidden = false,
        criteria = function(ctx)
            return ctx.event == "extra_life_used"
        end,
    },
    {
        id = "first_legend_tier_unlock",
        name = "Bloodline Legend",
        description = "Unlock the Legend tier through lifetime contributions.",
        hidden = true,
        criteria = function(ctx)
            if ctx.event ~= "contribution" then return false end
            return legendTierUnlocked()
        end,
    },
}

local byId = {}
for _, def in ipairs(ACHIEVEMENTS) do
    byId[def.id] = def
end

function A:Definitions()
    return ACHIEVEMENTS
end

function A:GetDef(id)
    return byId[id]
end

function A:IsEarned(id)
    return ns.Database:HasAchievement(id)
end

function A:GetEarned(id)
    return ns.Database:GetAchievement(id)
end

function A:EarnedCount()
    local n = 0
    for _ in pairs(ns.Database:GetAchievements()) do n = n + 1 end
    return n
end

function A:Browse()
    local earned = {}
    local locked = {}
    local visibleCount = 0

    for _, def in ipairs(ACHIEVEMENTS) do
        local entry = self:GetEarned(def.id)
        if entry then
            visibleCount = visibleCount + 1
            earned[#earned + 1] = {
                id = def.id,
                name = def.name,
                description = def.description,
                requirement = def.requirement or def.description,
                hidden = def.hidden and true or false,
                when = entry.when,
                characterKey = entry.characterKey,
            }
        elseif not def.hidden then
            visibleCount = visibleCount + 1
            locked[#locked + 1] = {
                id = def.id,
                name = def.name,
                description = def.description,
                requirement = def.requirement or def.description,
                hidden = false,
            }
        end
    end

    table.sort(earned, function(a, b)
        if (a.when or 0) ~= (b.when or 0) then
            return (a.when or 0) > (b.when or 0)
        end
        return (a.name or a.id or "") < (b.name or b.id or "")
    end)
    table.sort(locked, function(a, b)
        return (a.name or a.id or "") < (b.name or b.id or "")
    end)

    return {
        earnedCount = #earned,
        visibleCount = visibleCount,
        earned = earned,
        locked = locked,
    }
end

function A:VisibleDefinitions()
    local out = {}
    for _, def in ipairs(ACHIEVEMENTS) do
        if not def.hidden or self:IsEarned(def.id) then
            out[#out + 1] = def
        end
    end
    return out
end

function A:Evaluate(event, ctx)
    ctx = ctx or {}
    ctx.event = event or ctx.event or "manual"
    ctx.key = ctx.key or currentKey()
    ctx.rec = ctx.rec or (ctx.key and ns.Database:GetCharacter(ctx.key)) or nil

    for _, def in ipairs(ACHIEVEMENTS) do
        if not self:IsEarned(def.id) and canEvaluateDefinition(def, ctx) then
            local ok, passed = pcall(def.criteria, ctx)
            if ok and passed then
                local entry = ns.Database:EarnAchievement(def.id, ctx.key)
                if entry then
                    ns:Print("|cffc0a060Achievement earned:|r %s - %s", def.name, def.description)
                end
            end
        end
    end
end

function A:OnContribution(characterKey, receipt)
    self:Evaluate("contribution", { key = characterKey, receipt = receipt })
end

function A:OnRuleLog(characterKey, logEntry)
    self:Evaluate("rule_log", { key = characterKey, logEntry = logEntry })
end

function A:OnFinalDeath(characterKey, rec)
    self:Evaluate("death_final", { key = characterKey, rec = rec })
end

function A:OnExtraLifeUsed(characterKey, rec)
    self:Evaluate("extra_life_used", { key = characterKey, rec = rec })
end

function A:OnRunStateChanged(characterKey, newState, prevState, reason)
    self:Evaluate("run_state_changed", {
        key = characterKey,
        rec = characterKey and ns.Database:GetCharacter(characterKey) or nil,
        state = newState,
        previous = prevState,
        reason = reason,
    })
end

function A:OnLevelUp(newLevel)
    local key = currentKey()
    local rec = key and ns.Database:GetCharacter(key) or nil
    if rec then rec.levelCurrent = math.max(rec.levelCurrent or 1, tonumber(newLevel) or 1) end
    self:Evaluate("level_up", { key = key, rec = rec, level = newLevel })
end

function A:Init()
    ns:On("PLAYER_LEVEL_UP", function(level)
        A:OnLevelUp(level)
    end)

    -- Login is both a backfill pass for existing installs and an account-wide
    -- reevaluation point for lifetime milestones.
    self:Evaluate("login", { key = currentKey(), rec = currentRec() })
end
