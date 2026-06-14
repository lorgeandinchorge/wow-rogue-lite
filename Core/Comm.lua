-- Core/Comm.lua
-- Addon-to-addon messaging between the player's own characters.
--
-- We use SendAddonMessage with WHISPER target = bank character. This works
-- on the same realm; cross-realm addon whispers are unreliable in BC, so we
-- also support a mail-based fallback (see Requests.lua).
--
-- Message format (single line, pipe-delimited, escaped):
--   WRLv1|<op>|<payload>
-- where <payload> for REQ is:
--   <fromKey>|<tierIds csv>|<note>[|<clientRequestId>]   (4th field optional; avoids duplicate IDs on bank)
-- and for ACK is:
--   <requestId>|<status>
-- and for ACK2 is:
--   <requestId>|<status>|<method>|<when>|<tierIds csv>|<gold>|<extraLives>|<bankerKey>|<itemsCompact>
--   itemsCompact = id*qty,id*qty,...  (may be empty if truncated for size)
--
-- Prefixes must be registered on every client that sends/receives.

local ADDON_NAME, ns = ...
local C = ns:NewModule("Comm")

local PROTO = "WRLv1"
local prefix = ns.commPrefix

-- Addon messages are short on Classic; keep ACK2 under this total size (prefix is separate).
local MAX_ACK2_BODY = 220
local MAX_SCOPED_BODY = 230
local opHandlers = {}

