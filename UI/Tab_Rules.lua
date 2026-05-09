-- UI/Tab_Rules.lua
-- Account-wide profiles, rule toggles, and per-character rule log summary.

local ADDON_NAME, ns = ...
local Tab = ns:NewModule("Tab_Rules")

local RULE_ROW_H = 50
local OPT_ROW_H = 24
local LOG_LINES = 10
local DEATH_MODES = { "off", "local", "party", "guild" }
local DEATH_LABELS = {
    off = "Off",
    ["local"] = "Local",
    party = "Party",
    guild = "Guild",
}

local function safeTextColor(fs, c, a)
    if not fs or not c then return end
    fs:SetTextColor(c[1], c[2], c[3], a or 1)
end

local function setProfileButtonLook(btn, selected, Theme)
    if selected then
        btn.bg:SetColorTexture(Theme.c.gold[1] * 0.22, Theme.c.gold[2] * 0.22, Theme.c.gold[3] * 0.15, 1)
        safeTextColor(btn.label, Theme.c.goldH, 1)
    else
        btn.bg:SetColorTexture(Theme.c.bg2[1], Theme.c.bg2[2], Theme.c.bg2[3], 1)
        safeTextColor(btn.label, Theme.c.fg, 1)
    end
end

local function cycleDeathMode(cur)
    local idx = 1
    for i, m in ipairs(DEATH_MODES) do
        if m == cur then idx = i; break end
    end
    return DEATH_MODES[(idx % #DEATH_MODES) + 1]
end

local function buildRuleRow(parent, Theme)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(RULE_ROW_H)
    Theme:Fill(r, Theme.c.bg1, false)

    r.box = r:CreateTexture(nil, "ARTWORK")
    r.box:SetSize(12, 12)
    r.box:SetPoint("LEFT", 10, 0)

    r.name = Theme:Text(r, 12, Theme.c.fg)
    r.name:SetPoint("TOPLEFT", 30, -8)
    r.name:SetWidth(360)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)

    r.sev = Theme:Text(r, 10, Theme.c.fg2)
    r.sev:SetPoint("TOPRIGHT", -10, -8)
    r.sev:SetWidth(120)
    r.sev:SetJustifyH("RIGHT")
    r.sev:SetWordWrap(false)

    r.desc = Theme:Text(r, 10, Theme.c.fg2)
    r.desc:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.desc:SetPoint("TOPRIGHT", r, "TOPRIGHT", -10, -22)
    r.desc:SetJustifyH("LEFT")

    r.state = Theme:Text(r, 10, Theme.c.gold)
    r.state:SetPoint("RIGHT", r.sev, "LEFT", -6, 0)
    r.state:SetWidth(44)
    r.state:SetJustifyH("RIGHT")

    return r
end

local function buildOptRow(parent, Theme, onToggle)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(OPT_ROW_H)

    r.box = r:CreateTexture(nil, "ARTWORK")
    r.box:SetSize(12, 12)
    r.box:SetPoint("LEFT", 8, 0)

    r.label = Theme:Text(r, 11, Theme.c.fg)
    r.label:SetPoint("LEFT", 28, 0)
    r.label:SetWidth(520)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)

    r:SetScript("OnClick", function()
        if onToggle then onToggle(r) end
    end)
    return r
end

