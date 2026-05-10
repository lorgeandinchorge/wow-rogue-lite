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

function V:Init() end

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
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local _, count, _, _, _, _, link, _, hasNoValue = GetContainerItemInfo(bag, slot)
            if link and not hasNoValue then
                local copper = self:StackValue(link, count or 1)
                if copper > 0 then
                    total = total + copper
                    items[#items+1] = {
                        link = link, count = count or 1,
                        sellPrice = copper / (count or 1),
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
        maximumPotential = money + (bagValue or 0) + (gearValue or 0),
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
