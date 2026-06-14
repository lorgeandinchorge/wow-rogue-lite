local function resetHarness(options)
    options = options or {}
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
    if options.legacyGroupApis == false then
        _G.GetNumRaidMembers = nil
        _G.GetNumPartyMembers = nil
    else
        _G.GetNumRaidMembers = function() return 0 end
        _G.GetNumPartyMembers = function() return 2 end
    end
    _G.GetNumGroupMembers = options.groupMembers and function() return options.groupMembers end or nil
    _G.IsInRaid = options.inRaid ~= nil and function() return options.inRaid end or nil
    _G.IsInGroup = options.inGroup ~= nil and function() return options.inGroup end or nil
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

local function testSendGroupUsesModernPartyApis()
    local ns, sent = resetHarness({ legacyGroupApis = false, groupMembers = 2, inRaid = false })

    local ok = ns.Comm:SendGroup("STATE", "state")

    assertEqual(ok, true, "modern group send succeeds")
    assertEqual(sent[1].channel, "PARTY", "modern group send chooses party")
    assertEqual(sent[1].text, "WRLv1|STATE|state", "modern group state payload")
end

local function testSendGroupUsesModernRaidApis()
    local ns, sent = resetHarness({ legacyGroupApis = false, groupMembers = 5, inRaid = true })

    local ok = ns.Comm:SendGroup("STATE", "state")

    assertEqual(ok, true, "modern raid send succeeds")
    assertEqual(sent[1].channel, "RAID", "modern group send chooses raid")
    assertEqual(sent[1].text, "WRLv1|STATE|state", "modern raid state payload")
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
testSendGroupUsesModernPartyApis()
testSendGroupUsesModernRaidApis()
testSendGuildUsesGuildChannel()
testReceiveDispatchesRegisteredMultiplayerOpWithoutBreakingBankOps()

print("CommRouting.test.lua: ok")