function Tab:Init(parent)
    if self.panel then return end
    local Theme = ns.Theme

    local p = CreateFrame("Frame", nil, parent)
    self.panel = p
    ns.MainFrame:RegisterPanel("Rules", p)

    local title = Theme:Header(p, "Rules & Profiles", 16)
    title:SetPoint("TOPLEFT", 20, -18)

    self.currentProfile = Theme:Text(p, 11, Theme.c.gold)
    self.currentProfile:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    self.currentProfile:SetWidth(720)
    self.currentProfile:SetJustifyH("LEFT")

    -- Profile presets (two compact rows; fits 780px frame).
    self.profileButtons = {}
    local row1 = { "casual_roguelite", "banked_hardcore", "solo_self_found" }
    local row2 = { "ironman", "custom" }
    local y1, y2 = -46, -74
    local w1, w2 = 220, 220
    for i, pid in ipairs(row1) do
        local b = Theme:Button(p, ns.Settings:ProfileDisplayName(pid), w1, 22)
        b:SetPoint("TOPLEFT", title, "BOTTOMLEFT", (i - 1) * (w1 + 8), y1)
        b._profileId = pid
        b:SetScript("OnClick", function()
            ns.Settings:ApplyProfile(pid)
            Tab:Refresh()
        end)
        self.profileButtons[pid] = b
    end
    for i, pid in ipairs(row2) do
        local b = Theme:Button(p, ns.Settings:ProfileDisplayName(pid), w2, 22)
        b:SetPoint("TOPLEFT", title, "BOTTOMLEFT", (i - 1) * (w2 + 8), y2)
        b._profileId = pid
        b:SetScript("OnClick", function()
            ns.Settings:ApplyProfile(pid)
            Tab:Refresh()
        end)
        self.profileButtons[pid] = b
    end

    Theme:Divider(p, "TOPLEFT", "TOPRIGHT", 0, -136, 0.2)

    local scroll, content = Theme:ScrollArea(p)
    scroll:SetPoint("TOPLEFT", 20, -150)
    scroll:SetPoint("BOTTOMRIGHT", -20, 14)
    content:SetSize(720, 400)
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

    local y = 0
    self.optHeader = Theme:Text(content, 12, Theme.c.goldH)
    self.optHeader:SetPoint("TOPLEFT", 0, -y)
    self.optHeader:SetText("Account options")
    y = y + 18

    self.optBank = buildOptRow(content, Theme, function()
        local v = not (ns.Settings:Get("allowBankRewards", true) == true)
        ns.Settings:Set("allowBankRewards", v)
        Tab:Refresh()
    end)
    self.optBank:SetPoint("TOPLEFT", 0, -y)
    self.optBank:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    y = y + OPT_ROW_H + 2

    self.optRepeat = buildOptRow(content, Theme, function()
        local v = not (ns.Settings:Get("allowRepeatClaims", false) == true)
        ns.Settings:Set("allowRepeatClaims", v)
        Tab:Refresh()
    end)
    self.optRepeat:SetPoint("TOPLEFT", 0, -y)
    self.optRepeat:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    y = y + OPT_ROW_H + 2

    self.optDeath = buildOptRow(content, Theme, function()
        local cur = ns.Settings:Get("announceDeaths", "local")
        ns.Settings:Set("announceDeaths", cycleDeathMode(cur))
        Tab:Refresh()
    end)
    self.optDeath:SetPoint("TOPLEFT", 0, -y)
    self.optDeath:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    y = y + OPT_ROW_H + 8

    self.taintLine = Theme:Text(content, 11, Theme.c.fg)
    self.taintLine:SetPoint("TOPLEFT", 0, -y)
    self.taintLine:SetWidth(700)
    self.taintLine:SetJustifyH("LEFT")
    y = y + 20

    self.rulesHeader = Theme:Text(content, 12, Theme.c.goldH)
    self.rulesHeader:SetPoint("TOPLEFT", 0, -y)
    self.rulesHeader:SetText("Roguelite rules (this account)")
    y = y + 18

    self.ruleRows = {}
    local defs = ns.Rules:Definitions()
    for i, def in ipairs(defs) do
        local row = buildRuleRow(content, Theme)
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        row._ruleId = def.id
        row:SetScript("OnClick", function()
            local id = row._ruleId
            local on = ns.Rules:IsEnabled(id)
            ns.Settings:SetRuleEnabled(id, not on)
            ns.Settings:ApplyProfile("custom")
            Tab:Refresh()
        end)
        self.ruleRows[i] = row
        y = y + RULE_ROW_H + 4
    end

    y = y + 6
    self.logHeader = Theme:Text(content, 12, Theme.c.goldH)
    self.logHeader:SetPoint("TOPLEFT", 0, -y)
    self.logHeader:SetText("Recent rule log (this character)")
    y = y + 18

    self.logEmpty = Theme:Text(content, 10, Theme.c.fg2)
    self.logEmpty:SetPoint("TOPLEFT", 0, -y)
    self.logEmpty:SetWidth(700)
    self.logEmpty:SetJustifyH("LEFT")
    self.logEmpty:SetText("No entries yet.")
    y = y + 16

    self.logLines = {}
    for i = 1, LOG_LINES do
        local fs = Theme:Text(content, 10, Theme.c.fg2)
        fs:SetWidth(700)
        fs:SetJustifyH("LEFT")
        fs:SetPoint("TOPLEFT", 0, -y)
        self.logLines[i] = fs
        y = y + 32
    end

    self._scrollContentHeight = y + 16
    content:SetHeight(math.max(400, self._scrollContentHeight))

    p.Refresh = function() Tab:Refresh() end
    Tab:Refresh()
end

