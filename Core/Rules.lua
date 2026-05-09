-- Core/Rules.lua
-- Modular roguelite honor-rule system with a persistent per-character taint log.
--
-- Rules are data-driven objects.  Each rule:
--   • reads its enabled state from ns.Settings (WRL_DB.settings.rules[id])
--   • fires on one or more WoW game events
--   • logs every trigger to rec.ruleLog (persisted in WRL_DB.characters)
--   • prints a chat warning to the player
--   • may attempt a soft UI frame close; enforcement is NEVER guaranteed
--   • never attempts any server-side enforcement
--
-- Rule result vocabulary
--   "allowed"  – rule fired but the action is explicitly permitted (e.g. bank trade)
--   "warned"   – rule fired; action may or may not be a violation; player reminded
--   "blocked"  – rule fired; addon attempted to close a frame (soft close only)
--   "tainted"  – confirmed rule violation logged against this character
--
-- Log entries live in rec.ruleLog and survive /reload.
-- Log is capped at MAX_LOG_ENTRIES per character to prevent unbounded growth.

local ADDON_NAME, ns = ...
local Rules = ns:NewModule("Rules")

local MAX_LOG_ENTRIES = 200

-- ── Rule definitions ─────────────────────────────────────────────────────────
-- Fields:
--   id          (string)  – stable identifier; matches the key in WRL_DB.settings.rules
--   name        (string)  – human-readable short name for UI
--   description (string)  – one-line explanation shown in Rules tab
--   default     (bool)    – enabled state when no saved setting exists
--   severity    (string)  – "warn" | "strict" (hint for UI coloring; enforcement is always soft)
--   events      (table)   – WoW events that trigger the rule's handler
--   handler     (func)    – function(self, event) called when the event fires and rule is enabled
--                           Receives the Rules module as `self`.  nil for programmatic rules.

