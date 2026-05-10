local function resetHarness(isBankCharacter)
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

    local markedSeen
    local ns = {
        commPrefix = "WRL_COMM",
        Database = {},
        BankStatus = {
            MarkSeen = function(_, key)
                markedSeen = key
            end,
        },
        On = function() end,
        UnitKey = function()
            return isBankCharacter and "Bank-Realm" or "Run-Realm"
        end,
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns.Database:IsBankCharacter()
        return isBankCharacter == true
    end

    assert(loadfile("Core/Comm.lua"))("WoWRoguelite", ns)
    return ns, sent, function() return markedSeen end
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function testSendPresencePingWhispersBank()
    local ns, sent = resetHarness(false)

    local ok = ns.Comm:SendPresencePing("Bank-Realm")

    assertEqual(ok, true, "presence ping returns send result")
    assertEqual(#sent, 1, "presence ping sends one message")
    assertEqual(sent[1].prefix, "WRL_COMM", "presence ping prefix")
    assertEqual(sent[1].text, "WRLv1|PING|Run-Realm", "presence ping payload")
    assertEqual(sent[1].channel, "WHISPER", "presence ping channel")
    assertEqual(sent[1].target, "Bank-Realm", "presence ping target")
end

local function testBankRepliesToPresencePing()
    local ns, sent = resetHarness(true)

    ns.Comm:Receive("WRLv1|PING|Run-Realm", "Run-Realm", "WHISPER")

    assertEqual(#sent, 1, "bank replies with one presence pong")
    assertEqual(sent[1].text, "WRLv1|PONG|Bank-Realm", "presence pong payload")
    assertEqual(sent[1].target, "Run-Realm", "presence pong target")
end

local function testPongMarksBankSeen()
    local ns, _, markedSeen = resetHarness(false)

    ns.Comm:Receive("WRLv1|PONG|Bank-Realm", "Bank-Realm", "WHISPER")

    assertEqual(markedSeen(), "Bank-Realm", "presence pong marks bank seen")
end

testSendPresencePingWhispersBank()
testBankRepliesToPresencePing()
testPongMarksBankSeen()

print("CommPresence.test.lua: ok")
