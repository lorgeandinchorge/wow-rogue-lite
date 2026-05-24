-- Core/Loans.lua
-- Manual bank loan tracking. The addon records lending and repayment paperwork;
-- it never moves, mails, trades, or otherwise automates gold.

local ADDON_NAME, ns = ...
local L = ns:NewModule("Loans")

local COPPER_PER_GOLD = 10000
local KINDS = { borrow = true, repayment = true }

local function now()
    return time and time() or 0
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function ensureStorage()
    WRL_DB = WRL_DB or {}
    WRL_DB.loanReceipts = WRL_DB.loanReceipts or {}
end

local function floorCopper(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function floorGold(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function goldToCopper(value)
    return floorGold(value) * COPPER_PER_GOLD
end

local function rollId()
    WRL_DB._loanReceiptSeq = (WRL_DB._loanReceiptSeq or 0) + 1
    return string.format("l%d-%d", now(), WRL_DB._loanReceiptSeq)
end

function L:Init()
    ensureStorage()
end

function L:HighestLegacyRank()
    local highest = 0
    local unlocks = WRL_DB and WRL_DB.legacyUnlocks or {}
    if ns.LegacyUnlocks and ns.LegacyUnlocks.TrackOrder and ns.LegacyUnlocks.GetRank then
        for _, trackId in ipairs(ns.LegacyUnlocks:TrackOrder()) do
            highest = math.max(highest, ns.LegacyUnlocks:GetRank(trackId) or 0)
        end
        return highest
    end
    for _, trackId in ipairs({ "storage", "stipend", "fate" }) do
        highest = math.max(highest, math.floor(tonumber(unlocks[trackId]) or 0))
    end
    return highest
end

function L:BorrowCapCopper()
    local rank = self:HighestLegacyRank()
    return math.floor(rank * 3 / 2) * COPPER_PER_GOLD, rank
end

function L:FormatGold(copper)
    copper = floorCopper(copper)
    local gold = copper / COPPER_PER_GOLD
    if gold == math.floor(gold) then
        return tostring(math.floor(gold)) .. "g"
    end
    local text = string.format("%.2f", gold):gsub("0+$", ""):gsub("%.$", "")
    return text .. "g"
end

function L:_AccountIdForCharacter(characterKey)
    characterKey = trim(characterKey)
    if characterKey == "" then return nil end
    if ns.Database and ns.Database.AccountIdForCharacter then
        local accountId = ns.Database:AccountIdForCharacter(characterKey)
        if accountId then return accountId end
        if ns.Database.LinkCharacterToAccount then
            local account = ns.Database:LinkCharacterToAccount(characterKey, "acct-local")
            return account and account.id or "acct-local"
        end
    end
    return "acct-local"
end

function L:_OutstandingForAccount(accountId)
    ensureStorage()
    local outstanding = 0
    for _, receipt in ipairs(WRL_DB.loanReceipts or {}) do
        if receipt.accountId == accountId then
            local amount = floorCopper(receipt.amount)
            if receipt.kind == "borrow" then
                outstanding = outstanding + amount
            elseif receipt.kind == "repayment" then
                outstanding = outstanding - amount
            end
        end
    end
    return math.max(0, outstanding)
end

function L:BorrowCapForAccount(accountId)
    ensureStorage()
    local capCopper, highestRank = self:BorrowCapCopper()
    local outstanding = self:_OutstandingForAccount(accountId)
    return {
        accountId = accountId,
        highestRank = highestRank,
        capCopper = capCopper,
        outstandingCopper = outstanding,
        availableCopper = math.max(0, capCopper - outstanding),
    }
end

function L:BorrowCapForCharacter(characterKey)
    local accountId = self:_AccountIdForCharacter(characterKey)
    local cap = self:BorrowCapForAccount(accountId)
    cap.characterKey = trim(characterKey)
    return cap
end

function L:_AppendReceipt(kind, characterKey, amount, source, note, accountId)
    ensureStorage()
    amount = floorCopper(amount)
    characterKey = trim(characterKey)
    if characterKey == "" then return nil, "missing_character" end
    if amount <= 0 then return nil, "bad_amount" end
    if not KINDS[kind] then return nil, "bad_kind" end
    accountId = accountId or self:_AccountIdForCharacter(characterKey)
    local receipt = {
        id = rollId(),
        kind = kind,
        accountId = accountId,
        characterKey = characterKey,
        amount = amount,
        when = now(),
        source = source or "",
        note = note or "",
    }
    table.insert(WRL_DB.loanReceipts, receipt)
    while #WRL_DB.loanReceipts > 500 do
        table.remove(WRL_DB.loanReceipts, 1)
    end
    if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
        ns.MainFrame:RefreshCurrentTab()
    end
    return receipt
end

function L:RecordLoan(characterKey, amountGold, source, note)
    local amount = goldToCopper(amountGold)
    if amount <= 0 then return nil, "bad_amount" end
    local accountId = self:_AccountIdForCharacter(characterKey)
    local cap = self:BorrowCapForAccount(accountId)
    if amount > (cap.availableCopper or 0) then
        return nil, "over_cap", cap
    end
    return self:_AppendReceipt("borrow", characterKey, amount, source or "manual", note, accountId)
end

function L:RecordTestLoan(characterKey, amountGold, note)
    local amount = goldToCopper(amountGold)
    if amount <= 0 then return nil, "bad_amount" end
    local accountId = self:_AccountIdForCharacter(characterKey)
    return self:_AppendReceipt("borrow", characterKey, amount, "simulated", note or "local loan simulation", accountId)
end

function L:ClearSimulatedLoans()
    ensureStorage()
    local kept = {}
    local removed = 0
    for _, receipt in ipairs(WRL_DB.loanReceipts or {}) do
        if receipt.source == "simulated" then
            removed = removed + 1
        else
            kept[#kept + 1] = receipt
        end
    end
    WRL_DB.loanReceipts = kept
    if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
        ns.MainFrame:RefreshCurrentTab()
    end
    return removed
end

function L:ClearSimulatedLoansForAccount(accountId)
    ensureStorage()
    if not accountId then return 0 end
    local kept = {}
    local removed = 0
    for _, receipt in ipairs(WRL_DB.loanReceipts or {}) do
        local receiptAccount = receipt.accountId or self:_AccountIdForCharacter(receipt.characterKey)
        if receipt.source == "simulated" and receiptAccount == accountId then
            removed = removed + 1
        else
            kept[#kept + 1] = receipt
        end
    end
    WRL_DB.loanReceipts = kept
    if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
        ns.MainFrame:RefreshCurrentTab()
    end
    return removed
end

function L:ApplyRepayment(characterKey, amount, source, info)
    amount = floorCopper(amount)
    info = info or {}
    if amount <= 0 then
        return { repaid = 0, contributionRemainder = 0 }
    end
    local accountId = self:_AccountIdForCharacter(characterKey)
    local outstanding = self:_OutstandingForAccount(accountId)
    local repaid = math.min(amount, outstanding)
    local receipt = nil
    if repaid > 0 then
        receipt = self:_AppendReceipt(
            "repayment",
            characterKey,
            repaid,
            source or "contribution",
            info.note or "",
            accountId)
    end
    return {
        accountId = accountId,
        repaid = repaid,
        contributionRemainder = amount - repaid,
        receipt = receipt,
    }
end

function L:RecordManualRepayment(characterKey, amountGold, source, note)
    return self:ApplyRepayment(characterKey, goldToCopper(amountGold), source or "manual", { note = note })
end

function L:AccountLoanRows()
    ensureStorage()
    local byAccount = {}
    for _, account in pairs((WRL_DB and WRL_DB.accounts) or {}) do
        byAccount[account.id] = {
            accountId = account.id,
            label = account.label or "Unassigned",
            characterKey = nil,
            latestWhen = 0,
            latestKind = nil,
            borrowedCopper = 0,
            repaidCopper = 0,
            hasSimulatedLoan = false,
        }
    end
    for _, receipt in ipairs(WRL_DB.loanReceipts or {}) do
        local accountId = receipt.accountId or self:_AccountIdForCharacter(receipt.characterKey)
        local row = byAccount[accountId]
        if not row then
            row = {
                accountId = accountId,
                label = ns.Database and ns.Database.AccountLabel and ns.Database:AccountLabel(accountId) or "Unassigned",
                characterKey = nil,
                latestWhen = 0,
                latestKind = nil,
                borrowedCopper = 0,
                repaidCopper = 0,
                hasSimulatedLoan = false,
            }
            byAccount[accountId] = row
        end
        local amount = floorCopper(receipt.amount)
        if receipt.kind == "borrow" then
            row.borrowedCopper = row.borrowedCopper + amount
        elseif receipt.kind == "repayment" then
            row.repaidCopper = row.repaidCopper + amount
        end
        if (receipt.when or 0) >= (row.latestWhen or 0) then
            row.latestWhen = receipt.when or 0
            row.latestKind = receipt.kind
            row.characterKey = receipt.characterKey
        end
        if receipt.source == "simulated" then
            row.hasSimulatedLoan = true
        end
    end

    local rows = {}
    for accountId, row in pairs(byAccount) do
        local cap = self:BorrowCapForAccount(accountId)
        row.capCopper = cap.capCopper
        row.highestRank = cap.highestRank
        row.outstandingCopper = cap.outstandingCopper
        row.availableCopper = cap.availableCopper
        if (row.outstandingCopper or 0) > 0 or (row.borrowedCopper or 0) > 0 or (row.repaidCopper or 0) > 0 then
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b)
        if (a.outstandingCopper or 0) == (b.outstandingCopper or 0) then
            return tostring(a.label) < tostring(b.label)
        end
        return (a.outstandingCopper or 0) > (b.outstandingCopper or 0)
    end)
    return rows
end
