-- Core/Vendor.lua
-- Computes vendor sell-value of bag contents. Used to summarize what a run
-- "contributed" at the moment of death (money + items converted at vendor price).
--
-- BC API notes:
--   GetContainerNumSlots(bag)                 - slot count. bag 0 = backpack, 1..4 = bags.
--   GetContainerItemInfo(bag, slot)           - icon,count,locked,quality,readable,lootable,link,isFiltered,hasNoValue,itemID
--                                               On older BC clients hasNoValue/itemID may be nil; we fall back to GetItemInfo.
--   GetItemInfo(linkOrID)                     - ...,sellPrice = position 11
--   GetMoney()                                - current player copper

local ADDON_NAME, ns = ...
local V = ns:NewModule("Vendor")
local Container = ns.Container or {}
ns.Container = Container
local MAIL_POSTAGE_COPPER = 30
ns.MAIL_POSTAGE_COPPER = ns.MAIL_POSTAGE_COPPER or MAIL_POSTAGE_COPPER

function V:Init() end

function V:NetAfterPostage(copper)
    return math.max(0, math.floor(copper or 0) - (ns.MAIL_POSTAGE_COPPER or MAIL_POSTAGE_COPPER))
end

local function itemIDFromLink(link)
    return link and tonumber(tostring(link):match("item:(%d+)")) or nil
end

local function normaliseItemInfo(first, stackCount, _locked, _quality, _readable, _lootable, itemLink, _isFiltered, hasNoValue, itemID)
    if type(first) == "table" then
        local info = first
        local link = info.hyperlink or info.itemLink
        return {
            count = info.stackCount or info.quantity or info.count or 1,
            link = link,
            hasNoValue = info.hasNoValue,
            itemID = info.itemID or itemIDFromLink(link),
        }
    end

    return {
        count = stackCount or 1,
        link = itemLink,
        hasNoValue = hasNoValue,
        itemID = itemID or itemIDFromLink(itemLink),
    }
end

function Container:GetNumSlots(bag)
    local getNumSlots = GetContainerNumSlots
        or (C_Container and C_Container.GetContainerNumSlots)
    return getNumSlots and (getNumSlots(bag) or 0) or 0
end

function Container:GetItemInfo(bag, slot)
    local getItemInfo = GetContainerItemInfo
        or (C_Container and C_Container.GetContainerItemInfo)
    if not getItemInfo then return nil end

    local first, stackCount, locked, quality, readable, lootable, itemLink, isFiltered, hasNoValue, itemID =
        getItemInfo(bag, slot)
    if first == nil and stackCount == nil and itemLink == nil and itemID == nil then return nil end
    return normaliseItemInfo(first, stackCount, locked, quality, readable, lootable, itemLink, isFiltered, hasNoValue, itemID)
end

-- Returns vendor copper for a single stack. Returns 0 if unknown (e.g. item
-- info not yet cached or item is a no-vendor item).
function V:StackValue(link, count)
    if not link then return 0 end
    local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(link)
    if not sellPrice or sellPrice == 0 then return 0 end
    return sellPrice * (count or 1)
end

-- Walk all bags. Returns: totalCopper, list{ {link, count, sellPrice, copper} ... }
-- Soulbound filtering is intentionally NOT applied — player decides what to
-- actually mail. We just show the total potential value.
function V:BagsSnapshot()
    local total = 0
    local items = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots = Container:GetNumSlots(bag)
        for slot = 1, slots do
            local info = Container:GetItemInfo(bag, slot)
            if info and info.link and not info.hasNoValue then
                local copper = self:StackValue(info.link, info.count or 1)
                if copper > 0 then
                    total = total + copper
                    items[#items+1] = {
                        link = info.link, count = info.count or 1,
                        sellPrice = copper / (info.count or 1),
                        copper = copper,
                    }
                end
            end
        end
    end
    return total, items
end

-- Walk equipped inventory slots. Returns:
-- totalCopper, list{ {slot, link, count, sellPrice, copper} ... }
--
-- Most equipped gear cannot be mailed directly, but its sell value matters for
-- the "maximum possible if you sell everything first" death estimate.
function V:EquipmentSnapshot()
    local total = 0
    local items = {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        if link then
            local copper = self:StackValue(link, 1)
            if copper > 0 then
                total = total + copper
                items[#items + 1] = {
                    slot = slot,
                    link = link,
                    count = 1,
                    sellPrice = copper,
                    copper = copper,
                }
            end
        end
    end
    return total, items
end

-- Snapshot carried money, bag value, and equipped gear value separately.
-- Returns a table so death/contribution code can store an auditable estimate.
function V:FullCharacterSnapshot()
    local bagValue, bagItems = self:BagsSnapshot()
    local gearValue, gearItems = self:EquipmentSnapshot()
    local money = GetMoney and (GetMoney() or 0) or 0
    return {
        money = money,
        bagValue = bagValue or 0,
        gearValue = gearValue or 0,
        maximumPotential = self:NetAfterPostage(money + (bagValue or 0) + (gearValue or 0)),
        bagItems = bagItems or {},
        gearItems = gearItems or {},
    }
end

-- Sum of carried money + vendorable bag contents. This is what "goes to the bank"
-- conceptually on death (the player still has to mail it manually).
function V:TotalLiquidValue()
    local bagsCopper = select(1, self:BagsSnapshot())
    return (GetMoney() or 0) + bagsCopper, bagsCopper
end
