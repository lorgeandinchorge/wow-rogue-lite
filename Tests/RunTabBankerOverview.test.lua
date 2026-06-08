local function resetHarness()
    WRL_DB = {
        bankCharacter = "Bank-Realm",
        totalContributed = 123456,
        legacySpent = 23456,
        accounts = {
            ["acct-local"] = { id = "acct-local", label = "Local Account", createdAt = 100 },
            ["acct-graham"] = { id = "acct-graham", label = "Graham", createdAt = 101 },
        },
        accountLinks = {
            ["Bank-Realm"] = "acct-local",
            ["Havok-Realm"] = "acct-local",
            ["Graham-Realm"] = "acct-graham",
        },
        characters = {
            ["Bank-Realm"] = { key = "Bank-Realm", generation = 1, levelCurrent = 1, levelAtCreate = 1 },
            ["Havok-Realm"] = { key = "Havok-Realm", generation = 1, levelCurrent = 12, levelAtCreate = 10 },
            ["Graham-Realm"] = { key = "Graham-Realm", generation = 2, levelCurrent = 34, levelAtCreate = 1 },
        },
        contributionReceipts = {
            { characterKey = "Havok-Realm", accountId = "acct-local", amount = 10000, when = 100 },
            { characterKey = "Graham-Realm", accountId = "acct-graham", amount = 20000, when = 101 },
        },
        fulfillmentReceipts = {
            { requester = "Graham-Realm", method = "mail", when = 102, gold = 500, items = {} },
        },
        requests = {
            { id = "req-1", from = "Graham-Realm", status = "pending", accountId = "acct-graham", tierIds = { 101 }, when = 101 },
            { id = "req-2", from = "Havok-Realm", status = "gathering", accountId = "acct-local", tierIds = { 201 }, when = 102 },
            { status = "fulfilled" },
        },
    }
    WRL_CharDB = {}

    _G.GetRealmName = function() return "Realm" end
    _G.GetMoney = function() return 0 end

    local ns = {
        Database = {},
        LegacyUnlocks = {},
        Run = {},
        Tiers = {},
        Requests = {},
        BankResale = {},
        Loans = {},
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns:UnitKey() return "Bank-Realm" end
    function ns:Print() end
    function ns.Database:IsBankCharacter() return true end
    function ns.LegacyUnlocks:AvailableBudget() return 100000 end
    function ns.Run:GetState(rec) return rec and rec.status or "unknown" end
    function ns.Tiers:FormatMoney(copper) return tostring(copper) .. "c" end
    function ns.Database:AccountLabel(accountId)
        return WRL_DB.accounts[accountId] and WRL_DB.accounts[accountId].label or "Unassigned"
    end
    function ns.Database:AccountContributionRows()
        return {
            {
                accountId = "acct-graham",
                label = "Graham",
                total = 20000,
                percent = 66.7,
                characters = {
                    { characterKey = "Graham-Realm", total = 20000 },
                },
            },
            {
                accountId = "acct-local",
                label = "Local Account",
                total = 10000,
                percent = 33.3,
                characters = {
                    { characterKey = "Havok-Realm", total = 10000 },
                },
            },
        }
    end
    function ns.Database:CharacterContributionRows()
        return {
            { characterKey = "Graham-Realm", generation = 2, level = 34, total = 20000, percent = 66.7 },
            { characterKey = "Havok-Realm", generation = 1, level = 12, total = 10000, percent = 33.3 },
        }
    end
    function ns.Database:RecentBankLedgerRows()
        return {
            { kind = "fulfillment", characterKey = "Graham-Realm", accountLabel = "Graham", amount = 500, method = "mail", when = 102 },
            { kind = "loan_borrow", characterKey = "Graham-Realm", accountLabel = "Graham", amount = 10000, when = 103 },
            { kind = "resale", characterKey = "Graham-Realm", accountLabel = "Graham", amount = 125, itemName = "Chunk of Boar Meat", qty = 5, priceLabel = "TSM", when = 104 },
        }
    end
    function ns.Database:BankerSummary()
        return {
            pendingRequests = 2,
            readyRequests = 1,
            missingItemLines = 1,
            resaleRows = 2,
            outstandingLoanCopper = 10000,
            recentLedgerRows = 3,
            pricingStatus = "Pricing: TSM unavailable; using fallback labels when needed.",
        }
    end
    function ns.Database:BankerSummaryLines()
        return {
            "Requests: 2 pending / 1 ready",
            "Missing item lines: 1",
            "Resale rows: 2",
            "Outstanding loans: 1g",
            "Recent ledger rows: 3",
            "Pricing: TSM unavailable; using fallback labels when needed.",
        }
    end
    function ns.Database:AccountBankingSummaryRows()
        return {
            {
                accountId = "acct-local",
                isLocalAccount = true,
                characters = {
                    { characterKey = "Havok-Realm" },
                },
                label = "Local Account",
                contributedCopper = 819,
                outstandingCopper = 0,
                availableCopper = 0,
                resaleCopper = 400,
                fulfillmentCount = 8,
            },
            {
                accountId = "unassigned",
                isUnassigned = true,
                characters = {
                    { characterKey = "Tester-Realm" },
                },
                label = "Unassigned",
                contributedCopper = 0,
                outstandingCopper = 0,
                availableCopper = 0,
                resaleCopper = 775,
                fulfillmentCount = 0,
            },
            {
                accountId = "acct-graham",
                label = "Graham",
                contributedCopper = 20000,
                outstandingCopper = 10000,
                availableCopper = 20000,
                resaleCopper = 125,
                fulfillmentCount = 1,
            },
        }
    end
    function ns.Loans:BorrowCapForCharacter()
        return { capCopper = 30000, outstandingCopper = 10000, availableCopper = 20000, highestRank = 2 }
    end
    function ns.Loans:AccountLoanRows()
        return {
            {
                accountId = "acct-graham",
                label = "Graham",
                characterKey = "Graham-Realm",
                capCopper = 30000,
                outstandingCopper = 10000,
                availableCopper = 20000,
                latestWhen = 103,
                latestKind = "borrow",
            },
        }
    end
    function ns.Loans:FormatGold(copper)
        return tostring(math.floor((copper or 0) / 10000)) .. "g"
    end
    function ns.Loans:ClearSimulatedLoans()
        self.clearedSimLoans = true
        return 1
    end
    function ns.Loans:ClearSimulatedLoansForAccount(accountId)
        self.clearedLoanAccount = accountId
        return 1
    end
    function ns.BankResale:InventoryRows()
        return {
            { itemId = 769, name = "Chunk of Boar Meat", count = 5, priceEach = 25, totalCopper = 125 },
            { itemId = 723, name = "Goretusk Liver", count = 1, priceEach = 50, totalCopper = 50 },
        }
    end
    function ns.BankResale:RecordSale(itemId, qty, buyer)
        self.recordedSale = { itemId = itemId, qty = qty, buyer = buyer, totalCopper = (qty or 0) * 25 }
        return self.recordedSale
    end
    function ns.BankResale:PrepareCODMail(itemId, qty, buyer)
        self.preparedCOD = { itemId = itemId, qty = qty, buyer = buyer }
        self.pendingCOD = self.preparedCOD
        return self.preparedCOD
    end
    function ns.BankResale:ClearSimulatedStock()
        self.clearedSimStock = true
        self.pendingCOD = nil
        return true
    end
    function ns.BankResale:DismissInventoryStock(itemId, qty)
        self.dismissedStock = { itemId = itemId, qty = qty }
        return true
    end
    function ns.BankResale:DismissVisibleInventoryStock(rows)
        self.dismissedVisibleRows = rows
        return #(rows or {})
    end
    function ns.BankResale:RemoveSimulatedStock(itemId)
        self.removedSimStock = itemId
        return true
    end
    function ns.BankResale:SimulatedBuyer()
        return self.simulatedBuyer
    end
    function ns.Requests:BankRequestRows()
        return WRL_DB.requests
    end
    function ns.Requests:FulfillmentReadiness(req)
        if req and req.id == "req-1" then
            return {
                fulfillable = false,
                requiredGold = 1200,
                availableGold = 500,
                missingItems = {
                    { name = "Banker's Thread", required = 2, available = 0, missing = 2 },
                },
                items = {
                    { name = "Banker's Thread", required = 2, available = 0, missing = 2 },
                    { name = "Clerk's Potion", required = 3, available = 3, missing = 0 },
                },
            }
        end
        return {
            fulfillable = true,
            requiredGold = 500,
            availableGold = 1000,
            missingItems = {},
            items = {
                { name = "Runner's Bag", required = 2, available = 2, missing = 0 },
            },
        }
    end
    function ns.Requests:NeededSupplyRows()
        return {
            {
                itemId = 4496,
                name = "Small Brown Pouch",
                required = 3,
                available = 1,
                missing = 2,
                requests = 2,
                craftHint = "tailor-made",
                marketCopper = 1234,
                marketLabel = "TSM DBMarket",
            },
        }
    end
    function ns.Requests:NeededSupplyLines()
        return {
            "Small Brown Pouch: requested 3 / available 1 / missing 2 / requests 2 (tailor-made; TSM DBMarket 1234c)",
        }
    end

    assert(loadfile("UI/Tab_Run.lua"))("WoWRoguelite", ns)
    ns.Tab_Run._testNS = ns
    return ns.Tab_Run
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

local function assertNotContains(line, needle, message)
    if line and line:find(needle, 1, true) then
        error(string.format("%s: expected %q not to contain %q", message, tostring(line), needle), 2)
    end
end

local function testBankerOverviewReplacesRunSnapshotCopy()
    local tab = resetHarness()

    local left, right = tab:_BuildBankerOverviewLines("Bank-Realm")

    assertContains(left[1], "Name:", "banker overview starts with character identity")
    assertContains(left[4], "Realm: Realm", "banker overview includes realm")
    assertContains(left[5], "bank infrastructure", "banker overview names the bank run state")
    assertContains(left[6], "Lives remaining: n/a", "banker overview avoids runner life accounting")

    assertEqual(right[1], "|cffc0a060Requisitions Desk|r", "right pane starts with Requisitions Desk heading")
    local allRight = table.concat(right, "\n")
    assertContains(allRight, "|cffc0a060Banker Summary|r", "right pane includes compact banker summary")
    assertContains(allRight, "Requests: 2 pending / 1 ready", "banker summary shows request readiness counts")
    assertContains(allRight, "Missing item lines: 1", "banker summary shows missing item count")
    assertContains(allRight, "Resale rows: 2", "banker summary shows active resale rows")
    assertContains(allRight, "Outstanding loans: 1g", "banker summary shows outstanding loan total")
    assertContains(allRight, "Pricing: TSM unavailable", "banker summary shows pricing source status")
    assertContains(allRight, "Who", "bank desk table includes requester header")
    assertContains(allRight, "Account", "bank desk table includes account header")
    assertContains(allRight, "Ready", "bank desk table includes readiness header")
    assertContains(allRight, "Graham-Realm", "bank desk table lists active requester")
    assertContains(allRight, "Havok-Realm", "bank desk table lists the next requester")
    assertContains(allRight, "|cffc0a060Needed Supplies|r", "right pane includes aggregate needed supplies")
    assertContains(allRight, "Small Brown Pouch", "needed supplies lists aggregate starter-kit items")
    assertContains(allRight, "|cffc0a060Account Summary|r", "right pane includes account-level banking summary")
    assertContains(allRight, "Contrib", "account summary uses contribution column")
    assertContains(allRight, "Debt", "account summary uses debt column")
    assertContains(allRight, "Resale", "account summary uses resale column")
    assertContains(allRight, "|cffc0a060Contribution Board|r", "right pane includes contribution board")
    assertContains(allRight, "Character", "contribution board is grouped by character")
    assertContains(allRight, "|cffc0a060Loans Desk|r", "right pane includes loans desk")
    assertContains(allRight, "Account", "loans desk includes table header")
    assertContains(allRight, "Borrower", "loans desk includes borrower column")
    assertContains(allRight, "Graham", "loans desk lists borrower account")
    assertContains(allRight, "1g", "loans desk lists outstanding debt in gold")
    assertContains(allRight, "|cffc0a060Resale Desk|r", "right pane includes resale desk")
    assertContains(allRight, "Chunk of Boar Meat", "resale desk lists catalog inventory")
    assertContains(allRight, "Goretusk Liver", "resale desk lists additional catalog inventory")
    assertContains(allRight, "ledger", "right pane includes ledger heading")
    assertContains(allRight, "Time", "recent ledger uses a table header")
    assertContains(allRight, "Type", "recent ledger uses a type column")
    assertContains(allRight, "Amount", "recent ledger uses an amount column")
    assertContains(allRight, "TSM", "recent ledger exposes resale price source labels")
end

local function testRunnerDashboardShowsLoanSummary()
    local tab = resetHarness()
    tab._testNS.Multiplayer = {
        DashboardLines = function()
            return {
                "|cffc0a060Team Pulse|r",
                "Team: 1 nearby | 1 ready / 0 warning / 0 unknown | 1 signal",
                " - Friend lvl 31 | 2 lives | active",
            }
        end,
    }
    local lines = tab:_BuildCharacterOverviewLines("Graham-Realm", WRL_DB.characters["Graham-Realm"])
    local text = table.concat(lines, "\n")

    assertContains(text, "Loan cap:", "runner dashboard shows loan cap")
    assertContains(text, "Outstanding loan:", "runner dashboard shows outstanding debt")
    assertContains(text, "Borrow available:", "runner dashboard shows available borrow amount")
    assertContains(text, "1g", "runner dashboard renders loan values in gold")
    assertContains(text, "|cffc0a060Team Pulse|r", "runner dashboard includes co-op section")
    assertContains(text, "Team: 1 nearby", "runner dashboard includes co-op roster summary")
end

local function testRunnerSnapshotShowsRecentOutgoingRequestStatuses()
    local tab = resetHarness()
    WRL_CharDB.outgoing = {
        {
            id = "req-1",
            when = 100,
            bank = "Bank-Realm",
            tierIds = { 101, 201 },
            status = "sent",
        },
        {
            id = "req-2",
            when = 120,
            bank = "Bank-Realm",
            tierIds = { 301 },
            status = "confirmed",
            verificationStatus = "confirmed",
        },
        {
            id = "req-3",
            when = 110,
            bank = "Altbank-Realm",
            tierIds = { 401 },
            status = "needs_review",
            reviewReason = "invalid_banker",
        },
    }

    local lines = tab:_BuildCharacterSnapshotLines("Graham-Realm", WRL_DB.characters["Graham-Realm"])
    local text = table.concat(lines, "\n")

    assertContains(text, "Recent outgoing requests:", "runner snapshot names outgoing request history")
    assertContains(text, "301 | confirmed | Bank", "runner snapshot shows latest confirmed request")
    assertContains(text, "401 | needs review (invalid_banker) | Altbank", "runner snapshot shows review context")
    assertContains(text, "101, 201 | sent | Bank", "runner snapshot keeps older sent request visible")
end

local function testContributionActionOnlyShowsForPendingContributionRuns()
    local tab = resetHarness()

    assertEqual(tab:_ShouldShowContributionAction({ status = "dead_pending_contribution" }), true,
        "pending final contribution shows recovery action")
    assertEqual(tab:_ShouldShowContributionAction({ status = "active" }), false,
        "active runs do not show contribution recovery action")
    assertEqual(tab:_ShouldShowContributionAction({ status = "retired" }), false,
        "fully retired runs do not show contribution recovery action")
end

local function testContributionBoardShowsLocalAccountContributionsByCharacter()
    local tab = resetHarness()
    tab._testNS.Database.CharacterContributionRows = function()
        return {
            {
                characterKey = "Havok-Realm",
                generation = 1,
                level = 12,
                total = 819,
                percent = 100,
            },
        }
    end
    WRL_DB.accountLinks["Graham-Realm"] = nil
    WRL_DB.requests = {}

    local _, right = tab:_BuildBankerOverviewLines("Bank-Realm")
    local text = table.concat(right, "\n")
    local contributionText = text:match("|cffc0a060Contribution Board|r(.-)|cffc0a060Loans Desk|r") or text

    assertContains(text, "|cffc0a060Contribution Board|r", "contribution board still renders")
    assertContains(contributionText, "Havok-Realm", "default-account contributions render as character rows")
    assertContains(contributionText, "819c", "default-account contributions keep their amount")
    assertNotContains(contributionText, "Local Account", "contribution board should not show account labels")
end

local function testAccountAssignmentTextAssignsCharacterAndRequest()
    local tab = resetHarness()
    WRL_DB.requests = {
        { id = "req-1", from = "Havok-Realm", status = "pending", tierIds = { 201 }, when = 102 },
    }
    tab._testNS.Database.AssignCharacterToAccountLabel = function(_, characterKey, label)
        tab._assignedAccount = { characterKey = characterKey, label = label }
        return { id = "acct-havok", label = label }
    end

    local account = tab:_AssignAccountFromText("Havok-Realm Havok")

    assertEqual(account.id, "acct-havok", "assignment text creates/links the named account")
    assertEqual(tab._assignedAccount.characterKey, "Havok-Realm", "assignment text preserves the character key")
    assertEqual(tab._assignedAccount.label, "Havok", "assignment text preserves the account label")
    assertEqual(WRL_DB.requests[1].accountId, "acct-havok", "assignment updates matching pending requests")
end

local function testAccountSummaryRowAssignmentTargetsSingleUnassignedCharacter()
    local tab = resetHarness()
    local prompted = nil
    tab.PromptAssignAccount = function(_, req)
        prompted = req
    end

    tab:PromptAssignAccountRow({
        isUnassigned = true,
        characters = {
            { characterKey = "Tester-Realm" },
        },
    })

    assertEqual(prompted.from, "Tester-Realm", "single unassigned character opens targeted assignment prompt")
end

local function testAccountSummaryRowAssignmentFallsBackForMultipleCharacters()
    local tab = resetHarness()
    local manual = false
    tab.PromptAssignAccountEntry = function()
        manual = true
    end

    tab:PromptAssignAccountRow({
        isUnassigned = true,
        characters = {
            { characterKey = "Tester-Realm" },
            { characterKey = "Alt-Realm" },
        },
    })

    assertEqual(manual, true, "multi-character unassigned row opens manual assignment prompt")
end

local function testBankDeskActionButtonsAreDashboardOwned()
    local f = assert(io.open("UI/Tab_Run.lua", "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()

    assertContains(src, "ensureBankDeskButtons", "Bank Desk should own row-level action buttons")
    assertContains(src, "createBankDeskTableRow", "Bank Desk should render fixed table columns")
    assertContains(src, "button.who:SetPoint(\"LEFT\", button, \"LEFT\", 0, 0)", "Bank Desk Who column should have a fixed x position")
    assertContains(src, "button.gold:SetJustifyH(\"RIGHT\")", "Bank Desk gold column should right-align")
    assertContains(src, "button.items:SetJustifyH(\"RIGHT\")", "Bank Desk item count column should right-align")
    assertContains(src, "setBankDeskSection(self.bankDeskSection", "Bank Desk should render through selectable row controls")
    assertContains(src, "button.mailButton = createInlineIconButton(section, \"mail\", \"Interface\\\\Icons\\\\INV_Letter_15\")", "Bank Desk rows should include an inline mail icon action")
    assertContains(src, "button.doneButton = createInlineIconButton(section, \"done\", \"Interface\\\\RaidFrame\\\\ReadyCheck-Ready\")", "Bank Desk rows should include an inline fulfill checkmark action")
    assertContains(src, "button.accountButton = createInlineIconButton(section, \"A\", nil, 22)", "Bank Desk rows should include an inline account assignment action")
    assertContains(src, "button.mailButton = createInlineIconButton(section, \"mail\", \"Interface\\\\Icons\\\\INV_Letter_15\")", "Resale Desk rows should include an inline mail icon action")
    assertContains(src, "button.soldButton = createInlineIconButton(section, \"sold\", \"Interface\\\\RaidFrame\\\\ReadyCheck-Ready\")", "Resale Desk rows should include an inline checkmark sold action")
    assertContains(src, "button.cancelButton = createInlineIconButton(section, \"cancel\", \"Interface\\\\RaidFrame\\\\ReadyCheck-NotReady\")", "Resale Desk rows should include an inline red X cancel action")
    assertContains(src, "action.icon:SetTexture(texturePath)", "mail action should use an icon texture instead of a text glyph")
    assertContains(src, "owner:PromptResaleCOD(row)", "Resale row mail action should prepare COD for that row")
    assertContains(src, "owner:_RecordResaleRow(row)", "Resale row sold action should record that row")
    assertContains(src, "owner:_CancelResaleRow(row)", "Resale row cancel action should cancel pending resale work")
    assertContains(src, "ns.Requests:BeginMailFulfillment(req.id)", "bank desk mail action should prepare mail for the row request")
    assertContains(src, "ns.Requests:MarkFulfilled(req.id)", "bank desk fulfill action should mark the row request fulfilled")
    assertContains(src, "owner:PromptAssignAccount(req)", "bank desk account action should assign the row requester")
    assertContains(src, "self.bankContributionSection:SetPoint(\"TOPLEFT\", self.bankSnapshotSection, \"TOPRIGHT\", 10, 0)", "contribution board should sit next to bank snapshot")
end

local function testBankDeskCanSelectResaleRowsByClickTarget()
    local tab = resetHarness()

    assertEqual(tab:_ActiveResaleRow().itemId, 769, "first resale row starts active")
    tab:_SelectResaleRow(2)
    assertEqual(tab:_ActiveResaleRow().itemId, 723, "clicked resale row becomes active")
    tab:_SelectResaleRow(99)
    assertEqual(tab:_ActiveResaleRow().itemId, 723, "invalid resale click keeps current active row")
end

local function testSelectedResaleOrderDoesNotDefaultUnmatchedRequester()
    local tab = resetHarness()

    local order = tab:_SelectResaleRow(1)

    assertEqual(order.itemId, 769, "selected resale order keeps the item")
    assertEqual(order.qty, 5, "selected resale order defaults to the full row quantity")
    assertEqual(order.buyer, nil, "unmatched resale stock should not default to the active requester")

    order = tab:_SelectResaleRow(1)
    tab:PromptResaleCOD(order)
    tab:_CancelResaleRow(order)
    assertEqual(tab.pendingResaleOrder, nil, "cancel clears selected resale order")
    assertEqual(tab._testNS.BankResale.pendingCOD, nil, "cancel clears pending COD draft")
end

local function testCancelResaleRowRemovesSimulatedStockLine()
    local tab = resetHarness()
    local row = tab:_ResaleRows()[1]
    row.simulated = true

    tab:_CancelResaleRow(row)

    assertEqual(tab._testNS.BankResale.removedSimStock, 769, "cancel removes the simulated stock line")
end

local function testCancelResaleRowDismissesRealInventoryLine()
    local tab = resetHarness()
    local row = tab:_ResaleRows()[1]

    tab:_CancelResaleRow(row)

    assertEqual(tab._testNS.BankResale.dismissedStock.itemId, 769, "cancel dismisses the real inventory item")
    assertEqual(tab._testNS.BankResale.dismissedStock.qty, 5, "cancel dismisses the visible owned quantity")
    assertEqual(tab.pendingResaleOrder, nil, "cancel clears any selected resale order")
end

local function testSelectedResaleOrderUsesRequestedQuantityWhenRequestMatchesItem()
    local tab = resetHarness()
    tab._testNS.Requests.FulfillmentReadiness = function(_, req)
        return {
            items = {
                { id = 769, name = "Chunk of Boar Meat", required = 3, available = 5, missing = 0 },
            },
            missingItems = {},
            requiredGold = 0,
            availableGold = 0,
            fulfillable = true,
        }
    end

    local order = tab:_SelectResaleRow(1)
    tab:PromptResaleCOD(order)

    assertEqual(order.buyer, "Graham-Realm", "matching resale order uses active requester name")
    assertEqual(order.qty, 3, "matching resale order uses requested quantity instead of owned count")
    assertEqual(tab._lastResaleCOD.buyer, "Graham-Realm", "COD draft receives active requester name")
    assertEqual(tab._lastResaleCOD.qty, 3, "COD draft receives requested item quantity")
end

local function testResaleRowWithoutMatchingRequestDoesNotRecreatePhantomOrder()
    local tab = resetHarness()

    local order = tab:_SelectResaleRow(1)
    tab:_CancelResaleRow(tab:_ResaleRows()[1])
    local rebuilt = tab:_BuildResaleOrder(tab:_ResaleRows()[1])

    assertEqual(order.buyer, nil, "unrequested resale stock should not default to the active bank requester")
    assertEqual(order.qty, 5, "unrequested resale stock should keep the owned count")
    assertEqual(rebuilt.buyer, nil, "refresh should not recreate a phantom buyer after row cancel")
end

local function testResaleCODRehydratesStaleSelectionWithRequester()
    local tab = resetHarness()
    WRL_DB.requests[1].from = "Tester-Realm"
    tab._testNS.Requests.FulfillmentReadiness = function(_, req)
        return {
            items = {
                { id = 769, name = "Chunk of Boar Meat", required = 5, available = 5, missing = 0 },
            },
            missingItems = {},
            requiredGold = 0,
            availableGold = 0,
            fulfillable = true,
        }
    end
    tab.pendingResaleOrder = {
        itemId = 769,
        name = "Chunk of Boar Meat",
        itemName = "Chunk of Boar Meat",
        qty = 1,
        priceEach = 25,
        totalCopper = 25,
    }

    tab:PromptResaleCOD(tab:_ResaleRows()[1])

    assertEqual(tab._lastResalePrompted, nil, "stale resale selection should not prompt once requester is known")
    assertEqual(tab._lastResaleCOD.buyer, "Tester-Realm", "stale resale selection reuses the current requester")
    assertEqual(tab._lastResaleCOD.qty, 5, "stale resale selection refreshes to the current requested quantity")
end

local function testResaleCODUsesSimulatedBuyerWithoutBankRequest()
    local tab = resetHarness()
    for _, req in ipairs(WRL_DB.requests) do
        req.status = "fulfilled"
    end
    tab._testNS.BankResale.simulatedBuyer = "Tester-Realm"

    local order = tab:_SelectResaleRow(1)
    tab:PromptResaleCOD(order)

    assertEqual(tab._lastResalePrompted, nil, "simulated resale buyer should avoid the manual buyer prompt")
    assertEqual(tab._lastResaleCOD.buyer, "Tester-Realm", "resale sim uses its private buyer without creating a bank request")
end

local function testResaleDeskClearAllClearsSimulatedRowsAndSelection()
    local tab = resetHarness()
    local order = tab:_SelectResaleRow(1)
    tab:PromptResaleCOD(order)

    tab:_ClearResaleDesk()

    assertEqual(tab._testNS.BankResale.clearedSimStock, true, "clear all calls simulated stock cleanup")
    assertEqual(#tab._testNS.BankResale.dismissedVisibleRows, 2, "clear all dismisses visible inventory rows")
    assertEqual(tab.pendingResaleOrder, nil, "clear all removes selected resale order")
    assertEqual(tab._testNS.BankResale.pendingCOD, nil, "clear all removes pending COD draft")
    assertEqual(tab.bankResaleIndex, 1, "clear all resets resale selection")
end

local function testBankDeskCanCycleActiveRequests()
    local tab = resetHarness()

    assertEqual(tab:_ActiveBankRequest().id, "req-1", "first actionable request starts active")
    tab:_AdvanceBankRequest()
    assertEqual(tab:_ActiveBankRequest().id, "req-2", "next request advances active selection")
    tab:_AdvanceBankRequest()
    assertEqual(tab:_ActiveBankRequest().id, "req-1", "next request wraps around")
end

local function testLoansDeskRowClearClearsOneSimulatedRow()
    local tab = resetHarness()

    tab:_ClearLoanRow("acct-graham")

    assertEqual(tab._testNS.Loans.clearedLoanAccount, "acct-graham", "loans row clear removes simulated rows for one account")
end

local function testEmptyBankDeskMessageSitsUnderHeader()
    local tab = resetHarness()
    for _, req in ipairs(WRL_DB.requests) do
        req.status = "fulfilled"
    end

    local _, right = tab:_BuildBankerOverviewLines("Bank-Realm")

    assertEqual(right[1], "|cffc0a060Requisitions Desk|r", "right pane starts with Requisitions Desk heading")
    assertContains(right[2], "No pending bank requests", "empty bank desk message sits directly under the header")
    assertContains(right[3], "Mailbox work", "mailbox empty-state follows the no-pending line")
end

local function testBankDeskUsesBorderedSectionsWithStrongHeadings()
    local f = assert(io.open("UI/Tab_Run.lua", "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    local tocFile = assert(io.open("WoWRoguelite.toc", "rb"))
    local toc = tocFile:read("*a"):gsub("\r\n", "\n")
    tocFile:close()

    assertContains(toc, "Core/BankResale.lua", "TOC should load the BankResale module")
    assertContains(src, "CreateFrame(\"Frame\", nil, content)", "Bank Desk sections should be framed in the scroll content")
    assertContains(src, "Theme:Fill(section, Theme.c.bg1, true, \"panel\")", "Bank Desk sections should use light panel borders")
    assertContains(src, "section.borderLeft", "Bank Desk sections should have a full light left border")
    assertContains(src, "section.borderRight", "Bank Desk sections should have a full light right border")
    assertContains(src, "title:SetFont(STANDARD_TEXT_FONT", "Bank Desk section headings should be stronger than body text")
    assertContains(src, "Theme:Text(section, 13, Theme.c.goldH)", "Bank Desk section headings should be larger for scanning")
    assertContains(src, "Theme:Text(section, 11, Theme.c.fg2)", "Bank Desk section body text should be larger for readability")
    assertContains(src, "self.bankDeskSection", "Bank Desk should have its own right-side section")
    assertContains(src, "self.bankContributionSection", "Contribution Board should have its own right-side section")
    assertContains(src, "self.bankSummarySection", "Banker Summary should have its own full-width section")
    assertContains(src, "self.bankNeededSection", "Needed Supplies should have its own full-width section")
    assertContains(src, "self.bankAccountSection", "Account Summary should have its own full-width section")
    assertContains(src, "ensureAccountRows", "Account Summary should render with dedicated row frames")
    assertNotContains(src, "section.assignAccountButton", "Account Summary should not expose a blind header assignment button")
    assertContains(src, "row.assignButton", "Account Summary unassigned rows should expose row-level assignment")
    assertContains(src, "owner:PromptAssignAccountRow(row)", "Account Summary assign button should target its row")
    assertContains(src, "row.renameButton", "Account Summary local account rows should expose row-level rename")
    assertContains(src, "owner:PromptRenameLocalAccount(row.accountId)", "Account Summary rename button should target the local account row")
    assertContains(src, "setAccountSection(self.bankAccountSection", "Account Summary should use a real column renderer")
    assertContains(src, "row.account:SetPoint(\"LEFT\", row, \"LEFT\", 0, 0)", "Account Summary account column should have a fixed x position")
    assertContains(src, "row.contrib:SetJustifyH(\"RIGHT\")", "Account Summary contribution column should right-align")
    assertContains(src, "row.debt:SetJustifyH(\"RIGHT\")", "Account Summary debt column should right-align")
    assertContains(src, "row.avail:SetJustifyH(\"RIGHT\")", "Account Summary available column should right-align")
    assertContains(src, "row.resale:SetJustifyH(\"RIGHT\")", "Account Summary resale column should right-align")
    assertContains(src, "row.fulfill:SetJustifyH(\"RIGHT\")", "Account Summary fulfillment column should right-align")
    assertContains(src, "self.bankLoansSection", "Loans Desk should have its own right-side section")
    assertContains(src, "self.bankResaleSection", "Resale Desk should have its own right-side section")
    assertContains(src, "self.bankLedgerSection", "Recent ledger should have its own right-side section")
    assertContains(src, "buildBankSection(content, Theme, \"Contribution Board\")", "Contribution Board should have a strong section heading")
    assertContains(src, "ensureContributionRows", "Contribution Board should render with dedicated row frames")
    assertContains(src, "setContributionSection(self.bankContributionSection", "Contribution Board should use a real column renderer")
    assertContains(src, "row.character:SetPoint(\"LEFT\", row, \"LEFT\", 24, 0)", "Contribution Board character column should have a fixed x position")
    assertContains(src, "row.gen:SetPoint(\"LEFT\", row, \"LEFT\", 184, 0)", "Contribution Board generation column should have a fixed x position")
    assertContains(src, "row.total:SetJustifyH(\"RIGHT\")", "Contribution Board money column should right-align")
    assertContains(src, "row.share:SetJustifyH(\"RIGHT\")", "Contribution Board share column should right-align")
    assertContains(src, "buildBankSection(content, Theme, \"Resale Desk\")", "Resale Desk should have a strong section heading")
    assertContains(src, "buildBankSection(content, Theme, \"Loans Desk\")", "Loans Desk should have a strong section heading")
    assertContains(src, "createLoanTableRow", "Loans Desk should render fixed table columns")
    assertContains(src, "button.debt:SetJustifyH(\"RIGHT\")", "Loans Desk debt column should right-align")
    assertContains(src, "button.avail:SetJustifyH(\"RIGHT\")", "Loans Desk available column should right-align")
    assertContains(src, "section.loanClearButtons", "Loans Desk should include row clear buttons")
    assertContains(src, "button:SetPoint(\"LEFT\", rowFrame, \"RIGHT\", BANK_ROW_ACTION_GAP, 0)", "Loans Desk row clear buttons should sit inside the section edge")
    assertContains(src, "owner:_ClearLoanRow(row.accountId)", "Loans Desk clear should target one account row")
    assertContains(src, "ns.Loans:ClearSimulatedLoansForAccount(accountId)", "Loans Desk clear should remove simulated loan receipts only for one account")
    assertContains(src, "setResaleSection(self.bankResaleSection", "Resale Desk should render through selectable row controls")
    assertContains(src, "createResaleTableRow", "Resale Desk should render fixed table columns")
    assertContains(src, "button.req:SetJustifyH(\"RIGHT\")", "Resale Desk requested quantity should right-align")
    assertContains(src, "button.own:SetJustifyH(\"RIGHT\")", "Resale Desk owned quantity should right-align")
    assertContains(src, "button.total:SetJustifyH(\"RIGHT\")", "Resale Desk total column should right-align")
    assertContains(src, "Columns: Time | Type | Who | Account | Amount | Detail", "Recent Ledger fallback text should label columns with separators")
    assertContains(src, "resaleTableHeader", "Resale Desk should render as a compact table")
    assertContains(src, "\"Who\"", "Resale Desk table should expose requester names")
    assertContains(src, "Req", "Resale Desk table should expose requested quantity")
    assertContains(src, "Own", "Resale Desk table should expose owned quantity")
    assertContains(src, "section.clearResaleButton", "Resale Desk should include a top-right clear all button")
    assertContains(src, "button.text:SetText(\"x\")", "Resale Desk clear all should use a distinct white x instead of the red cancel icon")
    assertContains(src, "owner:ConfirmClearResaleDesk()", "Resale Desk clear all button should ask before clearing rows")
    assertContains(src, "StaticPopupDialogs[\"WRL_CLEAR_RESALE_DESK\"]", "Resale Desk clear all should use a confirmation popup")
    assertContains(src, "section.resaleButtons", "Resale Desk should create clickable row targets")
    assertContains(src, "button.selection:SetColorTexture", "selected resale rows should have a full-line highlight texture")
    assertContains(src, "local BANK_SCROLLBAR_GUTTER = 38", "bank dashboard should reserve an inside scrollbar gutter")
    assertContains(src, "local BANK_SECTION_WIDTH = BANK_DASHBOARD_WIDTH - BANK_SCROLLBAR_GUTTER", "bank sections should end before the scrollbar gutter")
    assertContains(src, "local BANK_ROW_ACTION_GAP = 10", "bank row actions should use a shared gap from row text")
    assertContains(src, "local BANK_ROW_TARGET_WIDTH = BANK_SECTION_WIDTH - 196", "bank desk row actions should stay inside the scrollbar gutter")
    assertContains(src, "local BANK_RESALE_ROW_TARGET_WIDTH = BANK_SECTION_WIDTH - 136", "Resale Desk row actions should start to the right of the Total column")
    assertContains(src, "local BANK_RESALE_SECTION_BOTTOM_PADDING = 14", "Resale Desk should reserve bottom padding below the last action row")
    assertContains(src, "local BANK_CLEAR_BUTTON_RIGHT_INSET = -(BANK_SCROLLBAR_GUTTER + 8)", "clear button should share the bank dashboard gutter")
    assertContains(src, "button:SetSize(BANK_ROW_TARGET_WIDTH, 18)", "selected resale row highlight should leave room for requester names and inline action buttons")
    assertContains(src, "button:SetSize(BANK_RESALE_ROW_TARGET_WIDTH, 18)", "selected resale rows should reserve enough width before inline action buttons")
    assertContains(src, "button:SetSize(BANK_ROW_TARGET_WIDTH, 18)", "bank desk row targets should share the right-safe action width")
    assertContains(src, "button:SetPoint(\"TOPRIGHT\", section, \"TOPRIGHT\", BANK_CLEAR_BUTTON_RIGHT_INSET, -8)", "Resale Desk clear all should sit inside the scrollbar gutter")
    assertContains(src, "button:SetPoint(\"TOPLEFT\", prev, \"BOTTOMLEFT\", 0, -4)", "selected resale row highlight should align to the visible table row")
    assertContains(src, "button.mailButton:SetPoint(\"LEFT\", button, \"RIGHT\", BANK_ROW_ACTION_GAP, 0)", "resale row actions should align vertically to the selected row")
    assertContains(src, "local resaleHeight = math.max(72, 46 + (shownRows * 22) + BANK_RESALE_SECTION_BOTTOM_PADDING)", "Resale Desk bottom border should expand below visible action rows")
    assertContains(src, "button.selection:Show()", "active resale row should show its full-line highlight")
    assertContains(src, "local keepScroll = self.scroll and self.scroll.GetVerticalScroll", "banker refresh should preserve scroll position")
    assertContains(src, "self.scroll:SetVerticalScroll(keepScroll)", "banker refresh should restore scroll after row selection")
    assertContains(src, "Tab:_SelectResaleRow", "Resale row targets should select the active resale row")
    assertContains(src, "buildLedgerSection(content, Theme)", "Recent Ledger should use its own specialized section")
    assertContains(src, "createLedgerTableRow", "Recent Ledger should render fixed table columns")
    assertContains(src, "LEDGER_COLUMNS", "Recent Ledger columns should be defined in one fixed column spec")
    assertContains(src, "row.dividers", "Recent Ledger should draw visible separators between columns")
    assertContains(src, "SetColorTexture", "Recent Ledger separators should be real UI textures, not spacing in formatted text")
    assertNotContains(src, "local ledgerTableHeader = string.format", "Recent Ledger should not depend on formatted text spacing for its table")
    assertContains(src, "row.amount:SetJustifyH(\"RIGHT\")", "Recent Ledger amount column should right-align")
    assertContains(src, "CreateFrame(\"EditBox\"", "Recent Ledger should include search input")
    assertContains(src, "ledger.searchBox:SetScript(\"OnTextChanged\"", "Recent Ledger search should refresh results")
    assertContains(src, "Theme:ScrollArea(ledger)", "Recent Ledger should have an inner scrollable surface")
    assertContains(src, "ledger.searchBox:SetSize(180, 18)", "Recent Ledger search box should stay compact")
    assertContains(src, "ledger.searchBox:SetPoint(\"LEFT\", ledger.title, \"RIGHT\", 14, 0)", "Recent Ledger search should sit on the title row")
    assertContains(src, "section.clearLedgerButton", "Recent Ledger should include a clear button")
    assertContains(src, "owner:ConfirmClearRecentLedger()", "Recent Ledger clear button should ask before hiding the ledger feed")
    assertContains(src, "StaticPopupDialogs[\"WRL_CLEAR_RECENT_LEDGER\"]", "Recent Ledger clear should use a confirmation popup")
    assertContains(src, "ns.Database:ClearRecentBankLedger()", "Recent Ledger clear should store a visibility cutoff instead of deleting receipts")
    assertContains(src, "section.owner = owner or section.owner", "Recent Ledger redraws should preserve their owner for clear-button callbacks")
    assertContains(src, "setLedgerSection(ledger, ledger._allLines or {}, ledger.owner)", "Recent Ledger search redraws should keep the clear button wired")
    assertContains(src, "ledgerScroll:SetPoint(\"BOTTOMRIGHT\", ledger, \"BOTTOMRIGHT\", -BANK_SCROLLBAR_GUTTER, 10)", "ledger inner scroll should stay inside the dashboard gutter")
    assertContains(src, "ledgerContent:SetSize(BANK_LEDGER_CONTENT_WIDTH, 1)", "ledger content width should derive from the right-safe section width")
    assertContains(src, "fs:SetWidth(BANK_LEDGER_CONTENT_WIDTH)", "ledger text should use the right-safe ledger content width")
    assertContains(src, "setLedgerSection(self.bankLedgerSection", "Recent Ledger should render through its scrollable section")
    assertContains(src, "appendRecentLedger(right, 50)", "Recent Ledger should search across more than the default visible rows")
    assertContains(src, "appendBankerSummary(right)", "Banker Summary should be generated with the bank report lines")
    assertContains(src, "appendNeededSupplies(right", "Needed Supplies should render aggregate pending request rows")
    assertContains(src, "appendAccountSummary(right", "Account Summary should render account-level reporting rows")
    assertContains(src, "left:SetWidth(304)", "left snapshot should shrink to give the Bank Desk more room")
    assertContains(src, "local BANK_DASHBOARD_WIDTH = 760", "bank Dashboard should leave a visible gutter before the scrollbar")
    assertContains(src, "local BANK_TOP_SECTION_WIDTH = math.floor((BANK_SECTION_WIDTH - 10) / 2)", "top-row bank boxes should fit inside the dashboard gutter")
    assertContains(src, "self.leftPane:Hide()", "bank Dashboard should hide the left pane for a single-column layout")
    assertContains(src, "self.rightPane:SetPoint(\"TOPLEFT\", self.panel, \"TOPLEFT\", 20, -64)", "bank Dashboard should stretch the scroll column across the panel")
    assertContains(src, "self.bankSnapshotSection = buildBankSection(content, Theme, \"Bank Snapshot\")", "bank snapshot should render in the single scroll column")
    assertContains(src, "self.bankSummarySection = buildBankSection(content, Theme, \"Banker Summary\")", "banker summary should render in the single scroll column")
    assertContains(src, "self.content:SetSize(BANK_DASHBOARD_WIDTH, 1)", "bank scroll content should reserve width for the inside scrollbar gutter")
    assertContains(src, "section:SetWidth(BANK_SECTION_WIDTH)", "bank sections should not draw under the main scrollbar")
end

local function testCharacterDashboardWiresCoopSummary()
    local tabFile = assert(io.open("UI/Tab_Run.lua", "rb"))
    local src = tabFile:read("*a"):gsub("\r\n", "\n")
    tabFile:close()
    local mpFile = assert(io.open("Core/Multiplayer.lua", "rb"))
    local multiplayer = mpFile:read("*a"):gsub("\r\n", "\n")
    mpFile:close()

    assertContains(src, "ns.Multiplayer:DashboardLines()", "character dashboard should render multiplayer summary")
    assertContains(multiplayer, "|cffc0a060Team Pulse|r", "multiplayer module should provide Team Pulse heading")
end

testBankerOverviewReplacesRunSnapshotCopy()
testRunnerDashboardShowsLoanSummary()
testRunnerSnapshotShowsRecentOutgoingRequestStatuses()
testContributionActionOnlyShowsForPendingContributionRuns()
testContributionBoardShowsLocalAccountContributionsByCharacter()
testCharacterDashboardWiresCoopSummary()
testAccountAssignmentTextAssignsCharacterAndRequest()
testAccountSummaryRowAssignmentTargetsSingleUnassignedCharacter()
testAccountSummaryRowAssignmentFallsBackForMultipleCharacters()
testBankDeskActionButtonsAreDashboardOwned()
testBankDeskCanSelectResaleRowsByClickTarget()
testSelectedResaleOrderDoesNotDefaultUnmatchedRequester()
testCancelResaleRowRemovesSimulatedStockLine()
testCancelResaleRowDismissesRealInventoryLine()
testSelectedResaleOrderUsesRequestedQuantityWhenRequestMatchesItem()
testResaleRowWithoutMatchingRequestDoesNotRecreatePhantomOrder()
testResaleCODRehydratesStaleSelectionWithRequester()
testResaleCODUsesSimulatedBuyerWithoutBankRequest()
testResaleDeskClearAllClearsSimulatedRowsAndSelection()
testLoansDeskRowClearClearsOneSimulatedRow()
testBankDeskCanCycleActiveRequests()
testEmptyBankDeskMessageSitsUnderHeader()
testBankDeskUsesBorderedSectionsWithStrongHeadings()

print("RunTabBankerOverview.test.lua: ok")
