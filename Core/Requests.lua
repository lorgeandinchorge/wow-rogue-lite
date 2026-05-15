-- Core/Requests.lua
-- Request queue + fulfillment state machine.
--
-- A "request" is: <fromCharacter> wants <list of tier bundles> delivered.
-- The bank character sees these in the Rewards tab. Fulfillment has two paths:
--
--   Mail path:   bank opens mailbox → clicks "Send via Mail" on a request →
--                addon auto-fills recipient + inserts attached items + gold.
--                (Player still has to hit "Send" themselves.)
--
--   Trade path:  bank opens a trade window with the requester → clicks
--                "Load into Trade" → addon calls PickupContainerItem /
--                ClickTradeButton for each item, adds the gold.
--
-- We also support a mail-based REQUEST path for when addon whispers fail:
-- requester mails a letter with subject "WRL-REQ: <tierIds csv>" to the bank
-- with zero attachments. Bank's MAIL_INBOX_UPDATE handler parses it.

local ADDON_NAME, ns = ...
local R = ns:NewModule("Requests")

local REQ_STATUS = { PENDING = "pending", GATHERING = "gathering", FULFILLED = "fulfilled", CANCELLED = "cancelled" }
local MAIL_SUBJECT_PREFIX = "WRL-REQ:"

local function newId()
    return tostring(time()) .. "-" .. tostring(math.random(1000, 9999))
end

