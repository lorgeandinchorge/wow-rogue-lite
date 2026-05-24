local function resetHarness()
    WRL_DB = {
        schema = 13,
        bankCharacter = "Bank-Realm",
        totalContributed = 0,
        legacySpent = 0,
        legacyUnlocks = { storage = 0, stipend = 0, fate = 0 },
        accounts = {
            ["acct-local"] = { id = "acct-local", label = "Local Account", createdAt = 100 },
            ["acct-graham"] = { id = "acct-graham", label = "Graham", createdAt = 101 },
        },
        accountLinks = {
            ["Bank-Realm"] = "acct-local",
            ["Graham-Realm"] = "acct-graham",
            ["Grahamalt-Realm"] = "acct-graham",
        },
        characters = {
            ["Bank-Realm"] = { key = "Bank-Realm", contributed = 0, history = {} },
            ["Graham-Realm"] = { key = "Graham-Realm", contributed = 0, history = {} },
            ["Grahamalt-Realm"] = { key = "Grahamalt-Realm", contributed = 0, history = {} },
        },
        contributionReceipts = {},
        fulfillmentReceipts = {},
        loanReceipts = {},
    }
    WRL_CharDB = {}

    _G.time = function() return 12345 end
    _G.GetRealmName = function() return "Realm" end
    _G.UnitLevel = function() return 10 end
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    _G.UnitRace = function() return "Human", "HUMAN" end
    _G.UnitGUID = function() return "Player-1" end
    _G.GetMoney = function() return 0 end
    _G.NUM_BAG_SLOTS = 0

    local ns = {
        Database = nil,
        LegacyUnlocks = nil,
        Loans = nil,
        Contributions = nil,
        Rewards = {},
        Tiers = {},
        Achievements = nil,
        Debug = function() end,
        Print = function() end,
        On = function() end,
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns:UnitKey()
        return "Bank-Realm"
    end

    function ns.Rewards:BuildRewardForTierIds()
        return { items = {}, gold = 0, extraLives = 0 }
    end

    function ns.Tiers:FormatMoney(copper)
        return tostring(copper or 0) .. "c"
    end

    assert(loadfile("Core/Database.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/LegacyUnlocks.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/Loans.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/Contributions.lua"))("WoWRoguelite", ns)
    ns.Database:Init()
    ns.LegacyUnlocks:Init()
    ns.Loans:Init()
    ns.Contributions:Init()
    return ns
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertTrue(value, message)
    if not value then error(message or "expected truthy value", 2) end
end

local function testBorrowCapUsesHighestPurchasedLegacyRank()
    local ns = resetHarness()

    local expected = { [0] = 0, [1] = 10000, [2] = 30000, [3] = 40000, [4] = 60000, [5] = 70000, [6] = 90000 }
    for rank = 0, 6 do
        WRL_DB.legacyUnlocks.storage = rank
        WRL_DB.legacyUnlocks.stipend = 0
        WRL_DB.legacyUnlocks.fate = 0
        local cap = ns.Loans:BorrowCapForAccount("acct-graham")
        assertEqual(cap.capCopper, expected[rank], "cap follows floor(rank * 3 / 2) gold for rank " .. tostring(rank))
        assertEqual(cap.highestRank, rank, "cap reports the highest purchased rank")
    end

    WRL_DB.legacyUnlocks.storage = 1
    WRL_DB.legacyUnlocks.stipend = 2
    WRL_DB.legacyUnlocks.fate = 1
    local cap = ns.Loans:BorrowCapForAccount("acct-graham")
    assertEqual(cap.capCopper, 30000, "fate rank one is counted as purchased rank one, not milestone three")
    assertEqual(cap.highestRank, 2, "highest rank comes from the largest purchased track rank")
end

local function testBorrowingIsBlockedWhenItExceedsAccountCap()
    local ns = resetHarness()
    WRL_DB.legacyUnlocks.storage = 2

    local first = ns.Loans:RecordLoan("Graham-Realm", 2, "manual", "training")
    local second, reason = ns.Loans:RecordLoan("Grahamalt-Realm", 2, "manual", "more training")

    assertTrue(first, "first loan inside cap records")
    assertEqual(first.amount, 20000, "manual loan amount is entered as gold and stored as copper")
    assertEqual(second, nil, "loan above account cap is blocked")
    assertEqual(reason, "over_cap", "blocked loan reports cap reason")
    assertEqual(#WRL_DB.loanReceipts, 1, "blocked loan does not write a receipt")
end

local function testSimulatedLoanCanBypassCapForLocalTesting()
    local ns = resetHarness()
    WRL_DB.legacyUnlocks.storage = 0

    local normal, normalReason = ns.Loans:RecordLoan("Graham-Realm", 1, "manual", "normal")
    local simulated = ns.Loans:RecordTestLoan("Graham-Realm", 1, "local test")

    assertEqual(normal, nil, "normal loan is still blocked at rank zero")
    assertEqual(normalReason, "over_cap", "normal rank-zero block reports over_cap")
    assertTrue(simulated, "simulated test loan records even with zero cap")
    assertEqual(simulated.amount, 10000, "simulated loan still stores gold input as copper")
    assertEqual(simulated.source, "simulated", "simulated loan receipt is marked as simulated")
end

local function testClearSimulatedLoansKeepsManualLoanReceipts()
    local ns = resetHarness()
    WRL_DB.legacyUnlocks.storage = 2

    ns.Loans:RecordTestLoan("Graham-Realm", 1, "local test")
    ns.Loans:RecordLoan("Graham-Realm", 1, "manual", "real debt")

    local removed = ns.Loans:ClearSimulatedLoans()

    assertEqual(removed, 1, "clear simulated removes one test loan")
    assertEqual(#WRL_DB.loanReceipts, 1, "manual loan receipt is kept")
    assertEqual(WRL_DB.loanReceipts[1].source, "manual", "remaining receipt is the real loan")
end

local function testClearSimulatedLoansForAccountClearsOneLoanRow()
    local ns = resetHarness()
    WRL_DB.legacyUnlocks.storage = 2

    ns.Loans:RecordTestLoan("Graham-Realm", 1, "graham test")
    ns.Loans:RecordTestLoan("Havok-Realm", 1, "local test")
    ns.Loans:RecordLoan("Grahamalt-Realm", 1, "manual", "real debt")

    local removed = ns.Loans:ClearSimulatedLoansForAccount("acct-graham")
    local rows = ns.Loans:AccountLoanRows()

    assertEqual(removed, 1, "account row clear removes only simulated receipts for that account")
    assertEqual(#WRL_DB.loanReceipts, 2, "other account simulated loan and manual loan remain")
    assertEqual(WRL_DB.loanReceipts[1].accountId, "acct-local", "other account simulated receipt is kept")
    assertEqual(WRL_DB.loanReceipts[2].source, "manual", "manual loan on cleared account is kept")
    local localRow
    for _, row in ipairs(rows) do
        if row.accountId == "acct-local" then
            localRow = row
        end
    end
    assertEqual(localRow and localRow.hasSimulatedLoan, true, "remaining simulated account still exposes row clear capability")
end

local function testDebtIsEnforcedByAccountButAuditedByCharacter()
    local ns = resetHarness()
    WRL_DB.legacyUnlocks.stipend = 3

    ns.Loans:RecordLoan("Graham-Realm", 2, "manual", "first")
    ns.Loans:RecordLoan("Grahamalt-Realm", 2, "manual", "second")
    local cap = ns.Loans:BorrowCapForAccount("acct-graham")

    assertEqual(cap.outstandingCopper, 40000, "same-account characters share one outstanding debt")
    assertEqual(cap.availableCopper, 0, "same-account debt consumes the shared cap")
    assertEqual(WRL_DB.loanReceipts[1].characterKey, "Graham-Realm", "first receipt preserves borrower character")
    assertEqual(WRL_DB.loanReceipts[2].characterKey, "Grahamalt-Realm", "second receipt preserves borrower character")
end

local function testRepaymentConsumesDebtBeforeContributionCredit()
    local ns = resetHarness()
    WRL_DB.legacyUnlocks.storage = 2

    assertTrue(ns.Loans:RecordLoan("Graham-Realm", 2, "manual", "starter loan"), "starter loan records before repayment")
    local receipt = ns.Contributions:Record("Graham-Realm", 5000, "manual", { confidence = "manual" })
    local cap = ns.Loans:BorrowCapForAccount("acct-graham")

    assertEqual(receipt, nil, "full debt repayment does not create a contribution receipt")
    assertEqual(cap.outstandingCopper, 15000, "repayment reduces outstanding debt")
    assertEqual(#WRL_DB.contributionReceipts, 0, "no contribution credit is written before debt is cleared")
    assertEqual(WRL_DB.loanReceipts[2].kind, "repayment", "repayment receipt is stored in loan ledger")
end

local function testOverflowRepaymentCreatesContributionForRemainder()
    local ns = resetHarness()
    WRL_DB.legacyUnlocks.storage = 2

    assertTrue(ns.Loans:RecordLoan("Graham-Realm", 1, "manual", "starter loan"), "starter loan records before overflow repayment")
    local receipt = ns.Contributions:Record("Graham-Realm", 25000, "manual", { confidence = "manual" })
    local cap = ns.Loans:BorrowCapForAccount("acct-graham")

    assertTrue(receipt, "overflow creates a normal contribution receipt")
    assertEqual(receipt.amount, 15000, "only money above repaid debt counts as contribution")
    assertEqual(cap.outstandingCopper, 0, "loan is fully repaid")
    assertEqual(WRL_DB.characters["Graham-Realm"].contributed, 15000, "character contribution total uses overflow only")
    assertEqual(WRL_DB.totalContributed, 15000, "lifetime contribution total uses overflow only")
end

local function testAccountAssignmentBackfillsLoanReceipts()
    local ns = resetHarness()
    WRL_DB.legacyUnlocks.storage = 2
    WRL_DB.accountLinks["Newbie-Realm"] = "acct-local"
    WRL_DB.characters["Newbie-Realm"] = { key = "Newbie-Realm", contributed = 0, history = {} }

    ns.Loans:RecordLoan("Newbie-Realm", 1, "manual", "paperwork")
    local account = ns.Database:AssignCharacterToAccountLabel("Newbie-Realm", "Newbie")

    assertEqual(WRL_DB.loanReceipts[1].accountId, account.id, "assignment backfills loan receipts")
end

testBorrowCapUsesHighestPurchasedLegacyRank()
testBorrowingIsBlockedWhenItExceedsAccountCap()
testSimulatedLoanCanBypassCapForLocalTesting()
testClearSimulatedLoansKeepsManualLoanReceipts()
testClearSimulatedLoansForAccountClearsOneLoanRow()
testDebtIsEnforcedByAccountButAuditedByCharacter()
testRepaymentConsumesDebtBeforeContributionCredit()
testOverflowRepaymentCreatesContributionForRemainder()
testAccountAssignmentBackfillsLoanReceipts()

print("Loans.test.lua: ok")
