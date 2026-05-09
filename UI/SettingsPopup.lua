-- UI/SettingsPopup.lua
-- Compact addon settings popup opened from the main-frame gear button.

local ADDON_NAME, ns = ...
local Popup = ns:NewModule("SettingsPopup")

local POPUP_W, POPUP_H = 420, 312
local ROW_H = 28

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
    row.label:SetWidth(330)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetText(label or "")

    row:SetScript("OnClick", function()
        if onClick then onClick(row) end
    end)

    return row
end

local function setToggle(row, on, Theme)
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
    Theme:Fill(f, Theme.c.bg0, true)
    table.insert(UISpecialFrames, "WRL_SettingsPopup")

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(48)
    Theme:Fill(header, Theme.c.bg1, false)

    local title = Theme:Header(header, "Settings", 16)
    title:SetPoint("TOPLEFT", 16, -12)

    local close = Theme:Button(header, "Close", 58, 22)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() f:Hide() end)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 18, -64)
    content:SetPoint("BOTTOMRIGHT", -18, 16)
    self.content = content

    local themeLabel = Theme:Text(content, 11, Theme.c.goldH)
    themeLabel:SetPoint("TOPLEFT", 0, 0)
    themeLabel:SetText("UI Theme")
    self.themeLabel = themeLabel

    local dd = CreateFrame("Frame", "WRL_SettingsThemeDropdown", content, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", themeLabel, "BOTTOMLEFT", -16, -4)
    dropdownSetWidth(dd, 176)
    self.themeDropdown = dd

    local deathLabel = Theme:Text(content, 11, Theme.c.goldH)
    deathLabel:SetPoint("TOPLEFT", 0, -66)
    deathLabel:SetText("Death Announcements")
    self.deathLabel = deathLabel

    local deathDd = CreateFrame("Frame", "WRL_SettingsDeathDropdown", content, "UIDropDownMenuTemplate")
    deathDd:SetPoint("TOPLEFT", deathLabel, "BOTTOMLEFT", -16, -4)
    dropdownSetWidth(deathDd, 176)
    self.deathDropdown = deathDd

    local options = Theme:Text(content, 11, Theme.c.goldH)
    options:SetPoint("TOPLEFT", 0, -132)
    options:SetText("Account Options")
    self.optionsLabel = options

    self.optBank = buildToggle(content, Theme, "Allow bank starter rewards", function()
        ns.Settings:Set("allowBankRewards", not (ns.Settings:Get("allowBankRewards", true) == true))
        Popup:Refresh()
        if ns.MainFrame then ns.MainFrame:RefreshCurrentTab() end
    end)
    self.optBank:SetPoint("TOPLEFT", options, "BOTTOMLEFT", 0, -8)
    self.optBank:SetPoint("RIGHT", content, "RIGHT", 0, 0)

    self.optRepeat = buildToggle(content, Theme, "Allow repeat reward claims", function()
        ns.Settings:Set("allowRepeatClaims", not (ns.Settings:Get("allowRepeatClaims", false) == true))
        Popup:Refresh()
        if ns.MainFrame then ns.MainFrame:RefreshCurrentTab() end
    end)
    self.optRepeat:SetPoint("TOPLEFT", self.optBank, "BOTTOMLEFT", 0, -2)
    self.optRepeat:SetPoint("RIGHT", content, "RIGHT", 0, 0)

    self.optSoftDeaths = buildToggle(content, Theme, "Announce soft deaths locally", function()
        ns.Settings:Set("announceSoftDeaths", not (ns.Settings:Get("announceSoftDeaths", false) == true))
        Popup:Refresh()
    end)
    self.optSoftDeaths:SetPoint("TOPLEFT", self.optRepeat, "BOTTOMLEFT", 0, -2)
    self.optSoftDeaths:SetPoint("RIGHT", content, "RIGHT", 0, 0)

    self.note = Theme:Text(content, 10, Theme.c.fg2)
    self.note:SetPoint("BOTTOMLEFT", 0, 0)
    self.note:SetWidth(380)
    self.note:SetJustifyH("LEFT")

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
                        ns:Print("UI theme set to %s. Reload UI to apply it fully.", itemLabel)
                        Popup:Refresh()
                    elseif reason == "gw2_unavailable" then
                        ns:Print("GW2 UI theme requires the GW2_UI addon to be installed and enabled.")
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

    local selectedTheme = ns.Theme:GetSelectedThemeId()
    local activeTheme = ns.Theme:GetActiveThemeId()
    local label = ns.Theme:ThemeLabel(selectedTheme)
    if selectedTheme ~= activeTheme then
        label = label .. " (using " .. ns.Theme:ThemeLabel(activeTheme) .. ")"
    end
    dropdownSetText(self.themeDropdown, label)

    local death = ns.Settings:Get("announceDeaths", "local")
    dropdownSetText(self.deathDropdown, DEATH_LABELS[death] or tostring(death))

    setToggle(self.optBank, ns.Settings:Get("allowBankRewards", true) == true, Theme)
    setToggle(self.optRepeat, ns.Settings:Get("allowRepeatClaims", false) == true, Theme)
    setToggle(self.optSoftDeaths, ns.Settings:Get("announceSoftDeaths", false) == true, Theme)

    local gw2Note = ns.Theme:IsThemeAvailable("gw2") and "GW2 UI detected." or "GW2 UI is not detected yet."
    self.note:SetText(gw2Note .. " Theme changes may need /reload for already-built frames.")
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
