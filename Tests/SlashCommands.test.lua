local prepared = 0

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

assert(loadfile("WoWRoguelite.lua"))("WoWRoguelite", ns)

SlashCmdList.WRL("contribute")

if prepared ~= 1 then
    error(("expected /wrl contribute to prepare contribution mail once, got %d"):format(prepared), 2)
end

print("SlashCommands.test.lua: ok")
