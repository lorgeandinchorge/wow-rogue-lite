-- UI/Tab_Tiers.lua
-- Tier ladder: lifetime contribution, current/next rank, progress bar, reward
-- cards, and full ladder. Uses ns.Tiers for all tier math and money formatting.

local ADDON_NAME, ns = ...
local Tab = ns:NewModule("Tab_Tiers")
local TD = ns.TierDisplay or {
    IsBaselineTier = function(t) return t and t.id == 0 end,
    CelebrationLineForTierId = function() return "" end,
    LadderRewardSummary = function(t)
        if t and t.id == 0 then return "No rewards yet" end
        return "-"
    end,
    RewardPills = function() return {} end,
    NextRankUpgradeLines = function() return {} end,
}

local TIER_DEBUG_PRINT = false

local function tiersDbg(fmt, ...)
    if not TIER_DEBUG_PRINT then return end
    print(("[WRL Tiers] " .. fmt):format(...))
end

local TIER_ROW_H = 76
local TIER_ROW_CURRENT_H = 90
local REWARD_CARD_PAD = 12
local TIER_ICON_SIZE = 18
local TIER_ICON_MAX = 5
local itemDisplayName

local function setShown(region, shown)
    if shown then
        region:Show()
    else
        region:Hide()
    end
end

local function mixColor(a, b, t)
    return {
        a[1] * (1 - t) + b[1] * t,
        a[2] * (1 - t) + b[2] * t,
        a[3] * (1 - t) + b[3] * t,
        1,
    }
end

