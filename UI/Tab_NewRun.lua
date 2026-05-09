-- UI/Tab_NewRun.lua
-- For the character starting a new run: shows which legacy rewards are unlocked
-- and lets them request any subset to be sent by the bank character.

local ADDON_NAME, ns = ...
local Tab = ns:NewModule("Tab_NewRun")

local TIER_ROW_H = 68
local MOD_ROW_H = 24
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
    Theme:Fill(f, Theme.c.bg1, true)

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

local function buildModifierRow(content, Theme)
    local r = CreateFrame("Button", nil, content)
    r:SetHeight(MOD_ROW_H)
    Theme:Fill(r, Theme.c.bg1, false)

    r.box = r:CreateTexture(nil, "ARTWORK")
    r.box:SetSize(10, 10)
    r.box:SetPoint("LEFT", 8, 0)

    r.label = Theme:Text(r, 10, Theme.c.fg)
    r.label:SetPoint("TOPLEFT", 24, -3)
    r.label:SetWidth(238)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)

    r.sub = Theme:Text(r, 7, Theme.c.fg2)
    r.sub:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -1)
    r.sub:SetWidth(250)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)

    r.state = Theme:Text(r, 9, Theme.c.gold)
    r.state:SetPoint("RIGHT", -6, 0)
    r.state:SetJustifyH("RIGHT")

    return r
end

local function selectionCount(selected, displayTiers, charKey, allowRepeat)
    local picked = 0
    for _, t in ipairs(displayTiers or {}) do
        local claimed = ns.Database:HasClaimedTier(charKey, t.id) and not allowRepeat
        if not claimed and selected[t.id] then
            picked = picked + 1
        end
    end
    return picked
end

local function countClaimable(displayTiers, charKey, allowRepeat)
    local n = 0
    for _, t in ipairs(displayTiers or {}) do
        local claimed = ns.Database:HasClaimedTier(charKey, t.id) and not allowRepeat
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