local RULE_DEFS = {

    -- ── No Auction House ────────────────────────────────────────────────────
    {
        id          = "no_auction_house",
        name        = "No Auction House",
        description = "Prohibits using the Auction House during a roguelite run.",
        default     = false,
        severity    = "strict",
        events      = { "AUCTION_HOUSE_SHOW" },
        handler     = function(self, event)
            -- Bank characters may use the AH to stock rewards.
            if ns.Database:IsBankCharacter() then return end

            self:Log("no_auction_house", "tainted", "Auction House opened")
            ns:Print(
                "|cffff6060[Rule] No Auction House:|r You opened the Auction House." ..
                " This is against your current ruleset.")

            -- Soft close — player can re-open; we log regardless.
            if AuctionFrame and AuctionFrame:IsShown() then
                HideUIPanel(AuctionFrame)
                self:Log("no_auction_house", "blocked", "Auction House frame closed by addon")
            end
        end,
    },

    -- ── No Mail Except Bank ─────────────────────────────────────────────────
    {
        id          = "no_mail_except_bank",
        name        = "No Mail Except Bank",
        description = "Only bank contributions and bank reward pickups are permitted at the mailbox.",
        default     = false,
        severity    = "warn",
        events      = { "MAIL_SHOW" },
        handler     = function(self, event)
            -- Bank characters use mail to fulfill requests — fully exempt.
            if ns.Database:IsBankCharacter() then return end

            -- Death module set this flag while guiding the player to the mailbox
            -- for their final contribution send.  This is explicitly allowed.
            if ns.Death and ns.Death._awaitingMailbox then
                self:Log("no_mail_except_bank", "allowed", "Final contribution workflow")
                return
            end

            -- Any other mailbox open: warn (we cannot verify whether the player is
            -- legitimately picking up bank rewards or violating the rule).
            self:Log("no_mail_except_bank", "warned", "Mailbox opened")
            ns:Print(
                "|cffffff00[Rule] No Mail Except Bank:|r Mailbox opened." ..
                " Only bank contributions and bank reward pickups are permitted.")
            -- We do NOT close the mailbox frame — the player may need it to
            -- collect legitimate bank reward mails.
        end,
    },

    -- ── No Trade Except Bank ────────────────────────────────────────────────
    {
        id          = "no_trade_except_bank",
        name        = "No Trade Except Bank",
        description = "Prohibits trading with anyone except the designated bank character.",
        default     = false,
        severity    = "strict",
        events      = { "TRADE_SHOW" },
        handler     = function(self, event)
            -- Bank characters use trade to fulfill requests — fully exempt.
            if ns.Database:IsBankCharacter() then return end

            -- The Requests module sets _activeTrade when the bank has loaded a
            -- fulfillment trade on the bank side.  On the requester side we can
            -- instead check whether the trade partner is the registered bank.
            local partnerName =
                (UnitName and UnitName("NPC"))
                or (TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText())

            if partnerName and WRL_DB and WRL_DB.bankCharacter then
                local bankShort = WRL_DB.bankCharacter:match("^([^%-]+)") or WRL_DB.bankCharacter
                if partnerName:lower() == bankShort:lower() then
                    self:Log("no_trade_except_bank", "allowed", "Trade with registered bank: " .. partnerName)
                    return
                end
            end

            -- Also allow if the Requests module flagged an active reward trade.
            if ns.Requests and ns.Requests._activeTrade then
                self:Log("no_trade_except_bank", "allowed", "Requests fulfillment trade")
                return
            end

            local detail = partnerName
                and ("Trade with '%s'"):format(partnerName)
                or  "Trade window opened"
            self:Log("no_trade_except_bank", "tainted", detail)
            ns:Print(
                "|cffff6060[Rule] No Trade Except Bank:|r " .. detail ..
                ". Only trades with the bank character are permitted.")

            -- Soft close attempt.
            if TradeFrame and TradeFrame:IsShown() then
                HideUIPanel(TradeFrame)
                self:Log("no_trade_except_bank", "blocked", "Trade frame closed by addon")
            end
        end,
    },

    -- ── No Grouping ─────────────────────────────────────────────────────────
    {
        id          = "no_grouping",
        name        = "No Grouping",
        description = "Prohibits joining a party or raid during a roguelite run.",
        default     = false,
        severity    = "strict",
        events      = { "GROUP_ROSTER_UPDATE", "RAID_ROSTER_UPDATE" },
        handler     = function(self, event)
            if ns.Database:IsBankCharacter() then return end

            local raidSize  = GetNumRaidMembers  and GetNumRaidMembers()  or 0
            local partySize = GetNumPartyMembers and GetNumPartyMembers() or 0
            local groupSize = (raidSize > 0) and raidSize or partySize

            -- Only warn on the transition from solo → grouped.
            -- _prevGroupSize is initialised in Rules:Init() to avoid false
            -- positives on the first event if the player logs in already grouped.
            local prev = self._prevGroupSize or 0
            self._prevGroupSize = groupSize

            if prev == 0 and groupSize > 0 then
                local detail = ("Joined %s (size %d)"):format(
                    raidSize > 0 and "raid" or "party", groupSize)
                self:Log("no_grouping", "tainted", detail)
                ns:Print(
                    "|cffff6060[Rule] No Grouping:|r " .. detail ..
                    ". Grouping is against your current ruleset.")
            end
        end,
    },

    -- ── No Dungeon Repeats ───────────────────────────────────────────────────
    {
        id          = "no_dungeon_repeats",
        name        = "No Dungeon Repeats",
        description = "Prohibits entering the same dungeon or instance more than once per character.",
        default     = false,
        severity    = "warn",
        events      = { "PLAYER_ENTERING_WORLD" },
        handler     = function(self, event)
            if ns.Database:IsBankCharacter() then return end

            local inInstance = IsInInstance and IsInInstance()
            if not inInstance then return end

            -- Identify the instance.  GetInstanceInfo() is available in TBC+.
            -- Fall back to zone text if the API is absent on old client builds.
            local instanceName
            if GetInstanceInfo then
                instanceName = GetInstanceInfo()
            end
            instanceName = instanceName
                or (GetRealZoneText and GetRealZoneText())
                or "unknown"

            local key = ns:UnitKey(); if not key then return end
            local rec = ns.Database:GetCharacter(key); if not rec then return end
            rec.visitedInstances = rec.visitedInstances or {}

            -- Normalise name to a simple slug for stable key storage.
            local slug = instanceName:lower():gsub("[^%a%d]+", "_")

            if rec.visitedInstances[slug] then
                local first   = rec.visitedInstances[slug]
                local dateStr = date and date("%Y-%m-%d", first) or tostring(first)
                local detail  = ("Re-entered '%s' (first visit %s)"):format(instanceName, dateStr)
                self:Log("no_dungeon_repeats", "tainted", detail)
                ns:Print(
                    "|cffff6060[Rule] No Dungeon Repeats:|r " .. detail ..
                    ". Dungeon repeats are against your current ruleset.")
            else
                rec.visitedInstances[slug] = time()
                ns:Debug("Rules: first visit to '%s' recorded (slug=%s).", instanceName, slug)
            end
        end,
    },

    {
        id          = "white_green_only",
        name        = "White/Green Gear Only",
        description = "Only white (common) or green (uncommon) quality gear may be worn.",
        default     = false,
        severity    = "warn",
        events      = {},       -- programmatic; no automatic detection yet
        handler     = nil,
    },
}

-- ── Internal lookup table ─────────────────────────────────────────────────────

local ruleById = {}
for _, def in ipairs(RULE_DEFS) do
    ruleById[def.id] = def
end

