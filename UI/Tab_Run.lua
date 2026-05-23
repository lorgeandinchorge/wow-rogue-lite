-- UI/Tab_Run.lua
-- Current run overview for the logged-in character with nil-safe fallbacks.

local ADDON_NAME, ns = ...
local Tab = ns:NewModule("Tab_Run")
local BANK_DASHBOARD_WIDTH = 760
local BANK_SCROLLBAR_GUTTER = 38
local BANK_SECTION_WIDTH = BANK_DASHBOARD_WIDTH - BANK_SCROLLBAR_GUTTER
local BANK_TOP_SECTION_WIDTH = math.floor((BANK_SECTION_WIDTH - 10) / 2)
local BANK_ROW_ACTION_GAP = 10
local BANK_ROW_TARGET_WIDTH = BANK_SECTION_WIDTH - 196
local BANK_CLEAR_BUTTON_RIGHT_INSET = -(BANK_SCROLLBAR_GUTTER + 8)
local BANK_LEDGER_CONTENT_WIDTH = BANK_SECTION_WIDTH - BANK_SCROLLBAR_GUTTER - 10
local CHARACTER_RIGHT_WIDTH = 420

local function shortName(full)
    return (full and full:match("^([^-]+)")) or full or "Unknown"
end

local function withRealm(key)
    local n, r = key and key:match("^([^%-]+)%-(.+)$")
    return n or key or "Unknown", r or (GetRealmName and GetRealmName() or "Unknown")
end

local function fmtWhen(ts)
    if not ts then return "Unknown" end
    if date then return date("%m-%d %H:%M", ts) end
    return tostring(ts)
end

local function classLabel(classToken)
    if not classToken or classToken == "" then return "Unknown" end
    return classToken:sub(1, 1) .. classToken:sub(2):lower()
end

local function stateLabel(state)
    if state == "fresh" then return "|cffc0a060fresh|r" end
    if state == "active" then return "|cff7ab27aactive|r" end
    if state == "dead_pending_contribution" then return "|cffffff00retired - contribution pending|r" end
    if state == "retired" then return "|cffb85c5cretired|r" end
    if state == "archived" then return "|cffb07828archived|r" end
    return "|cff9a948aunknown|r"
end

local function isRequestPending(status)
    return status == "sent" or status == "pending" or status == "gathering"
end

local function newestPendingOutgoing()
    local outgoing = WRL_CharDB and WRL_CharDB.outgoing
    if type(outgoing) ~= "table" then return nil end
    local best = nil
    for _, req in ipairs(outgoing) do
        if req and isRequestPending(req.status) then
            if (not best) or ((req.when or 0) > (best.when or 0)) then
                best = req
            end
        end
    end
    return best
end

local function requestTierLabel(req)
    local tierIds = req and req.tierIds
    if type(tierIds) ~= "table" or #tierIds == 0 then
        return "unknown rewards"
    end
    return table.concat(tierIds, ", ")
end

