-- Core/Multiplayer.lua
-- Lightweight auto co-op awareness for party/raid play.

local ADDON_NAME, ns = ...
local M = ns:NewModule("Multiplayer")

local FIELD = "^"
local SUMMARY_SCHEMA = "R2"
local ROSTER_TTL = 90
local EVENT_TTL = 300
local EVENT_LIMIT = 8
local SEND_COOLDOWN = 2

local roster = {}
local events = {}
local seenEvents = {}
local lastSentAt = {}
local seq = 0

local function now()
    return time and time() or 0
end

local function enabled()
    if ns.Settings and ns.Settings.Get then
        return ns.Settings:Get("multiplayerEnabled", true) == true
    end
    return true
end

local function guildEnabled()
    if not enabled() then return false end
    if ns.Settings and ns.Settings.Get then
        return ns.Settings:Get("multiplayerGuildDiscovery", true) == true
    end
    return true
end

local function clean(value)
    value = tostring(value or "")
    value = value:gsub("[%^|]", " ")
    value = value:gsub("%s+", " ")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function splitFields(payload)
    local fields = {}
    payload = tostring(payload or "")
    local pos = 1
    while true do
        local nextPos = payload:find(FIELD, pos, true)
        if not nextPos then
            fields[#fields + 1] = payload:sub(pos)
            break
        end
        fields[#fields + 1] = payload:sub(pos, nextPos - 1)
        pos = nextPos + 1
    end
    return fields
end

local function shortName(key)
    return (key and key:match("^([^-]+)")) or key or "Unknown"
end

local function eventLabel(kind)
    if kind == "soft_death" then return "soft death" end
    if kind == "final_death" then return "final death" end
    if kind == "revive" then return "revived" end
    if kind == "join" then return "joined" end
    if kind == "leave" then return "left" end
    if kind == "request_created" then return "request created" end
    if kind == "request_confirmed" then return "request confirmed" end
    if kind == "bank_fulfilled" then return "bank fulfilled" end
    if kind == "contribution_prepared" then return "contribution prepared" end
    if kind == "contribution_completed" then return "contribution completed" end
    if kind == "contribution_received" then return "contribution received" end
    return tostring(kind or "event")
end

local function readinessReasonLabel(reason)
    if reason == "older client" then return "older WRL client; details may be limited" end
    if reason == "guild presence" then return "guild discovery only" end
    if reason == "missing state" then return "missing run state" end
    if reason == "missing readiness" then return "readiness details missing" end
    if reason == "local state missing" then return "your run state is unavailable" end
    if reason == "version mismatch" then return "different WRL version" end
    if reason == "different profile" then return "different rule profile" end
    if reason == "different rules" then return "different enabled rules" end
    if reason == "no bank set" then return "peer has no bank set" end
    if reason == "your bank not set" then return "your bank is not set" end
    if reason == "your run ended" then return "your run has ended" end
    return reason
end

local function isAuditEvent(kind)
    return kind == "request_created"
        or kind == "request_confirmed"
        or kind == "bank_fulfilled"
        or kind == "contribution_prepared"
        or kind == "contribution_completed"
        or kind == "contribution_received"
end

local function isRequestWatchEvent(kind)
    return kind == "request_created"
        or kind == "request_confirmed"
        or kind == "bank_fulfilled"
end

local function isContributionWatchEvent(kind)
    return kind == "contribution_prepared"
        or kind == "contribution_completed"
        or kind == "contribution_received"
end

local function requestSubject(detail)
    detail = tostring(detail or "")
    local subject = detail:match("^(Rewards%s+.-)%s+to%s+")
        or detail:match("^(Rewards%s+.-)%s+by%s+")
        or detail:match("^(Rewards%s+.-)%s+for%s+")
    if subject and subject ~= "" then return subject end
    return detail ~= "" and detail or nil
end

local function isFinalDeathState(state)
    return state == "dead_pending_contribution" or state == "retired"
end

local function profileId()
    if ns.Settings and ns.Settings.GetProfile then
        return ns.Settings:GetProfile() or "unknown"
    end
    if WRL_DB and WRL_DB.settings and WRL_DB.settings.profile then
        return WRL_DB.settings.profile
    end
    return "unknown"
end

local function bankReady()
    return WRL_DB and WRL_DB.bankCharacter and WRL_DB.bankCharacter ~= ""
end

local function checksumAdd(sum, text)
    text = tostring(text or "")
    for i = 1, #text do
        sum = (sum + (text:byte(i) * i)) % 9973
    end
    return sum
end

local function ruleEnabled(ruleId)
    if ns.Rules and ns.Rules.IsEnabled then
        return ns.Rules:IsEnabled(ruleId) == true
    end
    if WRL_DB and WRL_DB.settings and WRL_DB.settings.rules then
        return WRL_DB.settings.rules[ruleId] == true
    end
    return false
end

local function rulesFingerprint()
    local enabledIds = {}
    if ns.Rules and ns.Rules.Definitions then
        for _, def in ipairs(ns.Rules:Definitions() or {}) do
            local id = def and def.id
            if id and ruleEnabled(id) then enabledIds[#enabledIds + 1] = id end
        end
    elseif WRL_DB and WRL_DB.settings and WRL_DB.settings.rules then
        for id, on in pairs(WRL_DB.settings.rules) do
            if on == true then enabledIds[#enabledIds + 1] = tostring(id) end
        end
        table.sort(enabledIds)
    end

    local sum = 0
    for _, id in ipairs(enabledIds) do
        sum = checksumAdd(sum, id)
    end
    return ("r%d-%04d"):format(#enabledIds, sum)
end

local function refreshUI()
    if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
        ns.MainFrame:RefreshCurrentTab()
    end
end

local function addLocalEvent(key, kind, detail, channel)
    seq = seq + 1
    table.insert(events, 1, {
        id = table.concat({ "local", clean(key), tostring(now()), tostring(seq), clean(kind) }, ":"),
        key = key or "Unknown",
        kind = kind or "event",
        level = 0,
        lives = 0,
        state = "unknown",
        detail = detail or "",
        channel = channel,
        when = now(),
    })
    while #events > EVENT_LIMIT do table.remove(events) end
    refreshUI()
end

function M:_SendBucket(bucket, sender)
    local t = now()
    if lastSentAt[bucket] and (t - lastSentAt[bucket]) < SEND_COOLDOWN then return false end
    lastSentAt[bucket] = t
    return sender()
end

function M:_CurrentSummary()
    local key = ns.UnitKey and ns:UnitKey() or nil
    if not key or key == "" then return nil end
    local rec = ns.Database and ns.Database.GetCurrentCharacter and ns.Database:GetCurrentCharacter() or nil
    local class = rec and rec.class
    if (not class or class == "") and UnitClass then
        class = select(2, UnitClass("player"))
    end
    local level = (rec and (rec.levelCurrent or rec.levelAtCreate)) or (UnitLevel and UnitLevel("player")) or 0
    local lives = rec and rec.livesRemaining
    if lives == nil then lives = 0 end
    local state = (ns.Run and ns.Run.GetState and rec and ns.Run:GetState(rec)) or (rec and rec.status) or "unknown"
    return {
        schema = SUMMARY_SCHEMA,
        key = key,
        version = ns.version or "?",
        class = class or "UNKNOWN",
        level = tonumber(level) or 0,
        lives = tonumber(lives) or 0,
        state = state or "unknown",
        profile = profileId(),
        rules = rulesFingerprint(),
        bankReady = bankReady(),
        finalDeath = isFinalDeathState(state),
    }
end

function M:_EncodeSummary(summary)
    if not summary then return nil end
    return table.concat({
        SUMMARY_SCHEMA,
        clean(summary.key),
        clean(summary.version),
        clean(summary.class),
        tostring(math.floor(tonumber(summary.level) or 0)),
        tostring(math.floor(tonumber(summary.lives) or 0)),
        clean(summary.state),
        clean(summary.profile or "unknown"),
        clean(summary.rules or "r0-0000"),
        summary.bankReady and "1" or "0",
        summary.finalDeath and "1" or "0",
    }, FIELD)
end

function M:_DecodeSummary(payload)
    local f = splitFields(payload)
    if not f[1] or f[1] == "" then return nil end
    if f[1] == SUMMARY_SCHEMA then
        if not f[2] or f[2] == "" then return nil end
        return {
            schema = f[1],
            key = f[2],
            version = f[3] or "?",
            class = f[4] or "UNKNOWN",
            level = tonumber(f[5]) or 0,
            lives = tonumber(f[6]) or 0,
            state = f[7] or "unknown",
            profile = f[8] or "unknown",
            rules = f[9] or "r0-0000",
            bankReady = f[10] == "1",
            finalDeath = f[11] == "1" or isFinalDeathState(f[7]),
        }
    end
    return {
        schema = "legacy",
        key = f[1],
        version = f[2] or "?",
        class = f[3] or "UNKNOWN",
        level = tonumber(f[4]) or 0,
        lives = tonumber(f[5]) or 0,
        state = f[6] or "unknown",
        readiness = "Unknown",
        readinessReason = "older client",
    }
end

function M:_EvaluateReadiness(peer)
    if not peer then return "Unknown", "missing state" end
    if peer.channel == "GUILD" then return "Unknown", "guild presence" end
    if peer.schema ~= SUMMARY_SCHEMA then return "Unknown", peer.readinessReason or "older client" end

    local localSummary = self:_CurrentSummary()
    if not localSummary then return "Unknown", "local state missing" end
    if not peer.version or peer.version == "" or not peer.profile or peer.profile == "" or not peer.rules or peer.rules == "" then
        return "Warning", "missing readiness"
    end
    if peer.version ~= localSummary.version then return "Warning", "version mismatch" end
    if peer.profile ~= localSummary.profile then return "Warning", "different profile" end
    if peer.rules ~= localSummary.rules then return "Warning", "different rules" end
    if not localSummary.bankReady then return "Warning", "your bank not set" end
    if not peer.bankReady then return "Warning", "no bank set" end
    if peer.finalDeath then return "Warning", "final death pending" end
    if localSummary.finalDeath then return "Warning", "your run ended" end
    if peer.state ~= localSummary.state then return "Warning", "different run state" end
    return "Ready", "aligned"
end

function M:_RememberPeer(summary, channel)
    if not summary or not summary.key then return end
    local selfKey = ns.UnitKey and ns:UnitKey() or nil
    if summary.key == selfKey then return end
    local isNew = roster[summary.key] == nil
    summary.channel = channel or summary.channel
    summary.seenAt = now()
    summary.readiness, summary.readinessReason = self:_EvaluateReadiness(summary)
    roster[summary.key] = summary
    if isNew and channel ~= "GUILD" then
        addLocalEvent(summary.key, "join", "WRL client seen", channel)
    end
    refreshUI()
end

function M:BroadcastHello()
    if not enabled() or not (ns.Comm and ns.Comm.SendGroup) then return false end
    return self:_SendBucket("group:HELLO", function()
        return ns.Comm:SendGroup("HELLO", self:_EncodeSummary(self:_CurrentSummary()))
    end)
end

function M:BroadcastState()
    if not enabled() or not (ns.Comm and ns.Comm.SendGroup) then return false end
    return self:_SendBucket("group:STATE", function()
        return ns.Comm:SendGroup("STATE", self:_EncodeSummary(self:_CurrentSummary()))
    end)
end

function M:BroadcastGuildHello()
    if not guildEnabled() or not (ns.Comm and ns.Comm.SendGuild) then return false end
    return self:_SendBucket("guild:HELLO", function()
        return ns.Comm:SendGuild("HELLO", self:_EncodeSummary(self:_CurrentSummary()))
    end)
end

function M:BroadcastBye()
    if not enabled() or not (ns.Comm and ns.Comm.SendGroup) then return false end
    local summary = self:_CurrentSummary()
    if not summary then return false end
    return ns.Comm:SendGroup("BYE", clean(summary.key))
end

function M:_NextEventId(kind)
    seq = seq + 1
    return table.concat({ clean(ns.UnitKey and ns:UnitKey() or "unknown"), tostring(now()), tostring(seq), clean(kind) }, ":")
end

function M:_EncodeEvent(kind, detail)
    local summary = self:_CurrentSummary()
    if not summary then return nil end
    return table.concat({
        self:_NextEventId(kind),
        clean(summary.key),
        clean(kind),
        tostring(math.floor(summary.level or 0)),
        tostring(math.floor(summary.lives or 0)),
        clean(summary.state),
        clean(detail or ""),
    }, FIELD)
end

function M:BroadcastEvent(kind, detail)
    if not enabled() or not (ns.Comm and ns.Comm.SendGroup) then return false end
    return ns.Comm:SendGroup("EVENT", self:_EncodeEvent(kind, detail))
end

function M:_AddEvent(payload, channel)
    local f = splitFields(payload)
    local eventId = f[1]
    if not eventId or eventId == "" or seenEvents[eventId] then return false end
    seenEvents[eventId] = now()
    local row = {
        id = eventId,
        key = f[2] or "Unknown",
        kind = f[3] or "event",
        level = tonumber(f[4]) or 0,
        lives = tonumber(f[5]) or 0,
        state = f[6] or "unknown",
        detail = f[7] or "",
        channel = channel,
        when = now(),
    }
    table.insert(events, 1, row)
    while #events > EVENT_LIMIT do table.remove(events) end
    refreshUI()
    return true
end

function M:Receive(op, payload, channel, sender)
    if not enabled() then return end
    if op == "HELLO" or op == "STATE" then
        local summary = self:_DecodeSummary(payload)
        self:_RememberPeer(summary, channel)
        if op == "HELLO" and channel ~= "GUILD" then
            self:BroadcastState()
        end
    elseif op == "EVENT" then
        self:_AddEvent(payload, channel)
    elseif op == "BYE" then
        local key = payload and payload ~= "" and payload or sender
        if key then roster[key] = nil end
        if key and channel ~= "GUILD" then
            addLocalEvent(key, "leave", "WRL client left", channel)
        end
        refreshUI()
    end
end

function M:RosterRows()
    local rows = {}
    local t = now()
    for key, row in pairs(roster) do
        if (t - (row.seenAt or 0)) <= ROSTER_TTL then
            rows[#rows + 1] = row
        else
            roster[key] = nil
        end
    end
    table.sort(rows, function(a, b) return (a.key or "") < (b.key or "") end)
    return rows
end

function M:EventRows()
    local rows = {}
    local t = now()
    for _, row in ipairs(events) do
        if (t - (row.when or 0)) <= EVENT_TTL then
            rows[#rows + 1] = row
        end
    end
    return rows
end

function M:PartyRequestRows(limit)
    local grouped = {}
    local order = {}
    for _, event in ipairs(self:EventRows()) do
        if isRequestWatchEvent(event.kind) then
            local subject = requestSubject(event.detail)
            if subject then
                local row = grouped[subject]
                if not row then
                    row = { subject = subject, milestones = {}, latest = event.when or 0 }
                    grouped[subject] = row
                    order[#order + 1] = row
                end
                row.latest = math.max(row.latest or 0, event.when or 0)
                if #row.milestones < 3 then
                    row.milestones[#row.milestones + 1] = ("%s %s"):format(shortName(event.key), eventLabel(event.kind))
                end
            end
        end
    end
    table.sort(order, function(a, b) return (a.latest or 0) > (b.latest or 0) end)
    limit = limit or #order
    while #order > limit do table.remove(order) end
    return order
end

function M:PartyContributionRows(limit)
    local grouped = {}
    local order = {}
    for _, event in ipairs(self:EventRows()) do
        if isContributionWatchEvent(event.kind) then
            local subject = tostring(event.detail or "")
            if subject ~= "" then
                local row = grouped[subject]
                if not row then
                    row = { subject = subject, milestones = {}, latest = event.when or 0 }
                    grouped[subject] = row
                    order[#order + 1] = row
                end
                row.latest = math.max(row.latest or 0, event.when or 0)
                if #row.milestones < 3 then
                    row.milestones[#row.milestones + 1] = ("%s %s"):format(shortName(event.key), eventLabel(event.kind))
                end
            end
        end
    end
    table.sort(order, function(a, b) return (a.latest or 0) > (b.latest or 0) end)
    limit = limit or #order
    while #order > limit do table.remove(order) end
    return order
end

function M:DashboardLines()
    local lines = { "|cffc0a060Co-op Run|r" }
    local peers = self:RosterRows()
    local feed = self:EventRows()
    if #peers > 0 or #feed > 0 then
        lines[#lines + 1] = "Visibility snapshot:"
        lines[#lines + 1] = ("Active WRL party peers: %d"):format(#peers)
        lines[#lines + 1] = ("Recent party activity: %d"):format(#feed)
        lines[#lines + 1] = "Local rules decide actions; this panel only reports party signals."
    end
    if #peers == 0 then
        if #feed > 0 then
            lines[#lines + 1] = "No active WRL party peers right now; showing recent party activity only."
        else
            lines[#lines + 1] = "No WRL co-op signals from your party yet."
            lines[#lines + 1] = "Requests, bank mail, deaths, and contributions still follow your local rules."
        end
    else
        lines[#lines + 1] = ("WRL players nearby: %d"):format(#peers)
        lines[#lines + 1] = "Co-op visibility only; local rules still decide requests, claims, deaths, and contribution credit."
        lines[#lines + 1] = "Ready/Warning/Unknown are visibility hints, not request gates."
        for i = 1, math.min(#peers, 5) do
            local p = peers[i]
            local readiness = p.readiness or "Unknown"
            local readableReason = readinessReasonLabel(p.readinessReason)
            local reason = readableReason and readableReason ~= "" and (" - " .. readableReason) or ""
            lines[#lines + 1] = (" - %s lvl %d | %d %s | %s | %s%s"):format(
                shortName(p.key),
                p.level or 0,
                p.lives or 0,
                (p.lives or 0) == 1 and "life" or "lives",
                p.state or "unknown",
                readiness,
                reason)
        end
    end
    if #feed > 0 then
        lines[#lines + 1] = "Recent co-op events:"
        for i = 1, math.min(#feed, 4) do
            local e = feed[i]
            local detail = e.detail and e.detail ~= "" and (" - " .. e.detail) or ""
            lines[#lines + 1] = (" - %s: %s%s"):format(shortName(e.key), eventLabel(e.kind), detail)
        end
        local auditShown = 0
        for i = 1, #feed do
            local e = feed[i]
            if isAuditEvent(e.kind) then
                if auditShown == 0 then
                    lines[#lines + 1] = "Peer audit context:"
                end
                local detail = e.detail and e.detail ~= "" and (" - " .. e.detail) or ""
                lines[#lines + 1] = (" - %s: %s%s"):format(shortName(e.key), eventLabel(e.kind), detail)
                auditShown = auditShown + 1
                if auditShown >= 3 then break end
            end
        end
        local watched = self:PartyRequestRows(3)
        if #watched > 0 then
            lines[#lines + 1] = "Party requests nearby (visibility only):"
            lines[#lines + 1] = "Nearby request milestones only; act from your own request and bank rows."
            for i = 1, #watched do
                lines[#lines + 1] = (" - %s: %s"):format(watched[i].subject, table.concat(watched[i].milestones, "; "))
            end
        end
        local contributions = self:PartyContributionRows(3)
        if #contributions > 0 then
            lines[#lines + 1] = "Party final contributions nearby (visibility only):"
            lines[#lines + 1] = "Nearby contribution milestones only; each runner's local contribution credit still decides outcomes."
            for i = 1, #contributions do
                lines[#lines + 1] = (" - %s: %s"):format(contributions[i].subject, table.concat(contributions[i].milestones, "; "))
            end
        end
    end
    return lines
end

function M:Init()
    if self._initialized then return end
    self._initialized = true
    if ns.Comm and ns.Comm.RegisterOpHandler then
        ns.Comm:RegisterOpHandler("HELLO", function(op, payload, sender, channel) self:Receive(op, payload, channel, sender) end)
        ns.Comm:RegisterOpHandler("STATE", function(op, payload, sender, channel) self:Receive(op, payload, channel, sender) end)
        ns.Comm:RegisterOpHandler("EVENT", function(op, payload, sender, channel) self:Receive(op, payload, channel, sender) end)
        ns.Comm:RegisterOpHandler("BYE", function(op, payload, sender, channel) self:Receive(op, payload, channel, sender) end)
    end
    if ns.On then
        ns:On("PLAYER_ENTERING_WORLD", function()
            self:BroadcastHello()
            self:BroadcastGuildHello()
        end)
        ns:On("GROUP_ROSTER_UPDATE", function() self:BroadcastHello() end)
        ns:On("PLAYER_LEVEL_UP", function() self:BroadcastState() end)
        ns:On("PLAYER_LEAVING_WORLD", function() self:BroadcastBye() end)
    end
end