local function splitPayloadByPipe(payload)
    local parts = {}
    local pos = 1
    local len = #payload
    while pos <= len do
        local dash = payload:find("|", pos, true)
        if not dash then
            parts[#parts + 1] = payload:sub(pos)
            break
        end
        parts[#parts + 1] = payload:sub(pos, dash - 1)
        pos = dash + 1
    end
    return parts
end

function C:Init()
    if C2_ChatInfo and C2_ChatInfo.RegisterAddonMessagePrefix then
        C2_ChatInfo.RegisterAddonMessagePrefix(prefix)
    elseif C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(prefix)
    end

    ns:On("CHAT_MSG_ADDON", function(msgPrefix, text, channel, sender)
        if msgPrefix ~= prefix then return end
        self:Receive(text, sender, channel)
    end)
end

local function encode(op, payload)
    return table.concat({ PROTO, op, payload or "" }, "|")
end

local function sendAddon(channel, msg, target)
    if not channel or not msg then return false end
    if C2_ChatInfo and C2_ChatInfo.SendAddonMessage then
        return C2_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        return C_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
    elseif SendAddonMessage then
        SendAddonMessage(prefix, msg, channel, target)
        return true
    end
    return false
end

local function sendWhisper(target, msg)
    return sendAddon("WHISPER", msg, target)
end

local function decode(text)
    local proto, op, payload = text:match("^([^|]+)|([^|]+)|(.*)$")
    if proto ~= PROTO then return nil end
    return op, payload
end

function C:SendPresencePing(bankCharKey)
    local fromKey = ns:UnitKey()
    if not bankCharKey or not fromKey then return false end
    return sendWhisper(bankCharKey, encode("PING", fromKey))
end

function C:SendPresencePong(toKey)
    local fromKey = ns:UnitKey()
    if not toKey or not fromKey then return false end
    return sendWhisper(toKey, encode("PONG", fromKey))
end

function C:RegisterOpHandler(op, callback)
    if not op or type(callback) ~= "function" then return false end
    opHandlers[op] = callback
    return true
end

function C:SendScoped(op, payload, channel, target)
    if not op or not channel then return false end
    local msg = encode(op, payload or "")
    if #msg > MAX_SCOPED_BODY then
        if ns.Debug then ns:Debug("Comm: refusing oversized %s message (%d bytes)", tostring(op), #msg) end
        return false
    end
    return sendAddon(channel, msg, target)
end

local function isInRaidGroup()
    if IsInRaid then return IsInRaid() == true end
    return GetNumRaidMembers and (GetNumRaidMembers() or 0) > 0
end

local function isInPartyGroup()
    if IsInGroup then return IsInGroup() == true end
    if GetNumGroupMembers then return (GetNumGroupMembers() or 0) > 0 end
    return GetNumPartyMembers and (GetNumPartyMembers() or 0) > 0
end

function C:SendGroup(op, payload)
    if isInRaidGroup() then
        return self:SendScoped(op, payload, "RAID")
    end
    if isInPartyGroup() then
        return self:SendScoped(op, payload, "PARTY")
    end
    return false
end

function C:SendGuild(op, payload)
    if IsInGuild and not IsInGuild() then return false end
    return self:SendScoped(op, payload, "GUILD")
end

-- Send a request from a non-bank character to the bank character.
-- tierIds is an array of tier ids the requester wants fulfilled.
function C:SendRequest(bankCharKey, tierIds, note)
    if not bankCharKey then
        ns:Print("No bank character set. Use |cffffff00/wrl setbank Name-Realm|r first.")
        return
    end

    -- Bank key is "Name-Realm"; WHISPER target is just "Name-Realm" (Blizzard
    -- handles same-realm by dropping the realm; cross-realm requires the dash).
    local fromKey = ns:UnitKey()
    local filtered = {}
    for _, id in ipairs(tierIds or {}) do
        local tid = tonumber(id) or id
        if not ns.Database:HasClaimedTier(fromKey, tid) then
            filtered[#filtered + 1] = tid
        end
    end
    if #filtered == 0 then
        ns:Print("Nothing to send: those rewards are already claimed for this character.")
        return
    end
    tierIds = filtered

    local reqRowId = ns.Requests:EnqueueOutgoing(bankCharKey, tierIds, note)
    local payload = table.concat({
        fromKey,
        table.concat(tierIds, ","),
        note or "",
        reqRowId or "",
    }, "|")
    local msg = encode("REQ", payload)

    local ok = sendWhisper(bankCharKey, msg)

    ns:Print(ok and "Legacy reward request sent to %s." or "Legacy reward request queued (bank offline): %s", bankCharKey)
end

-- Acknowledge a request back to the requester.
function C:SendAck(toKey, requestId, status)
    local msg = encode("ACK", requestId .. "|" .. status)
    sendWhisper(toKey, msg)
end

local function itemsCompactForWire(fulfillment)
    local bits = {}
    for _, it in ipairs(fulfillment.items or {}) do
        bits[#bits + 1] = tostring(it.id) .. "*" .. tostring(it.qty or 1)
    end
    return table.concat(bits, ",")
end

function C:SendAck2(toKey, fulfillment)
    if not fulfillment or not fulfillment.requestId then return end
    local tierCsv = table.concat(fulfillment.tierIds or {}, ",")
    local itemsStr = itemsCompactForWire(fulfillment)
    local banker = fulfillment.banker or ""
    local base = table.concat({
        fulfillment.requestId,
        fulfillment.status or "fulfilled",
        fulfillment.method or "manual",
        tostring(fulfillment.when or time()),
        tierCsv,
        tostring(fulfillment.gold or 0),
        tostring(fulfillment.extraLives or 0),
        banker,
        itemsStr,
    }, "|")
    local msg = encode("ACK2", base)
    if #msg > MAX_ACK2_BODY then
        msg = encode("ACK2", table.concat({
            fulfillment.requestId,
            fulfillment.status or "fulfilled",
            fulfillment.method or "manual",
            tostring(fulfillment.when or time()),
            tierCsv,
            tostring(fulfillment.gold or 0),
            tostring(fulfillment.extraLives or 0),
            banker,
            "",
        }, "|"))
    end
    sendWhisper(toKey, msg)
end

function C:Receive(text, sender, channel)
    local op, payload = decode(text)
    if not op then return end
    if op == "PING" then
        if ns.Database and ns.Database.IsBankCharacter and ns.Database:IsBankCharacter() then
            self:SendPresencePong((payload and payload ~= "") and payload or sender)
        end
        return
    elseif op == "PONG" then
        if ns.BankStatus and ns.BankStatus.MarkSeen then
            ns.BankStatus:MarkSeen((payload and payload ~= "") and payload or sender)
        end
        return
    elseif opHandlers[op] then
        opHandlers[op](op, payload or "", sender, channel)
        return
    elseif op == "REQ" then
        -- Only the bank character processes incoming requests.
        if not ns.Database:IsBankCharacter() then return end
        local parts = splitPayloadByPipe(payload)
        local fromKey = parts[1]
        local tiersCsv = parts[2] or ""
        local note = parts[3]
        local clientReqId = parts[4]
        if not fromKey then return end
        if note == nil then note = "" end
        local tierIds = {}
        for id in tiersCsv:gmatch("([^,]+)") do
            local nId = tonumber(id); if nId then tierIds[#tierIds+1] = nId end
        end
        local rid = (clientReqId and clientReqId ~= "") and clientReqId or nil
        ns.Requests:OnIncoming(fromKey, tierIds, note ~= "" and note or nil, "whisper", rid)
    elseif op == "ACK" then
        local reqId, status = payload:match("^([^|]+)|(.*)$")
        if reqId and status then
            ns.Requests:OnAck(reqId, status)
        end
    elseif op == "ACK2" then
        local reqId, status, method, whenStr, tierCsv, goldStr, exStr, bankerKey, itemsStr =
            payload:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
        if not reqId or reqId == "" then return end
        local tierIds = {}
        for id in (tierCsv or ""):gmatch("([^,]+)") do
            local nId = tonumber(id); if nId then tierIds[#tierIds + 1] = nId end
        end
        local items = {}
        for chunk, qty in (itemsStr or ""):gmatch("(%d+)%*(%d+)") do
            items[#items + 1] = { id = tonumber(chunk), qty = tonumber(qty) or 1, note = nil }
        end
        ns.Requests:OnAck2(reqId, {
            status = status,
            method = method,
            when = tonumber(whenStr),
            tierIds = tierIds,
            gold = tonumber(goldStr) or 0,
            extraLives = tonumber(exStr) or 0,
            items = items,
            banker = (bankerKey and bankerKey ~= "") and bankerKey or nil,
            requester = ns:UnitKey(),
        })
    end
end
