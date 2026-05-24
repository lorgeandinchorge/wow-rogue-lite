-- Core/Pricing.lua
-- Optional pricing adapter.  TSM is useful when present, but WoWRoguelite
-- must keep working when it is absent or its API shape changes.

local ADDON_NAME, ns = ...
local Pricing = ns:NewModule("Pricing")

function Pricing:Init() end

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
