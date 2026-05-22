local prepared  = 0
local prompted  = 0
local simulated = nil
local resaleSale = nil
local resaleCOD = nil
local resaleRowsPrinted = 0
local simulatedResale = nil

_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
_G.SlashCmdList = {}
_G.CreateFrame = function()
    return {
        SetScript = function() end,
        RegisterEvent = function() end,
    }
end

local ns = {
    Database = {},
    Settings = {},
    Run = {},
    Rules = {},
    Boons = {},
    BankStatus = {},
    Tiers = {},
    LegacyUnlocks = {},
    Vendor = {},
    Merchant = {},
    Contributions = {},
    Achievements = {},
    Comm = {},
    Requests = {},
    BankResale = {},
    Death = {},
    Export = {},
    Theme = {},
    MainFrame = {},
}

function ns.Death:PrepareContributionMail()
    prepared = prepared + 1
    return true
end

function ns.Merchant:PromptFinalRunSell()
    prompted = prompted + 1
    return true
end

function ns.Requests:OnIncoming(fromKey, tierIds, note, via, requestId)
    simulated = {
        fromKey = fromKey,
        tierIds = tierIds,
        note = note,
        via = via,
        requestId = requestId,
    }
end

function ns.BankResale:InventoryRows()
    return {
        { itemId = 769, name = "Chunk of Boar Meat", count = 4, priceEach = 25, totalCopper = 100 },
    }
end

function ns.BankResale:RecordSale(itemId, qty, buyer)
    if itemId == 99999 then return nil, "not_catalog" end
    if qty <= 0 then return nil, "bad_qty" end
    resaleSale = { itemId = itemId, qty = qty, buyer = buyer }
    return resaleSale
end

function ns.BankResale:PrepareCODMail(itemId, qty, buyer)
    if itemId == 99999 then return nil, "not_catalog" end
    if qty <= 0 then return nil, "bad_qty" end
    if not buyer or buyer == "" then return nil, "missing_buyer" end
    resaleCOD = { itemId = itemId, qty = qty, buyer = buyer }
    return resaleCOD
end

function ns.BankResale:SimulateStock(entries, buyer)
    simulatedResale = entries
    self.simulatedBuyer = buyer
    return true
end

function ns.BankResale:ClearSimulatedStock()
    simulatedResale = {}
    self.simulatedBuyer = nil
    return true
end

function ns.MainFrame:ShowTab(tab)
    self.lastTab = tab
end

assert(loadfile("WoWRoguelite.lua"))("WoWRoguelite", ns)

-- /wrl contribute → PrepareContributionMail
SlashCmdList.WRL("contribute")
if prepared ~= 1 then
    error(("expected /wrl contribute to call PrepareContributionMail once, got %d"):format(prepared), 2)
end

-- /wrl sellfinal → Merchant:PromptFinalRunSell
prompted = 0
SlashCmdList.WRL("sellfinal")
if prompted ~= 1 then
    error(("expected /wrl sellfinal to call PromptFinalRunSell once, got %d"):format(prompted), 2)
end

-- /wrl vendorfinal → same handler as sellfinal
prompted = 0
SlashCmdList.WRL("vendorfinal")
if prompted ~= 1 then
    error(("expected /wrl vendorfinal to call PromptFinalRunSell once, got %d"):format(prompted), 2)
end

-- /wrl simrequest creates a normal incoming test request.
SlashCmdList.WRL("simrequest Graham-Realm 101,201")
if not simulated then
    error("expected /wrl simrequest to create a simulated request", 2)
end
if simulated.fromKey ~= "Graham-Realm" then
    error(("expected simulated requester Graham-Realm, got %s"):format(tostring(simulated.fromKey)), 2)
end
if simulated.tierIds[1] ~= 101 or simulated.tierIds[2] ~= 201 then
    error("expected simulated request rewards 101 and 201", 2)
end
if simulated.via ~= "simulated" then
    error(("expected simulated request via marker, got %s"):format(tostring(simulated.via)), 2)
end

-- /wrl simrequest with no args uses a predictable default.
simulated = nil
SlashCmdList.WRL("simrequest")
if not simulated or simulated.fromKey ~= "Tester-Realm" or simulated.tierIds[1] ~= 101 then
    error("expected /wrl simrequest default to Tester-Realm reward 101", 2)
end

