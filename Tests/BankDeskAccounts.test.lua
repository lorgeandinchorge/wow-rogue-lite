local function resetHarness()
    WRL_DB = {
        schema = 11,
        bankCharacter = "Bank-Realm",
        totalContributed = 0,
        characters = {
            ["Bank-Realm"] = { key = "Bank-Realm", contributed = 0, history = {} },
            ["Runner-Realm"] = { key = "Runner-Realm", contributed = 0, history = {} },
        },
        requests = {},
        contributionReceipts = {},
        fulfillmentReceipts = {},
    }
    WRL_CharDB = {}

    _G.time = function() return 12345 end
    _G.GetRealmName = function() return "Realm" end
    _G.UnitLevel = function() return 10 end
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    _G.UnitRace = function() return "Human", "HUMAN" end
    _G.UnitGUID = function() return "Player-1" end
    _G.math.random = function() return 4321 end
    _G.NUM_BAG_SLOTS = 0

    local ns = {
        Achievements = nil,
        Database = nil,
        Debug = function() end,
        Print = function() end,
        On = function() end,
        Rewards = {},
        Tiers = {},
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
    assert(loadfile("Core/Contributions.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/Vendor.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/Requests.lua"))("WoWRoguelite", ns)
    ns.Database:Init()
    ns.Contributions:Init()
    return ns
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertContains(line, needle, message)
    if not line or not line:find(needle, 1, true) then
        error(string.format("%s: expected %q to contain %q", message, tostring(line), needle), 2)
    end
end

local function testMigrationCreatesDefaultAccountAndLinksLocalCharacters()
    local ns = resetHarness()

    local accountId = ns.Database:AccountIdForCharacter("Runner-Realm")

    assertEqual(accountId, "acct-local", "local characters migrate to the default account")
    assertEqual(WRL_DB.accounts[accountId].label, "Local Account", "default account has a stable label")
    assertEqual(WRL_DB.accountLinks["Bank-Realm"], "acct-local", "bank character is linked")
end

local function testManualAccountLabelsCanBeCreatedAndLinked()
    local ns = resetHarness()

    local account = ns.Database:CreateAccount("Graham")
    ns.Database:LinkCharacterToAccount("Graham-Realm", account.id)

    assertEqual(ns.Database:AccountIdForCharacter("Graham-Realm"), account.id, "manual account link is stored")
    assertEqual(ns.Database:AccountLabelForCharacter("Graham-Realm"), "Graham", "manual account label resolves")
end

local function testContributionsRecordAndSummarizeByAccount()
    local ns = resetHarness()
    local account = ns.Database:CreateAccount("Graham")
    ns.Database:LinkCharacterToAccount("Graham-Realm", account.id)
    WRL_DB.characters["Graham-Realm"] = { key = "Graham-Realm", generation = 2, levelCurrent = 34, contributed = 0, history = {} }

    local receipt = ns.Contributions:Record("Graham-Realm", 200, "manual", { confidence = "manual" })
    local rows = ns.Database:AccountContributionRows()

    assertEqual(receipt.accountId, account.id, "new contribution receipts store accountId")
    assertEqual(rows[1].accountId, account.id, "summary sorts highest contributor first")
    assertEqual(rows[1].total, 200, "summary rolls contribution into account total")
    assertEqual(rows[1].characters[1].characterKey, "Graham-Realm", "summary preserves character breakdown")
end

local function testContributionsCanSummarizeByCharacter()
    local ns = resetHarness()
    WRL_DB.characters["Graham-Realm"] = { key = "Graham-Realm", generation = 2, levelCurrent = 34, contributed = 0, history = {} }
    WRL_DB.characters["Havok-Realm"] = { key = "Havok-Realm", generation = 1, levelAtCreate = 10, levelCurrent = 12, contributed = 0, history = {} }

    ns.Contributions:Record("Havok-Realm", 100, "manual", { confidence = "manual" })
    ns.Contributions:Record("Graham-Realm", 200, "manual", { confidence = "manual" })
    ns.Contributions:Record("Havok-Realm", 50, "manual", { confidence = "manual" })
    local rows = ns.Database:CharacterContributionRows()

    assertEqual(rows[1].characterKey, "Graham-Realm", "character summary sorts highest contributor first")
    assertEqual(rows[1].generation, 2, "character summary includes generation")
    assertEqual(rows[1].level, 34, "character summary includes current level")
    assertEqual(rows[1].total, 200, "character summary totals one character")
    assertEqual(rows[2].characterKey, "Havok-Realm", "character summary includes local-account contributors by character")
    assertEqual(rows[2].level, 12, "character summary uses current level")
    assertEqual(rows[2].total, 150, "character summary rolls multiple receipts into one character row")
end

local function testAssigningAccountMovesExistingContributionReceipts()
    local ns = resetHarness()
    WRL_DB.characters["Graham-Realm"] = { key = "Graham-Realm", contributed = 0, history = {} }
    ns.Database:LinkCharacterToAccount("Graham-Realm", "acct-local")

    ns.Contributions:Record("Graham-Realm", 200, "manual", { confidence = "manual" })
    local account = ns.Database:AssignCharacterToAccountLabel("Graham-Realm", "Graham")
    local rows = ns.Database:AccountContributionRows()

    assertEqual(WRL_DB.contributionReceipts[1].accountId, account.id, "assignment backfills existing contribution receipts")
    assertEqual(rows[1].accountId, account.id, "summary uses the assigned account for existing receipts")
    assertEqual(rows[1].label, "Graham", "summary label follows the saved account assignment")
end

local function testRecentLedgerUsesUpdatedAccountAssignment()
    local ns = resetHarness()
    WRL_DB.characters["Graham-Realm"] = { key = "Graham-Realm", contributed = 0, history = {} }
    ns.Database:LinkCharacterToAccount("Graham-Realm", "acct-local")

    ns.Contributions:Record("Graham-Realm", 200, "manual", { confidence = "manual" })
    ns.Database:AssignCharacterToAccountLabel("Graham-Realm", "Graham")
    local rows = ns.Database:RecentBankLedgerRows(1)

    assertEqual(rows[1].accountLabel, "Graham", "recent ledger label follows the saved account assignment")
end

local function testRecentLedgerCanBeClearedWithoutDeletingReceipts()
    local ns = resetHarness()
    WRL_DB.characters["Graham-Realm"] = { key = "Graham-Realm", contributed = 0, history = {} }
    WRL_DB.contributionReceipts = {
        { characterKey = "Graham-Realm", amount = 200, when = 100 },
    }

    local before = ns.Database:RecentBankLedgerRows(10)
    ns.Database:ClearRecentBankLedger()
    WRL_DB.contributionReceipts[#WRL_DB.contributionReceipts + 1] = {
        characterKey = "Graham-Realm",
        amount = 300,
        when = 12346,
    }
    local after = ns.Database:RecentBankLedgerRows(10)

    assertEqual(#before, 1, "ledger initially shows existing receipt")
    assertEqual(#WRL_DB.contributionReceipts, 2, "clearing visible ledger does not delete receipts")
    assertEqual(after[1].amount, 300, "ledger shows entries newer than the clear cutoff")
    assertEqual(#after, 1, "ledger hides entries at or before the clear cutoff")
end

local function testRequestsStoreAssignedOrUnassignedAccount()
    local ns = resetHarness()
    local account = ns.Database:CreateAccount("Tester")
    ns.Database:LinkCharacterToAccount("Tester-Realm", account.id)

    ns.Requests:OnIncoming("Tester-Realm", { 101 }, "", "addon", "req-1")
    ns.Requests:OnIncoming("Stranger-Realm", { 101 }, "", "addon", "req-2")

    assertEqual(WRL_DB.requests[1].accountId, account.id, "known requester stores linked account")
    assertEqual(WRL_DB.requests[2].accountId, nil, "unknown requester remains unassigned")
end

testMigrationCreatesDefaultAccountAndLinksLocalCharacters()
testManualAccountLabelsCanBeCreatedAndLinked()
testContributionsRecordAndSummarizeByAccount()
testContributionsCanSummarizeByCharacter()
testAssigningAccountMovesExistingContributionReceipts()
testRecentLedgerUsesUpdatedAccountAssignment()
testRecentLedgerCanBeClearedWithoutDeletingReceipts()
testRequestsStoreAssignedOrUnassignedAccount()

print("BankDeskAccounts.test.lua: ok")