local function createTierIcon(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(TIER_ICON_SIZE, TIER_ICON_SIZE)

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

local function setTierIcon(icon, texture, count, title, line1, line2)
    icon.tex:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon.count:SetText(count or "")
    icon._tipTitle = title
    icon._tipLine1 = line1
    icon._tipLine2 = line2
    icon:Show()
    icon.count:Show()
end

local function fillTierIcons(row, tier, T)
    -- Resolve display contents via Rewards module; fall back to empty if unavailable.
    local c = (ns.Rewards and ns.Rewards:GetTierDisplayContents(tier.id))
        or { items = tier.items or {}, gold = tier.gold or 0, extraLives = tier.extraLives or 0 }
    local idx = 1
    for _, it in ipairs(c.items or {}) do
        if idx > TIER_ICON_MAX then break end
        setTierIcon(
            row.icons[idx],
            GetItemIcon(it.id) or "Interface\\Icons\\INV_Misc_QuestionMark",
            tostring(it.qty or ""),
            itemDisplayName(it),
            ("Qty: %d"):format(it.qty or 0),
            ("Item ID: %d"):format(it.id or 0))
        idx = idx + 1
    end
    if c.gold and c.gold > 0 and idx <= TIER_ICON_MAX then
        setTierIcon(
            row.icons[idx],
            "Interface\\Icons\\INV_Misc_Coin_01",
            "",
            "Gold",
            T:FormatMoney(c.gold),
            "Granted at this tier.")
        idx = idx + 1
    end
    if c.extraLives and c.extraLives > 0 and idx <= TIER_ICON_MAX then
        setTierIcon(
            row.icons[idx],
            "Interface\\Icons\\Spell_Holy_Resurrection",
            tostring(c.extraLives),
            "Extra Life",
            ("Grants +%d life"):format(c.extraLives),
            "Applies to future runs.")
        idx = idx + 1
    end
    while idx <= TIER_ICON_MAX do
        row.icons[idx]:Hide()
        row.icons[idx].count:Hide()
        row.icons[idx]._tipTitle = nil
        row.icons[idx]._tipLine1 = nil
        row.icons[idx]._tipLine2 = nil
        idx = idx + 1
    end
end

local function createRewardCard(parent, Theme, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width or 340)
    Theme:Fill(f, Theme.c.bg1, true)

    f.title = Theme:Text(f, 13, Theme.c.goldH)
    f.title:SetPoint("TOPLEFT", REWARD_CARD_PAD, -REWARD_CARD_PAD)

    f.sub = Theme:Text(f, 10, Theme.c.fg2)
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
    f.sub:SetWidth((width or 340) - REWARD_CARD_PAD * 2)
    f.sub:SetJustifyH("LEFT")

    f.lines = {}
    for i = 1, 14 do
        local ln = Theme:Text(f, 11, Theme.c.fg)
        ln:SetWidth((width or 340) - REWARD_CARD_PAD * 2)
        ln:SetJustifyH("LEFT")
        f.lines[i] = ln
    end

    function f:ClearLines()
        for _, ln in ipairs(self.lines) do
            ln:Hide()
        end
    end

    function f:SetContent(titleStr, subtitleStr, lineStrs)
        self.title:SetText(titleStr or "")
        local prev
        if subtitleStr and subtitleStr ~= "" then
            self.sub:SetText(subtitleStr)
            self.sub:Show()
            prev = self.sub
        else
            self.sub:Hide()
            prev = self.title
        end

        self:ClearLines()
        local anchor = prev
        for i, s in ipairs(lineStrs or {}) do
            local ln = self.lines[i]
            if not ln then break end
            ln:SetText(s or "")
            ln:ClearAllPoints()
            ln:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
            ln:Show()
            anchor = ln
        end

        local totalH = REWARD_CARD_PAD + self.title:GetStringHeight()
        if subtitleStr and subtitleStr ~= "" then
            totalH = totalH + 6 + self.sub:GetStringHeight()
        end
        for i = 1, #(lineStrs or {}) do
            if self.lines[i] and self.lines[i]:IsShown() then
                totalH = totalH + 4 + self.lines[i]:GetStringHeight()
            end
        end
        self:SetHeight(totalH + REWARD_CARD_PAD)
    end

    return f
end

local function buildTierRow(content, Theme)
    local r = CreateFrame("Frame", nil, content)
    r:SetHeight(TIER_ROW_H)
    r:EnableMouse(true)

    Theme:Fill(r, Theme.c.bg1, false)

    r.checkbox = r:CreateTexture(nil, "ARTWORK")
    r.checkbox:SetSize(10, 10)
    r.checkbox:SetPoint("LEFT", 14, 14)

    r.name = Theme:Text(r, 14, Theme.c.fg)
    r.name:SetPoint("TOPLEFT", r.checkbox, "TOPRIGHT", 10, 0)

    r.currentBadge = Theme:Text(r, 12, Theme.c.goldH)
    r.currentBadge:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
    r.currentBadge:SetText("CURRENT")
    r.currentBadge:Hide()

    r.threshold = Theme:Text(r, 11, Theme.c.gold)
    r.threshold:SetPoint("LEFT", r.currentBadge, "RIGHT", 10, 0)

    r.blurb = Theme:Text(r, 11, Theme.c.fg2)
    r.blurb:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.blurb:SetJustifyH("LEFT")
    r.blurb:SetWidth(420)

    r.rewards = Theme:Text(r, 10, Theme.c.fg2)
    r.rewards:SetPoint("TOPRIGHT", -14, -10)
    r.rewards:SetJustifyH("RIGHT")
    r.rewards:SetWidth(240)

    r.iconRow = CreateFrame("Frame", nil, r)
    r.iconRow:SetPoint("TOPRIGHT", r.rewards, "BOTTOMRIGHT", 0, -6)
    r.iconRow:SetSize(180, TIER_ICON_SIZE)
    r.icons = {}
    for i = 1, TIER_ICON_MAX do
        local icon = createTierIcon(r.iconRow)
        if i == 1 then
            icon:SetPoint("RIGHT", r.iconRow, "RIGHT", 0, 0)
        else
            icon:SetPoint("RIGHT", r.icons[i - 1], "LEFT", -6, 0)
        end
        r.icons[i] = icon
    end

    return r
end

itemDisplayName = function(it)
    local name = GetItemInfo(it.id)
    if name and name ~= "" then return name end
    return it.note or ("Item " .. tostring(it.id))
end

local function showTierTooltip(row, t, total, unlocked)
    local Th = ns.Theme
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(("Tier %d - %s"):format(t.id, t.name), Th.c.goldH[1], Th.c.goldH[2], Th.c.goldH[3])
    GameTooltip:AddLine(" ", 0.5, 0.5, 0.5)

    if TD.IsBaselineTier(t) then
        GameTooltip:AddLine("True baseline tier. No bank rewards yet.", Th.c.fg2[1], Th.c.fg2[2], Th.c.fg2[3])
    end

    -- Resolve reward contents from Rewards module.
    local c = (ns.Rewards and ns.Rewards:GetTierDisplayContents(t.id))
        or { items = t.items or {}, gold = t.gold or 0, extraLives = t.extraLives or 0 }

    for _, it in ipairs(c.items or {}) do
        GameTooltip:AddLine(
            ("%dx %s"):format(it.qty, itemDisplayName(it)),
            Th.c.fg[1], Th.c.fg[2], Th.c.fg[3])
    end

    if c.gold and c.gold > 0 then
        GameTooltip:AddLine(
            "Stipend: " .. ns.Tiers:FormatMoney(c.gold),
            Th.c.fg2[1], Th.c.fg2[2], Th.c.fg2[3])
    end

    if c.extraLives and c.extraLives > 0 then
        GameTooltip:AddLine(
            ("Extra lives on run: %d"):format(c.extraLives),
            Th.c.fg2[1], Th.c.fg2[2], Th.c.fg2[3])
    end

    if not unlocked then
        local need = math.max(0, (t.threshold or 0) - total)
        GameTooltip:AddLine(" ", 0.5, 0.5, 0.5)
        GameTooltip:AddLine(
            "Need " .. ns.Tiers:FormatMoney(need) .. " more to unlock.",
            Th.c.gold[1], Th.c.gold[2], Th.c.gold[3])
    end

    GameTooltip:Show()
end

function Tab:Init(parent)
    if self.panel then return end
    local Theme = ns.Theme

    local p = CreateFrame("Frame", nil, parent)
    self.panel = p
    ns.MainFrame:RegisterPanel("Tiers", p)

    local title = Theme:Header(p, "Tier Progression", 16)
    title:SetPoint("TOPLEFT", 20, -18)

    self.lifetimeText = Theme:Text(p, 12, Theme.c.gold)
    self.lifetimeText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

    self.zeroStateText = Theme:Text(p, 10, Theme.c.fg2)
    self.zeroStateText:SetPoint("TOPLEFT", self.lifetimeText, "BOTTOMLEFT", 0, -4)
    self.zeroStateText:SetWidth(700)
    self.zeroStateText:SetJustifyH("LEFT")

    local scroll, content = Theme:ScrollArea(p)
    scroll:SetPoint("TOPLEFT", 20, -94)
    scroll:SetPoint("BOTTOMRIGHT", -20, 16)
    content:SetSize(720, 600)
    scroll:EnableMouse(true)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sf, delta)
        local range = sf:GetVerticalScrollRange()
        if range <= 0 then return end
        local step = (delta > 0) and -25 or 25
        local nextValue = math.max(0, math.min(range, sf:GetVerticalScroll() + step))
        sf:SetVerticalScroll(nextValue)
        local bar = _G[(sf:GetName() or "") .. "ScrollBar"]
        if bar then bar:SetValue(nextValue) end
    end)
    self.scroll = scroll
    self.content = content

    self.uiError = Theme:Text(p, 11, Theme.c.red)
    self.uiError:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 4)
    self.uiError:SetWidth(680)
    self.uiError:SetJustifyH("LEFT")
    self.uiError:Hide()

    self.headerBlock = CreateFrame("Frame", nil, content)
    self.headerBlock:SetSize(720, 120)

    self.currentRankLabel = Theme:Text(self.headerBlock, 14, Theme.c.fg)
    self.currentRankLabel:SetPoint("TOPLEFT", 0, 0)

    self.currentBlurb = Theme:Text(self.headerBlock, 11, Theme.c.fg2)
    self.currentBlurb:SetPoint("TOPLEFT", self.currentRankLabel, "BOTTOMLEFT", 0, -4)
    self.currentBlurb:SetWidth(680)
    self.currentBlurb:SetJustifyH("LEFT")

    self.currentCelebration = Theme:Text(self.headerBlock, 11, Theme.c.gold)
    self.currentCelebration:SetPoint("TOPLEFT", self.currentBlurb, "BOTTOMLEFT", 0, -4)
    self.currentCelebration:SetWidth(680)
    self.currentCelebration:SetJustifyH("LEFT")

    self.currentStatus = Theme:Text(self.headerBlock, 10, Theme.c.fg2)
    self.currentStatus:SetPoint("TOPLEFT", self.currentCelebration, "BOTTOMLEFT", 0, -4)

    self.nextRankLabel = Theme:Text(self.headerBlock, 14, Theme.c.fg)
    self.nextRankLabel:SetPoint("TOPLEFT", self.currentStatus, "BOTTOMLEFT", 0, -12)

    self.nextRankDetail = Theme:Text(self.headerBlock, 11, Theme.c.fg2)
    self.nextRankDetail:SetPoint("TOPLEFT", self.nextRankLabel, "BOTTOMLEFT", 0, -4)
    self.nextRankDetail:SetWidth(680)
    self.nextRankDetail:SetJustifyH("LEFT")

    self.untilRankLine = Theme:Text(self.headerBlock, 11, Theme.c.gold)
    self.untilRankLine:SetPoint("TOPLEFT", self.nextRankDetail, "BOTTOMLEFT", 0, -4)

    self.maxBadge = Theme:Text(self.headerBlock, 11, Theme.c.goldH)
    self.maxBadge:SetPoint("LEFT", self.nextRankLabel, "RIGHT", 12, 0)
    self.maxBadge:SetText("MAX RANK")
    self.maxBadge:Hide()

    self.progressSection = CreateFrame("Frame", nil, content)
    self.progressSection:SetSize(720, 52)

    self.progressLabel = Theme:Text(self.progressSection, 11, Theme.c.fg2)
    self.progressLabel:SetPoint("TOPLEFT", 0, 0)

    self.progressBar = Theme:ProgressBar(self.progressSection, 680, 10)
    self.progressBar:SetPoint("TOPLEFT", self.progressLabel, "BOTTOMLEFT", 0, -6)

    self.progressDetail = Theme:Text(self.progressSection, 10, Theme.c.fg2)
    self.progressDetail:SetPoint("TOPLEFT", self.progressBar, "BOTTOMLEFT", 0, -4)
    self.progressDetail:SetWidth(680)
    self.progressDetail:SetJustifyH("LEFT")

    self.rewardRow = CreateFrame("Frame", nil, content)
    self.rewardRow:SetSize(720, 160)

    local cardW = 348
    self.cardCurrent = createRewardCard(self.rewardRow, Theme, cardW)
    self.cardCurrent:SetPoint("TOPLEFT", self.rewardRow, "TOPLEFT", 0, 0)

    self.cardNext = createRewardCard(self.rewardRow, Theme, cardW)
    self.cardNext:SetPoint("TOPLEFT", self.cardCurrent, "TOPRIGHT", 16, 0)

    self.ladderTitle = Theme:Text(content, 12, Theme.c.goldH)
    self.ladderTitle:SetText("Tier Ladder")
    self.rows = {}

    self.lockHeader = Theme:Text(content, 10, Theme.c.fg2)
    self.lockHeader:SetText("- LOCKED TIERS -")
    self.lockHeader:Hide()

    p.Refresh = function() Tab:Refresh() end
    self:Refresh()