function Tab:Init(parent)
    if self.panel then return end
    local Theme = ns.Theme
    local p = CreateFrame("Frame", nil, parent)
    self.panel = p
    ns.MainFrame:RegisterPanel("NewRun", p)

    local title = Theme:Header(p, "New Run - Legacy Rewards", 16)
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
    summaryRow:SetPoint("TOPLEFT", 20, -88)
    summaryRow:SetSize(720, 86)
    self.summaryRow = summaryRow

    self.statusCard = createInfoCard(summaryRow, Theme, 226, "Request Status")
    self.statusCard:SetPoint("TOPLEFT", 0, 0)

    self.progressCard = createInfoCard(summaryRow, Theme, 226, "Progress")
    self.progressCard:SetPoint("TOPLEFT", self.statusCard, "TOPRIGHT", 12, 0)

    self.selectionCard = createInfoCard(summaryRow, Theme, 226, "Selection")
    self.selectionCard:SetPoint("TOPLEFT", self.progressCard, "TOPRIGHT", 12, 0)

    self.sectionLabel = Theme:Text(p, 12, Theme.c.goldH)
    self.sectionLabel:SetPoint("TOPLEFT", summaryRow, "BOTTOMLEFT", 0, -12)
    self.sectionLabel:SetText("Available Legacy Rewards")

    self.modHeader = Theme:Text(p, 12, Theme.c.goldH)
    self.modHeader:SetPoint("TOPLEFT", self.sectionLabel, "BOTTOMLEFT", 0, -10)
    self.modHeader:SetText("Run Modifiers")

    self.modHint = Theme:Text(p, 10, Theme.c.fg2)
    self.modHint:SetPoint("TOPLEFT", self.modHeader, "BOTTOMLEFT", 0, -3)
    self.modHint:SetWidth(720)
    self.modHint:SetJustifyH("LEFT")
    self.modHint:SetText("Locked once your first legacy reward is claimed.")

    self.modWrap = CreateFrame("Frame", nil, p)
    self.modWrap:SetPoint("TOPLEFT", self.modHint, "BOTTOMLEFT", 0, -6)
    self.modWrap:SetSize(720, (MOD_ROW_H + 1) * 5 + 8)
    Theme:Fill(self.modWrap, Theme.c.bg1, true)

    self.boonPanel = CreateFrame("Frame", nil, self.modWrap)
    self.boonPanel:SetPoint("TOPLEFT", 8, -5)
    self.boonPanel:SetSize(344, self.modWrap:GetHeight() - 10)
    Theme:Fill(self.boonPanel, Theme.c.bg0, false)

    self.burdenPanel = CreateFrame("Frame", nil, self.modWrap)
    self.burdenPanel:SetPoint("TOPRIGHT", -8, -5)
    self.burdenPanel:SetSize(344, self.modWrap:GetHeight() - 10)
    Theme:Fill(self.burdenPanel, Theme.c.bg0, false)

    self.boonLabel = Theme:Text(self.boonPanel, 11, Theme.c.gold)
    self.boonLabel:SetPoint("TOPLEFT", 8, -4)
    self.boonLabel:SetText("Boons")

    self.burdenLabel = Theme:Text(self.burdenPanel, 11, Theme.c.gold)
    self.burdenLabel:SetPoint("TOPLEFT", 8, -4)
    self.burdenLabel:SetText("Burdens")

    local boonScroll, boonContent = Theme:ScrollArea(self.boonPanel)
    boonScroll:SetPoint("TOPLEFT", 8, -20)
    boonScroll:SetPoint("BOTTOMRIGHT", -24, 4)
    boonContent:SetSize(304, 1)
    self.boonScroll = boonScroll
    self.boonContent = boonContent

    local burdenScroll, burdenContent = Theme:ScrollArea(self.burdenPanel)
    burdenScroll:SetPoint("TOPLEFT", 8, -20)
    burdenScroll:SetPoint("BOTTOMRIGHT", -24, 4)
    burdenContent:SetSize(304, 1)
    self.burdenScroll = burdenScroll
    self.burdenContent = burdenContent

    self.boonRows = {}
    self.burdenRows = {}

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
    scroll:SetPoint("TOPLEFT", self.modWrap, "BOTTOMLEFT", 0, -8)
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
    Theme:Fill(footer, Theme.c.bg1, false)

    self.sendBtn = Theme:Button(footer, "Send Request", 140, 24)
    self.sendBtn:SetPoint("RIGHT", -16, 0)
    self.sendBtn:SetScript("OnClick", function() Tab:SendRequest() end)

    self.mailBtn = Theme:Button(footer, "Mail Fallback", 128, 24)
    self.mailBtn:SetPoint("RIGHT", self.sendBtn, "LEFT", -8, 0)
    self.mailBtn:SetScript("OnClick", function() Tab:BeginMailFallback() end)

    self.footerHint = Theme:Text(footer, 10, Theme.c.fg2)
    self.footerHint:SetPoint("LEFT", 16, 0)
    self.footerHint:SetWidth(438)
    self.footerHint:SetJustifyH("LEFT")

    p.Refresh = function() Tab:Refresh() end
end