local function sortedRewardIds(tierIds)
    local ids = {}
    for _, id in ipairs(tierIds or {}) do
        local n = tonumber(id)
        if n then ids[#ids + 1] = n end
    end
    table.sort(ids)
    return ids
end

function R:MailFallbackSubject(tierIds)
    return MAIL_SUBJECT_PREFIX .. " " .. table.concat(sortedRewardIds(tierIds), ",")
end

function R:MailFallbackBody(bankKey, tierIds, note)
    local fromKey = ns.UnitKey and ns:UnitKey() or "Unknown"
    local lines = {
        "WoW Roguelite legacy reward request.",
        ("Requester: %s"):format(fromKey),
        ("Bank: %s"):format(bankKey or "Unknown"),
        ("Rewards: %s"):format(table.concat(sortedRewardIds(tierIds), ", ")),
    }
    if note and note ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = note
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Bank character: open /wrl or the mailbox to import this request."
    return table.concat(lines, "\n")
end

function R:Init()
    ns:On("MAIL_INBOX_UPDATE", function() self:ScanInbox() end)
    ns:On("MAIL_SHOW",         function() self:ScanInbox() end)
    ns:On("TRADE_SHOW",        function() self:OnTradeShow() end)
    ns:On("TRADE_CLOSED",      function() self._activeTrade = nil end)
    ns:On("BAG_UPDATE",        function() self:RefreshBagItemIndicators() end)
    ns:On("BAG_UPDATE_DELAYED",function() self:RefreshBagItemIndicators() end)
    ns:On("PLAYERBANKSLOTS_CHANGED", function() self:RefreshBagItemIndicators() end)
    self:InitBagItemIndicators()
end

-- ---- local queue on the requester side (for retry / history) --------------

function R:EnqueueOutgoing(bankKey, tierIds, note)
    WRL_CharDB = WRL_CharDB or {}
    WRL_CharDB.outgoing = WRL_CharDB.outgoing or {}
    local id = newId()
    table.insert(WRL_CharDB.outgoing, {
        id = id,
        when = time(),
        bank = bankKey,
        tierIds = tierIds,
        note = note,
        status = "sent",
        mailSubject = self:MailFallbackSubject(tierIds),
    })
    return id
end

function R:BeginMailFallback(bankKey, tierIds, note)
    if not bankKey or bankKey == "" then
        ns:Print("Set a bank first with |cffffff00/wrl setbank Name-Realm|r.")
        return false, "missing_bank"
    end
    if not tierIds or #tierIds == 0 then
        ns:Print("Choose at least one unclaimed legacy reward first.")
        return false, "empty_request"
    end
    if not MailFrame or not MailFrame:IsShown() then
        ns:Print("Open your mailbox first, then click Mail Fallback again.")
        return false, "mail_closed"
    end

    if MailFrameTab2 and MailFrameTab2.Click then MailFrameTab2:Click() end

    local recipient = bankKey:match("^([^-]+)") or bankKey
    if SendMailNameEditBox then SendMailNameEditBox:SetText(recipient) end
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(self:MailFallbackSubject(tierIds)) end
    if SendMailBodyEditBox then SendMailBodyEditBox:SetText(self:MailFallbackBody(bankKey, tierIds, note)) end

    ns:Print("|cffc0a060Mail fallback prepared.|r Send this letter with no attachments so the bank can import your request.")
    return true
end

-- ---- bank-side queue -----------------------------------------------------

function R:OnIncoming(fromKey, tierIds, note, via, requestId)
    -- Ignore self-requests.
    if fromKey == ns:UnitKey() then return end
    WRL_DB.requests = WRL_DB.requests or {}

    if requestId then
        for _, r in ipairs(WRL_DB.requests) do
            if r.id == requestId then return end
        end
    end

    -- Dedup: same sender + same tier set within last 5 min = merge.
    for _, r in ipairs(WRL_DB.requests) do
        if r.from == fromKey and r.status == REQ_STATUS.PENDING and (time() - r.when) < 300 then
            local same = #r.tierIds == #tierIds
            if same then
                for i = 1, #tierIds do if r.tierIds[i] ~= tierIds[i] then same = false; break end end
            end
            if same then return end
        end
    end

    local req = {
        id = requestId or newId(), from = fromKey, tierIds = tierIds or {}, note = note or "",
        when = time(), via = via or "unknown", status = REQ_STATUS.PENDING,
    }
    table.insert(WRL_DB.requests, req)
    ns:Print("|cffc0a060New legacy reward request|r from %s (rewards %s). Open /wrl to fulfill.",
        fromKey, table.concat(tierIds or {}, ","))
    if ns.MainFrame and ns.MainFrame.Notify then ns.MainFrame:Notify("Rewards") end
end

local function shallowCopyItems(items)
    local out = {}
    for i, it in ipairs(items or {}) do
        out[i] = { id = it.id, qty = it.qty, note = it.note }
    end
    return out
end

function R:OnAck(reqId, status)
    WRL_CharDB.outgoing = WRL_CharDB.outgoing or {}
    for _, r in ipairs(WRL_CharDB.outgoing) do
        if r.id == reqId then r.status = status; break end
    end
    if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
        ns.MainFrame:RefreshCurrentTab()
    end
end

-- Rich fulfillment sync for the requester (see Comm ACK2). Does not replace OnAck.
function R:OnAck2(reqId, fields)
    if not reqId or not fields then return end
    WRL_CharDB.outgoing = WRL_CharDB.outgoing or {}
    for _, r in ipairs(WRL_CharDB.outgoing) do
        if r.id == reqId then
            r.status = fields.status or r.status or REQ_STATUS.FULFILLED
            r.fulfillment = {
                when = fields.when or time(),
                banker = fields.banker,
                requester = fields.requester or ns:UnitKey(),
                requestId = reqId,
                tierIds = fields.tierIds or r.tierIds or {},
                items = shallowCopyItems(fields.items),
                gold = fields.gold or 0,
                extraLives = fields.extraLives or 0,
                method = fields.method or "manual",
                status = fields.status or REQ_STATUS.FULFILLED,
            }
            break
        end
    end
    if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
        ns.MainFrame:RefreshCurrentTab()
    end
end

function R:PendingRequests()
    local out = {}
    for _, r in ipairs(WRL_DB.requests or {}) do
        if r.status == REQ_STATUS.PENDING or r.status == REQ_STATUS.GATHERING then out[#out+1] = r end
    end
    return out
end

function R:NeededItemMap()
    if not (ns.Database and ns.Database.IsBankCharacter and ns.Database:IsBankCharacter()) then
        return {}
    end

    local map = {}
    for _, req in ipairs(self:PendingRequests()) do
        local bundle = self:Bundle(req)
        for _, it in ipairs(bundle.items or {}) do
            local itemId = tonumber(it.id)
            local qty = tonumber(it.qty) or 0
            if itemId and qty > 0 then
                local cur = map[itemId]
                if not cur then
                    cur = { qty = 0, requests = 0 }
                    map[itemId] = cur
                end
                cur.qty = cur.qty + qty
                cur.requests = cur.requests + 1
            end
        end
    end
    return map
end

function R:NeededItemInfo(itemId)
    itemId = tonumber(itemId)
    if not itemId then return nil end
    local map = self._neededItemMap
    if not map then
        map = self:NeededItemMap()
        self._neededItemMap = map
    end
    return map[itemId]
end

function R:TooltipNeededLine(itemId)
    local info = self:NeededItemInfo(itemId)
    if not info then return nil end
    return ("Needed for Roguelite request: %d"):format(info.qty or 0)
end

local function bagSlotItemId(bag, slot)
    if not GetContainerItemInfo then return nil end
    local _, _, _, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
    if id then return tonumber(id) end
    if link then return tonumber(link:match("item:(%d+)")) end
    return nil
end

function R:OnBagItemTooltip(tooltip, bag, slot)
    if not tooltip or not bag or not slot then return end
    if not (ns.Database and ns.Database.IsBankCharacter and ns.Database:IsBankCharacter()) then return end
    local itemId = bagSlotItemId(bag, slot)
    if not itemId then return end
    local line = self:TooltipNeededLine(itemId)
    if not line then return end
    tooltip:AddLine(line, 0.95, 0.85, 0.35)
    tooltip:Show()
end

function R:InitBagItemIndicators()
    if self._bagIndicatorInited then return end
    self._bagIndicatorInited = true

    if GameTooltip and hooksecurefunc then
        hooksecurefunc(GameTooltip, "SetBagItem", function(tooltip, bag, slot)
            self:OnBagItemTooltip(tooltip, bag, slot)
        end)
    end

    if hooksecurefunc and type(ContainerFrame_Update) == "function" then
        hooksecurefunc("ContainerFrame_Update", function(frame)
            self:UpdateContainerHighlights(frame)
        end)
    end
end

local function ensureButtonHighlight(button)
    if button._wrlNeedHighlight then return button._wrlNeedHighlight end
    local tex = button:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    tex:SetBlendMode("ADD")
    tex:SetAlpha(0)
    tex:SetPoint("CENTER", button, "CENTER", 0, 0)
    tex:SetWidth(42)
    tex:SetHeight(42)
    button._wrlNeedHighlight = tex
    return tex
end

function R:UpdateContainerHighlights(frame)
    if not frame then return end
    local frameName = frame.GetName and frame:GetName() or nil
    local bag = frame.GetID and frame:GetID() or nil
    local size = frame.size or 0
    if not frameName or not bag or size <= 0 then return end

    local shouldHighlight = (ns.Database and ns.Database.IsBankCharacter and ns.Database:IsBankCharacter())
    if shouldHighlight and not self._neededItemMap then
        self._neededItemMap = self:NeededItemMap()
    end

    for slot = 1, size do
        local button = _G[frameName .. "Item" .. slot]
        if button then
            local hl = ensureButtonHighlight(button)
            if shouldHighlight then
                local itemId = bagSlotItemId(bag, slot)
                local needed = itemId and self:NeededItemInfo(itemId)
                hl:SetAlpha(needed and 0.28 or 0)
            else
                hl:SetAlpha(0)
            end
        end
    end
end

function R:RefreshBagItemIndicators(verbose)
    self._neededItemMap = self:NeededItemMap()

    if type(ContainerFrame_UpdateAll) == "function" then
        ContainerFrame_UpdateAll()
    elseif type(NUM_CONTAINER_FRAMES) == "number" then
        for i = 1, NUM_CONTAINER_FRAMES do
            local frame = _G["ContainerFrame" .. i]
            if frame and frame:IsShown() then
                self:UpdateContainerHighlights(frame)
            end
        end
    end

    if verbose then
        local count = 0
        for _ in pairs(self._neededItemMap or {}) do count = count + 1 end
        ns:Print("Request bag indicators refreshed (%d needed item IDs).", count)
    end
end

local MAX_BANK_FULFILLED_SHOWN = 12

-- Bank Rewards tab: pending/gathering rows first, then recent fulfilled (audit).
function R:BankRequestRows()
    local pending = self:PendingRequests()
    local fulfilled = {}
    for _, r in ipairs(WRL_DB.requests or {}) do
        if r.status == REQ_STATUS.FULFILLED then fulfilled[#fulfilled + 1] = r end
    end
    table.sort(fulfilled, function(a, b)
        return (a.fulfilledAt or 0) > (b.fulfilledAt or 0)
    end)
    local rows = {}
    for _, r in ipairs(pending) do rows[#rows + 1] = r end
    local n = math.min(MAX_BANK_FULFILLED_SHOWN, #fulfilled)
    for i = 1, n do rows[#rows + 1] = fulfilled[i] end
    return rows
end

function R:SetStatus(reqId, status)
    for _, r in ipairs(WRL_DB.requests or {}) do
        if r.id == reqId then r.status = status; return r end
    end
end

-- Build the complete reward bundle for a request.
-- Delegates to ns.Rewards:BuildRewardForTierIds, which merges all bundles for
-- the requested tier IDs, applies settings-based modifiers (disableGold, etc.),
-- and applies boon/burden reward modifiers for the requester character.
function R:Bundle(req)
    return ns.Rewards:BuildRewardForTierIds(req.tierIds, req.from)
end

local function itemDisplayName(itemId, note)
    local name = (GetItemInfo and GetItemInfo(itemId)) or nil
    if type(name) == "string" and name ~= "" then
        return note and note ~= "" and (name .. " (" .. note .. ")") or name
    end
    local fallback = "item:" .. tostring(itemId)
    return note and note ~= "" and (fallback .. " (" .. note .. ")") or fallback
end

function R:CountItemInBags(itemId)
    local have = 0
    local Container = ns.Container
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots = Container and Container.GetNumSlots and Container:GetNumSlots(bag) or 0
        for slot = 1, slots do
            local info = Container and Container.GetItemInfo and Container:GetItemInfo(bag, slot)
            if info and info.itemID == itemId then
                have = have + (info.count or 1)
            end
        end
    end
    return have
end

function R:FulfillmentReadiness(req)
    local bundle = self:Bundle(req)
    local details = {}
    local missing = {}
    local allItemsAvailable = true

    for _, it in ipairs(bundle.items or {}) do
        local required = it.qty or 0
        local have = self:CountItemInBags(it.id)
        local miss = math.max(0, required - have)
        local line = {
            id = it.id,
            name = itemDisplayName(it.id, it.note),
            required = required,
            available = have,
            missing = miss,
            note = it.note,
        }
        details[#details + 1] = line
        if miss > 0 then
            allItemsAvailable = false
            missing[#missing + 1] = line
        end
    end

    local requiredGold = bundle.gold or 0
    local availableGold = GetMoney and (GetMoney() or 0) or 0
    local enoughGold = availableGold >= requiredGold
    local fulfillable = allItemsAvailable and enoughGold

    return {
        bundle = bundle,
        items = details,
        missingItems = missing,
        requiredGold = requiredGold,
        availableGold = availableGold,
        enoughGold = enoughGold,
        allItemsAvailable = allItemsAvailable,
        fulfillable = fulfillable,
    }
end

function R:PrintMissingForRequest(req, readiness)
    readiness = readiness or self:FulfillmentReadiness(req)
    local missingItems = readiness.missingItems or {}
    local requiredGold = readiness.requiredGold or 0
    local availableGold = readiness.availableGold or 0

    if #missingItems == 0 and availableGold >= requiredGold then
        ns:Print("|cff7ab27aAll requested items are available for %s.|r", req.from or "request")
        return
    end

    ns:Print("|cffb85c5cMissing requirements for %s:|r", req.from or "request")
    for _, it in ipairs(missingItems) do
        ns:Print("  - %s: need %d, have %d, missing %d", it.name, it.required, it.available, it.missing)
    end
    if availableGold < requiredGold then
        ns:Print("  - Gold: need %s, have %s, missing %s",
            ns.Tiers:FormatMoney(requiredGold),
            ns.Tiers:FormatMoney(availableGold),
            ns.Tiers:FormatMoney(requiredGold - availableGold))
    end
end

-- ---- mail inbox parsing --------------------------------------------------
-- We look for mails with subject matching "WRL-REQ: <csv tier ids>" and treat
-- them as incoming requests (belt-and-suspenders for the addon-whisper path).

function R:ScanInbox()
    if not ns.Database:IsBankCharacter() then return end
    local n = GetInboxNumItems and GetInboxNumItems() or 0
    for i = 1, n do
        local _, _, sender, subject = GetInboxHeaderInfo(i)
        if subject and subject:sub(1, #MAIL_SUBJECT_PREFIX) == MAIL_SUBJECT_PREFIX then
            local csv = subject:sub(#MAIL_SUBJECT_PREFIX + 1):gsub("^%s+", "")
            local tierIds = {}
            for id in csv:gmatch("([^,]+)") do
                local nId = tonumber(id); if nId then tierIds[#tierIds+1] = nId end
            end
            if sender and #tierIds > 0 then
                self:OnIncoming(sender, tierIds, "(from mail)", "mail")
            end
        end
    end
end

-- ---- fulfillment: mail ---------------------------------------------------
-- Prep the Send Mail UI with the recipient + gold + attached items already in
-- bag slots the player selected. We can't actually stuff items *into* mail
-- attachment slots from arbitrary bag positions automatically — BC only lets
-- you ClickSendMailItemButton(idx) to pick up what's on the cursor. So we
-- guide the player: we pre-fill the header, pre-fill gold, and pop a tooltip
-- listing exactly what items to click-drag into the attachment slots.

function R:BeginMailFulfillment(reqId)
    local req; for _, r in ipairs(WRL_DB.requests or {}) do if r.id == reqId then req = r; break end end
    if not req then return end
    if not MailFrame or not MailFrame:IsShown() then
        ns:Print("Open your mailbox first, then click Fulfill again.")
        return
    end

    -- Switch to the Send Mail tab if not already.
    if MailFrameTab2 and MailFrameTab2.Click then MailFrameTab2:Click() end

    local readiness = self:FulfillmentReadiness(req)
    local bundle = readiness.bundle
    -- Recipient — strip realm for same-realm mail since BC's SendMailNameEditBox
    -- doesn't accept "Name-Realm" in all clients.
    local recipient = req.from:match("^([^-]+)") or req.from
    if SendMailNameEditBox then SendMailNameEditBox:SetText(recipient) end
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText("Roguelite legacy rewards") end
    if SendMailBodyEditBox then
        SendMailBodyEditBox:SetText(
            ("Legacy rewards for your new run.\nRewards: %s\n\nGood luck.")
                :format(table.concat(req.tierIds, ", ")))
    end

    -- Gold (MoneyInputFrame API — values in copper).
    if bundle.gold > 0 and MoneyInputFrame_SetCopper and SendMailMoney then
        MoneyInputFrame_SetCopper(SendMailMoney, bundle.gold)
    end

    -- Ask the user to drag attachments. We flash a chat message list.
    ns:Print("|cffc0a060Fulfilling %s|r — drag these into the mail attachments:", req.from)
    self:PrintMissingForRequest(req, readiness)
    for _, it in ipairs(bundle.items) do
        ns:Print("  - %dx item:%d (%s)", it.qty, it.id, it.note or "")
    end
    if bundle.gold > 0 then
        ns:Print("  - %s (pre-filled in money field)", ns.Tiers:FormatMoney(bundle.gold))
    end
    if bundle.extraLives > 0 then
        ns:Print("  - |cffffd700+%d life|r for %s (applied when you mark fulfilled).",
                 bundle.extraLives, req.from)
    end

    req._fulfillmentMethod = "mail"
    self:SetStatus(reqId, REQ_STATUS.GATHERING)
end

-- ---- fulfillment: trade --------------------------------------------------
-- When a TRADE_SHOW fires with the requester as target, we remember the
-- matching request and provide a checklist. The player performs the trade
-- manually; the addon does not place items or gold into the trade window.

function R:OnTradeShow()
    if not ns.Database:IsBankCharacter() then return end
    local partner = UnitName("NPC") or (TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText())
    if not partner then return end
    -- Match partner to a pending request (match by character short name).
    local match
    for _, r in ipairs(self:PendingRequests()) do
        local short = r.from:match("^([^-]+)") or r.from
        if short:lower() == partner:lower() then match = r; break end
    end
    if not match then return end
    self._activeTrade = match
    ns:Print("|cffc0a060Trade opened with %s.|r Use the Rewards tab trade checklist, then trade manually.", partner)
end

-- Called by the Rewards tab's trade helper button.
function R:LoadActiveTrade()
    local req = self._activeTrade
    if not req then ns:Print("No matching trade window is open."); return end
    local readiness = self:FulfillmentReadiness(req)
    local bundle = readiness.bundle
    self:PrintMissingForRequest(req, readiness)

    -- Gold first — simple and doesn't eat a trade slot.
    if (bundle.gold or 0) > 0 then
        ns:Print("  - Trade manually: %s", ns.Tiers:FormatMoney(bundle.gold))
    end

    -- For each requested item, find the first stack in bags and place it.
    -- We stop at 6 (trade window has 6 trade slots + 1 "will not be traded").
    for _, it in ipairs(bundle.items) do
        ns:Print("  - Trade manually: %dx item:%d (%s)", it.qty or 1, it.id, it.note or "")
    end
    req._fulfillmentMethod = "trade"
    ns:Print("Use the checklist above to trade %s's legacy rewards, then mark fulfilled.", req.from)
end

-- Scan bags for an itemID; return bag,slot,count of first stack found.
function R:FindItemInBags(itemId)
    local Container = ns.Container
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots = Container and Container.GetNumSlots and Container:GetNumSlots(bag) or 0
        for slot = 1, slots do
            local info = Container and Container.GetItemInfo and Container:GetItemInfo(bag, slot)
            if info and info.itemID == itemId then return bag, slot, info.count or 1 end
        end
    end
end

function R:MarkFulfilled(reqId)
    local req
    for _, r in ipairs(WRL_DB.requests or {}) do
        if r.id == reqId then req = r; break end
    end
    if not req then return end
    if req.status == REQ_STATUS.FULFILLED then return end

    local now = time()
    local method = req._fulfillmentMethod or "manual"
    local bundle = self:Bundle(req)
    local bankerKey = ns:UnitKey()

    req.status       = REQ_STATUS.FULFILLED
    req.fulfilledAt  = now
    req.fulfilledBy  = bankerKey
    req.method       = method
    req._fulfillmentMethod = nil

    local fulfillment = {
        when        = now,
        banker      = bankerKey,
        requester   = req.from,
        requestId   = req.id,
        tierIds     = req.tierIds or {},
        items       = shallowCopyItems(bundle.items),
        gold        = bundle.gold or 0,
        extraLives  = bundle.extraLives or 0,
        method      = method,
        status      = REQ_STATUS.FULFILLED,
    }
    req.fulfillment = fulfillment
    ns.Database:AppendFulfillmentReceipt(fulfillment)
    local requesterRec = ns.Database:GetCharacter(req.from)
    if requesterRec and (fulfillment.extraLives or 0) > 0 then
        requesterRec.livesRemaining = (requesterRec.livesRemaining or 1) + fulfillment.extraLives
    end

    -- Record claims on the requester's character record if it exists in this
    -- account's WRL_DB.  If not (off-account request), store receipts on the
    -- request itself so the data is preserved for future reference.
    local claimedOnRec = false
    for _, tierId in ipairs(req.tierIds or {}) do
        if requesterRec then
            ns.Database:MarkTierClaimed(req.from, tierId, {
                when        = now,
                requestId   = req.id,
                fulfilledBy = bankerKey,
                method      = method,
            })
            claimedOnRec = true
        end
    end

    -- Fallback: store receipt data on the request for off-account chars.
    if not claimedOnRec then
        req.storedClaimReceipts = req.storedClaimReceipts or {}
        for _, tierId in ipairs(req.tierIds or {}) do
            if not req.storedClaimReceipts[tierId] then
                req.storedClaimReceipts[tierId] = {
                    when        = now,
                    requestId   = req.id,
                    fulfilledBy = bankerKey,
                    method      = method,
                }
            end
        end
    end

    -- Acknowledge: legacy ACK for older clients, ACK2 with receipt summary for newer.
    ns.Comm:SendAck(req.from, req.id, REQ_STATUS.FULFILLED)
    ns.Comm:SendAck2(req.from, fulfillment)

    ns:Print("|cffc0a060Fulfilled|r %s's request (method: %s).", req.from, method)
    if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
        ns.MainFrame:RefreshCurrentTab()
    end
    self:RefreshBagItemIndicators()
end