-- /wrl simresale seeds resale stock and opens Dashboard.
simulatedResale = nil
simulated = nil
SlashCmdList.WRL("simresale 769:4,723:2")
if ns.MainFrame.lastTab ~= "Run" then
    error("expected /wrl simresale to open Dashboard", 2)
end
if not simulatedResale or simulatedResale[1].itemId ~= 769 or simulatedResale[1].qty ~= 4 or simulatedResale[2].itemId ~= 723 then
    error("expected /wrl simresale to seed requested item quantities", 2)
end
if simulated then
    error("expected /wrl simresale not to create a regular simulated bank request", 2)
end
if ns.BankResale.simulatedBuyer ~= "Tester-Realm" then
    error("expected /wrl simresale to seed a Tester-Realm resale buyer", 2)
end

-- /wrl simresale with no args uses a predictable default.
simulatedResale = nil
SlashCmdList.WRL("simresale")
if not simulatedResale or simulatedResale[1].itemId ~= 769 or simulatedResale[1].qty ~= 4 then
    error("expected /wrl simresale default to Chunk of Boar Meat stock", 2)
end

-- /wrl simresale clear removes simulated stock.
SlashCmdList.WRL("simresale clear")
if not simulatedResale or #simulatedResale ~= 0 then
    error("expected /wrl simresale clear to clear simulated stock", 2)
end

-- /wrl resale prints rows and opens Dashboard.
local printedMessages = {}
local origPrint = ns.Print
ns.Print = function(self, msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    printedMessages[#printedMessages + 1] = tostring(msg)
    if tostring(msg):find("Chunk of Boar Meat", 1, true) then resaleRowsPrinted = resaleRowsPrinted + 1 end
end
SlashCmdList.WRL("resale")
if ns.MainFrame.lastTab ~= "Run" then
    error("expected /wrl resale to open Dashboard", 2)
end
if resaleRowsPrinted ~= 1 then
    error("expected /wrl resale to print current resale rows", 2)
end

-- /wrl resale sold records a manual sale.
resaleSale = nil
SlashCmdList.WRL("resale sold 769 2 Tester-Realm")
if not resaleSale or resaleSale.itemId ~= 769 or resaleSale.qty ~= 2 or resaleSale.buyer ~= "Tester-Realm" then
    error("expected /wrl resale sold to record item, qty, and buyer", 2)
end

-- /wrl resale cod prepares COD mail.
resaleCOD = nil
SlashCmdList.WRL("resale cod 769 2 Tester-Realm")
if not resaleCOD or resaleCOD.itemId ~= 769 or resaleCOD.qty ~= 2 or resaleCOD.buyer ~= "Tester-Realm" then
    error("expected /wrl resale cod to prepare item, qty, and buyer", 2)
end

-- Invalid resale sale commands print clear errors.
printedMessages = {}
SlashCmdList.WRL("resale sold 769 0 Tester-Realm")
SlashCmdList.WRL("resale sold 99999 1 Tester-Realm")
SlashCmdList.WRL("resale cod 769 1")
local foundBadQty, foundNotCatalog, foundMissingBuyer = false, false, false
for _, m in ipairs(printedMessages) do
    if m:find("quantity", 1, true) then foundBadQty = true end
    if m:find("resale catalog", 1, true) then foundNotCatalog = true end
    if m:find("buyer", 1, true) then foundMissingBuyer = true end
end
if not foundBadQty then error("expected zero resale quantity to print quantity error", 2) end
if not foundNotCatalog then error("expected non-catalog resale item to print catalog error", 2) end
if not foundMissingBuyer then error("expected missing resale COD buyer to print buyer error", 2) end
ns.Print = origPrint

-- When Merchant module is absent the command should print rather than crash.
ns.Print = function(self, msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    printedMessages[#printedMessages + 1] = tostring(msg)
end
local savedMerchant = ns.Merchant
ns.Merchant = nil
prompted = 0
SlashCmdList.WRL("sellfinal")
if prompted ~= 0 then
    error("sellfinal with nil Merchant should not call PromptFinalRunSell", 2)
end
local foundNotReady = false
for _, m in ipairs(printedMessages) do
    if m:find("not ready", 1, true) then foundNotReady = true; break end
end
if not foundNotReady then
    error("sellfinal with nil Merchant should print 'not ready' message", 2)
end
ns.Merchant = savedMerchant
ns.Print = origPrint

print("SlashCommands.test.lua: ok")
