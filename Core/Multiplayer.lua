-- Core/Multiplayer.lua
-- Lightweight auto co-op awareness for party/raid play.

local ADDON_NAME, ns = ...
local M = ns:NewModule("Multiplayer")

local FIELD = "^"
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
    return tostring(kind or "event")
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
        key = key,
        version = ns.version or "?",
        class = class or "UNKNOWN",
        level = tonumber(level) or 0,
        lives = tonumber(lives) or 0,
        state = state or "unknown",
    }
end

function M:_EncodeSummary(summary)
    if not summary then return nil end
    return table.concat({
        clean(summary.key),
        clean(summary.version),
        clean(summary.class),
        tostring(math.floor(tonumber(summary.level) or 0)),
        tostring(math.floor(tonumber(summary.lives) or 0)),
        clean(summary.state),
    }, FIELD)
end

function M:_DecodeSummary(payload)
    local f = splitFields(payload)
    if not f[1] or f[1] == "" then return nil end
    return {
        key = f[1],
        version = f[2] or "?",
        class = f[3] or "UNKNOWN",
        level = tonumber(f[4]) or 0,
        lives = tonumber(f[5]) or 0,
        state = f[6] or "unknown",
    }
end

function M:_RememberPeer(summary, channel)
    if not summary or not summary.key then return end
    local selfKey = ns.UnitKey and ns:UnitKey() or nil
    if summary.key == selfKey then return end
    local isNew = roster[summary.key] == nil
    summary.channel = channel or summary.channel
    summary.seenAt = now()
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

function M:DashboardLines()
    local lines = { "|cffc0a060Co-op Run|r" }
    local peers = self:RosterRows()
    if #peers == 0 then
        lines[#lines + 1] = "No WRL co-op players seen in your group yet."
    else
        lines[#lines + 1] = ("WRL players nearby: %d"):format(#peers)
        for i = 1, math.min(#peers, 5) do
            local p = peers[i]
            lines[#lines + 1] = (" - %s lvl %d | %d %s | %s"):format(
                shortName(p.key),
                p.level or 0,
                p.lives or 0,
                (p.lives or 0) == 1 and "life" or "lives",
                p.state or "unknown")
        end
    end
    local feed = self:EventRows()
    if #feed > 0 then
        lines[#lines + 1] = "Recent co-op events:"
        for i = 1, math.min(#feed, 4) do
            local e = feed[i]
            local detail = e.detail and e.detail ~= "" and (" - " .. e.detail) or ""
            lines[#lines + 1] = (" - %s: %s%s"):format(shortName(e.key), eventLabel(e.kind), detail)
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
