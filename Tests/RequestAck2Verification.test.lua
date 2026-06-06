local function resetHarness()
    WRL_DB = {
        bankCharacter = "Bank-Realm",
        characters = {
            ["Runner-Realm"] = {
                key = "Runner-Realm",
                claimedTiers = {},
                livesRemaining = 1,
            },
        },
    }
    WRL_CharDB = {
        outgoing = {},
    }

    _G.time = function() return 12345 end
    _G.NUM_BAG_SLOTS = nil

    local refreshes = 0
    local multiplayerEvents = {}
    local ns = {
        Database = {},
        Debug = function() end,
        Print = function() end,
        On = function() end,
        MainFrame = {
            RefreshCurrentTab = function()
                refreshes = refreshes + 1
            end,
        },
        Multiplayer = {
            BroadcastEvent = function(_, kind, detail)
                multiplayerEvents[#multiplayerEvents + 1] = {
                    kind = kind,
                    detail = detail,
                }
                return true
            end,
        },
        Comm = {
            SendAck = function() end,
            SendAck2 = function() end,
        },
        Rewards = {},
        _refreshes = function() return refreshes end,
        _multiplayerEvents = multiplayerEvents,
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns:UnitKey()
        return "Runner-Realm"
    end

    function ns.Database:GetCharacter(key)
        return WRL_DB.characters[key]
    end

    function ns.Database:MarkTierClaimed(characterKey, tierId, claimInfo)
        local rec = self:GetCharacter(characterKey)
        if not rec then return end
        rec.claimedTiers = rec.claimedTiers or {}
        if not rec.claimedTiers[tierId] then
            rec.claimedTiers[tierId] = claimInfo or { when = time() }
        end
    end

    function ns.Database:AppendFulfillmentReceipt(receipt)
        WRL_DB.fulfillmentReceipts = WRL_DB.fulfillmentReceipts or {}
        WRL_DB.fulfillmentReceipts[#WRL_DB.fulfillmentReceipts + 1] = receipt
    end

    function ns.Database:AccountIdForCharacter()
        return nil
    end

    function ns.Rewards:BuildRewardForTierIds()
        return {
            items = {},
            gold = 1500,
            extraLives = 1,
        }
    end

    assert(loadfile("Core/Vendor.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/Pricing.lua"))("WoWRoguelite", ns)
    assert(loadfile("Core/Requests.lua"))("WoWRoguelite", ns)
    return ns
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function seedOutgoing(ns, id, bankKey)
    WRL_CharDB.outgoing[1] = {
        id = id,
        when = 100,
        bank = bankKey or "Bank-Realm",
        tierIds = { 101, 201 },
        status = "sent",
    }
    return WRL_CharDB.outgoing[1]
end

local function ack2Fields(overrides)
    local fields = {
        status = "fulfilled",
        method = "mail",
        when = 12340,
        tierIds = { 101, 201 },
        gold = 1500,
        extraLives = 1,
        banker = "Bank-Realm",
        items = { { id = 4496, qty = 1 } },
    }
    for k, v in pairs(overrides or {}) do fields[k] = v end
    return fields
end

local function testAck2IgnoresUnknownRequestId()
    local ns = resetHarness()
    seedOutgoing(ns, "req-1")

    local ok, reason = ns.Requests:OnAck2("missing-req", ack2Fields())

    assertEqual(ok, false, "unknown request id is rejected")
    assertEqual(reason, "unknown_request", "unknown request id reason")
    assertEqual(WRL_CharDB.outgoing[1].status, "sent", "unknown ACK2 does not mutate outgoing request")
    assertEqual(WRL_DB.characters["Runner-Realm"].claimedTiers[101], nil, "unknown ACK2 does not claim rewards")
end

local function testAck2RejectsWrongBanker()
    local ns = resetHarness()
    seedOutgoing(ns, "req-1")

    local ok, reason = ns.Requests:OnAck2("req-1", ack2Fields({ banker = "Stranger-Realm" }))

    assertEqual(ok, false, "wrong banker ACK2 is not auto-confirmed")
    assertEqual(reason, "invalid_banker", "wrong banker reason")
    assertEqual(WRL_CharDB.outgoing[1].status, "needs_review", "wrong banker moves request to review")
    assertEqual(WRL_DB.characters["Runner-Realm"].claimedTiers[101], nil, "wrong banker does not claim reward")
end

local function testDuplicateAck2IsSuppressed()
    local ns = resetHarness()
    local row = seedOutgoing(ns, "req-1")

    local ok = ns.Requests:OnAck2("req-1", ack2Fields())
    local duplicateOk, duplicateReason = ns.Requests:OnAck2("req-1", ack2Fields({ when = 12399, gold = 9999 }))

    assertEqual(ok, true, "first ACK2 confirms")
    assertEqual(duplicateOk, false, "duplicate ACK2 is suppressed")
    assertEqual(duplicateReason, "duplicate_ack2", "duplicate ACK2 reason")
    assertEqual(row.fulfillment.gold, 1500, "duplicate ACK2 does not overwrite fulfillment")
    assertEqual(row.ack2Count, 1, "duplicate ACK2 count stays one")
end

local function testValidAck2AutoConfirmsAndClaimsLocally()
    local ns = resetHarness()
    local row = seedOutgoing(ns, "req-1")

    local ok, reason = ns.Requests:OnAck2("req-1", ack2Fields())

    assertEqual(ok, true, "valid ACK2 auto-confirms")
    assertEqual(reason, "confirmed", "valid ACK2 reason")
    assertEqual(row.status, "confirmed", "valid ACK2 stores local confirmed status")
    assertEqual(row.verificationStatus, "confirmed", "valid ACK2 stores verification status")
    assertEqual(row.fulfillment.banker, "Bank-Realm", "valid ACK2 stores banker metadata")
    assertEqual(row.fulfillment.method, "mail", "valid ACK2 stores method metadata")
    assertEqual(WRL_DB.characters["Runner-Realm"].claimedTiers[101].fulfilledBy, "Bank-Realm", "valid ACK2 claims first tier locally")
    assertEqual(WRL_DB.characters["Runner-Realm"].claimedTiers[201].method, "mail", "valid ACK2 claims second tier locally")
    assertEqual(WRL_DB.characters["Runner-Realm"].livesRemaining, 2, "valid ACK2 applies local extra life")
end

local function testOutgoingRequestBroadcastsAuditEvent()
    local ns = resetHarness()

    ns.Requests:EnqueueOutgoing("Bank-Realm", { 101, 201 }, "")

    assertEqual(ns._multiplayerEvents[1].kind, "request_created", "outgoing request broadcasts audit event")
    assertEqual(ns._multiplayerEvents[1].detail, "Rewards 101, 201 to Bank", "outgoing request audit detail")
end

local function testValidAck2BroadcastsConfirmedAuditEvent()
    local ns = resetHarness()
    seedOutgoing(ns, "req-1")

    ns.Requests:OnAck2("req-1", ack2Fields())

    assertEqual(ns._multiplayerEvents[1].kind, "request_confirmed", "valid ACK2 broadcasts confirmed audit event")
    assertEqual(ns._multiplayerEvents[1].detail, "Rewards 101, 201 by Bank", "valid ACK2 audit detail")
end

local function testBankFulfillmentBroadcastsAuditEvent()
    local ns = resetHarness()
    WRL_DB.requests = {
        {
            id = "req-1",
            from = "Runner-Realm",
            tierIds = { 101, 201 },
            status = "pending",
        },
    }

    ns.Requests:MarkFulfilled("req-1")

    assertEqual(ns._multiplayerEvents[1].kind, "bank_fulfilled", "bank fulfillment broadcasts audit event")
    assertEqual(ns._multiplayerEvents[1].detail, "Rewards 101, 201 for Runner", "bank fulfillment audit detail")
end

local function testLegacyAckFulfilledNeedsReviewAndCanBeManuallyConfirmed()
    local ns = resetHarness()
    local row = seedOutgoing(ns, "req-1")

    local ok, reason = ns.Requests:OnAck("req-1", "fulfilled")

    assertEqual(ok, false, "legacy fulfilled ACK is not enough to auto-confirm")
    assertEqual(reason, "missing_ack2", "legacy fulfilled ACK records missing ACK2 reason")
    assertEqual(row.status, "needs_review", "legacy fulfilled ACK moves request to review")
    assertEqual(WRL_DB.characters["Runner-Realm"].claimedTiers[101], nil, "legacy ACK does not claim rewards")

    local manualOk, manualReason = ns.Requests:ManualConfirmOutgoing("req-1", "mail checked")

    assertEqual(manualOk, true, "manual review fallback confirms")
    assertEqual(manualReason, "manual_confirmed", "manual review reason")
    assertEqual(row.status, "manual_confirmed", "manual review stores local status")
    assertEqual(row.verificationStatus, "manual_confirmed", "manual review stores verification status")
    assertEqual(row.manualReviewNote, "mail checked", "manual review stores player note")
    assertEqual(WRL_DB.characters["Runner-Realm"].claimedTiers[101].method, "manual_review", "manual review claims reward locally")
end

local function testExistingBankRequestMessageStillUsesClientRequestId()
    WRL_DB = {
        bankCharacter = "Bank-Realm",
        requests = {},
    }
    WRL_CharDB = { outgoing = {} }

    local ns = {
        commPrefix = "WRL_COMM",
        Database = {},
        Requests = {},
        On = function() end,
        UnitKey = function() return "Bank-Realm" end,
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns.Database:IsBankCharacter() return true end
    function ns.Database:AccountIdForCharacter() return nil end
    function ns.Requests:OnIncoming(fromKey, tierIds, note, via, requestId)
        WRL_DB.requests[#WRL_DB.requests + 1] = {
            from = fromKey,
            tierIds = tierIds,
            note = note,
            via = via,
            id = requestId,
        }
    end

    assert(loadfile("Core/Comm.lua"))("WoWRoguelite", ns)

    ns.Comm:Receive("WRLv1|REQ|Runner-Realm|101,201|please|client-req-7", "Runner-Realm", "WHISPER")

    assertEqual(#WRL_DB.requests, 1, "legacy bank request message is still accepted")
    assertEqual(WRL_DB.requests[1].id, "client-req-7", "client request id remains compatible")
    assertEqual(WRL_DB.requests[1].tierIds[2], 201, "request tiers still parse")
end

testAck2IgnoresUnknownRequestId()
testAck2RejectsWrongBanker()
testDuplicateAck2IsSuppressed()
testValidAck2AutoConfirmsAndClaimsLocally()
testOutgoingRequestBroadcastsAuditEvent()
testValidAck2BroadcastsConfirmedAuditEvent()
testBankFulfillmentBroadcastsAuditEvent()
testLegacyAckFulfilledNeedsReviewAndCanBeManuallyConfirmed()
testExistingBankRequestMessageStillUsesClientRequestId()

print("RequestAck2Verification.test.lua: ok")
