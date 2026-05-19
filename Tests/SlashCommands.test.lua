local prepared  = 0
local prompted  = 0
local simulated = nil

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

-- When Merchant module is absent the command should print rather than crash.
local printedMessages = {}
local origPrint = ns.Print
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