-- Bank characters are out-of-run infrastructure. They may die, group, mail,
-- trade, use the AH, and travel freely without rule taints.
function Rules:IsBankExempt(characterKey)
    return ns.Database
        and ns.Database.IsBankCharacter
        and ns.Database:IsBankCharacter(characterKey or ns:UnitKey())
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Returns true when the named rule is currently enabled.
--- Consults WRL_DB.settings.rules[ruleId] first; falls back to the rule's own
--- default when no saved setting exists.
function Rules:IsEnabled(ruleId)
    if self:IsBankExempt() then return false end
    local def = ruleById[ruleId]
    if not def then return false end

    -- Read from the live settings table without going through Settings:Get so
    -- this remains callable even if Settings:Init() somehow runs after Rules.
    local stored
    if WRL_DB and WRL_DB.settings and WRL_DB.settings.rules then
        stored = WRL_DB.settings.rules[ruleId]
    end

    if stored == nil then
        return def.default
    end
    return stored == true
end

--- Append a rule event to the per-character persistent log.
--- `result`  one of "allowed" | "warned" | "blocked" | "tainted"
--- `detail`  short human-readable description of what happened
function Rules:Log(ruleId, result, detail)
    local key = ns:UnitKey(); if not key then return end
    if self:IsBankExempt(key) then return end
    local rec = ns.Database and ns.Database:GetCharacter(key)
    if not rec then return end

    rec.ruleLog = rec.ruleLog or {}
    table.insert(rec.ruleLog, {
        when    = time(),
        ruleId  = ruleId,
        result  = result or "warned",
        detail  = detail or "",
        zone    = (GetRealZoneText  and GetRealZoneText())  or "",
        subzone = (GetSubZoneText   and GetSubZoneText())   or "",
    })
    local entry = rec.ruleLog[#rec.ruleLog]

    -- Trim oldest entries to stay within the cap.
    while #rec.ruleLog > MAX_LOG_ENTRIES do
        table.remove(rec.ruleLog, 1)
    end

    ns:Debug("Rules: [%s] %s – %s", tostring(ruleId), tostring(result), tostring(detail))
    if ns.Achievements and ns.Achievements.OnRuleLog then
        ns.Achievements:OnRuleLog(key, entry)
    end
end

--- Return the full rule log for a character key (defaults to current player).
function Rules:GetLog(characterKey)
    characterKey = characterKey or ns:UnitKey()
    if not characterKey then return {} end
    local rec = ns.Database and ns.Database:GetCharacter(characterKey)
    if not rec then return {} end
    return rec.ruleLog or {}
end

--- Returns true when the character has at least one "tainted" entry in the log.
function Rules:HasTaints(characterKey)
    for _, entry in ipairs(self:GetLog(characterKey)) do
        if entry.result == "tainted" then return true end
    end
    return false
end

--- Count of "tainted" entries for a character.
function Rules:TaintCount(characterKey)
    local n = 0
    for _, entry in ipairs(self:GetLog(characterKey)) do
        if entry.result == "tainted" then n = n + 1 end
    end
    return n
end

--- Return the ordered list of all rule definitions.  Used by UI tab iteration.
function Rules:Definitions()
    return RULE_DEFS
end

--- Return a single rule definition by ID, or nil.
function Rules:GetDef(ruleId)
    return ruleById[ruleId]
end

-- ── Claimed reward guard ─────────────────────────────────────────────────────
-- Called by Tab_NewRun / Requests before a claim is submitted.
-- Returns true when the tier is new; returns false when it was already claimed.

function Rules:CheckTierClaimAvailable(characterKey, tierId)
    if not ns.Database:HasClaimedTier(characterKey, tierId) then return true end

    local detail = ("Duplicate claim attempted for tier %s"):format(tostring(tierId))
    self:Log("duplicate_reward_claim", "tainted", detail)
    ns:Print(
        "|cffff6060[Reward Already Claimed]:|r Tier %s has already been claimed" ..
        " by this character.",
        tostring(tierId))
    return false
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function Rules:Init()
    -- Snapshot the current group size so the first roster event that
    -- fires does not false-positive if the player logs in already in a group.
    local raidSize  = GetNumRaidMembers  and GetNumRaidMembers()  or 0
    local partySize = GetNumPartyMembers and GetNumPartyMembers() or 0
    self._prevGroupSize = (raidSize > 0) and raidSize or partySize

    -- Register WoW event listeners for all rules that declare events.
    -- Each listener checks IsEnabled() before delegating to the handler,
    -- so toggling a rule mid-session takes effect immediately.
    for _, def in ipairs(RULE_DEFS) do
        if def.events and #def.events > 0 and def.handler then
            local ruleDef = def   -- upvalue capture for the closure
            for _, event in ipairs(def.events) do
                ns:On(event, function(...)
                    if not Rules:IsEnabled(ruleDef.id) then return end
                    ruleDef.handler(Rules, event, ...)
                end)
            end
        end
    end

    ns:Debug("Rules: initialised – %d rules, %d enabled by default.",
        #RULE_DEFS,
        (function()
            local n = 0
            for _, d in ipairs(RULE_DEFS) do if d.default then n = n + 1 end end
            return n
        end)())
end
