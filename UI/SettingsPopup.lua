-- UI/SettingsPopup.lua
-- Scrollable addon settings surface opened from the main-frame gear button.

local ADDON_NAME, ns = ...
local Popup = ns:NewModule("SettingsPopup")

local POPUP_W, POPUP_H = 720, 520
local ROW_H = 28
local MOD_ROW_H = 30
local RULE_ROW_H = 50
local LOG_LINES = 10

local DEATH_MODES = { "off", "local", "party", "guild" }
local DEATH_LABELS = {
    off = "Off",
    ["local"] = "Local",
    party = "Party",
    guild = "Guild",
}

local function setTextColor(fs, color, alpha)
    if fs and color then
        fs:SetTextColor(color[1], color[2], color[3], alpha or 1)
    end
end

local function buildToggle(parent, Theme, label, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)

    row.box = row:CreateTexture(nil, "ARTWORK")
    row.box:SetSize(12, 12)
    row.box:SetPoint("LEFT", 0, 0)

    row.label = Theme:Text(row, 11, Theme.c.fg)
    row.label:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
    row.label:SetWidth(560)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetText(label or "")

    row:SetScript("OnClick", function()
        if onClick then onClick(row) end
    end)

    return row
end

local function setToggle(row, on, Theme)
    if not row then return end
    row.box:SetColorTexture(on and 0.38 or 0.40, on and 0.70 or 0.40, on and 0.38 or 0.40, on and 0.85 or 0.50)
    setTextColor(row.label, on and Theme.c.fg or Theme.c.fg2, 1)
end

local function dropdownSetText(dropdown, text)
    if UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(dropdown, text or "")
    elseif dropdown and dropdown.label then
        dropdown.label:SetText(text or "")
    end
end

local function dropdownSetWidth(dropdown, width)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dropdown, width or 150)
    end
end

local function buildSectionHeader(parent, Theme, text, y)
    local label = Theme:Text(parent, 12, Theme.c.goldH)
    label:SetPoint("TOPLEFT", 0, -y)
    label:SetText(text)
    label:SetJustifyH("LEFT")
    return label, y + 22
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

local function buildModifierRow(parent, Theme)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(MOD_ROW_H)
    Theme:Fill(r, Theme.c.bg1, false)

    r.box = r:CreateTexture(nil, "ARTWORK")
    r.box:SetSize(12, 12)
    r.box:SetPoint("LEFT", 10, 0)

    r.name = Theme:Text(r, 11, Theme.c.fg)
    r.name:SetPoint("TOPLEFT", 30, -5)
    r.name:SetWidth(210)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)

    r.desc = Theme:Text(r, 9, Theme.c.fg2)
    r.desc:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
    r.desc:SetWidth(210)
    r.desc:SetJustifyH("LEFT")
    r.desc:SetWordWrap(false)

    r.state = Theme:Text(r, 10, Theme.c.gold)
    r.state:SetPoint("RIGHT", -10, 0)
    r.state:SetWidth(54)
    r.state:SetJustifyH("RIGHT")

    return r
end

local function setProfileButtonLook(btn, selected, Theme)
    if not btn then return end
    if selected then
        btn.bg:SetColorTexture(Theme.c.gold[1] * 0.22, Theme.c.gold[2] * 0.22, Theme.c.gold[3] * 0.15, 1)
        setTextColor(btn.label, Theme.c.goldH, 1)
    else
        btn.bg:SetColorTexture(Theme.c.bg2[1], Theme.c.bg2[2], Theme.c.bg2[3], 1)
        setTextColor(btn.label, Theme.c.fg, 1)
    end
end

local function fmtWhen(ts)
    if ts and date then return date("%m-%d %H:%M", ts) end
    return ts and tostring(ts) or "?"
end

