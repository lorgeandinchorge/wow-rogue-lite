local function resetHarness()
    local sent = {}
    _G.C2_ChatInfo = nil
    _G.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() end,
        SendAddonMessage = function(prefix, text, channel, target)
            sent[#sent + 1] = {
                prefix = prefix,
                text = text,
                channel = channel,
                target = target,
            }
            return true
        end,
    }
    _G.SendAddonMessage = nil
    _G.GetNumRaidMembers = function() return 0 end
    _G.GetNumPartyMembers = function() return 2 end
    _G.IsInGuild = function() return true end

    local handled
    local ns = {
        commPrefix = "WRL_COMM",
        Database = {},
        Requests = {},
        BankStatus = {},
        UnitKey = function() return "Runner-Realm" end,
        On = function() end,
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns.Database:IsBankCharacter() return false end
    function ns.Requests:OnAck() end
    function ns.BankStatus:MarkSeen() end

    assert(loadfile("Core/Comm.lua"))("WoWRoguelite", ns)
    ns.Comm:RegisterOpHandler("HELLO", function(op, payload, sender, channel)
        handled = { op = op, payload = payload, sender = sender, channel = channel }
    end)
    return ns, sent, function() return handled end
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function testSendScopedUsesRequestedChannel()
    local ns, sent = resetHarness()

    local ok = ns.Comm:SendScoped("HELLO", "payload", "GUILD")

    assertEqual(ok, true, "scoped send succeeds")
    assertEqual(sent[1].prefix, "WRL_COMM", "scoped prefix")
    assertEqual(sent[1].text, "WRLv1|HELLO|payload", "scoped payload")
    assertEqual(sent[1].channel, "GUILD", "scoped channel")
    assertEqual(sent[1].target, nil, "guild has no target")
end

local function testSendGroupUsesPartyWhenNotInRaid()
    local ns, sent = resetHarness()

    local ok = ns.Comm:SendGroup("STATE", "state")

    assertEqual(ok, true, "group send succeeds")
    assertEqual(sent[1].channel, "PARTY", "group send chooses party")
    assertEqual(sent[1].text, "WRLv1|STATE|state", "group state payload")
end

local function testSendGuildUsesGuildChannel()
    local ns, sent = resetHarness()

    local ok = ns.Comm:SendGuild("HELLO", "guild-state")

    assertEqual(ok, true, "guild send succeeds")
    assertEqual(sent[1].channel, "GUILD", "guild channel")
    assertEqual(sent[1].text, "WRLv1|HELLO|guild-state", "guild payload")
end

local function testReceiveDispatchesRegisteredMultiplayerOpWithoutBreakingBankOps()
    local ns, _, handled = resetHarness()

    ns.Comm:Receive("WRLv1|HELLO|Friend-Realm^0.4.1c", "Friend-Realm", "PARTY")

    assertEqual(handled().op, "HELLO", "handler op")
    assertEqual(handled().payload, "Friend-Realm^0.4.1c", "handler payload")
    assertEqual(handled().sender, "Friend-Realm", "handler sender")
    assertEqual(handled().channel, "PARTY", "handler channel")
end

testSendScopedUsesRequestedChannel()
testSendGroupUsesPartyWhenNotInRaid()
testSendGuildUsesGuildChannel()
testReceiveDispatchesRegisteredMultiplayerOpWithoutBreakingBankOps()

print("CommRouting.test.lua: ok")
