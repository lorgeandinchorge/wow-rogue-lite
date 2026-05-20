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
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns:UnitKey() return "Bank-Realm" end
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
    function ns.Database:RecentBankLedgerRows()
        return {
            { kind = "fulfillment", characterKey = "Graham-Realm", accountLabel = "Graham", amount = 500, method = "mail", when = 102 },
        }
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

    assert(loadfile("UI/Tab_Run.lua"))("WoWRoguelite", ns)
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

local function testBankerOverviewReplacesRunSnapshotCopy()
    local tab = resetHarness()

    local left, right = tab:_BuildBankerOverviewLines("Bank-Realm")

    assertContains(left[1], "Name:", "banker overview starts with character identity")
    assertContains(left[4], "Realm: Realm", "banker overview includes realm")
    assertContains(left[5], "bank infrastructure", "banker overview names the bank run state")
    assertContains(left[6], "Lives remaining: n/a", "banker overview avoids runner life accounting")

    assertEqual(right[1], "|cffc0a060Bank Desk|r", "right pane starts with Bank Desk heading")
    assertContains(right[2], "2 request", "bank desk summarizes pending requests")
    assertContains(right[4], "Active request: Graham-Realm [Graham]", "bank desk names the active request and account")
    assertContains(right[6], "Readiness: missing", "bank desk shows a direct readiness status")
    assertContains(right[7], "Item: Banker's Thread - available 0 / requested 2 / missing 2", "bank desk lists missing item counts")
    assertContains(right[8], "Item: Clerk's Potion - available 3 / requested 3 / ready", "bank desk lists ready item counts")
    assertContains(right[9], "Gold: available 500c / requested 1200c / missing 700c", "bank desk lists gold counts")
    assertContains(right[10], "|cffc0a060Contribution Board|r", "right pane includes contribution board")
    assertContains(right[11], "Graham", "contribution board is grouped by account")
    assertContains(right[12], "Graham-Realm", "contribution board keeps character detail")
    assertContains(right[16], "ledger", "right pane includes ledger heading")
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

local function testBankDeskActionButtonsAreDashboardOwned()
    local f = assert(io.open("UI/Tab_Run.lua", "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()

    assertContains(src, 'Theme:Button(self.bankActionsBox, "Prepare Mail"', "Dashboard should own the bank mail action")
    assertContains(src, 'Theme:Button(self.bankActionsBox, "Mark Fulfilled"', "Dashboard should own the bank fulfill action")
    assertContains(src, 'Theme:Button(self.bankActionsBox, "Assign Account"', "Dashboard should own account assignment action")
    assertContains(src, 'Theme:Button(self.bankActionsBox, "Next Request"', "Dashboard should let the banker cycle active requests")
    assertContains(src, "self:_ActiveBankRequest()", "bank mail action should use the active Dashboard request")
    assertContains(src, "if actionReq then self.bankMailButton:Show()", "bank mail action only shows with actionable request")
    assertContains(src, "self.bankActionsBox = CreateFrame(\"Frame\", nil, left)", "bank actions should live under the Bank Snapshot")
    assertContains(src, "Theme:Fill(self.bankActionsBox, Theme.c.bg1, true)", "bank actions should use a color-only fill without panel texture tiling")
    assertContains(src, "self.bankActionsBox:SetPoint(\"TOPLEFT\", self.leftLines[7]", "bank action box should sit below snapshot lines")
    assertContains(src, "self.bankActionsBox.borderLeft", "bank action box should have a left border")
    assertContains(src, "self.bankActionsBox.borderRight", "bank action box should have a right border")
    assertContains(src, "Theme:Button(self.bankActionsBox, \"Prepare Mail\"", "bank mail button should be inside the action box")
end

local function testBankDeskCanCycleActiveRequests()
    local tab = resetHarness()

    assertEqual(tab:_ActiveBankRequest().id, "req-1", "first actionable request starts active")
    tab:_AdvanceBankRequest()
    assertEqual(tab:_ActiveBankRequest().id, "req-2", "next request advances active selection")
    tab:_AdvanceBankRequest()
    assertEqual(tab:_ActiveBankRequest().id, "req-1", "next request wraps around")
end

local function testBankDeskUsesBorderedSectionsWithStrongHeadings()
    local f = assert(io.open("UI/Tab_Run.lua", "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()

    assertContains(src, "CreateFrame(\"Frame\", nil, content)", "Bank Desk sections should be framed in the scroll content")
    assertContains(src, "Theme:Fill(section, Theme.c.bg1, true, \"panel\")", "Bank Desk sections should use light panel borders")
    assertContains(src, "section.borderLeft", "Bank Desk sections should have a full light left border")
    assertContains(src, "section.borderRight", "Bank Desk sections should have a full light right border")
    assertContains(src, "title:SetFont(STANDARD_TEXT_FONT", "Bank Desk section headings should be stronger than body text")
    assertContains(src, "Theme:Text(section, 13, Theme.c.goldH)", "Bank Desk section headings should be larger for scanning")
    assertContains(src, "Theme:Text(section, 11, Theme.c.fg2)", "Bank Desk section body text should be larger for readability")
    assertContains(src, "self.bankDeskSection", "Bank Desk should have its own right-side section")
    assertContains(src, "self.bankContributionSection", "Contribution Board should have its own right-side section")
    assertContains(src, "self.bankLedgerSection", "Recent ledger should have its own right-side section")
    assertContains(src, "buildBankSection(content, Theme, \"Contribution Board\")", "Contribution Board should have a strong section heading")
    assertContains(src, "setBankSection(self.bankContributionSection", "Contribution Board should be rendered as its own bordered box")
    assertContains(src, "buildLedgerSection(content, Theme)", "Recent Ledger should use its own specialized section")
    assertContains(src, "CreateFrame(\"EditBox\"", "Recent Ledger should include search input")
    assertContains(src, "ledger.searchBox:SetScript(\"OnTextChanged\"", "Recent Ledger search should refresh results")
    assertContains(src, "Theme:ScrollArea(ledger)", "Recent Ledger should have an inner scrollable surface")
    assertContains(src, "ledger.searchBox:SetSize(180, 18)", "Recent Ledger search box should stay compact")
    assertContains(src, "setLedgerSection(self.bankLedgerSection", "Recent Ledger should render through its scrollable section")
    assertContains(src, "appendRecentLedger(right, 50)", "Recent Ledger should search across more than the default visible rows")
    assertContains(src, "left:SetWidth(304)", "left snapshot should shrink to give the Bank Desk more room")
    assertContains(src, "content:SetSize(420", "right content should be wider for Bank Desk readability")
end

testBankerOverviewReplacesRunSnapshotCopy()
testContributionActionOnlyShowsForPendingContributionRuns()
testBankDeskActionButtonsAreDashboardOwned()
testBankDeskCanCycleActiveRequests()
testBankDeskUsesBorderedSectionsWithStrongHeadings()

print("RunTabBankerOverview.test.lua: ok")
