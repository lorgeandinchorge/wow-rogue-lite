-- Core/Pricing.lua
-- Optional pricing adapter.  TSM is useful when present, but WoWRoguelite
-- must keep working when it is absent or its API shape changes.

local ADDON_NAME, ns = ...
local Pricing = ns:NewModule("Pricing")

function Pricing:Init() end

local RESALE_SOURCE_ORDER = { "auto", "tsm_dbmarket", "local_fallback" }
local RESALE_SOURCE_LABELS = {
    auto = "Auto: TSM DBMarket -> double vendor -> catalog fallback",
    tsm_dbmarket = "TSM DBMarket only",
    local_fallback = "Local fallback: double vendor -> catalog fallback",
}
local RESALE_SOURCE_NOTES = {
    auto = "Uses TSM DBMarket when available, otherwise local fallback.",
    tsm_dbmarket = "Rows without TSM data cannot be priced.",
    local_fallback = "Uses double vendor or catalog fallback; does not query TSM.",
}

local function itemIdFrom(value)
    if type(value) == "number" then return value end
    local text = tostring(value or "")
    return tonumber(text:match("item:(%d+)")) or tonumber(text:match("i:(%d+)")) or tonumber(text)
end

local function callTSM(source, itemString)
    local api = _G and _G.TSM_API
    if not api or type(api.GetCustomPriceValue) ~= "function" then
        return nil
    end

    local attempts = {
        { source, itemString },
        { source:lower(), itemString },
        { itemString, source },
        { itemString, source:lower() },
    }
    for _, args in ipairs(attempts) do
        local ok, value = pcall(api.GetCustomPriceValue, args[1], args[2])
        value = tonumber(value)
        if ok and value and value > 0 then
            return math.floor(value)
        end
    end
end

function Pricing:MarketValue(item)
    local itemId = itemIdFrom(item)
    if not itemId then return nil, "TSM unavailable" end

    local value = callTSM("DBMarket", "i:" .. tostring(itemId))
        or callTSM("DBMarket", "item:" .. tostring(itemId))
    if value then
        return value, "TSM DBMarket"
    end
    return nil, "TSM unavailable"
end

function Pricing:NormalizeResaleSource(source)
    source = tostring(source or "")
    if source == "tsm_dbmarket" or source == "local_fallback" or source == "auto" then
        return source
    end
    return "auto"
end

function Pricing:ResaleSourceOptions()
    local out = {}
    for i, source in ipairs(RESALE_SOURCE_ORDER) do
        out[i] = {
            id = source,
            label = RESALE_SOURCE_LABELS[source],
            note = RESALE_SOURCE_NOTES[source],
        }
    end
    return out
end

function Pricing:ResaleSourceLabel(source)
    source = self:NormalizeResaleSource(source)
    return RESALE_SOURCE_LABELS[source]
end

function Pricing:ResaleSourceNote(source)
    source = self:NormalizeResaleSource(source)
    return RESALE_SOURCE_NOTES[source]
end

local function vendorSellPrice(itemId)
    if not GetItemInfo then return 0 end
    local _, _, _, _, _, _, _, _, _, _, liveSellPrice = GetItemInfo(tonumber(itemId))
    return math.max(0, math.floor(tonumber(liveSellPrice or 0) or 0))
end

function Pricing:LocalResalePrice(itemId, fallbackCopper)
    local fallback = math.max(0, math.floor(tonumber(fallbackCopper or 0) or 0))
    local doubledVendor = vendorSellPrice(itemId) * 2
    if doubledVendor > fallback then
        return {
            copper = doubledVendor,
            sourceId = "double_vendor",
            sourceLabel = "double vendor",
        }
    end
    return {
        copper = fallback,
        sourceId = "catalog_fallback",
        sourceLabel = "catalog fallback",
    }
end

function Pricing:ResalePrice(itemId, fallbackCopper, sourceMode)
    local mode = self:NormalizeResaleSource(sourceMode or (ns.Settings and ns.Settings.Get and ns.Settings:Get("pricing.resaleSource", "auto")) or "auto")
    if mode == "auto" or mode == "tsm_dbmarket" then
        local marketCopper, marketLabel = self:MarketValue(itemId)
        if marketCopper then
            return {
                copper = marketCopper,
                sourceId = "tsm_dbmarket",
                sourceLabel = marketLabel or "TSM DBMarket",
            }
        end
        if mode == "tsm_dbmarket" then
            return nil, "no_tsm_price", "No TSM DBMarket"
        end
    end
    return self:LocalResalePrice(itemId, fallbackCopper)
end