local function rulesSummary(maxRules)
    local defs = ns.Rules and ns.Rules.Definitions and ns.Rules:Definitions() or {}
    local enabled = {}
    for _, def in ipairs(defs) do
        if def and def.id and ns.Rules:IsEnabled(def.id) then
            enabled[#enabled + 1] = def.name or def.id
        end
    end
    table.sort(enabled)
    local out = {}
    if #enabled == 0 then
        out[1] = "Enabled rules: none"
        return out
    end
    out[1] = ("Enabled rules: %d"):format(#enabled)
    local n = math.min(maxRules or 3, #enabled)
    for i = 1, n do out[#out + 1] = " - " .. enabled[i] end
    if #enabled > n then out[#out + 1] = (" - ... and %d more"):format(#enabled - n) end
    return out
end

local function claimedSummary(rec, maxShown)
    local rows = {}
    local claims = rec and rec.claimedTiers
    if type(claims) ~= "table" or not next(claims) then
        rows[1] = "Claimed rewards: none"
        return rows
    end

    local entries = {}
    for tierId, info in pairs(claims) do
        entries[#entries + 1] = { tierId = tierId, info = info or {} }
    end
    table.sort(entries, function(a, b)
        return (a.info.when or 0) > (b.info.when or 0)
    end)

    rows[1] = ("Claimed rewards: %d"):format(#entries)
    local limit = math.min(maxShown or 4, #entries)
    for i = 1, limit do
        local e = entries[i]
        rows[#rows + 1] = (" - Tier %s (%s)"):format(tostring(e.tierId), fmtWhen(e.info.when))
    end
    if #entries > limit then
        rows[#rows + 1] = (" - ... and %d more"):format(#entries - limit)
    end
    return rows
end

local function activeBoonsSummary(rec)
    local rows = {}
    local boons = rec and rec.boons
    if not boons or not next(boons) then
        rows[1] = "Active boons: none"
        return rows
    end
    local names = {}
    for id in pairs(boons) do
        local def = ns.Boons and ns.Boons:GetBoonDef(id)
        names[#names + 1] = def and def.name or id
    end
    table.sort(names)
    rows[1] = ("Active boons: %d"):format(#names)
    for _, n in ipairs(names) do rows[#rows + 1] = " - " .. n end
    return rows
end

local function activeBurdensSummary(rec)
    local rows = {}
    local burdens = rec and rec.burdens
    if not burdens or not next(burdens) then
        rows[1] = "Active burdens: none"
        return rows
    end
    local names = {}
    for id in pairs(burdens) do
        local def = ns.Boons and ns.Boons:GetBurdenDef(id)
        names[#names + 1] = def and def.name or id
    end
    table.sort(names)
    rows[1] = ("Active burdens: %d"):format(#names)
    for _, n in ipairs(names) do rows[#rows + 1] = " - " .. n end
    return rows
end

local function bagEstimate()
    local money = GetMoney and (GetMoney() or 0) or 0
    local bagValue = 0
    if ns.Vendor and ns.Vendor.BagsSnapshot then
        local ok, val = pcall(function() return select(1, ns.Vendor:BagsSnapshot()) end)
        if ok and type(val) == "number" then
            bagValue = math.max(0, math.floor(val))
        end
    end
    return money, bagValue, money + bagValue
end

local function recentReceipts(charKey, maxShown)
    local rows = {}
    local list = (ns.Contributions and ns.Contributions.ForCharacter and ns.Contributions:ForCharacter(charKey)) or {}
    if #list == 0 then
        rows[1] = "Recent contribution receipts: none"
        return rows
    end
    table.sort(list, function(a, b) return (a.when or 0) > (b.when or 0) end)
    rows[1] = ("Recent contribution receipts: %d total"):format(#list)
    local limit = math.min(maxShown or 4, #list)
    for i = 1, limit do
        local r = list[i]
        rows[#rows + 1] = (" - %s | %s | %s"):format(
            fmtWhen(r.when),
            ns.Tiers and ns.Tiers.FormatMoney and ns.Tiers:FormatMoney(r.amount or 0) or tostring(r.amount or 0),
            r.confidence or "unknown")
    end
    return rows
end

local function recentRuleWarnings(charKey, maxShown)
    local rows = {}
    local log = (ns.Rules and ns.Rules.GetLog and ns.Rules:GetLog(charKey)) or {}
    local filtered = {}
    for _, e in ipairs(log) do
        if e and (e.result == "tainted" or e.result == "warned" or e.result == "blocked") then
            filtered[#filtered + 1] = e
        end
    end
    if #filtered == 0 then
        rows[1] = "Recent taint/warning entries: none"
        return rows
    end
    table.sort(filtered, function(a, b) return (a.when or 0) > (b.when or 0) end)
    rows[1] = ("Recent taint/warning entries: %d"):format(#filtered)
    local limit = math.min(maxShown or 4, #filtered)
    for i = 1, limit do
        local e = filtered[i]
        local detail = e.detail or ""
        if #detail > 42 then detail = detail:sub(1, 39) .. "..." end
        rows[#rows + 1] = (" - %s [%s] %s"):format(fmtWhen(e.when), e.result or "?", detail)
    end
    return rows
end

local function recentDeaths(rec, maxShown)
    local rows = {}
    local log = rec and rec.deathLog or nil
    if type(log) ~= "table" or #log == 0 then
        rows[1] = "Death history: none"
        return rows
    end
    rows[1] = ("Death history: %d"):format(#log)
    local startIdx = math.max(1, #log - (maxShown or 4) + 1)
    for i = #log, startIdx, -1 do
        local d = log[i]
        local zone = d.zone or "Unknown zone"
        local level = d.level or "?"
        rows[#rows + 1] = (" - %s | Lv%s | %s"):format(fmtWhen(d.when), tostring(level), zone)
    end
    return rows
end

local function achievementSummaryLine()
    if not ns.Achievements or not ns.Achievements.EarnedCount then
        return "Achievements: unavailable"
    end

    local earnedCount = ns.Achievements:EarnedCount()
    return ("Achievements: %d earned - open Achievements"):format(earnedCount)
end

local function requestRows()
    if ns.Requests and ns.Requests.BankRequestRows then
        return ns.Requests:BankRequestRows() or {}
    end
    return WRL_DB and WRL_DB.requests or {}
end

local function isActionableRequest(req)
    return req and (req.status == "pending" or req.status == "gathering")
end

local function actionableBankRequests()
    local rows = {}
    for _, req in ipairs(requestRows()) do
        if isActionableRequest(req) then
            rows[#rows + 1] = req
        end
    end
    return rows
end

function Tab:_ActiveBankRequest()
    local rows = actionableBankRequests()
    if #rows == 0 then
        self.bankRequestIndex = 1
        return nil
    end
    self.bankRequestIndex = math.max(1, math.min(self.bankRequestIndex or 1, #rows))
    return rows[self.bankRequestIndex]
end

function Tab:_AdvanceBankRequest()
    local rows = actionableBankRequests()
    if #rows == 0 then
        self.bankRequestIndex = 1
        return nil
    end
    self.bankRequestIndex = ((self.bankRequestIndex or 1) % #rows) + 1
    return rows[self.bankRequestIndex]
end

function Tab:_BankDeskRows()
    return actionableBankRequests()
end

function Tab:_SelectBankRequest(index)
    local rows = self:_BankDeskRows()
    index = math.floor(tonumber(index) or 0)
    if index < 1 or index > #rows then
        return self:_ActiveBankRequest()
    end
    self.bankRequestIndex = index
    return rows[index]
end

function Tab:_ResaleRows()
    return ns.BankResale and ns.BankResale.InventoryRows and ns.BankResale:InventoryRows() or {}
end

function Tab:_ActiveResaleRow(rows)
    rows = rows or self:_ResaleRows()
    if #rows == 0 then
        self.bankResaleIndex = 1
        return nil
    end
    self.bankResaleIndex = math.max(1, math.min(self.bankResaleIndex or 1, #rows))
    return rows[self.bankResaleIndex]
end

function Tab:_AdvanceResaleRow()
    local rows = self:_ResaleRows()
    if #rows == 0 then
        self.bankResaleIndex = 1
        return nil
    end
    self.bankResaleIndex = ((self.bankResaleIndex or 1) % #rows) + 1
    return rows[self.bankResaleIndex]
end

function Tab:_SelectResaleRow(index)
    local rows = self:_ResaleRows()
    index = math.floor(tonumber(index) or 0)
    if index < 1 or index > #rows then
        return self:_ActiveResaleRow(rows)
    end
    self.bankResaleIndex = index
    local row = rows[index]
    self.pendingResaleOrder = self:_BuildResaleOrder(row)
    return self.pendingResaleOrder
end

function Tab:_DefaultResaleBuyer()
    local draft = ns.BankResale and ns.BankResale.pendingCOD
    if draft and draft.buyer then return draft.buyer end
    if self.pendingResaleOrder and self.pendingResaleOrder.buyer then return self.pendingResaleOrder.buyer end
    local req = self:_ActiveBankRequest()
    if req and req.from then return req.from end
    if ns.BankResale and ns.BankResale.SimulatedBuyer then
        local buyer = ns.BankResale:SimulatedBuyer()
        if buyer and buyer ~= "" then return buyer end
    end
    return nil
end

function Tab:_RequestItemForResaleRow(row)
    if not row then return nil, nil end
    local req = self:_ActiveBankRequest()
    if not req or not ns.Requests or not ns.Requests.FulfillmentReadiness then return req, nil end
    local ok, ready = pcall(function()
        return ns.Requests:FulfillmentReadiness(req)
    end)
    if not ok or not ready then return req, nil end
    for _, item in ipairs(ready.items or {}) do
        local itemId = tonumber(item.id or item.itemId)
        if itemId and itemId == tonumber(row.itemId) then
            return req, item
        end
    end
    return req, nil
end

function Tab:_BuildResaleOrder(row)
    if not row then return nil end
    local req, requestItem = self:_RequestItemForResaleRow(row)
    local requestedQty = requestItem and tonumber(requestItem.required or requestItem.qty)
    local qty = math.max(1, math.floor(requestedQty or tonumber(row.count) or tonumber(row.qty) or 1))
    return {
        itemId = row.itemId,
        itemName = row.name,
        name = row.name,
        qty = qty,
        buyer = (req and req.from) or self:_DefaultResaleBuyer(),
        priceEach = row.priceEach,
        totalCopper = (row.priceEach or 0) * qty,
    }
end

function Tab:_ResaleOrderForRow(row)
    if not row then return nil end
    local fresh = self:_BuildResaleOrder(row)
    local pending = self.pendingResaleOrder
    if pending and pending.itemId == row.itemId then
        pending.buyer = (fresh and fresh.buyer) or pending.buyer
        pending.qty = (fresh and fresh.qty) or pending.qty
        pending.name = pending.name or (fresh and fresh.name)
        pending.itemName = pending.itemName or (fresh and fresh.itemName)
        pending.priceEach = pending.priceEach or (fresh and fresh.priceEach) or row.priceEach
        pending.totalCopper = (pending.priceEach or 0) * math.max(1, math.floor(tonumber(pending.qty) or 1))
        return pending
    end
    return fresh
end

function Tab:_RecordResaleRow(row)
    local draft = ns.BankResale and ns.BankResale.pendingCOD
    local sale = draft or self:_ResaleOrderForRow(row)
    if sale and ns.BankResale and ns.BankResale.RecordSale then
        local receipt = ns.BankResale:RecordSale(sale.itemId, math.max(1, math.floor(tonumber(sale.qty) or 1)), sale.buyer)
        if receipt then
            ns:Print("Recorded resale: %dx %s for %s.",
                receipt.qty or sale.qty or 1,
                receipt.itemName or sale.name or ("item:" .. tostring(sale.itemId)),
                ns.Tiers:FormatMoney(receipt.totalCopper or sale.totalCopper or 0))
        end
        self.pendingResaleOrder = nil
        self:Refresh()
    else
        ns:Print("No resale catalog item is available to record.")
    end
end

function Tab:_CancelResaleRow(row)
    local pending = ns.BankResale and ns.BankResale.pendingCOD
    if row and row.simulated and ns.BankResale and ns.BankResale.RemoveSimulatedStock then
        ns.BankResale:RemoveSimulatedStock(row.itemId)
        if ns.BankResale then ns.BankResale.pendingCOD = nil end
        self.pendingResaleOrder = nil
        ns:Print("Removed simulated resale stock line.")
    elseif pending and (not row or pending.itemId == row.itemId) then
        ns.BankResale.pendingCOD = nil
        self.pendingResaleOrder = nil
        ns:Print("Canceled pending resale COD mail.")
    elseif self.pendingResaleOrder and (not row or self.pendingResaleOrder.itemId == row.itemId) then
        self.pendingResaleOrder = nil
        ns:Print("Canceled selected resale order.")
    else
        ns:Print("No pending resale COD mail to cancel.")
    end
    self:Refresh()
end

function Tab:_ClearResaleDesk()
    if ns.BankResale then
        ns.BankResale.pendingCOD = nil
        if ns.BankResale.ClearSimulatedStock then
            ns.BankResale:ClearSimulatedStock()
        end
    end
    self.pendingResaleOrder = nil
    self.bankResaleIndex = 1
    ns:Print("Cleared simulated resale desk stock.")
    self:Refresh()
end

function Tab:ConfirmClearResaleDesk()
    if not StaticPopupDialogs or not StaticPopup_Show then
        self:_ClearResaleDesk()
        return
    end
    StaticPopupDialogs["WRL_CLEAR_RESALE_DESK"] = StaticPopupDialogs["WRL_CLEAR_RESALE_DESK"] or {
        text = "Clear the Resale Desk? Pending simulated stock and COD drafts will be removed.",
        button1 = "Clear",
        button2 = "Cancel",
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function(_, owner)
            if owner and owner._ClearResaleDesk then owner:_ClearResaleDesk() end
        end,
    }
    StaticPopup_Show("WRL_CLEAR_RESALE_DESK", nil, nil, self)
end

function Tab:_ClearRecentLedger()
    if ns.Database and ns.Database.ClearRecentBankLedger then
        ns.Database:ClearRecentBankLedger()
    end
    ns:Print("Recent ledger hidden. New bank activity will appear here.")
    self:Refresh()
end

function Tab:ConfirmClearRecentLedger()
    if not StaticPopupDialogs or not StaticPopup_Show then
        self:_ClearRecentLedger()
        return
    end
    StaticPopupDialogs["WRL_CLEAR_RECENT_LEDGER"] = StaticPopupDialogs["WRL_CLEAR_RECENT_LEDGER"] or {
        text = "Clear the visible Recent Ledger? Receipts and contribution totals will be kept.",
        button1 = "Clear",
        button2 = "Cancel",
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function(_, owner)
            if owner and owner._ClearRecentLedger then owner:_ClearRecentLedger() end
        end,
    }
    StaticPopup_Show("WRL_CLEAR_RECENT_LEDGER", nil, nil, self)
end

function Tab:_FirstActionableBankRequest(unassignedOnly)
    for _, req in ipairs(actionableBankRequests()) do
        if isActionableRequest(req) and ((not unassignedOnly) or not req.accountId) then
            return req
        end
    end
    return nil
end

local function requestSummaryLine(req)
    if not req then return "No pending bank requests. Suspiciously peaceful." end
    local status = req.status or "pending"
    local account = req.accountId and ns.Database and ns.Database.AccountLabel and ns.Database:AccountLabel(req.accountId) or "Unassigned"
    return ("%s from %s [%s] - %s"):format(status, shortName(req.from), account, requestTierLabel(req))
end

local function readinessSummary(req)
    if not req or not ns.Requests or not ns.Requests.FulfillmentReadiness then
        return "Mailbox work: nothing ready for the clerk."
    end
    local ok, ready = pcall(function() return ns.Requests:FulfillmentReadiness(req) end)
    if not ok or not ready then return "Mailbox work: readiness unavailable." end
    local gold = ready.requiredGold or 0
    local missingGold = math.max(0, gold - (ready.availableGold or 0))
    local missingItems = #(ready.missingItems or {})
    if ready.fulfillable then
        return ("Ready to prepare mail: %s plus listed supplies. The vault has stopped sighing."):format(ns.Tiers:FormatMoney(gold))
    end
    return ("Missing for next mail: %d item line(s), %s. The ledger has concerns."):format(missingItems, ns.Tiers:FormatMoney(missingGold))
end

local function bankDeskItemLine(item)
    local name = item and item.name or ("item:" .. tostring(item and item.id or "?"))
    local required = item and item.required or 0
    local available = item and item.available or 0
    local missing = item and item.missing or 0
    if missing > 0 then
        return ("Item: %s - available %d / requested %d / missing %d"):format(name, available, required, missing)
    end
    return ("Item: %s - available %d / requested %d / ready"):format(name, available, required)
end

local function bankDeskGoldLine(ready)
    local requiredGold = ready and ready.requiredGold or 0
    local availableGold = ready and ready.availableGold or 0
    local missingGold = math.max(0, requiredGold - availableGold)
    local state = missingGold > 0 and ("missing " .. ns.Tiers:FormatMoney(missingGold)) or "ready"
    return ("Gold: available %s / requested %s / %s"):format(
        ns.Tiers:FormatMoney(availableGold),
        ns.Tiers:FormatMoney(requiredGold),
        state)
end

local function appendActiveRequestLines(lines, req)
    if not req then
        lines[#lines + 1] = "No pending bank requests. Suspiciously peaceful."
        lines[#lines + 1] = "Mailbox work: nothing ready for the clerk."
        return
    end

    local account = req.accountId and ns.Database and ns.Database.AccountLabel and ns.Database:AccountLabel(req.accountId) or "Unassigned"
    lines[#lines + 1] = ("Active request: %s [%s]"):format(req.from or "Unknown", account)
    lines[#lines + 1] = ("Rewards: %s"):format(requestTierLabel(req))

    local ok, ready = pcall(function()
        return ns.Requests and ns.Requests.FulfillmentReadiness and ns.Requests:FulfillmentReadiness(req) or nil
    end)
    if not ok or not ready then
        lines[#lines + 1] = "Readiness: unavailable. The paperwork is staring back."
        return
    end

    local requiredGold = ready.requiredGold or 0
    local availableGold = ready.availableGold or 0
    local missingGold = math.max(0, requiredGold - availableGold)
    local missingItems = ready.missingItems or {}
    if ready.fulfillable then
        lines[#lines + 1] = ("Readiness: ready for mail - %s gold, 0 item line(s) missing."):format(ns.Tiers:FormatMoney(requiredGold))
    else
        lines[#lines + 1] = ("Readiness: missing %d item line(s), %s gold."):format(#missingItems, ns.Tiers:FormatMoney(missingGold))
    end

    local items = ready.items or {}
    local shownItems = math.min(4, #items)
    for i = 1, shownItems do
        lines[#lines + 1] = bankDeskItemLine(items[i])
    end
    if #items == 0 then
        lines[#lines + 1] = "Item: no item stacks requested."
    elseif #items > shownItems then
        lines[#lines + 1] = ("Item: ... and %d more item line(s)"):format(#items - shownItems)
    end
    lines[#lines + 1] = bankDeskGoldLine(ready)
end

local function requestReadyLabel(req)
    if not req or not ns.Requests or not ns.Requests.FulfillmentReadiness then
        return "unknown", "?", "?"
    end
    local ok, ready = pcall(function()
        return ns.Requests:FulfillmentReadiness(req)
    end)
    if not ok or not ready then return "unknown", "?", "?" end
    local missingGold = math.max(0, (ready.requiredGold or 0) - (ready.availableGold or 0))
    local missingItems = #(ready.missingItems or {})
    local state = ready.fulfillable and "ready" or "missing"
    return state, ns.Tiers:FormatMoney(missingGold), tostring(missingItems)
end

local function appendBankDeskTable(lines, maxRows, owner)
    local rows = owner and owner._BankDeskRows and owner:_BankDeskRows() or actionableBankRequests()
    if #rows == 0 then
        lines[#lines + 1] = "No pending bank requests. Suspiciously peaceful."
        lines[#lines + 1] = "Mailbox work: nothing ready for the clerk."
        return
    end

    lines[#lines + 1] = string.format("%-18s %-14s %-16s %-8s %10s %5s", "Who", "Account", "Rewards", "Ready", "Gold", "Items")
    local limit = math.min(maxRows or 8, #rows)
    for i = 1, limit do
        local req = rows[i]
        local who = req.from or "Unknown"
        local account = req.accountId and ns.Database and ns.Database.AccountLabel and ns.Database:AccountLabel(req.accountId) or "Unassigned"
        local rewards = requestTierLabel(req)
        local ready, gold, items = requestReadyLabel(req)
        if #who > 18 then who = who:sub(1, 15) .. "..." end
        if #account > 14 then account = account:sub(1, 11) .. "..." end
        if #rewards > 16 then rewards = rewards:sub(1, 13) .. "..." end
        lines[#lines + 1] = string.format("%-18s %-14s %-16s %-8s %10s %5s",
            who,
            account,
            rewards,
            ready,
            gold,
            items)
    end
    if #rows > limit then
        lines[#lines + 1] = ("... and %d more request(s)"):format(#rows - limit)
    end
end

local function appendContributionBoard(lines, maxAccounts, maxCharacters)
    lines[#lines + 1] = "|cffc0a060Contribution Board|r"
    local rows = ns.Database and ns.Database.CharacterContributionRows and ns.Database:CharacterContributionRows() or {}
    if #rows == 0 then
        lines[#lines + 1] = "No account contributions recorded yet. The vault remains emotionally available."
        return
    end
    lines[#lines + 1] = string.format("%-3s %-14s | %1s | %2s | %8s | %5s", "#", "Character", "G", "Lv", "Total", "Share")
    for i = 1, math.min(maxCharacters or maxAccounts or 5, #rows) do
        local row = rows[i]
        local character = row.characterKey or "Unknown"
        if #character > 14 then character = character:sub(1, 11) .. "..." end
        lines[#lines + 1] = string.format("%-3s %-14s | %1s | %2s | %8s | %5.1f%%",
            tostring(i) .. ".",
            character,
            tostring(row.generation or 1),
            tostring(row.level or "?"),
            ns.Tiers:FormatMoney(row.total or 0),
            row.percent or 0)
    end
end

local function appendResaleDesk(lines, maxRows, owner)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cffc0a060Resale Desk|r"
    local rows = ns.BankResale and ns.BankResale.InventoryRows and ns.BankResale:InventoryRows() or {}
    if #rows == 0 then
        lines[#lines + 1] = "No resale catalog goods found. The shelves are judging everyone equally."
        return
    end
    local resaleTableHeader = string.format("%-20s %-18s %3s %3s %8s %8s", "Item", "Who", "Req", "Own", "Each", "Total")
    lines[#lines + 1] = resaleTableHeader
    local limit = math.min(maxRows or 5, #rows)
    for i = 1, limit do
        local row = rows[i]
        local order = owner and owner._BuildResaleOrder and owner:_BuildResaleOrder(row) or nil
        local name = row.name or ("item:" .. tostring(row.itemId or "?"))
        local buyer = (order and order.buyer) or "Unknown"
        if #name > 20 then name = name:sub(1, 17) .. "..." end
        if #buyer > 18 then buyer = buyer:sub(1, 15) .. "..." end
        lines[#lines + 1] = string.format("%-20s %-18s %3s %3d %8s %8s",
            name,
            buyer,
            tostring(order and order.qty or row.count or 0),
            row.count or 0,
            ns.Tiers:FormatMoney(row.priceEach or 0),
            ns.Tiers:FormatMoney((order and order.totalCopper) or row.totalCopper or 0))
    end
    if #rows > limit then
        lines[#lines + 1] = ("... and %d more resale item(s)"):format(#rows - limit)
    end
end

local function appendRecentLedger(lines, maxRows)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cffc0a060Recent ledger|r"
    local rows = ns.Database and ns.Database.RecentBankLedgerRows and ns.Database:RecentBankLedgerRows(maxRows or 6) or {}
    if #rows == 0 then
        lines[#lines + 1] = "No recent ledger activity. The ink is getting ideas."
        return
    end
    for _, row in ipairs(rows) do
        if row.kind == "fulfillment" then
            lines[#lines + 1] = (" - %s fulfilled for %s (%s, %s)"):format(
                fmtWhen(row.when),
                row.characterKey or "Unknown",
                row.accountLabel or "Unassigned",
                row.method or "manual")
        elseif row.kind == "resale" then
            lines[#lines + 1] = (" - %s resale to %s: %dx %s for %s"):format(
                fmtWhen(row.when),
                row.characterKey or "Unknown",
                row.qty or 0,
                row.itemName or "catalog item",
                ns.Tiers:FormatMoney(row.amount or 0))
        else
            lines[#lines + 1] = (" - %s contribution from %s (%s): %s"):format(
                fmtWhen(row.when),
                row.characterKey or "Unknown",
                row.accountLabel or "Unassigned",
                ns.Tiers:FormatMoney(row.amount or 0))
        end
    end
end

local function writeLines(target, lines)
    for i = 1, #target do
        local fs = target[i]
        local txt = lines and lines[i]
        if txt and txt ~= "" then
            fs:SetText(txt)
            fs:Show()
        else
            fs:Hide()
        end
    end
end

local function hideLines(lines)
    for _, fs in ipairs(lines or {}) do
        fs:Hide()
    end
end

local function splitBankSections(lines)
    local desk = {}
    local contributions = {}
    local resale = {}
    local ledger = {}
    local target = desk
    for i, line in ipairs(lines or {}) do
        if i == 1 then
            -- The framed section title owns this heading.
        elseif line == "|cffc0a060Contribution Board|r" then
            target = contributions
        elseif line == "|cffc0a060Resale Desk|r" then
            target = resale
        elseif line == "" then
            if target == contributions then
                target = resale
            else
                target = ledger
            end
        elseif line == "|cffc0a060Recent ledger|r" then
            target = ledger
        else
            target[#target + 1] = line
        end
    end
    return desk, contributions, resale, ledger
end

local setLedgerSection

local function buildBankSection(content, Theme, titleText)
    local section = CreateFrame("Frame", nil, content)
    section:SetWidth(BANK_SECTION_WIDTH)
    Theme:Fill(section, Theme.c.bg1, true, "panel")
    section.borderLeft = section:CreateTexture(nil, "BORDER")
    section.borderLeft:SetColorTexture(Theme.c.gold[1], Theme.c.gold[2], Theme.c.gold[3], 0.28)
    section.borderLeft:SetPoint("TOPLEFT", 0, 0)
    section.borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
    section.borderLeft:SetWidth(1)
    section.borderRight = section:CreateTexture(nil, "BORDER")
    section.borderRight:SetColorTexture(Theme.c.gold[1], Theme.c.gold[2], Theme.c.gold[3], 0.28)
    section.borderRight:SetPoint("TOPRIGHT", 0, 0)
    section.borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
    section.borderRight:SetWidth(1)

    local title = Theme:Text(section, 13, Theme.c.goldH)
    section.title = title
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText(titleText or "")
    if title.SetFont then
        title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    end

    section.lines = {}
    for i = 1, 16 do
        local fs = Theme:Text(section, 11, Theme.c.fg2)
        fs:SetWidth(BANK_SECTION_WIDTH - 24)
        fs:SetJustifyH("LEFT")
        fs:SetSpacing(2)
        section.lines[i] = fs
    end

    return section
end

local function setBankSectionWidth(section, width)
    if not section or not width then return end
    section:SetWidth(width)
    for _, fs in ipairs(section.lines or {}) do
        fs:SetWidth(width - 24)
    end
end

local function buildLedgerSection(content, Theme)
    local ledger = buildBankSection(content, Theme, "Recent Ledger")
    ledger:SetHeight(176)
    for _, fs in ipairs(ledger.lines or {}) do fs:Hide() end

    ledger.searchBox = CreateFrame("EditBox", nil, ledger, "InputBoxTemplate")
    ledger.searchBox:SetSize(180, 18)
    ledger.searchBox:SetPoint("TOPLEFT", ledger.title, "BOTTOMLEFT", 0, -8)
    ledger.searchBox:SetAutoFocus(false)
    ledger.searchBox:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "")
    ledger.searchBox:SetTextInsets(4, 4, 0, 0)
    ledger.searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ledger.searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    ledger.searchBox:SetScript("OnTextChanged", function()
        if setLedgerSection then
            setLedgerSection(ledger, ledger._allLines or {}, ledger.owner)
        end
    end)

    local searchHint = Theme:Text(ledger, 9, Theme.c.fg2)
    ledger.searchHint = searchHint
    searchHint:SetPoint("LEFT", ledger.searchBox, "RIGHT", 6, 0)
    searchHint:SetText("Search")

    local ledgerScroll, ledgerContent = Theme:ScrollArea(ledger)
    ledgerScroll:SetPoint("TOPLEFT", ledger.searchBox, "BOTTOMLEFT", 0, -8)
    ledgerScroll:SetPoint("BOTTOMRIGHT", ledger, "BOTTOMRIGHT", -BANK_SCROLLBAR_GUTTER, 10)
    ledgerContent:SetSize(BANK_LEDGER_CONTENT_WIDTH, 1)
    ledger.scroll = ledgerScroll
    ledger.content = ledgerContent
    ledger.ledgerLines = {}
    for i = 1, 50 do
        local fs = Theme:Text(ledgerContent, 10, Theme.c.fg2)
        fs:SetWidth(BANK_LEDGER_CONTENT_WIDTH)
        fs:SetJustifyH("LEFT")
        fs:SetSpacing(2)
        if i == 1 then
            fs:SetPoint("TOPLEFT", 0, -2)
        else
            fs:SetPoint("TOPLEFT", ledger.ledgerLines[i - 1], "BOTTOMLEFT", 0, -4)
        end
        ledger.ledgerLines[i] = fs
    end

    return ledger
end

local function setBankSection(section, lines)
    if not section then return 0 end
    local prev = section.title
    local height = 30
    for i, fs in ipairs(section.lines or {}) do
        local text = lines and lines[i]
        fs:ClearAllPoints()
        if text and text ~= "" then
            fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -5)
            fs:SetText(text)
            fs:Show()
            prev = fs
            height = height + 18
        else
            fs:Hide()
        end
    end
    section:SetHeight(math.max(72, height + 10))
    section:Show()
    return section:GetHeight()
end

local function createContributionTableRow(section, isHeader)
    local row = CreateFrame("Frame", nil, section)
    row:SetSize(BANK_TOP_SECTION_WIDTH - 24, 18)
    local color = isHeader and ns.Theme.c.fg or ns.Theme.c.fg2
    row.rank = ns.Theme:Text(row, 10, color)
    row.character = ns.Theme:Text(row, 10, color)
    row.gen = ns.Theme:Text(row, 10, color)
    row.level = ns.Theme:Text(row, 10, color)
    row.total = ns.Theme:Text(row, 10, color)
    row.share = ns.Theme:Text(row, 10, color)

    row.rank:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.rank:SetWidth(20)
    row.rank:SetJustifyH("LEFT")
    row.character:SetPoint("LEFT", row, "LEFT", 24, 0)
    row.character:SetWidth(150)
    row.character:SetJustifyH("LEFT")
    row.gen:SetPoint("LEFT", row, "LEFT", 184, 0)
    row.gen:SetWidth(22)
    row.gen:SetJustifyH("CENTER")
    row.level:SetPoint("LEFT", row, "LEFT", 210, 0)
    row.level:SetWidth(24)
    row.level:SetJustifyH("CENTER")
    row.total:SetPoint("RIGHT", row, "RIGHT", -50, 0)
    row.total:SetWidth(48)
    row.total:SetJustifyH("RIGHT")
    row.share:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.share:SetWidth(46)
    row.share:SetJustifyH("RIGHT")
    return row
end

local function ensureContributionRows(section)
    if section.contributionHeader then return end
    section.contributionHeader = createContributionTableRow(section, true)
    section.contributionRows = {}
    for i = 1, 5 do
        section.contributionRows[i] = createContributionTableRow(section, false)
    end
end

local function setContributionRowText(row, rank, character, generation, level, total, share)
    row.rank:SetText(rank or "")
    row.character:SetText(character or "")
    row.gen:SetText(generation or "")
    row.level:SetText(level or "")
    row.total:SetText(total or "")
    row.share:SetText(share or "")
end

local function setContributionSection(section, maxRows)
    if not section then return 0 end
    ensureContributionRows(section)
    for _, fs in ipairs(section.lines or {}) do fs:Hide() end

    local rows = ns.Database and ns.Database.CharacterContributionRows and ns.Database:CharacterContributionRows() or {}
    section.contributionHeader:ClearAllPoints()
    section.contributionHeader:SetPoint("TOPLEFT", section.title, "BOTTOMLEFT", 0, -8)

    if #rows == 0 then
        section.contributionHeader:Hide()
        for _, row in ipairs(section.contributionRows or {}) do row:Hide() end
        local empty = section.lines and section.lines[1]
        if empty then
            empty:ClearAllPoints()
            empty:SetPoint("TOPLEFT", section.title, "BOTTOMLEFT", 0, -8)
            empty:SetText("No character contributions recorded yet. The vault remains emotionally available.")
            empty:Show()
        end
        section:SetHeight(72)
        section:Show()
        return section:GetHeight()
    end

    section.contributionHeader:Show()
    setContributionRowText(section.contributionHeader, "#", "Character", "G", "Lv", "Total", "Share")
    local limit = math.min(maxRows or 5, #rows)
    local prev = section.contributionHeader
    for i, rowFrame in ipairs(section.contributionRows or {}) do
        local data = rows[i]
        if i <= limit and data then
            local character = data.characterKey or "Unknown"
            if #character > 18 then character = character:sub(1, 15) .. "..." end
            rowFrame:ClearAllPoints()
            rowFrame:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4)
            setContributionRowText(rowFrame,
                tostring(i) .. ".",
                character,
                tostring(data.generation or 1),
                tostring(data.level or "?"),
                ns.Tiers:FormatMoney(data.total or 0),
                string.format("%.1f%%", data.percent or 0))
            rowFrame:Show()
            prev = rowFrame
        else
            rowFrame:Hide()
        end
    end
    section:SetHeight(math.max(72, 46 + (limit * 22)))
    section:Show()
    return section:GetHeight()
end

local function createInlineIconButton(section, label, texturePath, width)
    local action = CreateFrame("Button", nil, section)
    action:SetSize(width or 18, 18)
    action.bg = action:CreateTexture(nil, "BACKGROUND")
    action.bg:SetAllPoints(action)
    action.bg:SetColorTexture(ns.Theme.c.gold[1], ns.Theme.c.gold[2], ns.Theme.c.gold[3], 0.12)
    if texturePath then
        action.icon = action:CreateTexture(nil, "ARTWORK")
        action.icon:SetSize(12, 12)
        action.icon:SetPoint("CENTER", action, "CENTER", 0, 0)
        action.icon:SetTexture(texturePath)
    else
        action.text = ns.Theme:Text(action, 9, ns.Theme.c.fg)
        action.text:SetPoint("CENTER", action, "CENTER", 0, 0)
        action.text:SetText(label)
    end
    return action
end

local function ensureBankDeskButtons(section)
    section.bankDeskButtons = section.bankDeskButtons or {}
    for i = #section.bankDeskButtons + 1, 16 do
        local button = CreateFrame("Button", nil, section)
        button:SetSize(BANK_ROW_TARGET_WIDTH, 18)
        button.selection = button:CreateTexture(nil, "BACKGROUND")
        button.selection:SetAllPoints(button)
        button.selection:SetColorTexture(ns.Theme.c.gold[1], ns.Theme.c.gold[2], ns.Theme.c.gold[3], 0.18)
        button.selection:Hide()
        button.mailButton = createInlineIconButton(section, "mail", "Interface\\Icons\\INV_Letter_15")
        button.doneButton = createInlineIconButton(section, "done", "Interface\\RaidFrame\\ReadyCheck-Ready")
        button.accountButton = createInlineIconButton(section, "A", nil, 22)
        section.bankDeskButtons[i] = button
    end
end

local function setBankDeskSection(section, lines, rows, owner)
    local height = setBankSection(section, lines)
    if not section then return height end
    ensureBankDeskButtons(section)
    rows = rows or {}
    local shownRows = math.min(#rows, math.max(0, #(section.lines or {}) - 1))
    for i, button in ipairs(section.bankDeskButtons or {}) do
        local fs = section.lines and section.lines[i + 1]
        if i <= shownRows and fs then
            local rowIndex = i
            local req = rows[i]
            local selected = (owner.bankRequestIndex or 1) == i
            fs:SetText(lines[i + 1] or "")
            fs:SetWidth(BANK_ROW_TARGET_WIDTH)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", fs, "TOPLEFT", -4, 3)
            if button.selection then
                if selected then button.selection:Show() else button.selection:Hide() end
            end
            button:SetScript("OnClick", function()
                owner:_SelectBankRequest(rowIndex)
                owner:Refresh()
            end)
            button:Show()

            button.mailButton:ClearAllPoints()
            button.mailButton:SetPoint("LEFT", button, "RIGHT", BANK_ROW_ACTION_GAP, 0)
            button.mailButton:SetScript("OnClick", function()
                owner:_SelectBankRequest(rowIndex)
                if req and ns.Requests and ns.Requests.BeginMailFulfillment then
                    ns.Requests:BeginMailFulfillment(req.id)
                else
                    ns:Print("No pending bank request is ready for mail.")
                end
            end)
            button.mailButton:Show()

            button.doneButton:ClearAllPoints()
            button.doneButton:SetPoint("LEFT", button.mailButton, "RIGHT", 4, 0)
            button.doneButton:SetScript("OnClick", function()
                owner:_SelectBankRequest(rowIndex)
                if req and ns.Requests and ns.Requests.MarkFulfilled then
                    ns.Requests:MarkFulfilled(req.id)
                    owner:Refresh()
                else
                    ns:Print("No pending bank request to mark fulfilled.")
                end
            end)
            button.doneButton:Show()

            button.accountButton:ClearAllPoints()
            button.accountButton:SetPoint("LEFT", button.doneButton, "RIGHT", 4, 0)
            button.accountButton:SetScript("OnClick", function()
                owner:_SelectBankRequest(rowIndex)
                if req and not req.accountId then
                    owner:PromptAssignAccount(req)
                else
                    ns:Print("Requester is already assigned to an account.")
                end
            end)
            if req and not req.accountId then button.accountButton:Show() else button.accountButton:Hide() end
        else
            if button.selection then button.selection:Hide() end
            button:Hide()
            if button.mailButton then button.mailButton:Hide() end
            if button.doneButton then button.doneButton:Hide() end
            if button.accountButton then button.accountButton:Hide() end
        end
    end
    return height
end

local function ensureResaleButtons(section)
    section.resaleButtons = section.resaleButtons or {}
    for i = #section.resaleButtons + 1, 16 do
        local button = CreateFrame("Button", nil, section)
        button:SetSize(BANK_ROW_TARGET_WIDTH, 18)
        button.selection = button:CreateTexture(nil, "BACKGROUND")
        button.selection:SetAllPoints(button)
        button.selection:SetColorTexture(ns.Theme.c.gold[1], ns.Theme.c.gold[2], ns.Theme.c.gold[3], 0.18)
        button.selection:Hide()
        button.mailButton = createInlineIconButton(section, "mail", "Interface\\Icons\\INV_Letter_15")
        button.soldButton = createInlineIconButton(section, "sold", "Interface\\RaidFrame\\ReadyCheck-Ready")
        button.cancelButton = createInlineIconButton(section, "cancel", "Interface\\RaidFrame\\ReadyCheck-NotReady")
        section.resaleButtons[i] = button
    end
end

local function setResaleSection(section, lines, rows, owner)
    local height = setBankSection(section, lines)
    if not section then return height end
    ensureResaleButtons(section)
    if not section.clearResaleButton then
        local button = CreateFrame("Button", nil, section)
        button:SetSize(18, 18)
        button:SetPoint("TOPRIGHT", section, "TOPRIGHT", BANK_CLEAR_BUTTON_RIGHT_INSET, -8)
        button.bg = button:CreateTexture(nil, "BACKGROUND")
        button.bg:SetAllPoints(button)
        button.bg:SetColorTexture(ns.Theme.c.gold[1], ns.Theme.c.gold[2], ns.Theme.c.gold[3], 0.12)
        button.text = ns.Theme:Text(button, 11, ns.Theme.c.fg)
        button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.text:SetText("x")
        button:SetScript("OnClick", function()
            owner:ConfirmClearResaleDesk()
        end)
        section.clearResaleButton = button
    end
    section.clearResaleButton:Show()
    rows = rows or {}
    local shownRows = math.min(#rows, math.max(0, #(section.lines or {}) - 1))
    for i, button in ipairs(section.resaleButtons or {}) do
        local fs = section.lines and section.lines[i + 1]
        if i <= shownRows and fs then
            local rowIndex = i
            local row = rows[i]
            local selected = (owner.bankResaleIndex or 1) == i
            fs:SetText(lines[i + 1] or "")
            fs:SetWidth(BANK_ROW_TARGET_WIDTH)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", fs, "TOPLEFT", -4, 3)
            if button.selection then
                if selected then button.selection:Show() else button.selection:Hide() end
            end
            button:SetScript("OnClick", function()
                owner:_SelectResaleRow(rowIndex)
                owner:Refresh()
            end)
            button:Show()
            button.mailButton:ClearAllPoints()
            button.mailButton:SetPoint("LEFT", button, "RIGHT", BANK_ROW_ACTION_GAP, 0)
            button.mailButton:SetScript("OnClick", function()
                owner:_SelectResaleRow(rowIndex)
                owner:PromptResaleCOD(row)
            end)
            button.mailButton:Show()
            button.soldButton:ClearAllPoints()
            button.soldButton:SetPoint("LEFT", button.mailButton, "RIGHT", 4, 0)
            button.soldButton:SetScript("OnClick", function()
                owner:_SelectResaleRow(rowIndex)
                owner:_RecordResaleRow(row)
            end)
            button.soldButton:Show()
            button.cancelButton:ClearAllPoints()
            button.cancelButton:SetPoint("LEFT", button.soldButton, "RIGHT", 4, 0)
            button.cancelButton:SetScript("OnClick", function()
                owner:_SelectResaleRow(rowIndex)
                owner:_CancelResaleRow(row)
            end)
            button.cancelButton:Show()
        else
            if button.selection then button.selection:Hide() end
            button:Hide()
            if button.mailButton then button.mailButton:Hide() end
            if button.soldButton then button.soldButton:Hide() end
            if button.cancelButton then button.cancelButton:Hide() end
        end
    end
    return height
end

local function ensureLedgerClearButton(section, owner)
    if not section or not owner then return end
    if not section.clearLedgerButton then
        local button = createInlineIconButton(section, "x", nil)
        button:SetPoint("TOPRIGHT", section, "TOPRIGHT", BANK_CLEAR_BUTTON_RIGHT_INSET, -8)
        section.clearLedgerButton = button
    end
    section.clearLedgerButton:SetScript("OnClick", function()
        owner:ConfirmClearRecentLedger()
    end)
    section.clearLedgerButton:Show()
end

setLedgerSection = function(section, lines, owner)
    if not section then return 0 end
    section.owner = owner or section.owner
    ensureLedgerClearButton(section, section.owner)
    section._allLines = lines or {}
    local query = ""
    if section.searchBox and section.searchBox.GetText then
        query = (section.searchBox:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    end

    local filtered = {}
    for _, line in ipairs(lines or {}) do
        local plain = tostring(line or "")
        if query == "" or plain:lower():find(query, 1, true) then
            filtered[#filtered + 1] = plain
        end
    end
    if #filtered == 0 then
        filtered[1] = query ~= "" and "No ledger entries match that search." or "No recent ledger activity. The ink is getting ideas."
    end

    for i, fs in ipairs(section.ledgerLines or {}) do
        local text = filtered[i]
        if text and text ~= "" then
            fs:SetText(text)
            fs:Show()
        else
            fs:Hide()
        end
    end
    if section.content then
        section.content:SetHeight(math.max(1, (#filtered * 18) + 10))
    end
    if section.scroll then
        section.scroll:SetVerticalScroll(0)
    end
    section:SetHeight(176)
    section:Show()
    return section:GetHeight()
end

function Tab:_BuildBankerOverviewLines(key)
    local name, realm = withRealm(key)

    local fmtMoney = function(copper)
        if ns.Tiers and ns.Tiers.FormatMoney then
            return ns.Tiers:FormatMoney(copper or 0)
        end
        return tostring(copper or 0)
    end

    local left = {
        ("Name: |cffc0a060%s|r"):format(name),
        "Class: Bank",
        "Level: n/a",
        ("Realm: %s"):format(realm),
        "Run state: bank infrastructure",
        "Lives remaining: n/a",
        achievementSummaryLine(),
    }

    local pending, gathering, fulfilled, unassigned = 0, 0, 0, 0
    for _, req in ipairs(requestRows()) do
        if req.status == "pending" then pending = pending + 1 end
        if req.status == "gathering" then gathering = gathering + 1 end
        if req.status == "fulfilled" then fulfilled = fulfilled + 1 end
        if isActionableRequest(req) and not req.accountId then unassigned = unassigned + 1 end
    end

    local nextReq = self:_ActiveBankRequest()
    local right = {
        "|cffc0a060Bank Desk|r",
    }
    appendBankDeskTable(right, 8, self)
    appendContributionBoard(right, 5)
    appendResaleDesk(right, 6, self)
    appendRecentLedger(right, 50)

    return left, right
end

function Tab:PromptAssignAccount(req)
    if not req or not req.from then return end
    if not StaticPopupDialogs or not StaticPopup_Show then
        ns:Print("Assign account with |cffffff00/wrl account LABEL %s|r.", req.from)
        return
    end
    StaticPopupDialogs["WRL_ACCOUNT_LABEL"] = StaticPopupDialogs["WRL_ACCOUNT_LABEL"] or {
        text = "Assign %s to account label:",
        button1 = "Assign",
        button2 = "Cancel",
        hasEditBox = 1,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function(popup, characterKey)
            local editBox = popup.editBox or _G[popup:GetName() .. "EditBox"]
            local label = editBox and editBox:GetText() or ""
            if label and label ~= "" and ns.Database and ns.Database.AssignCharacterToAccountLabel then
                local account = ns.Database:AssignCharacterToAccountLabel(characterKey, label)
                for _, r in ipairs(WRL_DB.requests or {}) do
                    if r.from == characterKey then r.accountId = account and account.id or r.accountId end
                end
                ns:Print("Assigned %s to account %s.", characterKey, account and account.label or label)
                if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then ns.MainFrame:RefreshCurrentTab() end
            end
        end,
        EditBoxOnEnterPressed = function(editBox)
            local popup = editBox:GetParent()
            local characterKey = popup.data
            StaticPopupDialogs["WRL_ACCOUNT_LABEL"].OnAccept(popup, characterKey)
            popup:Hide()
        end,
        EditBoxOnEscapePressed = function(editBox)
            editBox:GetParent():Hide()
        end,
    }
    local popup = StaticPopup_Show("WRL_ACCOUNT_LABEL", req.from)
    if popup then popup.data = req.from end
end

function Tab:PromptResaleCOD(row)
    if not row then
        ns:Print("No resale catalog item is selected.")
        return
    end
    row = self:_ResaleOrderForRow(row)
    if row and row.buyer and ns.BankResale and ns.BankResale.PrepareCODMail then
        local draft, reason = ns.BankResale:PrepareCODMail(row.itemId, row.qty or 1, row.buyer)
        self._lastResaleCOD = draft
        if draft then
            self.pendingResaleOrder = draft
            return
        end
        if reason == "mailbox_closed" then
            ns:Print("Open your mailbox first, then prepare resale COD mail again.")
        elseif reason == "missing_buyer" then
            ns:Print("Resale COD mail requires a buyer.")
        else
            ns:Print("Could not prepare resale COD mail.")
        end
        return
    end
    if not StaticPopupDialogs or not StaticPopup_Show then
        ns:Print("Use |cffffff00/wrl resale cod %d 1 BUYER|r to prepare COD mail.", row.itemId or 0)
        return
    end
    self._lastResalePrompted = row.itemId
    StaticPopupDialogs["WRL_RESALE_COD"] = StaticPopupDialogs["WRL_RESALE_COD"] or {
        text = "Prepare COD mail for %s. Enter buyer and quantity:",
        button1 = "Prepare COD",
        button2 = "Cancel",
        hasEditBox = 1,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function(popup, data)
            local editBox = popup.editBox or _G[popup:GetName() .. "EditBox"]
            local text = editBox and editBox:GetText() or ""
            local buyer, qtyText = text:match("^(%S+)%s*(%S*)$")
            local qty = tonumber(qtyText) or 1
            local saleRow = data and data.row
            if saleRow and ns.BankResale and ns.BankResale.PrepareCODMail then
                local draft, reason = ns.BankResale:PrepareCODMail(saleRow.itemId, math.min(qty, saleRow.count or qty), buyer)
                Tab._lastResaleCOD = draft
                if not draft then
                    if reason == "mailbox_closed" then
                        ns:Print("Open your mailbox first, then prepare resale COD mail again.")
                    elseif reason == "missing_buyer" then
                        ns:Print("Resale COD mail requires a buyer.")
                    else
                        ns:Print("Could not prepare resale COD mail.")
                    end
                end
            end
        end,
        EditBoxOnEnterPressed = function(editBox)
            local popup = editBox:GetParent()
            StaticPopupDialogs["WRL_RESALE_COD"].OnAccept(popup, popup.data)
            popup:Hide()
        end,
        EditBoxOnEscapePressed = function(editBox)
            editBox:GetParent():Hide()
        end,
    }
    local popup = StaticPopup_Show("WRL_RESALE_COD", row.name or ("item:" .. tostring(row.itemId)))
    if popup then popup.data = { row = row } end
end

function Tab:_ShouldShowContributionAction(rec)
    local state = ns.Run and ns.Run.GetState and ns.Run:GetState(rec) or rec and rec.status
    return state == "dead_pending_contribution"
end

function Tab:Init(parent)
    if self.panel then return end
    local Theme = ns.Theme

    local p = CreateFrame("Frame", nil, parent)
    self.panel = p
    ns.MainFrame:RegisterPanel("Run", p)

    local title = Theme:Header(p, "Dashboard", 16)
    title:SetPoint("TOPLEFT", 20, -18)

    self.hint = Theme:Text(p, 11, Theme.c.fg2)
    self.hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    self.hint:SetText("Snapshot of your current character's run state and audit trail.")

    self.contributionButton = Theme:Button(p, "Prepare Contribution Mail", 170, 22)
    self.contributionButton:SetPoint("TOPRIGHT", -20, -18)
    self.contributionButton:SetScript("OnClick", function()
        if ns.Death and ns.Death.PrepareContributionMail then
            ns.Death:PrepareContributionMail()
        end
    end)
    self.contributionButton:Hide()

    Theme:Divider(p, "TOPLEFT", "TOPRIGHT", 0, -54, 0.2)

    local left = CreateFrame("Frame", nil, p)
    left:SetPoint("TOPLEFT", 20, -64)
    left:SetPoint("BOTTOMLEFT", 20, 18)
    left:SetWidth(304)
    self.leftPane = left

    local right = CreateFrame("Frame", nil, p)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 16, 0)
    right:SetPoint("BOTTOMRIGHT", -20, 18)
    self.rightPane = right

    self.leftTitle = Theme:Text(left, 12, Theme.c.goldH)
    self.leftTitle:SetPoint("TOPLEFT", 0, 0)
    self.leftTitle:SetText("Run Snapshot")
    self.leftLines = {}
    for i = 1, 18 do
        local fs = Theme:Text(left, 11, Theme.c.fg)
        fs:SetWidth(300)
        fs:SetJustifyH("LEFT")
        if i == 1 then
            fs:SetPoint("TOPLEFT", self.leftTitle, "BOTTOMLEFT", 0, -8)
        else
            fs:SetPoint("TOPLEFT", self.leftLines[i - 1], "BOTTOMLEFT", 0, -4)
        end
        self.leftLines[i] = fs
    end

    local scroll, content = Theme:ScrollArea(right)
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    content:SetSize(CHARACTER_RIGHT_WIDTH, 1)
    self.scroll = scroll
    self.content = content
    self.bankSnapshotSection = buildBankSection(content, Theme, "Bank Snapshot")
    setBankSectionWidth(self.bankSnapshotSection, BANK_TOP_SECTION_WIDTH)
    self.bankSnapshotSection:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -2)
    self.bankSnapshotSection:Hide()
    self.bankDeskSection = buildBankSection(content, Theme, "Bank Desk")
    self.bankDeskSection:Hide()
    self.bankContributionSection = buildBankSection(content, Theme, "Contribution Board")
    setBankSectionWidth(self.bankContributionSection, BANK_TOP_SECTION_WIDTH)
    self.bankContributionSection:Hide()
    self.bankResaleSection = buildBankSection(content, Theme, "Resale Desk")
    self.bankResaleSection:Hide()
    self.bankLedgerSection = buildLedgerSection(content, Theme)
    self.bankLedgerSection:Hide()

    self.rightLines = {}
    local prev = nil
    for i = 1, 60 do
        local fs = Theme:Text(content, 10, Theme.c.fg2)
        fs:SetWidth(408)
        fs:SetJustifyH("LEFT")
        if i == 1 then
            fs:SetPoint("TOPLEFT", 0, -2)
        else
            fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4)
        end
        prev = fs
        self.rightLines[i] = fs
    end

    p.Refresh = function() Tab:Refresh() end
    Tab:Refresh()
end

function Tab:Refresh()
    if not self.panel then return end

    local key = ns:UnitKey()
    local rec = key and ns.Database and ns.Database.GetCharacter and ns.Database:GetCharacter(key) or nil
    if not key or not rec then
        if self.leftPane then self.leftPane:Show() end
        if self.rightPane then
            self.rightPane:ClearAllPoints()
            self.rightPane:SetPoint("TOPLEFT", self.leftPane, "TOPRIGHT", 16, 0)
            self.rightPane:SetPoint("BOTTOMRIGHT", -20, 18)
        end
        self.content:SetSize(CHARACTER_RIGHT_WIDTH, 1)
        if self.bankSnapshotSection then self.bankSnapshotSection:Hide() end
        if self.bankDeskSection then self.bankDeskSection:Hide() end
        if self.bankContributionSection then self.bankContributionSection:Hide() end
        if self.bankResaleSection then self.bankResaleSection:Hide() end
        if self.bankLedgerSection then self.bankLedgerSection:Hide() end
        writeLines(self.leftLines, {
            "Character: unavailable",
            "Run data has not initialized yet.",
        })
        writeLines(self.rightLines, {
            "Waiting for character record...",
        })
        self.content:SetHeight(80)
        self.scroll:SetVerticalScroll(0)
        return
    end

    local name, realm = withRealm(key)
    if ns.Database:IsBankCharacter(key) then
        local keepScroll = self.scroll and self.scroll.GetVerticalScroll and self.scroll:GetVerticalScroll() or 0
        if self.contributionButton then self.contributionButton:Hide() end
        if self.leftPane then self.leftPane:Hide() end
        if self.rightPane then
            self.rightPane:ClearAllPoints()
            self.rightPane:SetPoint("TOPLEFT", self.panel, "TOPLEFT", 20, -64)
            self.rightPane:SetPoint("BOTTOMRIGHT", self.panel, "BOTTOMRIGHT", -20, 18)
        end
        self.content:SetSize(BANK_DASHBOARD_WIDTH, 1)
        local bankRows = self:_BankDeskRows()
        local resaleRows = self:_ResaleRows()
        self:_ActiveResaleRow(resaleRows)
        self.hint:SetText("Bank Desk dashboard: requests, account contributions, and recent ledger work.")
        self.leftTitle:SetText("Bank Snapshot")
        local left, right = self:_BuildBankerOverviewLines(key)
        hideLines(self.leftLines)
        hideLines(self.rightLines)
        local deskLines, contributionLines, resaleLines, ledgerLines = splitBankSections(right)
        local snapshotH = setBankSection(self.bankSnapshotSection, left)
        self.bankContributionSection:ClearAllPoints()
        self.bankContributionSection:SetPoint("TOPLEFT", self.bankSnapshotSection, "TOPRIGHT", 10, 0)
        local contributionH = setContributionSection(self.bankContributionSection, 5)
        local topH = math.max(snapshotH, contributionH)
        self.bankSnapshotSection:SetHeight(topH)
        self.bankContributionSection:SetHeight(topH)
        local deskH = setBankDeskSection(self.bankDeskSection, deskLines, bankRows, self)
        self.bankDeskSection:ClearAllPoints()
        self.bankDeskSection:SetPoint("TOPLEFT", self.bankSnapshotSection, "BOTTOMLEFT", 0, -10)
        self.bankResaleSection:ClearAllPoints()
        self.bankResaleSection:SetPoint("TOPLEFT", self.bankDeskSection, "BOTTOMLEFT", 0, -10)
        local resaleH = setResaleSection(self.bankResaleSection, resaleLines, resaleRows, self)
        self.bankLedgerSection:ClearAllPoints()
        self.bankLedgerSection:SetPoint("TOPLEFT", self.bankResaleSection, "BOTTOMLEFT", 0, -10)
        local ledgerH = setLedgerSection(self.bankLedgerSection, ledgerLines, self)
        self.content:SetHeight(math.max(1, topH + deskH + resaleH + ledgerH + 56))
        self.scroll:SetVerticalScroll(keepScroll)
        return
    end

    self.hint:SetText("Character-focused dashboard for the logged-in runner.")
    if self.leftPane then self.leftPane:Show() end
    if self.rightPane then
        self.rightPane:ClearAllPoints()
        self.rightPane:SetPoint("TOPLEFT", self.leftPane, "TOPRIGHT", 16, 0)
        self.rightPane:SetPoint("BOTTOMRIGHT", -20, 18)
    end
    self.content:SetSize(CHARACTER_RIGHT_WIDTH, 1)
    if self.bankSnapshotSection then self.bankSnapshotSection:Hide() end
    if self.bankDeskSection then self.bankDeskSection:Hide() end
    if self.bankContributionSection then self.bankContributionSection:Hide() end
    if self.bankResaleSection then self.bankResaleSection:Hide() end
    if self.bankLedgerSection then self.bankLedgerSection:Hide() end
    self.leftTitle:SetText("Character Dashboard")

    local runState = ns.Run and ns.Run.GetState and ns.Run:GetState(rec) or rec.status or "unknown"
    if self.contributionButton then
        if self:_ShouldShowContributionAction(rec) then
            self.contributionButton:Show()
        else
            self.contributionButton:Hide()
        end
    end
    local level = rec.levelCurrent or rec.levelAtCreate or (UnitLevel and UnitLevel("player")) or "?"
    local lives = rec.livesRemaining or 0
    local pending = newestPendingOutgoing()
    local money, bags, total = bagEstimate()

    local left = {
        ("Name: |cffc0a060%s|r"):format(name),
        ("Class: %s"):format(classLabel(rec.class)),
        ("Level: %s"):format(tostring(level)),
        ("Realm: %s"):format(realm),
        ("Run state: %s"):format(stateLabel(runState)),
        ("Lives remaining: %d"):format(math.max(0, lives)),
        achievementSummaryLine(),
        "",
        ("Estimated contribution: %s"):format(ns.Tiers:FormatMoney(total)),
        (" - Money: %s"):format(ns.Tiers:FormatMoney(money)),
        (" - Vendorable bags: %s"):format(ns.Tiers:FormatMoney(bags)),
    }

    if pending then
        left[#left + 1] = ""
        left[#left + 1] = ("Pending outgoing request: %s"):format(requestTierLabel(pending))
        left[#left + 1] = (" - Status: %s | Sent: %s"):format(pending.status or "sent", fmtWhen(pending.when))
        left[#left + 1] = (" - Bank: %s"):format(shortName(pending.bank))
    else
        left[#left + 1] = ""
        left[#left + 1] = "Pending outgoing request: none"
    end

    writeLines(self.leftLines, left)

    local right = {}
    right[#right + 1] = "|cffc0a060Active rules|r"
    local ruleBits = rulesSummary(6)
    for i = 1, #ruleBits do right[#right + 1] = ruleBits[i] end
    right[#right + 1] = ""
    right[#right + 1] = "|cffc0a060Claimed rewards|r"
    local claimBits = claimedSummary(rec, 6)
    for i = 1, #claimBits do right[#right + 1] = claimBits[i] end
    right[#right + 1] = ""
    right[#right + 1] = "|cffc0a060Active boons and burdens|r"
    local boonBits = activeBoonsSummary(rec)
    for i = 1, #boonBits do right[#right + 1] = boonBits[i] end
    local burdenBits = activeBurdensSummary(rec)
    for i = 1, #burdenBits do right[#right + 1] = burdenBits[i] end
    right[#right + 1] = ""
    right[#right + 1] = "|cffc0a060Recent contribution receipts|r"
    local receipts = recentReceipts(key, 5)
    for i = 1, #receipts do right[#right + 1] = receipts[i] end
    right[#right + 1] = ""
    right[#right + 1] = "|cffc0a060Recent taint/warning log entries|r"
    local warnings = recentRuleWarnings(key, 6)
    for i = 1, #warnings do right[#right + 1] = warnings[i] end

    if runState == "retired" or runState == "archived" then
        right[#right + 1] = ""
        right[#right + 1] = "|cffc0a060Death history|r"
        local deaths = recentDeaths(rec, 6)
        for i = 1, #deaths do right[#right + 1] = deaths[i] end
    end

    writeLines(self.rightLines, right)
    self.content:SetHeight(math.max(1, (#right * 16) + 20))
    self.scroll:SetVerticalScroll(0)
end