end

local function layoutHeaderBlock(self)
    local h = 0
    h = h + self.currentRankLabel:GetStringHeight()
    h = h + 4 + self.currentBlurb:GetStringHeight()
    if self.currentCelebration:IsShown() then
        h = h + 4 + self.currentCelebration:GetStringHeight()
    end
    h = h + 4 + self.currentStatus:GetStringHeight()
    h = h + 12 + self.nextRankLabel:GetStringHeight()
    h = h + 4 + self.nextRankDetail:GetStringHeight()
    if self.untilRankLine:IsShown() then
        h = h + 4 + self.untilRankLine:GetStringHeight()
    end
    self.headerBlock:SetHeight(math.max(80, h))
end

function Tab:Refresh()
    if not self.panel then return end
    tiersDbg("Refresh() start")
    self.uiError:Hide()

    local ok, err = pcall(function() self:_RefreshImpl() end)
    if not ok then
        self.uiError:SetText("Tier panel failed: " .. tostring(err))
        self.uiError:Show()
        ns:Print("Tier UI error: %s", tostring(err))
        if self.content then
            self.content:SetHeight(400)
        end
    end
end

function Tab:_RefreshImpl()
    local Theme = ns.Theme
    local T = ns.Tiers
    if not T or not T.Definitions then
        error("ns.Tiers module missing")
    end

    local defs = T:Definitions()
    if not defs or #defs == 0 then
        error("no tier definitions")
    end

    local total = (WRL_DB and WRL_DB.totalContributed) or 0
    if ns.Database and ns.Database.TotalContributed then
        total = ns.Database:TotalContributed()
    end

    local cur = T:CurrentTier(total)
    local nxt = T:NextTier(total)
    local pct = T:ProgressToNext(total)
    pct = pct or 0

    tiersDbg("total=%s cur=%s next=%s rowsDefs=%d", tostring(total), cur and cur.name or "nil", nxt and nxt.name or "MAX", #defs)

    local unlockedList = T:UnlockedTiers(total)
    self.lifetimeText:SetText(string.format(
        "Lifetime contributed: %s   |   %d / %d tiers unlocked",
        T:FormatMoney(total),
        #unlockedList,
        #defs))
    if WRL_DB and WRL_DB.bankCharacter then
        self.zeroStateText:SetText(("Bank character: |cffc0a060%s|r"):format(WRL_DB.bankCharacter))
    else
        self.zeroStateText:SetText("|cff9a948aNo bank character set yet.|r Tier progress still shows here; set the bank toon with |cffe6e0d4/wrl setbank|r.")
    end

    if not cur or not cur.name then
        error("CurrentTier returned invalid tier")
    end

    self.currentRankLabel:SetText(("Current Rank: |cffe6e0d4%s|r"):format(cur.name))
    self.currentBlurb:SetText(cur.blurb or "")

    local celeb = TD.CelebrationLineForTierId(cur.id)
    self.currentCelebration:SetText(celeb ~= "" and ('"' .. celeb .. '"') or "")
    setShown(self.currentCelebration, celeb ~= "")

    self.currentStatus:ClearAllPoints()
    if celeb ~= "" then
        self.currentStatus:SetPoint("TOPLEFT", self.currentCelebration, "BOTTOMLEFT", 0, -4)
    else
        self.currentStatus:SetPoint("TOPLEFT", self.currentBlurb, "BOTTOMLEFT", 0, -4)
    end
    if TD.IsBaselineTier(cur) then
        self.currentStatus:SetText("Baseline tier active. No rewards yet; contribute to the bank to unlock your first rank reward.")
    else
        self.currentStatus:SetText("Unlocked and active. This rank's rewards are available for new runs.")
    end

    setShown(self.maxBadge, nxt == nil)
    if nxt then
        local remain = math.max(0, (nxt.threshold or 0) - total)
        self.nextRankLabel:SetText(("Next Rank: |cffc0a060%s|r"):format(nxt.name))
        self.nextRankDetail:SetText(string.format(
            "Unlocks at %s contributed. You need %s more.",
            T:FormatMoney(nxt.threshold or 0),
            T:FormatMoney(remain)))
        self.untilRankLine:SetText(string.format(
            "%s more until |cffc0a060%s|r",
            T:FormatMoney(remain),
            nxt.name))
        self.untilRankLine:Show()
    else
        self.nextRankLabel:SetText("Next Rank: |cffc0a060-|r")
        self.nextRankDetail:SetText("Max rank reached. You already hold the top tier.")
        self.untilRankLine:Hide()
    end

    layoutHeaderBlock(self)

    self.progressBar:SetProgress(pct)
    local pctInt = math.floor(pct * 100 + 0.5)
    self.progressLabel:SetText(("Progress toward next rank: |cffc0a060%d%%|r"):format(pctInt))
    if nxt then
        self.progressDetail:SetText(string.format(
            "Progress: %d%%  (%s / %s)",
            pctInt,
            T:FormatMoney(total),
            T:FormatMoney(nxt.threshold or 0)))
    else
        self.progressDetail:SetText("Progress: 100% - you've reached the final rank.")
    end

    local progH = self.progressLabel:GetStringHeight() + 6 + 10 + 4 + self.progressDetail:GetStringHeight() + 4
    self.progressSection:SetHeight(math.max(48, progH))

    local currentLines = {}
    if TD.IsBaselineTier(cur) then
        currentLines[1] = "No rewards on the Barebones baseline."
        if nxt then
            currentLines[2] = ("First unlock: |cffc0a060%s|r at %s."):format(nxt.name, T:FormatMoney(nxt.threshold or 0))
        else
            currentLines[2] = "All tiers are already unlocked."
        end
    else
        for _, s in ipairs(TD.RewardPills(cur, T)) do
            currentLines[#currentLines + 1] = s
        end
    end
    self.cardCurrent:SetContent(
        "Current rank rewards",
        TD.IsBaselineTier(cur) and "Baseline (tier 0)" or nil,
        currentLines)

    if nxt then
        local up = TD.NextRankUpgradeLines(cur, nxt, T)
        local nextLines = {}
        for _, s in ipairs(up) do nextLines[#nextLines + 1] = s end
        if #nextLines == 0 then
            nextLines[1] = "No rewards configured for this tier yet."
        end
        self.cardNext:SetContent(
            "Next rank preview: " .. nxt.name,
            "Full bundle at this tier",
            nextLines)
    else
        self.cardNext:SetContent(
            "Ascendant",
            nil,
            { "|cffffcc00You are Legend.|r Nothing left to earn - enjoy the immortal bloodline." })
    end

    self.rewardRow:SetHeight(math.max(self.cardCurrent:GetHeight(), self.cardNext:GetHeight()))

    for i = #self.rows + 1, #defs do
        self.rows[i] = buildTierRow(self.content, Theme)
    end
    for i = #defs + 1, #self.rows do
        self.rows[i]:Hide()
    end

    local currentBg = mixColor(Theme.c.bg2, Theme.c.gold, 0.14)
    local LOCK_ALPHA = 0.45
    local LOCK_REWARD_ALPHA = 0.65
    local LOCK_HEADER_GAP = 6

    local y = 0

    self.headerBlock:ClearAllPoints()
    self.headerBlock:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
    y = y + self.headerBlock:GetHeight() + 8

    self.progressSection:ClearAllPoints()
    self.progressSection:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
    y = y + self.progressSection:GetHeight() + 16

    self.rewardRow:ClearAllPoints()
    self.rewardRow:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
    y = y + self.rewardRow:GetHeight() + 16

    self.ladderTitle:ClearAllPoints()
    self.ladderTitle:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
    y = y + self.ladderTitle:GetStringHeight() + 8

    local firstLocked = true
    for i, t in ipairs(defs) do
        local unlocked = total >= (t.threshold or 0)
        local isCurrent = cur.id == t.id

        if not unlocked and firstLocked then
            self.lockHeader:ClearAllPoints()
            self.lockHeader:SetPoint("TOPLEFT", self.content, "TOPLEFT", 4, -y)
            self.lockHeader:Show()
            firstLocked = false
            y = y + self.lockHeader:GetStringHeight() + LOCK_HEADER_GAP
        end

        local row = self.rows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", self.content, "RIGHT", -16, 0)
        row:SetHeight(isCurrent and TIER_ROW_CURRENT_H or TIER_ROW_H)
        row:Show()

        local dimmed = not unlocked
        if isCurrent then
            Theme:Fill(row, currentBg, true)
            row.currentBadge:Show()
            row.threshold:ClearAllPoints()
            row.threshold:SetPoint("LEFT", row.currentBadge, "RIGHT", 10, 0)
        else
            Theme:Fill(row, Theme.c.bg1, false)
            row.currentBadge:Hide()
            row.threshold:ClearAllPoints()
            row.threshold:SetPoint("LEFT", row.name, "RIGHT", 12, 0)
        end

        local col = unlocked and Theme.c.gold or Theme.c.fg2
        row.checkbox:SetColorTexture(col[1], col[2], col[3], 1)

        local fg = Theme.c.fg
        local fg2 = Theme.c.fg2
        local na = dimmed and LOCK_ALPHA or 1
        local ra = dimmed and LOCK_REWARD_ALPHA or 1

        row.name:SetText(("Tier %d - %s"):format(t.id, t.name))
        row.name:SetTextColor(fg[1], fg[2], fg[3], na)

        row.threshold:SetText((t.threshold or 0) > 0 and (">= " .. T:FormatMoney(t.threshold or 0)) or "(baseline)")
        row.threshold:SetTextColor(
            (unlocked and Theme.c.gold[1] or Theme.c.fg2[1]) * (dimmed and 0.85 or 1),
            (unlocked and Theme.c.gold[2] or Theme.c.fg2[2]) * (dimmed and 0.85 or 1),
            (unlocked and Theme.c.gold[3] or Theme.c.fg2[3]) * (dimmed and 0.85 or 1),
            na)

        row.blurb:SetText(t.blurb or "")
        row.blurb:SetTextColor(fg2[1], fg2[2], fg2[3], na)

        row.rewards:SetText(TD.LadderRewardSummary(t, T))
        row.rewards:SetTextColor(fg2[1], fg2[2], fg2[3], ra)
        fillTierIcons(row, t, T)

        row:SetScript("OnEnter", function(rf)
            showTierTooltip(rf, t, total, unlocked)
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        y = y + row:GetHeight() + 6
    end

    if firstLocked then
        self.lockHeader:Hide()
    end

    self.content:SetHeight(math.max(400, y))
    local w = self.scroll and self.scroll:GetWidth()
    if w and w > 40 then
        self.content:SetWidth(w)
    else
        self.content:SetWidth(720)
    end
    if self.scroll and self.scroll.UpdateScrollChildRect then
        self.scroll:UpdateScrollChildRect()
    end

    tiersDbg("layout done contentHeight=%d tierRows=%d", math.max(400, y), #defs)
end
