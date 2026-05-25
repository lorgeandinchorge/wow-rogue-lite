local function resetHarness()
    WRL_DB = {
        settings = {
            pricing = {
                resaleSource = "auto",
            },
        },
    }
    _G.TSM_API = nil
    _G.GetItemInfo = function(itemId)
        if tonumber(itemId) == 723 then
            return "Goretusk Liver", nil, nil, nil, nil, nil, nil, nil, nil, nil, 40
        end
        if tonumber(itemId) == 769 then
            return "Chunk of Boar Meat", nil, nil, nil, nil, nil, nil, nil, nil, nil, 1
        end
    end

    local ns = {
        Settings = {},
        Tiers = { FormatMoney = function(_, copper) return tostring(copper or 0) .. "c" end },
    }
    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end
    function ns.Settings:Get(path, default)
        if path == "pricing.resaleSource" then
            return WRL_DB.settings.pricing.resaleSource or default
        end
        return default
    end

    assert(loadfile("Core/Pricing.lua"))("WoWRoguelite", ns)
    return ns
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function testMarketValueAcceptsIAndItemStrings()
    local ns = resetHarness()
    local calls = {}
    _G.TSM_API = {
        GetCustomPriceValue = function(source, itemString)
            calls[#calls + 1] = source .. "|" .. itemString
            if itemString == "item:769" then return 1234 end
        end,
    }

    local value, label = ns.Pricing:MarketValue(769)

    assertEqual(value, 1234, "market value falls through to item:itemId format")
    assertEqual(label, "TSM DBMarket", "market value labels DBMarket")
    assertEqual(calls[1], "DBMarket|i:769", "market value tries compact item string first")
    assertEqual(calls[2], "dbmarket|i:769", "market value tries lowercase source second")
    assertEqual(calls[3], "i:769|DBMarket", "market value tolerates reversed TSM argument order")
    assertEqual(calls[5], "DBMarket|item:769", "market value tries long item string after compact attempts")
end

local function testMarketValueIgnoresInvalidZeroAndThrowingTSM()
    local ns = resetHarness()
    local count = 0
    _G.TSM_API = {
        GetCustomPriceValue = function()
            count = count + 1
            if count == 1 then return 0 end
            if count == 2 then return "nope" end
            error("TSM exploded")
        end,
    }

    local value, label = ns.Pricing:MarketValue(769)

    assertEqual(value, nil, "invalid TSM values are ignored")
    assertEqual(label, "TSM unavailable", "missing market data labels unavailable")
end

local function testAutoResalePricePrefersTSM()
    local ns = resetHarness()
    _G.TSM_API = {
        GetCustomPriceValue = function(source, itemString)
            if source == "DBMarket" and itemString == "i:769" then return 333 end
        end,
    }

    local price = ns.Pricing:ResalePrice(769, 25)

    assertEqual(price.copper, 333, "auto resale uses TSM when available")
    assertEqual(price.sourceId, "tsm_dbmarket", "auto resale source id records TSM")
    assertEqual(price.sourceLabel, "TSM DBMarket", "auto resale source label records TSM")
end

local function testAutoResalePriceFallsBackToLocal()
    local ns = resetHarness()

    local vendor = ns.Pricing:ResalePrice(723, 50)
    local fallback = ns.Pricing:ResalePrice(769, 25)

    assertEqual(vendor.copper, 80, "auto resale falls back to double vendor")
    assertEqual(vendor.sourceId, "double_vendor", "double vendor source is explicit")
    assertEqual(vendor.sourceLabel, "double vendor", "double vendor label is explicit")
    assertEqual(fallback.copper, 25, "auto resale falls back to catalog fallback")
    assertEqual(fallback.sourceId, "catalog_fallback", "catalog fallback source is explicit")
    assertEqual(ns.Pricing:ShortSourceLabel(vendor.sourceId), "vendor", "double vendor short label is explicit")
    assertEqual(ns.Pricing:ShortSourceLabel(fallback.sourceId), "fallback", "catalog fallback short label is explicit")
end

local function testStrictTSMReturnsNoPriceWhenMissing()
    local ns = resetHarness()
    WRL_DB.settings.pricing.resaleSource = "tsm_dbmarket"

    local price, reason = ns.Pricing:ResalePrice(769, 25)

    assertEqual(price, nil, "strict TSM mode does not use local fallback")
    assertEqual(reason, "no_tsm_price", "strict TSM mode reports missing price")
end

testMarketValueAcceptsIAndItemStrings()
testMarketValueIgnoresInvalidZeroAndThrowingTSM()
testAutoResalePricePrefersTSM()
testAutoResalePriceFallsBackToLocal()
testStrictTSMReturnsNoPriceWhenMissing()

print("Pricing.test.lua: ok")
