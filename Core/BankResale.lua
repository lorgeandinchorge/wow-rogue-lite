-- Core/BankResale.lua
-- Bank-side resale catalog for useful quest and leveling goods. The addon
-- prices and records manual sales; it never moves, mails, trades, or vendors
-- items automatically.

local ADDON_NAME, ns = ...
local BR = ns:NewModule("BankResale")

local CATALOG = {
    -- Low-level meats and organs.
    { id = 769,  name = "Chunk of Boar Meat", fallbackCopper = 25 },
    { id = 723,  name = "Goretusk Liver", fallbackCopper = 50 },
    { id = 729,  name = "Stringy Vulture Meat", fallbackCopper = 25 },
    { id = 731,  name = "Goretusk Snout", fallbackCopper = 50 },
    { id = 1015, name = "Lean Wolf Flank", fallbackCopper = 80 },
    { id = 1080, name = "Tough Condor Meat", fallbackCopper = 80 },
    { id = 2672, name = "Stringy Wolf Meat", fallbackCopper = 25 },
    { id = 2673, name = "Coyote Meat", fallbackCopper = 35 },
    { id = 2674, name = "Crawler Meat", fallbackCopper = 35 },
    { id = 2675, name = "Crawler Claw", fallbackCopper = 35 },
    { id = 2924, name = "Crocolisk Meat", fallbackCopper = 50 },
    { id = 3173, name = "Bear Meat", fallbackCopper = 50 },
    { id = 3667, name = "Tender Crocolisk Meat", fallbackCopper = 120 },
    { id = 3712, name = "Turtle Meat", fallbackCopper = 150 },
    { id = 5465, name = "Small Spider Leg", fallbackCopper = 35 },
    { id = 5469, name = "Strider Meat", fallbackCopper = 50 },
    { id = 5503, name = "Clam Meat", fallbackCopper = 50 },
    { id = 5504, name = "Tangy Clam Meat", fallbackCopper = 100 },
    { id = 12202, name = "Tiger Meat", fallbackCopper = 150 },
    { id = 12203, name = "Red Wolf Meat", fallbackCopper = 150 },
    { id = 12204, name = "Heavy Kodo Meat", fallbackCopper = 180 },
    { id = 12205, name = "White Spider Meat", fallbackCopper = 180 },
    { id = 12206, name = "Tender Crab Meat", fallbackCopper = 180 },
    { id = 12207, name = "Giant Egg", fallbackCopper = 200 },
    { id = 12208, name = "Tender Wolf Meat", fallbackCopper = 220 },
    { id = 27668, name = "Lynx Meat", fallbackCopper = 90 },
    { id = 27669, name = "Bat Flesh", fallbackCopper = 90 },
    { id = 27671, name = "Buzzard Meat", fallbackCopper = 150 },
    { id = 27674, name = "Ravager Flesh", fallbackCopper = 180 },
    { id = 27677, name = "Chunk o' Basilisk", fallbackCopper = 180 },
    { id = 27678, name = "Clefthoof Meat", fallbackCopper = 220 },
    { id = 27681, name = "Warped Flesh", fallbackCopper = 220 },
    { id = 27682, name = "Talbuk Venison", fallbackCopper = 220 },

    -- Cloth and common hand-in materials.
    { id = 2589, name = "Linen Cloth", fallbackCopper = 20 },
    { id = 2592, name = "Wool Cloth", fallbackCopper = 40 },
    { id = 4306, name = "Silk Cloth", fallbackCopper = 80 },
    { id = 4338, name = "Mageweave Cloth", fallbackCopper = 120 },
    { id = 14047, name = "Runecloth", fallbackCopper = 180 },
    { id = 21877, name = "Netherweave Cloth", fallbackCopper = 220 },

    -- Creature drops that are commonly useful for quests or stocking.
    { id = 730,  name = "Murloc Eye", fallbackCopper = 35 },
    { id = 1468, name = "Murloc Fin", fallbackCopper = 35 },
    { id = 2251, name = "Gooey Spider Leg", fallbackCopper = 35 },
    { id = 2296, name = "Great Goretusk Snout", fallbackCopper = 75 },
    { id = 2318, name = "Light Leather", fallbackCopper = 40 },
    { id = 2319, name = "Medium Leather", fallbackCopper = 80 },
    { id = 2934, name = "Ruined Leather Scraps", fallbackCopper = 20 },
    { id = 3183, name = "Mangy Claw", fallbackCopper = 35 },
    { id = 3404, name = "Buzzard Wing", fallbackCopper = 75 },
    { id = 3685, name = "Raptor Egg", fallbackCopper = 80 },
    { id = 3689, name = "Bloodstone Marble", fallbackCopper = 60 },
    { id = 3713, name = "Soothing Spices", fallbackCopper = 40 },
    { id = 4232, name = "Medium Hide", fallbackCopper = 120 },
    { id = 5635, name = "Sharp Claw", fallbackCopper = 80 },
    { id = 5637, name = "Large Fang", fallbackCopper = 120 },
    { id = 5784, name = "Slimy Murloc Scale", fallbackCopper = 80 },
    { id = 5785, name = "Thick Murloc Scale", fallbackCopper = 120 },
    { id = 6289, name = "Raw Longjaw Mud Snapper", fallbackCopper = 35 },
    { id = 6303, name = "Raw Slitherskin Mackerel", fallbackCopper = 35 },
    { id = 6308, name = "Raw Bristle Whisker Catfish", fallbackCopper = 75 },
    { id = 6358, name = "Oily Blackmouth", fallbackCopper = 120 },
    { id = 6359, name = "Firefin Snapper", fallbackCopper = 120 },
    { id = 7070, name = "Elemental Water", fallbackCopper = 250 },
    { id = 7077, name = "Heart of Fire", fallbackCopper = 250 },
    { id = 7078, name = "Essence of Fire", fallbackCopper = 400 },
    { id = 8150, name = "Deeprock Salt", fallbackCopper = 180 },
    { id = 12808, name = "Essence of Undeath", fallbackCopper = 400 },
}

