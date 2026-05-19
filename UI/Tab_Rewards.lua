-- UI/Tab_Rewards.lua
-- Role-aware rewards workflow:
--   * run characters request unlocked legacy rewards from the bank
--   * bank characters fulfill incoming and recent reward requests

local ADDON_NAME, ns = ...
local Tab = ns:NewModule("Tab_Rewards")

local TIER_ROW_H = 68
local REQ_ROW_H = 148
local ROW_ICON_SIZE = 18
local ROW_ICON_MAX = 5

local function safeTextColor(fs, color, alpha)
    fs:SetTextColor(color[1], color[2], color[3], alpha or 1)
end

local function rewardSummary(t)
    if not t then return "" end
    -- Resolve reward contents from Rewards module; fall back to tier fields for safety.
    local c = (ns.Rewards and ns.Rewards:GetTierDisplayContents(t.id))
        or { items = t.items or {}, gold = t.gold or 0, extraLives = t.extraLives or 0 }
    local parts = {}
    if c.gold and c.gold > 0 then parts[#parts + 1] = ns.Tiers:FormatMoney(c.gold) end
    for _, it in ipairs(c.items or {}) do
        parts[#parts + 1] = ("%dx %s"):format(it.qty, it.note or ("item:" .. it.id))
    end
    if c.extraLives and c.extraLives > 0 then
        parts[#parts + 1] = ("|cffffd700+%d life|r"):format(c.extraLives)
    end
    if #parts == 0 then
        return "No rewards on this rank."
    end
    return table.concat(parts, "  -  ")
end

local function itemName(it)
    local name = GetItemInfo(it.id)
    if name and name ~= "" then return name end
    return it.note or ("Item " .. tostring(it.id))
end

local function createRewardIcon(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ROW_ICON_SIZE, ROW_ICON_SIZE)

    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints(b)
    b.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    b.count = parent:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 9, "")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)

    b.border = b:CreateTexture(nil, "BORDER")
    b.border:SetPoint("TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:SetColorTexture(0.75, 0.63, 0.38, 0.45)

    b:SetScript("OnEnter", function(self)
        if not self._tipTitle then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self._tipTitle, 0.878, 0.753, 0.502)
        if self._tipLine1 then GameTooltip:AddLine(self._tipLine1, 0.902, 0.878, 0.831, true) end
        if self._tipLine2 then GameTooltip:AddLine(self._tipLine2, 0.604, 0.580, 0.541, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return b
end

local function setRewardIcon(icon, texture, count, title, line1, line2)
    icon.tex:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon.count:SetText(count or "")
    icon._tipTitle = title
    icon._tipLine1 = line1
    icon._tipLine2 = line2
    icon:Show()
    icon.count:Show()
end

local function fillRewardIcons(row, tier)
    -- Resolve reward contents from Rewards module; fall back to tier fields for safety.
    local c = (ns.Rewards and ns.Rewards:GetTierDisplayContents(tier.id))
        or { items = tier.items or {}, gold = tier.gold or 0, extraLives = tier.extraLives or 0 }
    local idx = 1
    for _, it in ipairs(c.items or {}) do
        if idx > ROW_ICON_MAX then break end
        setRewardIcon(
            row.icons[idx],
            GetItemIcon(it.id) or "Interface\\Icons\\INV_Misc_QuestionMark",
            tostring(it.qty or ""),
            itemName(it),
            ("Qty: %d"):format(it.qty or 0),
            ("Item ID: %d"):format(it.id or 0))
        idx = idx + 1
    end
    if c.gold and c.gold > 0 and idx <= ROW_ICON_MAX then
        setRewardIcon(
            row.icons[idx],
            "Interface\\Icons\\INV_Misc_Coin_01",
            "",
            "Gold",
            ns.Tiers:FormatMoney(c.gold),
            "Included with this rank.")
        idx = idx + 1
    end
    if c.extraLives and c.extraLives > 0 and idx <= ROW_ICON_MAX then
        setRewardIcon(
            row.icons[idx],
            "Interface\\Icons\\Spell_Holy_Resurrection",
            tostring(c.extraLives),
            "Extra Life",
            ("Grants +%d life"):format(c.extraLives),
            "Applied after the request is fulfilled.")
        idx = idx + 1
    end
    while idx <= ROW_ICON_MAX do
        row.icons[idx]:Hide()
        row.icons[idx].count:Hide()
        row.icons[idx]._tipTitle = nil
        row.icons[idx]._tipLine1 = nil
        row.icons[idx]._tipLine2 = nil
        idx = idx + 1
    end
end

local function createInfoCard(parent, Theme, width, titleText)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width)
    Theme:Fill(f, Theme.c.bg1, true, "panel")

    f.title = Theme:Text(f, 12, Theme.c.goldH)
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText(titleText or "")

    f.lines = {}
    for i = 1, 5 do
        local line = Theme:Text(f, 11, Theme.c.fg2)
        line:SetWidth(width - 24)
        line:SetJustifyH("LEFT")
        f.lines[i] = line
    end

    function f:SetLines(lines)
        local prev = self.title
        local height = 10 + self.title:GetStringHeight()
        for i = 1, #self.lines do
            local line = self.lines[i]
            local text = lines and lines[i]
            line:ClearAllPoints()
            if text and text ~= "" then
                line:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6)
                line:SetText(text)
                line:Show()
                prev = line
                height = height + 6 + line:GetStringHeight()
            else
                line:Hide()
            end
        end
        self:SetHeight(height + 12)
    end

    return f
end

local function buildOptRow(content, Theme)
    local r = CreateFrame("Button", nil, content)
    r:SetHeight(TIER_ROW_H)
    Theme:Fill(r, Theme.c.bg1, false)

    r.box = r:CreateTexture(nil, "ARTWORK")
    r.box:SetSize(10, 10)
    r.box:SetPoint("LEFT", 14, 0)

    r.label = Theme:Text(r, 13, Theme.c.fg)
    r.label:SetPoint("TOPLEFT", 34, -8)

    r.sub = Theme:Text(r, 10, Theme.c.fg2)
    r.sub:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -4)
    r.sub:SetWidth(320)
    r.sub:SetJustifyH("LEFT")

    r.state = Theme:Text(r, 10, Theme.c.gold)
    r.state:SetPoint("TOPRIGHT", -14, -10)
    r.state:SetJustifyH("RIGHT")

    r.reward = Theme:Text(r, 10, Theme.c.fg2)
    r.reward:SetPoint("TOPRIGHT", r.state, "BOTTOMRIGHT", 0, -4)
    r.reward:SetJustifyH("RIGHT")
    r.reward:SetWidth(280)

    r.iconRow = CreateFrame("Frame", nil, r)
    r.iconRow:SetPoint("TOPRIGHT", r.reward, "BOTTOMRIGHT", 0, -6)
    r.iconRow:SetSize(160, ROW_ICON_SIZE)
    r.icons = {}
    for i = 1, ROW_ICON_MAX do
        local icon = createRewardIcon(r.iconRow)
        if i == 1 then
            icon:SetPoint("RIGHT", r.iconRow, "RIGHT", 0, 0)
        else
            icon:SetPoint("RIGHT", r.icons[i - 1], "LEFT", -6, 0)
        end
        r.icons[i] = icon
    end

    return r
