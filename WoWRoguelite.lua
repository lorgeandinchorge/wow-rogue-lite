-- WoWRoguelite.lua
-- Bootstrap / namespace / slash commands.
--
-- Each addon file gets two params: ADDON_NAME and a private table we all share.
-- We hang everything off that private table (ns.*) so nothing leaks into _G.

local ADDON_NAME, ns = ...

ns.name        = ADDON_NAME
ns.version     = "0.3.8a"
ns.commPrefix  = "WRL_COMM" -- must be <= 16 chars for RegisterAddonMessagePrefix

-- Module registration helper. Modules call ns:NewModule("Name") and attach
-- functions to the returned table; other modules read them via ns.Name.
function ns:NewModule(name)
    local m = self[name] or {}
    self[name] = m
    return m
end

-- Print helper (quiet, prefixed). Color: GW2-ish gold.
local PREFIX = "|cffc0a060[Roguelite]|r "
function ns:Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

-- Debug gate: set WRL_DB.debug = true via slash command to enable.
function ns:Debug(msg, ...)
    if not (WRL_DB and WRL_DB.debug) then return end
    if select("#", ...) > 0 then msg = msg:format(...) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff808080[WRL]|r " .. tostring(msg))
end

-- Unit identity: "Player-Realm". Stable across logins; used as primary key.
function ns:UnitKey(unit)
    unit = unit or "player"
    local name, realm = UnitName(unit)
    if not name then return nil end
    if not realm or realm == "" then realm = GetRealmName() end
    -- Collapse spaces in realm name — Blizzard does this in cross-realm IDs.
    realm = realm:gsub("%s+", "")
    return name .. "-" .. realm
end

local function parseGoldAmount(text)
    text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local number, suffix = text:match("^(%d+)(g?)$")
    if not number then return nil end
    local value = tonumber(number)
    if not value then return nil end
    return value
end

local function formatLoanGold(copper)
    if ns.Loans and ns.Loans.FormatGold then
        return ns.Loans:FormatGold(copper or 0)
    end
    return tostring(math.floor((tonumber(copper) or 0) / 10000)) .. "g"
end

local function shortPriceLabel(source)
    if ns.Pricing and ns.Pricing.ShortSourceLabel then
        return ns.Pricing:ShortSourceLabel(source)
    end
    return source and tostring(source) or "fallback"
end

-- Central event frame. Individual modules register callbacks on ns:On(event, cb).
local events = CreateFrame("Frame")
local handlers = {}
events:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do list[i](...) end
end)

function ns:On(event, cb)
    if not handlers[event] then
        handlers[event] = {}
        local ok, err = pcall(events.RegisterEvent, events, event)
        if not ok then
            ns:Debug("Could not register event %s: %s", tostring(event), tostring(err))
        end
    end
    table.insert(handlers[event], cb)
end

-- PLAYER_LOGIN fires once and guarantees SavedVariables are loaded. We do
-- the real init there instead of ADDON_LOADED so all modules see a ready DB.
ns:On("PLAYER_LOGIN", function()
    ns.Database:Init()
    ns.Settings:Init()     -- must follow Database (reads WRL_DB); precedes all consumers
    ns.Run:Init()          -- must follow Database (reads records); precedes Death
    ns.Rules:Init()        -- must follow Settings (reads rule toggles); precedes event-driven modules
    ns.Boons:Init()        -- must follow Rules/Settings; re-applies selected burden rules
    ns.BankStatus:Init()
    ns.Tiers:Init()
    ns.LegacyUnlocks:Init()
    ns.Vendor:Init()
    ns.Merchant:Init()
    ns.Pricing:Init()
    ns.BankResale:Init()
    ns.Loans:Init()
    ns.Contributions:Init() -- must follow Database + Vendor; used by Death
    ns.Achievements:Init()  -- must follow Contributions/Run/Rules/Tiers for criteria checks
    ns.Comm:Init()
    ns.Requests:Init()
    -- DeathScreen must Init before Death so Death:Init can call
    -- TryPresentPendingDeathScreen on login with the UI available.
    if ns.DeathScreen then ns.DeathScreen:Init() end
    ns.Death:Init()
    ns.Export:Init()        -- after data modules; before UI

    -- Advance "fresh" characters to "active" now that all modules are ready.
    ns.Run:ActivateCurrentRunIfNeeded()

    ns.Theme:Init()
    ns.MainFrame:Init()
    if ns.AddonOptions then ns.AddonOptions:Init() end

    ns:Print("v%s loaded. Type /wrl to open.", ns.version)
end)