function Tab:Refresh()
    if not self.panel then return end
    local Theme = ns.Theme

    local isBank = ns.Database:IsBankCharacter()
    local bank = WRL_DB.bankCharacter
    local total = ns.Database:TotalContributed()
    local legacySpent = ns.LegacyUnlocks and ns.LegacyUnlocks:Spent() or 0
    local legacyAvailable = ns.LegacyUnlocks and ns.LegacyUnlocks:AvailableBudget() or total

    local charKey = ns:UnitKey()
    local allowRepeat = ns.Database:AllowRepeatClaims()

    local displayTiers = activeLegacyRows()

    for _, t in ipairs(displayTiers) do
        local claimed = ns.Database:HasClaimedTier(charKey, t.id) and not allowRepeat
        if claimed then
            self.selected[t.id] = nil
        end
    end

    local claimableCount = countClaimable(displayTiers, charKey, allowRepeat)
    local selectedCount = selectionCount(self.selected, displayTiers, charKey, allowRepeat)
    local modifiersLocked = not (ns.Boons and ns.Boons.IsLocked) or ns.Boons:IsLocked(charKey)
    local rec = ns.Database and ns.Database:GetCharacter(charKey)

    if isBank then
        self.hint:SetText("This character is marked as the bank. Open this tab on a run character to request unlocked legacy rewards.")
    elseif bank then
        self.hint:SetText(("Pick the unlocked legacy rewards you want delivered from |cffc0a060%s|r. Buy more unlocks on the Tiers tab."):format(bank))
    else
        self.hint:SetText("No bank character is set yet. You can still review unlocked legacy rewards here, then assign a bank with |cffffff00/wrl setbank Name-Realm|r or run |cffffff00/wrl setbank|r on your bank toon.")
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
    if isBank then
        statusLines = {
            "Role: bank character",
            "Requests are fulfilled from the bank side.",
            "Switch to a run character to build a request.",
        }
    elseif not bank then
        statusLines = {
            "Role: run character",
            "No destination bank set.",
            "You can still inspect unlocks below.",
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
        ("Selected now: %d"):format(selectedCount),
        (claimableCount > 0 and "Toggle any unlocked reward below to include it."
            or (#displayTiers > 0 and "All unlocked rewards below are already claimed."
            or "No legacy rewards are unlocked yet.")),
    })

    local cardHeight = math.max(self.statusCard:GetHeight(), self.progressCard:GetHeight(), self.selectionCard:GetHeight())
    self.summaryRow:SetHeight(cardHeight)

    local offerMailFallback = bank and ns.BankStatus and ns.BankStatus:ShouldOfferMailFallback(bank)
    if offerMailFallback then
        self.footerHint:SetText("Bank is not confirmed online. Send Request queues the addon whisper; Mail Fallback prepares a mailbox letter the bank can import later.")
    else
        self.footerHint:SetText("Requests are sent to the configured bank. Mail fulfillment happens on the banker side in the Requests tab.")
    end

    local boonDefs = (ns.Boons and ns.Boons.BoonDefs and ns.Boons:BoonDefs()) or {}
    local burdenDefs = (ns.Boons and ns.Boons.BurdenDefs and ns.Boons:BurdenDefs()) or {}

    for i = #self.boonRows + 1, #boonDefs do
        local row = buildModifierRow(self.boonContent, Theme)
        row:SetScript("OnClick", function()
            if modifiersLocked then return end
            local id = row._id
            local list = {}
            for boonId in pairs((rec and rec.boons) or {}) do
                if boonId ~= id then
                    list[#list + 1] = boonId
                end
            end
            if not (rec and rec.boons and rec.boons[id]) then
                list[#list + 1] = id
            end
            if ns.Boons then
                ns.Boons:SetBoons(charKey, list)
            end
            Tab:Refresh()
        end)
        self.boonRows[i] = row
    end
    for i = #boonDefs + 1, #self.boonRows do self.boonRows[i]:Hide() end

    local boonY = 0
    for i, def in ipairs(boonDefs) do
        local row = self.boonRows[i]
        local selected = rec and rec.boons and rec.boons[def.id] ~= nil
        row._id = def.id
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.boonContent, "TOPLEFT", 0, -boonY)
        row:SetPoint("RIGHT", self.boonContent, "RIGHT", 0, 0)
        row:Show()

        row.box:SetColorTexture(selected and 0.85 or 0.40, selected and 0.75 or 0.40, selected and 0.35 or 0.40, selected and 0.90 or 0.50)
        row.label:SetText(def.name or def.id)
        row.sub:SetText(def.description or "")
        if modifiersLocked then
            safeTextColor(row.state, Theme.c.fg2, 0.7)
            row.state:SetText("LOCKED")
            row:SetAlpha(0.5)
        elseif selected then
            safeTextColor(row.state, Theme.c.gold, 1)
            row.state:SetText("ON")
            row:SetAlpha(1)
        else
            safeTextColor(row.state, Theme.c.fg2, 1)
            row.state:SetText("OFF")
            row:SetAlpha(1)
        end
        boonY = boonY + MOD_ROW_H + 1
    end
    self.boonContent:SetHeight(math.max(1, boonY))

    for i = #self.burdenRows + 1, #burdenDefs do
        local row = buildModifierRow(self.burdenContent, Theme)
        row:SetScript("OnClick", function()
            if modifiersLocked then return end
            local id = row._id
            local list = {}
            for burdenId in pairs((rec and rec.burdens) or {}) do
                if burdenId ~= id then
                    list[#list + 1] = burdenId
                end
            end
            if not (rec and rec.burdens and rec.burdens[id]) then
                list[#list + 1] = id
            end
            if ns.Boons then
                ns.Boons:SetBurdens(charKey, list)
            end
            Tab:Refresh()
        end)
        self.burdenRows[i] = row
    end
    for i = #burdenDefs + 1, #self.burdenRows do self.burdenRows[i]:Hide() end

    local burdenY = 0
    for i, def in ipairs(burdenDefs) do
        local row = self.burdenRows[i]
        local selected = rec and rec.burdens and rec.burdens[def.id] ~= nil
        row._id = def.id
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.burdenContent, "TOPLEFT", 0, -burdenY)
        row:SetPoint("RIGHT", self.burdenContent, "RIGHT", 0, 0)
        row:Show()

        row.box:SetColorTexture(selected and 0.85 or 0.40, selected and 0.75 or 0.40, selected and 0.35 or 0.40, selected and 0.90 or 0.50)
        row.label:SetText(def.name or def.id)
        row.sub:SetText(def.description or "")
        if modifiersLocked then
            safeTextColor(row.state, Theme.c.fg2, 0.7)
            row.state:SetText("LOCKED")
            row:SetAlpha(0.5)
        elseif selected then
            safeTextColor(row.state, Theme.c.gold, 1)
            row.state:SetText("ON")
            row:SetAlpha(1)
        else
            safeTextColor(row.state, Theme.c.fg2, 1)
            row.state:SetText("OFF")
            row:SetAlpha(1)
        end
        burdenY = burdenY + MOD_ROW_H + 1
    end
    self.burdenContent:SetHeight(math.max(1, burdenY))

    local footerWouldCollide = (#displayTiers == 0)
    if footerWouldCollide then
        self.sendBtn:Hide()
        self.mailBtn:Hide()
        self.footerHint:Hide()
    else
        self.sendBtn:Show()
        self.footerHint:Show()
        if offerMailFallback then
            self.mailBtn:Show()
        else
            self.mailBtn:Hide()
        end
    end

    if isBank then
        self.sendBtn:Disable()
        self.sendBtn:SetAlpha(0.45)
    elseif not bank or selectedCount == 0 or not ns.Settings:Get("allowBankRewards", true) then
        self.sendBtn:Disable()
        self.sendBtn:SetAlpha(0.45)
    else
        self.sendBtn:Enable()
        self.sendBtn:SetAlpha(1)
    end

    if not footerWouldCollide and offerMailFallback and not isBank and bank and selectedCount > 0 and ns.Settings:Get("allowBankRewards", true) then
        self.mailBtn:Enable()
        self.mailBtn:SetAlpha(1)
    else
        self.mailBtn:Disable()
        self.mailBtn:SetAlpha(0.45)
    end

    if not ns.Settings:Get("allowBankRewards", true) then
        self.footerHint:SetText("Bank starter rewards are disabled by the active rules profile.")
    end

    for i = #self.rows + 1, #displayTiers do
        local row = buildOptRow(self.content, Theme)
        row:SetScript("OnClick", function()
            local tier = row._tier
            if not tier then return end
            local claimed = ns.Database:HasClaimedTier(charKey, tier.id) and not ns.Database:AllowRepeatClaims()
            if claimed then return end
            self.selected[tier.id] = not self.selected[tier.id] or nil
            Tab:Refresh()
        end)
        self.rows[i] = row
    end
    for i = #displayTiers + 1, #self.rows do self.rows[i]:Hide() end

    local y = 0
    for i, t in ipairs(displayTiers) do
        local row = self.rows[i]
        local claimed = ns.Database:HasClaimedTier(charKey, t.id) and not allowRepeat
        local selected = self.selected[t.id] == true and not claimed
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
    for tierId, picked in pairs(self.selected or {}) do
        if picked then
            local allowed = true
            if ns.Rules and ns.Rules.CheckRepeatClaim then
                allowed = ns.Rules:CheckRepeatClaim(charKey, tierId)
            elseif not ns.Database:AllowRepeatClaims() and ns.Database:HasClaimedTier(charKey, tierId) then
                allowed = false
            end
            if allowed then
                tierIds[#tierIds + 1] = tierId
            end
        end
    end
    table.sort(tierIds)
    return tierIds
end

function Tab:SendRequest()
    local bank = WRL_DB and WRL_DB.bankCharacter
    if not bank then
        ns:Print("Set a bank first with |cffffff00/wrl setbank Name-Realm|r.")
        return
    end
    if ns.Database:IsBankCharacter() then
        ns:Print("Open New Run on a run character, not the bank.")
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
        ns:Print("Open New Run on a run character, not the bank.")
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
