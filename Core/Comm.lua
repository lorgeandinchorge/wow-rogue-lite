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

local function decode(text)
    local proto, op, payload = text:match("^([^|]+)|([^|]+)|(.*)$")
    if proto ~= PROTO then return nil end
    return op, payload
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

    local ok = false
    if C2_ChatInfo and C2_ChatInfo.SendAddonMessage then
        ok = C2_ChatInfo.SendAddonMessage(prefix, msg, "WHISPER", bankCharKey)
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        ok = C_ChatInfo.SendAddonMessage(prefix, msg, "WHISPER", bankCharKey)
    elseif SendAddonMessage then
        SendAddonMessage(prefix, msg, "WHISPER", bankCharKey)
        ok = true
    end

    ns:Print(ok and "Legacy reward request sent to %s." or "Legacy reward request queued (bank offline): %s", bankCharKey)
end

-- Acknowledge a request back to the requester.
function C:SendAck(toKey, requestId, status)
    local msg = encode("ACK", requestId .. "|" .. status)
    if C2_ChatInfo and C2_ChatInfo.SendAddonMessage then
        C2_ChatInfo.SendAddonMessage(prefix, msg, "WHISPER", toKey)
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(prefix, msg, "WHISPER", toKey)
    elseif SendAddonMessage then
        SendAddonMessage(prefix, msg, "WHISPER", toKey)
    end
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
    if C2_ChatInfo and C2_ChatInfo.SendAddonMessage then
        C2_ChatInfo.SendAddonMessage(prefix, msg, "WHISPER", toKey)
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(prefix, msg, "WHISPER", toKey)
    elseif SendAddonMessage then
        SendAddonMessage(prefix, msg, "WHISPER", toKey)
    end
end

function C:Receive(text, sender, channel)
    local op, payload = decode(text)
    if not op then return end
    if op == "REQ" then
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