-- Slash commands -------------------------------------------------------------
SLASH_WRL1 = "/wrl"
SLASH_WRL2 = "/roguelite"
SlashCmdList["WRL"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = rest or ""

    if cmd == "" or cmd == "show" or cmd == "toggle" then
        ns.MainFrame:Toggle()
    elseif cmd == "setbank" then
        ns.Database:SetBankCharacter(rest ~= "" and rest or ns:UnitKey())
    elseif cmd == "bank" then
        local key = WRL_DB and WRL_DB.bankCharacter
        ns:Print("Bank character: %s", key or "not set (use /wrl setbank Name-Realm)")
    elseif cmd == "request" then
        ns.MainFrame:ShowTab("Rewards")
    elseif cmd == "dashboard" or cmd == "dash" then
        ns.MainFrame:ShowTab("Run")
    elseif cmd == "bankreport" or cmd == "banksummary" then
        if not (ns.Database and ns.Database.BankerSummaryLines) then
            ns:Print("Banker summary is not ready yet.")
            return
        end
        ns:Print("Banker Summary:")
        for _, line in ipairs(ns.Database:BankerSummaryLines()) do
            ns:Print("  %s", line)
        end
        if ns.MainFrame and ns.MainFrame.ShowTab then
            ns.MainFrame:ShowTab("Run")
        end
    elseif cmd == "needed" or cmd == "supplies" then
        if not (ns.Requests and ns.Requests.NeededSupplyLines) then
            ns:Print("Needed supplies report is not ready yet.")
            return
        end
        ns:Print("Needed Supplies:")
        for _, line in ipairs(ns.Requests:NeededSupplyLines()) do
            ns:Print("  %s", line)
        end
        if ns.MainFrame and ns.MainFrame.ShowTab then
            ns.MainFrame:ShowTab("Run")
        end
    elseif cmd == "account" then
        local label, characterKey = rest:match("^(%S+)%s+(.+)$")
        if not label or label == "" then
            ns:Print("Usage: /wrl account LABEL Character-Realm")
        elseif not (ns.Database and ns.Database.AssignCharacterToAccountLabel) then
            ns:Print("Account grouping is not ready yet.")
        else
            characterKey = characterKey and characterKey:gsub("^%s+", ""):gsub("%s+$", "") or ns:UnitKey()
            local account = ns.Database:AssignCharacterToAccountLabel(characterKey, label)
            for _, req in ipairs((WRL_DB and WRL_DB.requests) or {}) do
                if req.from == characterKey then req.accountId = account and account.id or req.accountId end
            end
            ns:Print("Assigned %s to account %s.", characterKey, account and account.label or label)
            if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
                ns.MainFrame:RefreshCurrentTab()
            end
        end
    elseif cmd == "simrequest" or cmd == "simreq" then
        if not (ns.Requests and ns.Requests.OnIncoming) then
            ns:Print("Requests module is not ready yet.")
            return
        end
        local requester, rewardText = rest:match("^(%S+)%s*(.-)$")
        requester = requester and requester ~= "" and requester or "Tester-Realm"
        rewardText = rewardText and rewardText ~= "" and rewardText or "101"
        local tierIds = {}
        for id in rewardText:gmatch("([^,%s]+)") do
            local n = tonumber(id)
            if n then tierIds[#tierIds + 1] = n end
        end
        if #tierIds == 0 then
            ns:Print("Usage: /wrl simrequest [Character-Realm] [RewardId,RewardId]")
            return
        end
        local requestId = ("sim-%s-%s"):format(tostring(time and time() or 0), tostring(math.random and math.random(1000, 9999) or 1000))
        ns.Requests:OnIncoming(requester, tierIds, "Simulated tester request.", "simulated", requestId)
        ns:Print("Simulated request from %s for rewards %s.", requester, table.concat(tierIds, ","))
        if ns.MainFrame and ns.MainFrame.ShowTab then
            ns.MainFrame:ShowTab("Run")
        elseif ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
            ns.MainFrame:RefreshCurrentTab()
        end
    elseif cmd == "simresale" or cmd == "simresell" then
        if not (ns.BankResale and ns.BankResale.SimulateStock) then
            ns:Print("Bank resale desk is not ready yet.")
            return
        end
        local simText = rest ~= "" and rest or "769:4,723:2"
        if simText:lower() == "clear" then
            ns.BankResale:ClearSimulatedStock()
            ns:Print("Simulated resale stock cleared.")
            if ns.MainFrame and ns.MainFrame.ShowTab then
                ns.MainFrame:ShowTab("Run")
            end
            return
        end

        local entries = {}
        for token in simText:gmatch("([^,%s]+)") do
            local itemText, qtyText = token:match("^(%d+)[:xX](%d+)$")
            local itemId = tonumber(itemText or token)
            local qty = tonumber(qtyText) or 1
            if itemId and qty > 0 then
                entries[#entries + 1] = { itemId = itemId, qty = qty }
            end
        end
        if #entries == 0 then
            ns:Print("Usage: /wrl simresale [ITEM_ID:QTY,ITEM_ID:QTY] or /wrl simresale clear")
            return
        end
        local ok, reason = ns.BankResale:SimulateStock(entries, "Tester-Realm")
        if not ok then
            if reason == "not_catalog" then
                ns:Print("Simulated resale stock must use items in the resale catalog.")
            else
                ns:Print("Could not create simulated resale stock.")
            end
            return
        end
        ns:Print("Simulated resale stock created with %d item line(s).", #entries)
        if ns.MainFrame and ns.MainFrame.ShowTab then
            ns.MainFrame:ShowTab("Run")
        elseif ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
            ns.MainFrame:RefreshCurrentTab()
        end
    elseif cmd == "simloan" then
        if not (ns.Loans and ns.Loans.RecordLoan) then
            ns:Print("Loan desk is not ready yet.")
            return
        end
        local borrower, amountText = rest:match("^(%S+)%s*(%S*)$")
        borrower = borrower and borrower ~= "" and borrower or "Tester-Realm"
        local amount = parseGoldAmount(amountText ~= "" and amountText or "1")
        local recorder = ns.Loans.RecordTestLoan or ns.Loans.RecordLoan
        local receipt, reason, cap = recorder(ns.Loans, borrower, amount or 0, "local loan simulation")
        if not receipt then
            if reason == "over_cap" then
                ns:Print("Simulated loan would exceed cap; available: %s.", formatLoanGold(cap and cap.availableCopper or 0))
            else
                ns:Print("Usage: /wrl simloan [Character-Realm] [GOLD]")
            end
            return
        end
        ns:Print("Simulated loan recorded for %s: %s.", borrower, formatLoanGold(receipt.amount or 0))
        if ns.MainFrame and ns.MainFrame.ShowTab then
            ns.MainFrame:ShowTab("Run")
        elseif ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
            ns.MainFrame:RefreshCurrentTab()
        end
    elseif cmd == "contribute" or cmd == "contribution" then
        if ns.Death and ns.Death.PrepareContributionMail then
            ns.Death:PrepareContributionMail()
        else
            ns:Print("Contribution flow is not ready yet.")
        end
    elseif cmd == "loan" or cmd == "loans" then
        if not (ns.Loans and ns.Loans.AccountLoanRows) then
            ns:Print("Loan desk is not ready yet.")
            return
        end
        local sub, subRest = rest:match("^(%S+)%s*(.-)$")
        sub = (sub or ""):lower()
        subRest = subRest or ""
        if sub == "borrow" or sub == "repay" then
            local characterKey, amountText = subRest:match("^(%S+)%s+(%S+)$")
            local amount = parseGoldAmount(amountText)
            if not characterKey or not amount then
                ns:Print(sub == "borrow" and "Usage: /wrl loan borrow Character-Realm GOLD" or "Usage: /wrl loan repay Character-Realm GOLD")
                return
            end
            if sub == "borrow" then
                local receipt, reason, cap = ns.Loans:RecordLoan(characterKey, amount, "manual", "slash command")
                if not receipt then
                    if reason == "over_cap" then
                        ns:Print("Loan would exceed available cap (%s available). Buy Legacy ranks first, or use /wrl simloan for UI testing.", formatLoanGold(cap and cap.availableCopper or 0))
                    else
                        ns:Print("Could not record loan.")
                    end
                    return
                end
                ns:Print("Recorded loan to %s: %s.", characterKey, formatLoanGold(receipt.amount or 0))
            else
                local result = ns.Loans:RecordManualRepayment(characterKey, amount, "manual", "slash command")
                if not result or (result.repaid or 0) <= 0 then
                    ns:Print("No outstanding loan debt found for %s.", characterKey)
                    return
                end
                ns:Print("Recorded loan repayment from %s: %s.", characterKey, formatLoanGold(result.repaid or 0))
            end
            if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
                ns.MainFrame:RefreshCurrentTab()
            end
        elseif sub ~= "" then
            ns:Print("Usage: /wrl loan | /wrl loan borrow Character-Realm GOLD | /wrl loan repay Character-Realm GOLD")
            return
        else
            local rows = ns.Loans:AccountLoanRows()
            if #rows == 0 then
                ns:Print("Loans Desk: no active loans.")
            else
                ns:Print("Loans Desk:")
                for _, row in ipairs(rows) do
                    ns:Print("  %s / %s - debt %s, available %s, cap %s",
                        row.label or "Unassigned",
                        row.characterKey or "Unknown",
                        formatLoanGold(row.outstandingCopper or 0),
                        formatLoanGold(row.availableCopper or 0),
                        formatLoanGold(row.capCopper or 0))
                end
            end
            if ns.MainFrame and ns.MainFrame.ShowTab then
                ns.MainFrame:ShowTab("Run")
            end
        end
    elseif cmd == "resale" then
        if not (ns.BankResale and ns.BankResale.InventoryRows) then
            ns:Print("Bank resale desk is not ready yet.")
            return
        end
        local sub, subRest = rest:match("^(%S+)%s*(.-)$")
        sub = (sub or ""):lower()
        subRest = subRest or ""
        if sub == "sold" or sub == "cod" then
            local itemText, qtyText, buyer = subRest:match("^(%S+)%s+(%S+)%s*(.-)$")
            local itemId = tonumber(itemText)
            local qty = tonumber(qtyText)
            if not itemId then
                ns:Print(sub == "cod" and "Usage: /wrl resale cod ITEM_ID QTY BUYER" or "Usage: /wrl resale sold ITEM_ID QTY [BUYER]")
                return
            end
            if not qty or qty <= 0 then
                ns:Print("Resale sale quantity must be greater than zero.")
                return
            end
            if sub == "cod" and (not buyer or buyer == "") then
                ns:Print("Resale COD mail requires a buyer.")
                return
            end
            local receipt, reason
            if sub == "cod" then
                receipt, reason = ns.BankResale:PrepareCODMail(itemId, qty, buyer)
            else
                receipt, reason = ns.BankResale:RecordSale(itemId, qty, buyer)
            end
            if not receipt then
                if reason == "not_catalog" then
                    ns:Print("Item %s is not in the resale catalog.", tostring(itemId))
                elseif reason == "bad_qty" then
                    ns:Print("Resale sale quantity must be greater than zero.")
                elseif reason == "missing_buyer" then
                    ns:Print("Resale COD mail requires a buyer.")
                elseif reason == "mailbox_closed" then
                    ns:Print("Open your mailbox first, then prepare resale COD mail again.")
                elseif reason == "cod_unavailable" then
                    ns:Print("COD mail fields are not available on this client.")
                else
                    ns:Print(sub == "cod" and "Could not prepare resale COD mail." or "Could not record resale sale.")
                end
                return
            end
            if sub == "cod" then
                ns:Print("Prepared resale COD mail: %dx %s to %s for %s.",
                    receipt.qty or 0,
                    receipt.itemName or ("item:" .. tostring(receipt.itemId)),
                    receipt.buyer or "Unknown",
                    ns.Tiers and ns.Tiers.FormatMoney and ns.Tiers:FormatMoney(receipt.totalCopper or 0) or tostring(receipt.totalCopper or 0))
            else
                ns:Print("Recorded resale: %dx %s for %s.",
                    receipt.qty or 0,
                    receipt.itemName or ("item:" .. tostring(receipt.itemId)),
                    ns.Tiers and ns.Tiers.FormatMoney and ns.Tiers:FormatMoney(receipt.totalCopper or 0) or tostring(receipt.totalCopper or 0))
            end
        elseif sub ~= "" then
            ns:Print("Usage: /wrl resale | /wrl resale cod ITEM_ID QTY BUYER | /wrl resale sold ITEM_ID QTY [BUYER]")
            return
        else
            local rows = ns.BankResale:InventoryRows()
            if #rows == 0 then
                ns:Print("Resale Desk: no catalog goods found in bank inventory.")
            else
                ns:Print("Resale Desk:")
                for _, row in ipairs(rows) do
                    local source = shortPriceLabel(row.priceShortLabel or row.priceSource or row.priceLabel)
                    ns:Print("  %s x%d - %s each [%s] (%s total)",
                        row.name or ("item:" .. tostring(row.itemId)),
                        row.count or 0,
                        ns.Tiers and ns.Tiers.FormatMoney and ns.Tiers:FormatMoney(row.priceEach or 0) or tostring(row.priceEach or 0),
                        source,
                        ns.Tiers and ns.Tiers.FormatMoney and ns.Tiers:FormatMoney(row.totalCopper or 0) or tostring(row.totalCopper or 0))
                end
            end
            if ns.MainFrame and ns.MainFrame.ShowTab then
                ns.MainFrame:ShowTab("Run")
            end
        end
    elseif cmd == "settings" then
        -- Print current account-wide settings to chat for debug inspection.
        local s = WRL_DB and WRL_DB.settings
        if not s then ns:Print("Settings not yet initialised."); return end
        ns:Print("=== Settings (profile: %s) ===", s.profile or "?")
        ns:Print("  allowBankRewards  = %s", tostring(s.allowBankRewards))
        ns:Print("  announceDeaths     = %s", tostring(s.announceDeaths))
        ns:Print("  announceSoftDeaths = %s", tostring(s.announceSoftDeaths))
        ns:Print("  uiTheme            = %s (active: %s)",
            tostring(s.uiTheme),
            ns.Theme and ns.Theme:GetActiveThemeId() or "?")
        ns:Print("  fontProfile        = %s",
            tostring(s.fontProfile))
        if s.rules then
            local ruleLines = {}
            for ruleId, enabled in pairs(s.rules) do
                ruleLines[#ruleLines + 1] = string.format("    %s = %s", ruleId, tostring(enabled))
            end
            if #ruleLines > 0 then
                table.sort(ruleLines)
                ns:Print("  rules:")
                for _, line in ipairs(ruleLines) do ns:Print(line) end
            else
                ns:Print("  rules: (all defaults)")
            end
        end
    elseif cmd == "profile" then
        -- /wrl profile                → show current profile
        -- /wrl profile <id>           → apply named profile
        -- /wrl profile list           → list available profiles
        if rest == "" then
            ns:Print("Current profile: %s (%s)",
                ns.Settings:GetProfile(),
                ns.Settings:ProfileDisplayName(ns.Settings:GetProfile()))
        elseif rest == "list" then
            ns:Print("Available profiles:")
            for _, id in ipairs(ns.Settings:ProfileList()) do
                local active = (ns.Settings:GetProfile() == id) and " *" or ""
                ns:Print("  %s – %s%s", id, ns.Settings:ProfileDisplayName(id), active)
            end
        else
            if ns.Settings:ApplyProfile(rest) then
                ns:Print("Profile applied: %s (%s)", rest, ns.Settings:ProfileDisplayName(rest))
            end
        end
    elseif cmd == "rules" then
        -- /wrl rules              → show enabled rules for the current character
        -- /wrl rules log          → print recent taint/warn log entries
        -- /wrl rules log <key>    → print log for a specific character key
        if rest == "" then
            ns:Print("=== Rules (profile: %s) ===", ns.Settings:GetProfile())
            for _, def in ipairs(ns.Rules:Definitions()) do
                local on = ns.Rules:IsEnabled(def.id)
                ns:Print("  [%s] %s – %s",
                    on and "|cff00ff00ON|r" or "|cffaaaaaaOFF|r",
                    def.name,
                    def.description)
            end
            local taints = ns.Rules:TaintCount()
            ns:Print("Taint entries this character: %d", taints)
        elseif rest == "log" or rest:sub(1, 4) == "log " then
            local charKey = rest:match("^log%s+(.+)$") or ns:UnitKey()
            local log = ns.Rules:GetLog(charKey)
            if #log == 0 then
                ns:Print("No rule log entries for %s.", tostring(charKey))
            else
                ns:Print("=== Rule log: %s (%d entries) ===", charKey, #log)
                -- Print last 10 entries, newest last.
                local start = math.max(1, #log - 9)
                for i = start, #log do
                    local e = log[i]
                    local color = (e.result == "tainted" or e.result == "blocked") and "|cffff6060" or "|cffffff00"
                    ns:Print("  %s[%s]|r %s – %s (%s)",
                        color, e.result, e.ruleId, e.detail,
                        date and date("%H:%M", e.when) or tostring(e.when))
                end
            end
        else
            ns:Print("Usage: /wrl rules | /wrl rules log | /wrl rules log Name-Realm")
        end
    elseif cmd == "theme" then
        local themeId = rest:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if themeId == "" then
            ns:Print("Current UI theme: %s (active: %s)",
                ns.Theme:ThemeLabel(ns.Theme:GetSelectedThemeId()),
                ns.Theme:ThemeLabel(ns.Theme:GetActiveThemeId()))
            ns:Print("Usage: /wrl theme %s", ns.Theme:ThemeUsageText())
        else
            local ok, reason = ns.Theme:SetTheme(themeId)
            if ok then
                ns:Print("UI theme set to %s.", ns.Theme:ThemeLabel(themeId))
                if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
                    ns.MainFrame:RefreshCurrentTab()
                end
            elseif reason == "gw2_unavailable" then
                ns:Print("GW2 UI theme requires GW2 UI or GW2 UI TBC to be installed and enabled.")
            else
                ns:Print("Unknown theme %q. Use %s.", themeId, ns.Theme:ThemeSentenceText())
            end
        end
    elseif cmd == "debug" then
        WRL_DB.debug = not WRL_DB.debug
        ns:Print("Debug: %s", WRL_DB.debug and "on" or "off")
    elseif cmd == "reqrefresh" or (cmd == "requests" and rest == "refresh") then
        if ns.Requests and ns.Requests.RefreshBagItemIndicators then
            ns.Requests:RefreshBagItemIndicators(true)
        else
            ns:Print("Requests module is not ready yet.")
        end
    elseif cmd == "reset" then
        if rest == "confirm" then
            wipe(WRL_DB); ns.Database:Init()
            ns:Print("Database wiped.")
        else
            ns:Print("This will wipe ALL Roguelite data. Type |cffff6060/wrl reset confirm|r to proceed.")
        end
    elseif cmd == "export" then
        -- /wrl export           → same as /wrl export run (current character)
        -- /wrl export run       → compact run summary + copyable popup
        -- /wrl export account   → account-wide legacy summary + copyable popup
        local sub = rest:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if sub == "" or sub == "run" then
            ns.Export:DoRunExport()
        elseif sub == "account" then
            ns.Export:DoAccountExport()
        else
            ns:Print("Usage: /wrl export | /wrl export run | /wrl export account")
        end
    elseif cmd == "sellfinal" or cmd == "vendorfinal" then
        -- Sell all vendorable bag and equipped items at the currently open
        -- merchant. Merchant:PromptFinalRunSell() owns the merchant-open guard
        -- and confirmation dialog.
        if ns.Merchant and ns.Merchant.PromptFinalRunSell then
            ns.Merchant:PromptFinalRunSell()
        else
            ns:Print("Merchant module is not ready yet.")
        end
    elseif cmd == "help" then
        ns:Print("Commands:")
        ns:Print("  /wrl                - toggle window")
        ns:Print("  /wrl setbank        - mark current char as the bank")
        ns:Print("  /wrl setbank NAME   - set an external bank character")
        ns:Print("  /wrl bank           - show current bank char")
        ns:Print("  /wrl dashboard      - open the Dashboard tab")
        ns:Print("  /wrl request        - open the Rewards tab")
        ns:Print("  /wrl account L C-R  - assign Character-Realm to account label L")
        ns:Print("  /wrl bankreport     - print banker summary lines")
        ns:Print("  /wrl needed         - print aggregate needed supplies")
        ns:Print("  /wrl simrequest C-R IDS - simulate a pending bank request")
        ns:Print("  /wrl simresale IDS  - simulate resale stock, e.g. 769:4,723:2")
        ns:Print("  /wrl simloan C-R GOLD - simulate a manual loan")
        ns:Print("  /wrl contribute     - prepare pending final contribution mail")
        ns:Print("  /wrl loan           - show loan desk status")
        ns:Print("  /wrl loan borrow C-R GOLD - record a manual loan")
        ns:Print("  /wrl loan repay C-R GOLD - record a manual repayment")
        ns:Print("  /wrl resale         - show the bank resale desk inventory")
        ns:Print("  /wrl resale cod ID QTY BUYER - prepare COD mail for resale")
        ns:Print("  /wrl resale sold ID QTY [BUYER] - record a manual resale")
        ns:Print("  /wrl sellfinal      - sell bags and equipped gear at the current vendor")
        ns:Print("  /wrl settings       - print current settings to chat")
        ns:Print("  /wrl profile        - show active profile")
        ns:Print("  /wrl profile list   - list all profiles")
        ns:Print("  /wrl profile <id>   - apply a profile by ID")
        ns:Print("  /wrl rules          - list rules and enabled state")
        ns:Print("  /wrl rules log      - print recent taint/warn log entries")
        ns:Print("  /wrl theme <id>     - set UI theme: %s", ns.Theme:ThemeSentenceText())
        ns:Print("  /wrl debug          - toggle debug logging")
        ns:Print("  /wrl reqrefresh     - refresh bag item indicators")
        ns:Print("  /wrl export         - export current run summary (opens popup)")
        ns:Print("  /wrl export run     - same as /wrl export")
        ns:Print("  /wrl export account - export account-wide legacy summary")
        ns:Print("  /wrl reset          - wipe ALL addon data (requires confirm)")
        ns:Print("  /wrl help           - show this message")
    else
        ns:Print("Unknown command: %q  -  type /wrl help for a list.", cmd)
    end
end