end

local function firstClaimable(displayTiers, charKey)
    for _, t in ipairs(displayTiers or {}) do
        if not ns.Database:HasClaimedTier(charKey, t.id) then
            return t
        end
    end
    return nil
end

local function selectedRewardLabel(self, displayTiers)
    local selectedId = self.selectedRewardId
    for _, t in ipairs(displayTiers or {}) do
        if t.id == selectedId then
            return t.name or ("Legacy " .. tostring(t.id))
        end
    end
    return "Choose an unlocked reward"
end

local function countClaimable(displayTiers, charKey)
    local n = 0
    for _, t in ipairs(displayTiers or {}) do
        local claimed = ns.Database:HasClaimedTier(charKey, t.id)
        if not claimed then n = n + 1 end
    end
    return n
end

local function bankStatusColor(status)
    if status == "online" or status == "self" then return "|cff7ab27a" end
    if status == "offline" then return "|cffb85c5c" end
    return "|cff9a948a"
end

local function activeLegacyRows()
    local out = {}
    if not (ns.LegacyUnlocks and ns.LegacyUnlocks.ActiveNodes) then return out end
    for _, node in ipairs(ns.LegacyUnlocks:ActiveNodes()) do
        out[#out + 1] = {
            id = node.nodeId,
            name = ("%s %d - %s"):format(node.trackName or node.trackId or "Legacy", node.rank or 0, node.name or "Unlock"),
            trackName = node.trackName,
            rank = node.rank,
            node = node,
        }
        out[#out].blurb = node.trackName == "Fate"
            and "Rare survival power for future runs."
            or node.trackName == "Storage"
            and "Storage support from your legacy unlocks."
            or "Gold support from your legacy unlocks."
    end
    return out
end

local function shortName(full)
    return (full and full:match("^([^-]+)")) or full or "Unknown"
end

local function rewardNames(tierIds)
    local byId = {}
    for _, t in ipairs(ns.Tiers:Definitions()) do
        byId[t.id] = t
    end
    local out = {}
    for _, id in ipairs(tierIds or {}) do
        local node = ns.LegacyUnlocks and ns.LegacyUnlocks.NodeById and ns.LegacyUnlocks:NodeById(id)
        local trackId = ns.LegacyUnlocks and ns.LegacyUnlocks.TrackIdForNode and ns.LegacyUnlocks:TrackIdForNode(id)
        local track = trackId and ns.LegacyUnlocks:TrackDef(trackId)
        local t = byId[id]
        if node and track then
            out[#out + 1] = ("%s %d"):format(track.name or trackId, node.rank or 0)
        else
            out[#out + 1] = t and t.name or ("Reward " .. tostring(id))
        end
    end
    if #out == 0 then
        return "No rewards selected"
    end
    return table.concat(out, ", ")
end

local function incomingStatusLabel(status)
    if status == "gathering" then return "|cffc0a060Preparing|r" end
    if status == "fulfilled" then return "|cff7ab27aFulfilled|r" end
    if status == "cancelled" then return "|cffb85c5cCancelled|r" end
    return "|cff9a948aPending|r"
end

local function formatFulfillmentMeta(f)
    if not f then return nil end
    local bits = {}
    bits[#bits + 1] = ("Method: %s"):format(f.method or "?")
    if f.banker then bits[#bits + 1] = ("Banker: %s"):format(shortName(f.banker)) end
    if f.gold and f.gold > 0 then
        bits[#bits + 1] = ("Gold: %s"):format(ns.Tiers:FormatMoney(f.gold))
    end
    if (f.extraLives or 0) > 0 then
        bits[#bits + 1] = ("Extra lives: %d"):format(f.extraLives)
    end
    local n = #(f.items or {})
    if n > 0 then bits[#bits + 1] = ("Items in bundle: %d stack(s)"):format(n) end
    return table.concat(bits, " | ")
end

local function readinessLabel(info)
    if not info then return "|cff9a948aReadiness unavailable|r" end
    if info.fulfillable then return "|cff7ab27aReady to fulfill|r" end
    return "|cffb85c5cMissing items or gold|r"
end

local function readinessLines(info)
    if not info then
        return "Could not compute availability."
    end
    local lines = {}
    for _, it in ipairs(info.items or {}) do
        local color = (it.missing > 0) and "|cffb85c5c" or "|cff7ab27a"
        lines[#lines + 1] = ("%s%s|r - need %d, have %d, missing %d"):format(
            color, it.name or ("item:" .. tostring(it.id)), it.required or 0, it.available or 0, it.missing or 0)
    end
    if #lines == 0 then
        lines[#lines + 1] = "|cff9a948aNo item stacks in this request.|r"
    end

    local requiredGold = info.requiredGold or 0
    local availableGold = info.availableGold or 0
    local missingGold = math.max(0, requiredGold - availableGold)
    local goldColor = (missingGold > 0) and "|cffb85c5c" or "|cff7ab27a"
    lines[#lines + 1] = ("%sGold: need %s, have %s, missing %s|r"):format(
        goldColor,
        ns.Tiers:FormatMoney(requiredGold),
        ns.Tiers:FormatMoney(availableGold),
        ns.Tiers:FormatMoney(missingGold))
    return table.concat(lines, "\n")
end

local function buildRequestRow(content, Theme)
    local r = CreateFrame("Frame", nil, content)
    r:SetHeight(REQ_ROW_H)
    Theme:Fill(r, Theme.c.bg1, false)

    r.requestor = Theme:Text(r, 13, Theme.c.fg)
    r.requestor:SetPoint("TOPLEFT", 14, -10)
    r.requestor:SetWidth(150)
    r.requestor:SetJustifyH("LEFT")

    r.requested = Theme:Text(r, 12, Theme.c.fg)
    r.requested:SetPoint("TOPLEFT", 178, -10)
    r.requested:SetWidth(330)
    r.requested:SetJustifyH("LEFT")

    r.meta = Theme:Text(r, 10, Theme.c.fg2)
    r.meta:SetPoint("TOPLEFT", r.requested, "BOTTOMLEFT", 0, -6)
    r.meta:SetWidth(330)
    r.meta:SetJustifyH("LEFT")

    r.readiness = Theme:Text(r, 10, Theme.c.fg2)
    r.readiness:SetPoint("TOPLEFT", r.meta, "BOTTOMLEFT", 0, -6)
    r.readiness:SetWidth(330)
    r.readiness:SetJustifyH("LEFT")

    r.sent = Theme:Text(r, 12, Theme.c.gold)
    r.sent:SetPoint("TOPLEFT", 532, -10)
    r.sent:SetWidth(90)
    r.sent:SetJustifyH("LEFT")

    r.sentMeta = Theme:Text(r, 10, Theme.c.fg2)
    r.sentMeta:SetPoint("TOPLEFT", r.sent, "BOTTOMLEFT", 0, -6)
    r.sentMeta:SetWidth(150)
    r.sentMeta:SetJustifyH("LEFT")

    r.btnMail = Theme:Button(r, "Fulfill via Mail", 140, 22)
    r.btnMail:SetPoint("BOTTOMRIGHT", -14, 10)

    r.btnTrade = Theme:Button(r, "Trade Checklist", 140, 22)
    r.btnTrade:SetPoint("BOTTOMRIGHT", r.btnMail, "BOTTOMLEFT", -6, 0)

    r.btnDone = Theme:Button(r, "Mark Fulfilled", 120, 22)
    r.btnDone:SetPoint("BOTTOMRIGHT", r.btnTrade, "BOTTOMLEFT", -6, 0)

    r.btnCancel = Theme:Button(r, "Cancel", 70, 22)
    r.btnCancel:SetPoint("BOTTOMRIGHT", r.btnDone, "BOTTOMLEFT", -6, 0)

    return r
end

local function setBankRequestRow(row, req)
    local Theme = ns.Theme
    local ready = nil
    if req.status ~= "fulfilled" then
        ready = ns.Requests:FulfillmentReadiness(req)
    end

    if req.status == "fulfilled" then
        Theme:Fill(row, Theme.c.bg1, false)
    elseif ready and ready.fulfillable then
        Theme:Fill(row, { 0.110, 0.150, 0.122, 1.00 }, false)
    else
        Theme:Fill(row, { 0.165, 0.120, 0.120, 1.00 }, false)
    end

    row.requestor:SetText(("|cffc0a060%s|r"):format(shortName(req.from)))
    row.requested:SetText(rewardNames(req.tierIds))
    local meta = { ("%s\nvia %s"):format(date("%H:%M %b-%d", req.when), req.via or "unknown") }
    if req.storedClaimReceipts and next(req.storedClaimReceipts) then
        meta[#meta + 1] = "|cff9a948aClaim receipts stored on request (requester not in this account roster).|r"
    end
    if req.status == "fulfilled" and req.fulfillment then
        meta[#meta + 1] = ("|cff7ab27aFulfilled %s|r"):format(date("%H:%M %b-%d", req.fulfilledAt or req.fulfillment.when or time()))
        local rm = formatFulfillmentMeta(req.fulfillment)
        if rm then meta[#meta + 1] = rm end
    end
    row.meta:SetText(table.concat(meta, "\n"))
    row.readiness:SetText(req.status == "fulfilled" and "|cff7ab27aFulfillment recorded.|r" or readinessLines(ready))
    row.sent:SetText(incomingStatusLabel(req.status))
    if req.status == "fulfilled" then
        row.sentMeta:SetText(req.fulfillment and formatFulfillmentMeta(req.fulfillment) or "Fulfilled (details on bank account).")
        row.btnMail:Hide()
        row.btnTrade:Hide()
        row.btnDone:Hide()
        row.btnCancel:Hide()
    else
        row.sentMeta:SetText(ready and readinessLabel(ready) or "Waiting on banker fulfillment.")
        row.btnMail:Show()
        row.btnTrade:Show()
        row.btnDone:Show()
        row.btnCancel:Show()
    end
end

function Tab:Init(parent)
    if self.panel then return end
    local Theme = ns.Theme
    local p = CreateFrame("Frame", nil, parent)
    self.panel = p
    ns.MainFrame:RegisterPanel("Rewards", p)

    local title = Theme:Header(p, "Rewards", 16)
    title:SetPoint("TOPLEFT", 20, -18)

    self.hint = Theme:Text(p, 11, Theme.c.fg2)
    self.hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    self.hint:SetWidth(720)
    self.hint:SetJustifyH("LEFT")
    self.hint:SetSpacing(2)

    self.bankLine = Theme:Text(p, 10, Theme.c.gold)
    self.bankLine:SetPoint("TOPLEFT", self.hint, "BOTTOMLEFT", 0, -6)
    self.bankLine:SetWidth(720)
    self.bankLine:SetJustifyH("LEFT")

    local summaryRow = CreateFrame("Frame", nil, p)
    summaryRow:SetPoint("TOPLEFT", 20, -82)
    summaryRow:SetSize(720, 86)
    self.summaryRow = summaryRow

    self.statusCard = createInfoCard(summaryRow, Theme, 226, "Request Status")
    self.statusCard:SetPoint("TOPLEFT", 0, 0)

    self.progressCard = createInfoCard(summaryRow, Theme, 226, "Progress")
    self.progressCard:SetPoint("TOPLEFT", self.statusCard, "TOPRIGHT", 12, 0)

    self.selectionCard = createInfoCard(summaryRow, Theme, 226, "Selection")
    self.selectionCard:SetPoint("TOPLEFT", self.progressCard, "TOPRIGHT", 12, 0)

    self.requestLabel = Theme:Text(p, 12, Theme.c.goldH)
    self.requestLabel:SetPoint("TOPLEFT", summaryRow, "BOTTOMLEFT", 0, -14)
    self.requestLabel:SetText("Request Reward")

    local dd = CreateFrame("Frame", "WRL_RewardsDropdown", p, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", self.requestLabel, "BOTTOMLEFT", -16, -4)
    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dd, 390) end
    self.rewardDropdown = dd

    self.prepareMailBtn = Theme:Button(p, "Prepare Mail", 130, 24)
    self.prepareMailBtn:SetPoint("LEFT", dd, "RIGHT", -8, 2)
    self.prepareMailBtn:SetScript("OnClick", function() Tab:BeginMailFallback() end)

    self.requestHelp = Theme:Text(p, 10, Theme.c.fg2)
    self.requestHelp:SetPoint("LEFT", self.prepareMailBtn, "RIGHT", 12, 0)
    self.requestHelp:SetWidth(184)
    self.requestHelp:SetJustifyH("LEFT")

    self.empty = Theme:Text(p, 11, Theme.c.fg2)
    self.empty:SetWidth(720)
    self.empty:SetJustifyH("LEFT")
    self.empty:Hide()

    self.bankSetupTitle = Theme:Header(p, "No Bank Set Up", 18)
    self.bankSetupTitle:SetPoint("CENTER", p, "CENTER", 0, 36)
    self.bankSetupTitle:Hide()

    self.bankSetupBody = Theme:Text(p, 12, Theme.c.fg2)
    self.bankSetupBody:SetPoint("TOP", self.bankSetupTitle, "BOTTOM", 0, -10)
    self.bankSetupBody:SetWidth(460)
    self.bankSetupBody:SetJustifyH("CENTER")
    self.bankSetupBody:Hide()

    local scroll, content = Theme:ScrollArea(p)
    scroll:SetPoint("TOPLEFT", self.requestLabel, "BOTTOMLEFT", 0, -44)
    scroll:SetPoint("BOTTOMRIGHT", -20, 52)
    content:SetSize(720, 1)
    self.scroll = scroll
    self.content = content
    self.rows = {}
    self.selected = {}

    local footer = CreateFrame("Frame", nil, p)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    footer:SetHeight(46)
    Theme:Fill(footer, Theme.c.bg1, false, "footer")
    self.footer = footer

    self.footerHint = Theme:Text(footer, 10, Theme.c.fg2)
    self.footerHint:SetPoint("LEFT", 16, 0)
    self.footerHint:SetWidth(600)
    self.footerHint:SetJustifyH("LEFT")

    local bankView = CreateFrame("Frame", nil, p)
    bankView:SetAllPoints(p)
    bankView:SetFrameLevel(p:GetFrameLevel() + 5)
    bankView:Hide()
    self.bankView = bankView

    local bankTitle = Theme:Header(bankView, "Rewards", 16)
    bankTitle:SetPoint("TOPLEFT", 20, -18)

    self.bankHint = Theme:Text(bankView, 11, Theme.c.fg2)
    self.bankHint:SetPoint("TOPLEFT", bankTitle, "BOTTOMLEFT", 0, -4)
    self.bankHint:SetWidth(720)
    self.bankHint:SetJustifyH("LEFT")

    self.bankColumns = CreateFrame("Frame", nil, bankView)
    self.bankColumns:SetPoint("TOPLEFT", 20, -72)
    self.bankColumns:SetPoint("TOPRIGHT", -20, -72)
    self.bankColumns:SetHeight(18)

    self.bankColRequestor = Theme:Text(self.bankColumns, 10, Theme.c.goldH)
    self.bankColRequestor:SetPoint("LEFT", 8, 0)
    self.bankColRequestor:SetText("Requestor")

    self.bankColRequested = Theme:Text(self.bankColumns, 10, Theme.c.goldH)
    self.bankColRequested:SetPoint("LEFT", 172, 0)
    self.bankColRequested:SetText("Requested")

    self.bankColStatus = Theme:Text(self.bankColumns, 10, Theme.c.goldH)
    self.bankColStatus:SetPoint("LEFT", 526, 0)
    self.bankColStatus:SetText("Status")

    Theme:Divider(bankView, "TOPLEFT", "TOPRIGHT", 0, -94, 0.2)

    local bankScroll, bankContent = Theme:ScrollArea(bankView)
    bankScroll:SetPoint("TOPLEFT", 20, -104)
    bankScroll:SetPoint("BOTTOMRIGHT", -20, 16)
    bankContent:SetSize(720, 1)
    self.bankScroll = bankScroll
    self.bankContent = bankContent
    self.bankRows = {}

    self.bankEmpty = Theme:Text(bankContent, 12, Theme.c.fg2)
    self.bankEmpty:SetPoint("TOPLEFT", 0, -10)
    self.bankEmpty:SetWidth(700)
    self.bankEmpty:SetJustifyH("LEFT")

    p.Refresh = function() Tab:Refresh() end
end

function Tab:ShowBankSetupGuidance()
    if self.bankView then self.bankView:Hide() end
    if self.summaryRow then self.summaryRow:Hide() end
    if self.requestLabel then self.requestLabel:Hide() end
    if self.rewardDropdown then self.rewardDropdown:Hide() end
    if self.prepareMailBtn then self.prepareMailBtn:Hide() end
    if self.requestHelp then self.requestHelp:Hide() end
    if self.scroll then self.scroll:Hide() end
    if self.footer then self.footer:Hide() end
    if self.empty then self.empty:Hide() end
    if self.bankLine then self.bankLine:Hide() end
    if self.hint then
        self.hint:SetText("")
        self.hint:Hide()
    end
    self.bankSetupTitle:SetText("No Bank Set Up")
    self.bankSetupBody:SetText("Set a destination bank with |cffffff00/wrl setbank Name-Realm|r, or log into the bank character and run |cffffff00/wrl setbank|r. Rewards requests and fulfillment both use that bank.")
    self.bankSetupTitle:Show()
    self.bankSetupBody:Show()
end

function Tab:ShowRunWorkflow()
    if self.bankView then self.bankView:Hide() end
    if self.summaryRow then self.summaryRow:Show() end
    if self.requestLabel then self.requestLabel:Show() end
    if self.rewardDropdown then self.rewardDropdown:Show() end
    if self.prepareMailBtn then self.prepareMailBtn:Show() end
    if self.requestHelp then self.requestHelp:Show() end
    if self.footer then self.footer:Show() end
    if self.bankLine then self.bankLine:Show() end
    if self.hint then self.hint:Show() end
    self.bankSetupTitle:Hide()
    self.bankSetupBody:Hide()
end

function Tab:HideRunWorkflow()
    if self.summaryRow then self.summaryRow:Hide() end
    if self.requestLabel then self.requestLabel:Hide() end
    if self.rewardDropdown then self.rewardDropdown:Hide() end
    if self.prepareMailBtn then self.prepareMailBtn:Hide() end
    if self.requestHelp then self.requestHelp:Hide() end
    if self.scroll then self.scroll:Hide() end
    if self.footer then self.footer:Hide() end
    if self.empty then self.empty:Hide() end
    if self.bankLine then self.bankLine:Hide() end
    if self.hint then self.hint:Hide() end
end

function Tab:RefreshBankWorkflow()
    self.bankSetupTitle:Hide()
    self.bankSetupBody:Hide()
    if self.bankView then self.bankView:Show() end
    self.bankHint:SetText("Incoming requests and recent fulfilled requests. Use mail or trade helpers, then mark requests fulfilled once you have manually completed delivery.")

    local rows = ns.Requests:BankRequestRows()
    if #rows == 0 then
        for _, row in ipairs(self.bankRows) do row:Hide() end
        self.bankEmpty:Show()
        self.bankEmpty:SetText("No incoming reward requests yet.")
        self.bankContent:SetHeight(120)
        return
    end

    self.bankEmpty:Hide()

    for i = #self.bankRows + 1, #rows do
        self.bankRows[i] = buildRequestRow(self.bankContent, ns.Theme)
    end
    for i = #rows + 1, #self.bankRows do
        self.bankRows[i]:Hide()
    end

    local y = 0
    for i, req in ipairs(rows) do
        local row = self.bankRows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.bankContent, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", self.bankContent, "RIGHT", -16, 0)
        row:Show()

        setBankRequestRow(row, req)
        if req.status ~= "fulfilled" then
            local reqId = req.id
            row.btnMail:SetScript("OnClick", function()
                ns.Requests:BeginMailFulfillment(reqId)
            end)
            row.btnTrade:SetScript("OnClick", function()
                ns.Requests:LoadActiveTrade()
            end)
            row.btnDone:SetScript("OnClick", function()
                ns.Requests:MarkFulfilled(reqId)
                Tab:Refresh()
            end)
            row.btnCancel:SetScript("OnClick", function()
                ns.Requests:SetStatus(reqId, "cancelled")
                Tab:Refresh()
            end)
        end

        y = y + REQ_ROW_H + 4
    end

    self.bankContent:SetHeight(math.max(1, y))
end

function Tab:Refresh()
    if not self.panel then return end
    local Theme = ns.Theme

    local isBank = ns.Database:IsBankCharacter()
    local bank = WRL_DB.bankCharacter

    if not bank then
        self:ShowBankSetupGuidance()
        return
    end

    if isBank then
        self:HideRunWorkflow()
        self:RefreshBankWorkflow()
        return
    end

    self:ShowRunWorkflow()

    local total = ns.Database:TotalContributed()
    local legacySpent = ns.LegacyUnlocks and ns.LegacyUnlocks:Spent() or 0
    local legacyAvailable = ns.LegacyUnlocks and ns.LegacyUnlocks:AvailableBudget() or total

    local charKey = ns:UnitKey()

    local displayTiers = activeLegacyRows()

    local claimableCount = countClaimable(displayTiers, charKey)
    local rec = ns.Database and ns.Database:GetCharacter(charKey)
    local canRequest = (not rec) or (not ns.Run) or ns.Run:IsPlayable(rec)

    if self.selectedRewardId and ns.Database:HasClaimedTier(charKey, self.selectedRewardId) then
        self.selectedRewardId = nil
    end
    local selectedKnown = false
    for _, t in ipairs(displayTiers) do
        if t.id == self.selectedRewardId and not ns.Database:HasClaimedTier(charKey, t.id) then
            selectedKnown = true
            break
        end
    end
    if not selectedKnown then
        local first = firstClaimable(displayTiers, charKey)
        self.selectedRewardId = first and first.id or nil
    end
    local selectedCount = self.selectedRewardId and 1 or 0

    if not canRequest then
        self.hint:SetText("This run is retired. Dead or retired characters cannot request new bank rewards.")
    else
        self.hint:SetText(("Request unlocked starter rewards from your bank. Buy more unlocks on the Legacy tab, then prepare mail for |cffc0a060%s|r."):format(bank))
    end

    local bankStatus, bankStatusLabel = "missing", "No bank set"
    if bank and ns.BankStatus then
        bankStatus, bankStatusLabel = ns.BankStatus:Status(bank)
    elseif bank then
        bankStatus, bankStatusLabel = "unknown", "Unknown"
    end

    if bank then
        self.bankLine:SetText(("Destination bank: |cffc0a060%s|r  %s[%s]|r"):format(
            bank,
            bankStatusColor(bankStatus),
            bankStatusLabel or "Unknown"))
    else
        self.bankLine:SetText("|cff9a948aDestination bank not configured.|r Off-account banks are supported with |cffe6e0d4/wrl setbank Name-Realm|r.")
    end

    local statusLines
    if not canRequest then
        statusLines = {
            "Role: retired run character",
            "This run is over.",
            "No new starter rewards can be requested.",
        }
    else
        statusLines = {
            "Role: run character",
            ("Unlocked rewards: %d"):format(#displayTiers),
            ("Claimable now: %d"):format(claimableCount),
        }
    end
    self.statusCard:SetLines(statusLines)

    local progressLines = {
        ("Lifetime contributed: %s"):format(ns.Tiers:FormatMoney(total)),
        ("Spent on unlocks: %s"):format(ns.Tiers:FormatMoney(legacySpent)),
        ("Available budget: %s"):format(ns.Tiers:FormatMoney(legacyAvailable)),
    }
    self.progressCard:SetLines(progressLines)

    self.selectionCard:SetLines({
        ("Selectable rewards: %d"):format(claimableCount),
        ("Selected now: %s"):format(selectedRewardLabel(self, displayTiers)),
        (claimableCount > 0 and "Use the dropdown, then prepare a mailbox request."
            or (#displayTiers > 0 and "All unlocked rewards below are already claimed."
            or "No legacy rewards are unlocked yet.")),
    })

    local cardHeight = math.max(self.statusCard:GetHeight(), self.progressCard:GetHeight(), self.selectionCard:GetHeight())
    self.summaryRow:SetHeight(cardHeight)

    self.footerHint:SetText("Prepare Mail creates a request letter for the banker to import. The final Send button stays manual.")

    if UIDropDownMenu_Initialize and self.rewardDropdown then
        UIDropDownMenu_Initialize(self.rewardDropdown, function(_, level)
            for _, t in ipairs(displayTiers) do
                local claimed = ns.Database:HasClaimedTier(charKey, t.id)
                local reward = t
                local info = UIDropDownMenu_CreateInfo()
                info.text = (t.name or ("Legacy " .. tostring(t.id))) .. (claimed and " (claimed)" or "")
                info.value = t.id
                info.disabled = claimed
                info.checked = self.selectedRewardId == t.id
                info.func = function()
                    self.selectedRewardId = reward.id
                    self:Refresh()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end
    if self.rewardDropdown then
        if UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(self.rewardDropdown, selectedRewardLabel(self, displayTiers))
        elseif self.rewardDropdown.label then
            self.rewardDropdown.label:SetText(selectedRewardLabel(self, displayTiers))
        end
    end
    if self.requestHelp then
        self.requestHelp:SetText(claimableCount > 0 and ("Claimable: " .. claimableCount) or "Unlock rewards on Legacy first.")
    end

    local footerWouldCollide = (#displayTiers == 0)
    if footerWouldCollide then
        self.prepareMailBtn:Hide()
        self.footerHint:Hide()
    else
        self.prepareMailBtn:Show()
        self.footerHint:Show()
    end

    if isBank or not bank or selectedCount == 0 or not ns.Settings:Get("allowBankRewards", true) or not canRequest then
        self.prepareMailBtn:Disable()
        self.prepareMailBtn:SetAlpha(0.45)
    else
        self.prepareMailBtn:Enable()
        self.prepareMailBtn:SetAlpha(1)
    end

    if not ns.Settings:Get("allowBankRewards", true) then
        self.footerHint:SetText("Bank starter rewards are disabled by the active rules profile.")
    end

    for i = #self.rows + 1, #displayTiers do
        local row = buildOptRow(self.content, Theme)
        row:SetScript("OnClick", function()
            local tier = row._tier
            if not tier then return end
            local claimed = ns.Database:HasClaimedTier(charKey, tier.id)
            if claimed then return end
            self.selectedRewardId = tier.id
            Tab:Refresh()
        end)
        self.rows[i] = row
    end
    for i = #displayTiers + 1, #self.rows do self.rows[i]:Hide() end

    local y = 0
    for i, t in ipairs(displayTiers) do
        local row = self.rows[i]
        local claimed = ns.Database:HasClaimedTier(charKey, t.id)
        local selected = self.selectedRewardId == t.id and not claimed
        row._tier = t
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", self.content, "RIGHT", -16, 0)
        row:Show()
        row:SetAlpha(claimed and 0.55 or 1)

        row.box:SetColorTexture(selected and 0.85 or 0.40, selected and 0.75 or 0.40, selected and 0.35 or 0.40, selected and 0.90 or 0.50)
        row.label:SetText(t.name or ("Legacy " .. tostring(t.id)))
        row.sub:SetText(t.blurb or "")
        row.reward:SetText(rewardSummary(t))
        fillRewardIcons(row, t)
        if claimed then
            row.state:SetText("|cff9a948aCLAIMED|r")
        elseif selected then
            row.state:SetText("|cffc0a060SELECTED|r")
        else
            row.state:SetText("|cff9a948aAVAILABLE|r")
        end
        y = y + TIER_ROW_H + 4
    end

    if #displayTiers == 0 then
        self.scroll:Hide()
        self.empty:Hide()
        self.content:SetHeight(80)
    else
        self.scroll:Show()
        self.empty:Hide()
        self.content:SetHeight(math.max(1, y))
    end
end

function Tab:SelectedRewardIds()
    local charKey = ns:UnitKey()
    local tierIds = {}
    local tierId = self.selectedRewardId
    if tierId then
        local allowed = true
        if ns.Rules and ns.Rules.CheckTierClaimAvailable then
            allowed = ns.Rules:CheckTierClaimAvailable(charKey, tierId)
        elseif ns.Database:HasClaimedTier(charKey, tierId) then
            allowed = false
        end
        if allowed then
            tierIds[#tierIds + 1] = tierId
        end
    end
    return tierIds
end

function Tab:SendRequest()
    local bank = WRL_DB and WRL_DB.bankCharacter
    if not bank then
        ns:Print("Set a bank first with |cffffff00/wrl setbank Name-Realm|r.")
        return
    end
    if ns.Database:IsBankCharacter() then
        ns:Print("Open Rewards on a run character to send a request.")
        return
    end
    local rec = ns.Database:GetCurrentCharacter()
    if ns.Run and rec and not ns.Run:IsPlayable(rec) then
        ns:Print("This run is retired. Dead or retired characters cannot request new bank rewards.")
        return
    end
    if not ns.Settings:Get("allowBankRewards", true) then
        ns:Print("Bank starter rewards are disabled by the active rules profile.")
        return
    end

    local tierIds = self:SelectedRewardIds()
    if #tierIds == 0 then
        ns:Print("Choose at least one unclaimed legacy reward first.")
        return
    end

    ns.Comm:SendRequest(bank, tierIds, "")
    if ns.BankStatus and ns.BankStatus:ShouldOfferMailFallback(bank) then
        ns:Print("If the bank is offline, open a mailbox and use Mail Fallback to leave a request letter.")
    else
        wipe(self.selected)
    end
    self:Refresh()
    if ns.MainFrame and ns.MainFrame.RefreshHeader then
        ns.MainFrame:RefreshHeader()
    end
end

function Tab:BeginMailFallback()
    local bank = WRL_DB and WRL_DB.bankCharacter
    if not bank then
        ns:Print("Set a bank first with |cffffff00/wrl setbank Name-Realm|r.")
        return
    end
    if ns.Database:IsBankCharacter() then
        ns:Print("Open Rewards on a run character to prepare mail fallback.")
        return
    end
    local rec = ns.Database:GetCurrentCharacter()
    if ns.Run and rec and not ns.Run:IsPlayable(rec) then
        ns:Print("This run is retired. Dead or retired characters cannot request new bank rewards.")
        return
    end
    if not ns.Settings:Get("allowBankRewards", true) then
        ns:Print("Bank starter rewards are disabled by the active rules profile.")
        return
    end

    local tierIds = self:SelectedRewardIds()
    if #tierIds == 0 then
        ns:Print("Choose at least one unclaimed legacy reward first.")
        return
    end

    ns.Requests:BeginMailFallback(bank, tierIds, "")
end