local catalogById = {}
for _, item in ipairs(CATALOG) do
    catalogById[item.id] = item
end

function BR:Init()
    WRL_DB = WRL_DB or {}
    WRL_DB.resaleReceipts = WRL_DB.resaleReceipts or {}
    WRL_DB.resaleSimStock = WRL_DB.resaleSimStock or {}
end

function BR:Catalog()
    return CATALOG
end

function BR:CatalogItem(itemId)
    return catalogById[tonumber(itemId or 0)]
end

function BR:IsCatalogItem(itemId)
    return self:CatalogItem(itemId) ~= nil
end

function BR:ItemName(itemId)
    local catalogItem = self:CatalogItem(itemId)
    local liveName = GetItemInfo and select(1, GetItemInfo(tonumber(itemId))) or nil
    if type(liveName) == "string" and liveName ~= "" then return liveName end
    return catalogItem and catalogItem.name or ("item:" .. tostring(itemId))
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function shortRecipient(value)
    local name = trim(value)
    return name:match("^([^-]+)") or name
end

local function sendMailBodyEditBox()
    if SendMailBodyEditBox and SendMailBodyEditBox.SetText then return SendMailBodyEditBox end
    if _G and _G.SendMailBodyEditBox and _G.SendMailBodyEditBox.SetText then return _G.SendMailBodyEditBox end
    if SendMailBodyScrollFrame and SendMailBodyScrollFrame.EditBox and SendMailBodyScrollFrame.EditBox.SetText then
        return SendMailBodyScrollFrame.EditBox
    end
    if SendMailFrame then
        return (SendMailFrame.BodyEditBox and SendMailFrame.BodyEditBox.SetText and SendMailFrame.BodyEditBox)
            or (SendMailFrame.bodyEditBox and SendMailFrame.bodyEditBox.SetText and SendMailFrame.bodyEditBox)
            or (SendMailFrame.Body and SendMailFrame.Body.SetText and SendMailFrame.Body)
            or nil
    end
end