function Tab:Refresh()
    if not self.panel then return end
    local Theme = ns.Theme

    local prof = ns.Settings:GetProfile()
    self.currentProfile:SetText(("Active profile: |cffc0a060%s|r"):format(ns.Settings:ProfileDisplayName(prof)))

    for pid, btn in pairs(self.profileButtons) do
        setProfileButtonLook(btn, prof == pid, Theme)
    end

    -- Account toggles
    local bankOn = ns.Settings:Get("allowBankRewards", true) == true
    self.optBank.box:SetColorTexture(bankOn and 0.38 or 0.40, bankOn and 0.70 or 0.40,
        bankOn and 0.38 or 0.40, bankOn and 0.85 or 0.50)
    self.optBank.label:SetText("Allow bank starter rewards (mail / trade from bank)")

    local repOn = ns.Settings:Get("allowRepeatClaims", false) == true
    self.optRepeat.box:SetColorTexture(repOn and 0.85 or 0.40, repOn and 0.75 or 0.40,
        repOn and 0.35 or 0.40, repOn and 0.90 or 0.50)
    self.optRepeat.label:SetText("Allow repeat tier claims (same rank more than once)")

    local death = ns.Settings:Get("announceDeaths", "local")
    local dlab = DEATH_LABELS[death] or tostring(death)
    self.optDeath.box:SetColorTexture(0.40, 0.55, 0.75, 0.75)
    self.optDeath.label:SetText(("Death announcements: %s (click to cycle)"):format(dlab))

    local key = ns:UnitKey()
    local taints = (key and ns.Rules:TaintCount(key)) or 0
    local warns = 0
    if key then
        for _, e in ipairs(ns.Rules:GetLog(key)) do
            if e.result == "warned" or e.result == "blocked" then warns = warns + 1 end
        end
    end
    if taints > 0 then
        safeTextColor(self.taintLine, Theme.c.red, 1)
        self.taintLine:SetText(
            ("Taints: |cffff6060%d|r  ·  Warnings/blocks in log: %d"):format(taints, warns))
    else
        safeTextColor(self.taintLine, Theme.c.fg, 1)
        self.taintLine:SetText(("Taints: 0  ·  Warnings/blocks in log: %d"):format(warns))
    end

    for i, def in ipairs(ns.Rules:Definitions()) do
        local row = self.ruleRows[i]
        if row then
            local on = ns.Rules:IsEnabled(def.id)
            row.box:SetColorTexture(on and 0.38 or 0.40, on and 0.70 or 0.40, on and 0.38 or 0.40, on and 0.85 or 0.50)
            row.name:SetText(def.name or def.id)
            row.desc:SetText(def.description or "")
            local sev = (def.severity or ""):lower()
            if sev == "strict" then
                safeTextColor(row.sev, Theme.c.red, 1)
                row.sev:SetText("strict")
            else
                safeTextColor(row.sev, Theme.c.gold, 1)
                row.sev:SetText(sev ~= "" and sev or "warn")
            end
            safeTextColor(row.state, Theme.c.gold, 1)
            row.state:SetText(on and "ON" or "OFF")
        end
    end

    local log = (key and ns.Rules:GetLog(key)) or {}
    local n = #log
    if n == 0 then
        self.logEmpty:Show()
        for i = 1, LOG_LINES do self.logLines[i]:Hide() end
    else
        self.logEmpty:Hide()
        local shown = 0
        for idx = n, math.max(1, n - LOG_LINES + 1), -1 do
            shown = shown + 1
            if shown > LOG_LINES then break end
            local e = log[idx]
            local fs = self.logLines[shown]
            local whenStr = e.when and date("%m-%d %H:%M", e.when) or "?"
            local res = e.result or "?"
            local col = Theme.c.fg2
            if res == "tainted" then col = Theme.c.red
            elseif res == "warned" then col = Theme.c.goldH
            elseif res == "blocked" then col = Theme.c.gold
            elseif res == "allowed" then col = Theme.c.green end
            local detail = e.detail or ""
            if #detail > 72 then detail = detail:sub(1, 69) .. "..." end
            local ruleShort = e.ruleId or "?"
            if #ruleShort > 22 then ruleShort = ruleShort:sub(1, 19) .. "..." end
            fs:SetTextColor(col[1], col[2], col[3], 1)
            fs:SetText(("%s  %s  [%s]  %s"):format(whenStr, ruleShort, res, detail))
            fs:Show()
        end
        for i = shown + 1, LOG_LINES do
            self.logLines[i]:Hide()
        end
    end

    self.scroll:SetVerticalScroll(0)
end