function Popup:ToggleModifier(kind, id)
    if not id or not ns.Boons then return end
    local key = ns:UnitKey()
    if not key or ns.Boons:IsLocked(key) then
        ns:Print("Run modifiers lock once the run has claimed rewards or retired.")
        return
    end
    local rec = ns.Database and ns.Database:GetCharacter(key)
    if not rec then return end

    local source = kind == "burden" and (rec.burdens or {}) or (rec.boons or {})
    local list = {}
    for selectedId in pairs(source) do
        if selectedId ~= id then
            list[#list + 1] = selectedId
        end
    end
    if not source[id] then
        list[#list + 1] = id
    end

    if kind == "burden" then
        ns.Boons:SetBurdens(key, list)
    else
        ns.Boons:SetBoons(key, list)
    end
    self:Refresh()
    if ns.MainFrame then ns.MainFrame:RefreshCurrentTab() end
end

function Popup:RefreshModifierRows()
    local Theme = ns.Theme
    local key = ns:UnitKey()
    local rec = key and ns.Database and ns.Database:GetCharacter(key)
    local locked = not (ns.Boons and key and rec) or ns.Boons:IsLocked(key)

    if self.modifiersHint then
        self.modifiersHint:SetText(locked
            and "These choices apply to the current run and are locked after a reward claim or retirement."
            or "Choose optional run modifiers before requesting starter rewards.")
    end

    local function paint(row, def, selected)
        row._id = def.id
        row.name:SetText(def.name or def.id)
        row.desc:SetText(def.description or "")
        row.box:SetColorTexture(selected and 0.85 or 0.40, selected and 0.75 or 0.40, selected and 0.35 or 0.40, selected and 0.90 or 0.50)
        row.state:SetText(locked and "LOCKED" or (selected and "ON" or "OFF"))
        setTextColor(row.name, selected and Theme.c.fg or Theme.c.fg2, 1)
        setTextColor(row.state, locked and Theme.c.fg2 or Theme.c.gold, 1)
        row:SetAlpha(locked and 0.55 or 1)
    end

    local boonDefs = ns.Boons and ns.Boons.BoonDefs and ns.Boons:BoonDefs() or {}
    for i, def in ipairs(boonDefs) do
        local row = self.boonRows and self.boonRows[i]
        if row then
            paint(row, def, rec and rec.boons and rec.boons[def.id] ~= nil)
        end
    end

    local burdenDefs = ns.Boons and ns.Boons.BurdenDefs and ns.Boons:BurdenDefs() or {}
    for i, def in ipairs(burdenDefs) do
        local row = self.burdenRows and self.burdenRows[i]
        if row then
            paint(row, def, rec and rec.burdens and rec.burdens[def.id] ~= nil)
        end
    end
end

function Popup:Init()
    if self.frame then return end
    local Theme = ns.Theme

    local f = CreateFrame("Frame", "WRL_SettingsPopup", UIParent)
    f:SetSize(POPUP_W, POPUP_H)
    f:SetFrameStrata("DIALOG")
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Theme:Fill(f, Theme.c.bg0, true, "frame")
    table.insert(UISpecialFrames, "WRL_SettingsPopup")

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(52)
    Theme:Fill(header, Theme.c.headerBg or Theme.c.bg1, false, "header")
    self.header = header

    local title = Theme:Header(header, "Settings", 18)
    title:SetPoint("TOPLEFT", 18, -13)
    self.title = title

    local close = Theme:Button(header, "Close", 58, 22)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function() f:Hide() end)

    local scroll, content = Theme:ScrollArea(f)
    scroll:SetPoint("TOPLEFT", 20, -68)
    scroll:SetPoint("BOTTOMRIGHT", -38, 18)
    content:SetSize(640, 1)
    self.scroll = scroll
    self.content = content

    local y = 0
    self.themeLabel, y = buildSectionHeader(content, Theme, "UI Theme", y)
    local dd = CreateFrame("Frame", "WRL_SettingsThemeDropdown", content, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", self.themeLabel, "BOTTOMLEFT", -16, -2)
    dropdownSetWidth(dd, 196)
    self.themeDropdown = dd
    self.note = Theme:Text(content, 10, Theme.c.fg2)
    self.note:SetPoint("TOPLEFT", 220, -y)
    self.note:SetWidth(400)
    self.note:SetJustifyH("LEFT")
    y = y + 48

    self.fontLabel, y = buildSectionHeader(content, Theme, "Font", y)
    local fontDd = CreateFrame("Frame", "WRL_SettingsFontDropdown", content, "UIDropDownMenuTemplate")
    fontDd:SetPoint("TOPLEFT", self.fontLabel, "BOTTOMLEFT", -16, -2)
    dropdownSetWidth(fontDd, 196)
    self.fontDropdown = fontDd
    self.fontNote = Theme:Text(content, 10, Theme.c.fg2)
    self.fontNote:SetPoint("TOPLEFT", 220, -y)
    self.fontNote:SetWidth(400)
    self.fontNote:SetJustifyH("LEFT")
    y = y + 48

    self.deathLabel, y = buildSectionHeader(content, Theme, "Death Announcements", y)
    local deathDd = CreateFrame("Frame", "WRL_SettingsDeathDropdown", content, "UIDropDownMenuTemplate")
    deathDd:SetPoint("TOPLEFT", self.deathLabel, "BOTTOMLEFT", -16, -2)
    dropdownSetWidth(deathDd, 196)
    self.deathDropdown = deathDd
    self.optSoftDeaths = buildToggle(content, Theme, "Announce soft deaths locally", function()
        ns.Settings:Set("announceSoftDeaths", not (ns.Settings:Get("announceSoftDeaths", false) == true))
        Popup:Refresh()
    end)
    self.optSoftDeaths:SetPoint("TOPLEFT", 220, -(y - 4))
    self.optSoftDeaths:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    y = y + 46

    self.optionsLabel, y = buildSectionHeader(content, Theme, "Account Options", y)
    self.optBank = buildToggle(content, Theme, "Allow bank starter rewards", function()
        ns.Settings:Set("allowBankRewards", not (ns.Settings:Get("allowBankRewards", true) == true))
        Popup:Refresh()
        if ns.MainFrame then ns.MainFrame:RefreshCurrentTab() end
    end)
    self.optBank:SetPoint("TOPLEFT", 0, -y)
    self.optBank:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    y = y + ROW_H + 18

    self.modifiersLabel, y = buildSectionHeader(content, Theme, "Run Modifiers", y)
    self.modifiersHint = Theme:Text(content, 10, Theme.c.fg2)
    self.modifiersHint:SetPoint("TOPLEFT", 0, -y)
    self.modifiersHint:SetWidth(620)
    self.modifiersHint:SetJustifyH("LEFT")
    y = y + 24

    self.boonsHeader = Theme:Text(content, 11, Theme.c.gold)
    self.boonsHeader:SetPoint("TOPLEFT", 0, -y)
    self.boonsHeader:SetText("Boons")
    self.burdensHeader = Theme:Text(content, 11, Theme.c.gold)
    self.burdensHeader:SetPoint("TOPLEFT", 324, -y)
    self.burdensHeader:SetText("Burdens")
    y = y + 18

    self.boonRows = {}
    self.burdenRows = {}
    local modifierStartY = y
    local boonDefs = ns.Boons and ns.Boons.BoonDefs and ns.Boons:BoonDefs() or {}
    local burdenDefs = ns.Boons and ns.Boons.BurdenDefs and ns.Boons:BurdenDefs() or {}
    local modifierRows = math.max(#boonDefs, #burdenDefs)
    for i = 1, modifierRows do
        if boonDefs[i] then
            local row = buildModifierRow(content, Theme)
            row:SetPoint("TOPLEFT", 0, -(modifierStartY + (i - 1) * (MOD_ROW_H + 4)))
            row:SetWidth(308)
            row._kind = "boon"
            row:SetScript("OnClick", function()
                Popup:ToggleModifier(row._kind, row._id)
            end)
            self.boonRows[i] = row
        end
        if burdenDefs[i] then
            local row = buildModifierRow(content, Theme)
            row:SetPoint("TOPLEFT", 324, -(modifierStartY + (i - 1) * (MOD_ROW_H + 4)))
            row:SetWidth(308)
            row._kind = "burden"
            row:SetScript("OnClick", function()
                Popup:ToggleModifier(row._kind, row._id)
            end)
            self.burdenRows[i] = row
        end
    end
    y = y + math.max(1, modifierRows) * (MOD_ROW_H + 4) + 14

    self.rulesProfileLabel, y = buildSectionHeader(content, Theme, "Rules & Profiles", y)
    self.currentProfile = Theme:Text(content, 11, Theme.c.gold)
    self.currentProfile:SetPoint("TOPLEFT", 0, -y)
    self.currentProfile:SetWidth(620)
    self.currentProfile:SetJustifyH("LEFT")
    y = y + 24

    self.profileButtons = {}
    local profiles = ns.Settings:ProfileList()
    local btnW, btnH, gap = 120, 22, 8
    for i, pid in ipairs(profiles) do
        local b = Theme:Button(content, ns.Settings:ProfileDisplayName(pid), btnW, btnH)
        b:SetPoint("TOPLEFT", (i - 1) * (btnW + gap), -y)
        b._profileId = pid
        b:SetScript("OnClick", function()
            ns.Settings:ApplyProfile(pid)
            Popup:Refresh()
            if ns.MainFrame then ns.MainFrame:RefreshCurrentTab() end
        end)
        self.profileButtons[pid] = b
    end
    y = y + btnH + 18

    self.rulesHeader = Theme:Text(content, 12, Theme.c.goldH)
    self.rulesHeader:SetPoint("TOPLEFT", 0, -y)
    self.rulesHeader:SetText("Rule Toggles")
    y = y + 18

    self.ruleRows = {}
    local defs = ns.Rules and ns.Rules.Definitions and ns.Rules:Definitions() or {}
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
            Popup:Refresh()
            if ns.MainFrame then ns.MainFrame:RefreshCurrentTab() end
        end)
        self.ruleRows[i] = row
        y = y + RULE_ROW_H + 4
    end

    y = y + 8
    self.logLabel, y = buildSectionHeader(content, Theme, "Recent Rule Log", y)
    self.taintLine = Theme:Text(content, 11, Theme.c.fg)
    self.taintLine:SetPoint("TOPLEFT", 0, -y)
    self.taintLine:SetWidth(620)
    self.taintLine:SetJustifyH("LEFT")
    y = y + 22

    self.logEmpty = Theme:Text(content, 10, Theme.c.fg2)
    self.logEmpty:SetPoint("TOPLEFT", 0, -y)
    self.logEmpty:SetWidth(620)
    self.logEmpty:SetJustifyH("LEFT")
    self.logEmpty:SetText("No entries yet.")
    y = y + 16

    self.logLines = {}
    for i = 1, LOG_LINES do
        local fs = Theme:Text(content, 10, Theme.c.fg2)
        fs:SetWidth(620)
        fs:SetJustifyH("LEFT")
        fs:SetPoint("TOPLEFT", 0, -y)
        self.logLines[i] = fs
        y = y + 32
    end

    self._scrollContentHeight = y + 16
    content:SetHeight(math.max(POPUP_H - 90, self._scrollContentHeight))

    self.frame = f
    f:Hide()
    self:Refresh()
end

function Popup:Refresh()
    if not self.frame then return end
    local Theme = ns.Theme

    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(self.themeDropdown, function(_, level)
            for _, item in ipairs(ns.Theme:ThemeList()) do
                local itemId = item.id
                local itemLabel = item.label
                local info = UIDropDownMenu_CreateInfo()
                info.text = itemLabel .. (item.available and "" or " (unavailable)")
                info.value = itemId
                info.disabled = not item.available
                info.checked = item.selected
                info.func = function()
                    local ok, reason = ns.Theme:SetTheme(itemId)
                    if ok then
                        ns:Print("UI theme set to %s.", itemLabel)
                        Popup:Refresh()
                    elseif reason == "gw2_unavailable" then
                        ns:Print("GW2 UI theme requires GW2 UI or GW2 UI TBC to be installed and enabled.")
                    end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end

    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(self.deathDropdown, function(_, level)
            local cur = ns.Settings:Get("announceDeaths", "local")
            for _, mode in ipairs(DEATH_MODES) do
                local deathMode = mode
                local info = UIDropDownMenu_CreateInfo()
                info.text = DEATH_LABELS[deathMode] or deathMode
                info.value = deathMode
                info.checked = cur == deathMode
                info.func = function()
                    ns.Settings:Set("announceDeaths", deathMode)
                    Popup:Refresh()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end

    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(self.fontDropdown, function(_, level)
            for _, item in ipairs(ns.Theme:FontProfileList()) do
                local profileId = item.id
                local itemLabel = item.label
                local info = UIDropDownMenu_CreateInfo()
                info.text = itemLabel
                info.value = profileId
                info.checked = item.selected
                info.func = function()
                    local ok = ns.Theme:SetFontProfile(profileId)
                    if ok then
                        ns:Print("Font set to %s.", itemLabel)
                        Popup:Refresh()
                    end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end

    local selectedTheme = ns.Theme:GetSelectedThemeId()
    local activeTheme = ns.Theme:GetActiveThemeId()
    local label = ns.Theme:ThemeLabel(selectedTheme)
    if selectedTheme ~= activeTheme then
        label = label .. " (using " .. ns.Theme:ThemeLabel(activeTheme) .. ")"
    end
    dropdownSetText(self.themeDropdown, label)

    local death = ns.Settings:Get("announceDeaths", "local")
    dropdownSetText(self.deathDropdown, DEATH_LABELS[death] or tostring(death))

    local selectedFont = ns.Theme:GetSelectedFontProfileId()
    dropdownSetText(self.fontDropdown, ns.Theme:FontProfileLabel(selectedFont))

    setToggle(self.optBank, ns.Settings:Get("allowBankRewards", true) == true, Theme)
    setToggle(self.optSoftDeaths, ns.Settings:Get("announceSoftDeaths", false) == true, Theme)

    local gw2Note = ns.Theme:IsThemeAvailable("gw2") and "GW2 UI detected." or "GW2 UI is not detected yet."
    self.note:SetText(gw2Note .. " Theme changes apply immediately to open addon windows.")
    if self.fontNote then
        local profile = ns.Theme:GetFontProfile()
        self.fontNote:SetText((profile.description or "") .. " Font changes apply immediately to open addon windows.")
    end

    local prof = ns.Settings:GetProfile()
    self.currentProfile:SetText(("Active profile: |cffc0a060%s|r"):format(ns.Settings:ProfileDisplayName(prof)))
    for pid, btn in pairs(self.profileButtons or {}) do
        setProfileButtonLook(btn, prof == pid, Theme)
    end

    self:RefreshModifierRows()

    for i, def in ipairs(ns.Rules and ns.Rules:Definitions() or {}) do
        local row = self.ruleRows and self.ruleRows[i]
        if row then
            local on = ns.Rules:IsEnabled(def.id)
            row.box:SetColorTexture(on and 0.38 or 0.40, on and 0.70 or 0.40, on and 0.38 or 0.40, on and 0.85 or 0.50)
            row.name:SetText(def.name or def.id)
            row.desc:SetText(def.description or "")
            local sev = (def.severity or ""):lower()
            if sev == "strict" then
                setTextColor(row.sev, Theme.c.red, 1)
                row.sev:SetText("strict")
            else
                setTextColor(row.sev, Theme.c.gold, 1)
                row.sev:SetText(sev ~= "" and sev or "warn")
            end
            setTextColor(row.state, Theme.c.gold, 1)
            row.state:SetText(on and "ON" or "OFF")
        end
    end

    local key = ns:UnitKey()
    local taints = (key and ns.Rules and ns.Rules.TaintCount and ns.Rules:TaintCount(key)) or 0
    local warns = 0
    if key and ns.Rules and ns.Rules.GetLog then
        for _, e in ipairs(ns.Rules:GetLog(key)) do
            if e.result == "warned" or e.result == "blocked" then warns = warns + 1 end
        end
    end
    if taints > 0 then
        setTextColor(self.taintLine, Theme.c.red, 1)
        self.taintLine:SetText(("Taints: |cffff6060%d|r - Warnings/blocks in log: %d"):format(taints, warns))
    else
        setTextColor(self.taintLine, Theme.c.fg, 1)
        self.taintLine:SetText(("Taints: 0 - Warnings/blocks in log: %d"):format(warns))
    end

    local log = (key and ns.Rules and ns.Rules.GetLog and ns.Rules:GetLog(key)) or {}
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
            fs:SetText(("%s  %s  [%s]  %s"):format(fmtWhen(e.when), ruleShort, res, detail))
            fs:Show()
        end
        for i = shown + 1, LOG_LINES do
            self.logLines[i]:Hide()
        end
    end
end

function Popup:RefreshTheme()
    if not self.frame then return end
    local Theme = ns.Theme
    Theme:Fill(self.frame, Theme.c.bg0, true, "frame")
    if self.header then Theme:Fill(self.header, Theme.c.headerBg or Theme.c.bg1, false, "header") end
    if self.title then setTextColor(self.title, Theme.c.fg, 1) end
    if self.themeLabel then setTextColor(self.themeLabel, Theme.c.goldH, 1) end
    if self.fontLabel then setTextColor(self.fontLabel, Theme.c.goldH, 1) end
    if self.deathLabel then setTextColor(self.deathLabel, Theme.c.goldH, 1) end
    if self.optionsLabel then setTextColor(self.optionsLabel, Theme.c.goldH, 1) end
    if self.modifiersLabel then setTextColor(self.modifiersLabel, Theme.c.goldH, 1) end
    if self.boonsHeader then setTextColor(self.boonsHeader, Theme.c.gold, 1) end
    if self.burdensHeader then setTextColor(self.burdensHeader, Theme.c.gold, 1) end
    if self.rulesProfileLabel then setTextColor(self.rulesProfileLabel, Theme.c.goldH, 1) end
    if self.rulesHeader then setTextColor(self.rulesHeader, Theme.c.goldH, 1) end
    if self.logLabel then setTextColor(self.logLabel, Theme.c.goldH, 1) end
    for _, row in ipairs(self.boonRows or {}) do
        Theme:Fill(row, Theme.c.bg1, false)
    end
    for _, row in ipairs(self.burdenRows or {}) do
        Theme:Fill(row, Theme.c.bg1, false)
    end
    for _, row in ipairs(self.ruleRows or {}) do
        Theme:Fill(row, Theme.c.bg1, false)
    end
    self:Refresh()
end

function Popup:Show()
    self:Init()
    self:Refresh()
    self.frame:Show()
end

function Popup:Toggle()
    self:Init()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Show()
    end
end