local function prefillSendMailBody(body)
    local function apply()
        local editBox = sendMailBodyEditBox()
        if not editBox then return false end
        editBox:SetText(body or "")
        if editBox.ClearFocus then editBox:ClearFocus() end
        return true
    end
    local ok = apply()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() apply() end)
    end
    return ok
end

function BR:PriceForItem(itemId)
    local catalogItem = self:CatalogItem(itemId)
    if not catalogItem then return nil, "not_catalog" end
    local fallback = math.max(0, math.floor(tonumber(catalogItem.fallbackCopper or 0) or 0))
    if ns.Pricing and ns.Pricing.ResalePrice then
        local detail, reason, label = ns.Pricing:ResalePrice(itemId, fallback)
        if not detail then
            return nil, reason or "no_price", {
                sourceId = "unpriced",
                sourceLabel = label or "No price",
            }
        end
        return detail.copper or 0, nil, detail
    end
    local sellPrice = 0
    if GetItemInfo then
        local _, _, _, _, _, _, _, _, _, _, liveSellPrice = GetItemInfo(tonumber(itemId))
        sellPrice = tonumber(liveSellPrice or 0) or 0
    end
    local copper = math.max(fallback, sellPrice * 2)
    return copper, nil, {
        copper = copper,
        sourceId = (sellPrice * 2) > fallback and "double_vendor" or "catalog_fallback",
        sourceLabel = (sellPrice * 2) > fallback and "double vendor" or "catalog fallback",
    }
end

function BR:CODSubject()
    return "Roguelite resale desk"
end

function BR:CODBody(draft)
    local money = ns.Tiers and ns.Tiers.FormatMoney and ns.Tiers:FormatMoney(draft.totalCopper or 0) or tostring(draft.totalCopper or 0)
    local lines = {
        "Resale desk fulfillment.",
        "",
        ("Item: %dx %s"):format(draft.qty or 0, draft.itemName or ("item:" .. tostring(draft.itemId))),
        ("COD due: %s"):format(money),
        ("Price source: %s"):format(draft.priceLabel or "unknown"),
        "",
        "Here are the items you ordered. The bank has selected a price and is trying to look casual about it.",
    }
    return table.concat(lines, "\n")
end

function BR:PrepareCODMail(itemId, qty, buyer)
    itemId = tonumber(itemId)
    qty = math.floor(tonumber(qty) or 0)
    buyer = trim(buyer)
    if not itemId or not self:IsCatalogItem(itemId) then
        return nil, "not_catalog"
    end
    if qty <= 0 then
        return nil, "bad_qty"
    end
    if buyer == "" then
        return nil, "missing_buyer"
    end
    if not MailFrame or not MailFrame.IsShown or not MailFrame:IsShown() then
        return nil, "mailbox_closed"
    end

    local codFrame = SendMailCOD or SendMailCODMoney
    if not codFrame or not MoneyInputFrame_SetCopper then
        return nil, "cod_unavailable"
    end

    if MailFrameTab2 and MailFrameTab2.Click then MailFrameTab2:Click() end

    local priceEach, priceReason, priceDetail = self:PriceForItem(itemId)
    if not priceEach then
        return nil, "no_price", priceReason
    end
    local draft = {
        itemId = itemId,
        itemName = self:ItemName(itemId),
        qty = qty,
        priceEach = priceEach,
        priceSource = priceDetail and priceDetail.sourceId or nil,
        priceLabel = priceDetail and priceDetail.sourceLabel or nil,
        totalCopper = priceEach * qty,
        buyer = buyer,
        seller = ns.UnitKey and ns:UnitKey() or nil,
        when = time and time() or 0,
    }

    if SendMailNameEditBox then SendMailNameEditBox:SetText(shortRecipient(buyer)) end
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(self:CODSubject()) end
    prefillSendMailBody(self:CODBody(draft))
    if SendMailMoney then MoneyInputFrame_SetCopper(SendMailMoney, 0) end
    MoneyInputFrame_SetCopper(codFrame, draft.totalCopper)

    self.pendingCOD = draft
    ns:Print("Prepared COD resale mail for %s: attach %dx %s, COD %s.",
        buyer,
        qty,
        draft.itemName,
        ns.Tiers and ns.Tiers.FormatMoney and ns.Tiers:FormatMoney(draft.totalCopper) or tostring(draft.totalCopper))
    if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
        ns.MainFrame:RefreshCurrentTab()
    end
    return draft
end

function BR:SimulateStock(entries, buyer)
    WRL_DB = WRL_DB or {}
    local nextStock = {}
    for _, entry in ipairs(entries or {}) do
        local itemId = tonumber(entry.itemId or entry.id)
        local qty = math.max(0, math.floor(tonumber(entry.qty or entry.count) or 0))
        if itemId and qty > 0 then
            if not self:IsCatalogItem(itemId) then
                return false, "not_catalog"
            end
            nextStock[#nextStock + 1] = {
                itemId = itemId,
                qty = qty,
            }
        end
    end
    WRL_DB.resaleSimStock = nextStock
    buyer = trim(buyer)
    if buyer ~= "" then
        WRL_DB.resaleSimBuyer = buyer
    end
    if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
        ns.MainFrame:RefreshCurrentTab()
    end
    return true
end

function BR:SimulatedBuyer()
    return trim(WRL_DB and WRL_DB.resaleSimBuyer)
end

function BR:ClearSimulatedStock()
    WRL_DB = WRL_DB or {}
    WRL_DB.resaleSimStock = {}
    WRL_DB.resaleSimBuyer = nil
    if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
        ns.MainFrame:RefreshCurrentTab()
    end
    return true
end

function BR:RemoveSimulatedStock(itemId)
    WRL_DB = WRL_DB or {}
    itemId = tonumber(itemId)
    if not itemId then return false, "bad_item" end
    local nextStock = {}
    local removed = false
    for _, entry in ipairs(WRL_DB.resaleSimStock or {}) do
        if tonumber(entry.itemId) == itemId then
            removed = true
        else
            nextStock[#nextStock + 1] = entry
        end
    end
    WRL_DB.resaleSimStock = nextStock
    if #nextStock == 0 then
        WRL_DB.resaleSimBuyer = nil
    end
    if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
        ns.MainFrame:RefreshCurrentTab()
    end
    if removed then return true end
    return false, "not_found"
end

function BR:ConsumeSimulatedStock(itemId, qty)
    WRL_DB = WRL_DB or {}
    itemId = tonumber(itemId)
    qty = math.max(0, math.floor(tonumber(qty) or 0))
    if not itemId then return false, "bad_item" end
    if qty <= 0 then return false, "bad_qty" end

    local remainingToConsume = qty
    local consumed = false
    local nextStock = {}
    for _, entry in ipairs(WRL_DB.resaleSimStock or {}) do
        local entryItemId = tonumber(entry.itemId)
        local entryQty = math.max(0, math.floor(tonumber(entry.qty) or 0))
        if entryItemId == itemId and remainingToConsume > 0 then
            consumed = true
            if entryQty > remainingToConsume then
                entry.qty = entryQty - remainingToConsume
                remainingToConsume = 0
                nextStock[#nextStock + 1] = entry
            else
                remainingToConsume = remainingToConsume - entryQty
            end
        else
            nextStock[#nextStock + 1] = entry
        end
    end
    WRL_DB.resaleSimStock = nextStock
    if #nextStock == 0 then
        WRL_DB.resaleSimBuyer = nil
    end
    if consumed then return true end
    return false, "not_found"
end

local function bankFrameShown()
    if not BankFrame then return false end
    if BankFrame.IsShown then return BankFrame:IsShown() end
    return true
end

local function scanBagIds()
    local ids = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        ids[#ids + 1] = bag
    end
    if bankFrameShown() then
        ids[#ids + 1] = -1
        local firstBankBag = (NUM_BAG_SLOTS or 4) + 1
        local lastBankBag = firstBankBag + (NUM_BANKBAGSLOTS or 7) - 1
        for bag = firstBankBag, lastBankBag do
            ids[#ids + 1] = bag
        end
    end
    return ids
end

function BR:InventoryRows()
    local byId = {}
    local Container = ns.Container
    for _, bag in ipairs(scanBagIds()) do
        local slots = Container and Container.GetNumSlots and Container:GetNumSlots(bag) or 0
        for slot = 1, slots do
            local info = Container and Container.GetItemInfo and Container:GetItemInfo(bag, slot)
            local itemId = info and tonumber(info.itemID)
            local qty = info and math.max(0, math.floor(info.count or 1)) or 0
            if itemId and qty > 0 and self:IsCatalogItem(itemId) then
                local row = byId[itemId]
                if not row then
                    local price, _, priceDetail = self:PriceForItem(itemId)
                    price = price or 0
                    row = {
                        itemId = itemId,
                        name = self:ItemName(itemId),
                        count = 0,
                        priceEach = price,
                        priceSource = priceDetail and priceDetail.sourceId or nil,
                        priceLabel = priceDetail and priceDetail.sourceLabel or nil,
                        totalCopper = 0,
                    }
                    byId[itemId] = row
                end
                row.count = row.count + qty
                row.totalCopper = row.count * row.priceEach
            end
        end
    end
    for _, sim in ipairs((WRL_DB and WRL_DB.resaleSimStock) or {}) do
        local itemId = tonumber(sim.itemId)
        local qty = math.max(0, math.floor(tonumber(sim.qty) or 0))
        if itemId and qty > 0 and self:IsCatalogItem(itemId) then
            local row = byId[itemId]
            if not row then
                local price, _, priceDetail = self:PriceForItem(itemId)
                price = price or 0
                row = {
                    itemId = itemId,
                    name = self:ItemName(itemId),
                    count = 0,
                    priceEach = price,
                    priceSource = priceDetail and priceDetail.sourceId or nil,
                    priceLabel = priceDetail and priceDetail.sourceLabel or nil,
                    totalCopper = 0,
                    simulated = true,
                }
                byId[itemId] = row
            end
            row.count = row.count + qty
            row.totalCopper = row.count * row.priceEach
            row.simulated = true
        end
    end

    local rows = {}
    for _, row in pairs(byId) do rows[#rows + 1] = row end
    table.sort(rows, function(a, b)
        if tostring(a.name) == tostring(b.name) then
            return (a.itemId or 0) < (b.itemId or 0)
        end
        return tostring(a.name) < tostring(b.name)
    end)
    return rows
end

function BR:RecordSale(itemId, qty, buyer)
    itemId = tonumber(itemId)
    qty = math.floor(tonumber(qty) or 0)
    if not itemId or not self:IsCatalogItem(itemId) then
        return nil, "not_catalog"
    end
    if qty <= 0 then
        return nil, "bad_qty"
    end

    WRL_DB = WRL_DB or {}
    WRL_DB.resaleReceipts = WRL_DB.resaleReceipts or {}
    local priceEach, priceReason, priceDetail = self:PriceForItem(itemId)
    if not priceEach then
        return nil, "no_price", priceReason
    end
    local receipt = {
        when = time and time() or 0,
        itemId = itemId,
        itemName = self:ItemName(itemId),
        qty = qty,
        priceEach = priceEach,
        priceSource = priceDetail and priceDetail.sourceId or nil,
        priceLabel = priceDetail and priceDetail.sourceLabel or nil,
        totalCopper = priceEach * qty,
        buyer = buyer and buyer ~= "" and buyer or nil,
        seller = ns.UnitKey and ns:UnitKey() or nil,
    }
    table.insert(WRL_DB.resaleReceipts, receipt)
    while #WRL_DB.resaleReceipts > 500 do
        table.remove(WRL_DB.resaleReceipts, 1)
    end
    if self.pendingCOD and self.pendingCOD.itemId == itemId and self.pendingCOD.qty == qty then
        self.pendingCOD = nil
    end
    self:ConsumeSimulatedStock(itemId, qty)

    if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
        ns.MainFrame:RefreshCurrentTab()
    end
    return receipt
end
