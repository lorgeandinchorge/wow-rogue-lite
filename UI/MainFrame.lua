-- UI/MainFrame.lua
-- Main window. Hosts the tab bar + content area + header (bank status,
-- lifetime total, current character status). Minimap button to open it.

local ADDON_NAME, ns = ...
local M = ns:NewModule("MainFrame")

local TABS = { "Run", "Achievements", "Legacy", "Rewards" }
local TAB_LABELS = {
    Run = "Current Run",
    Achievements = "Achievements",
    Legacy = "Legacy",
    Rewards = "Rewards",
}

local FRAME_W, FRAME_H = 780, 480

function M:Init()
    if self.frame then return end
    local Theme = ns.Theme

    local f = CreateFrame("Frame", "WRL_MainFrame", UIParent)
    f:SetSize(FRAME_W, FRAME_H)
    f:SetFrameStrata("HIGH")
    table.insert(UISpecialFrames, "WRL_MainFrame")
    f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        WRL_CharDB.ui = WRL_CharDB.ui or {}
        WRL_CharDB.ui.x, WRL_CharDB.ui.y = x, y
    end)

    -- Restore position.
    if WRL_CharDB and WRL_CharDB.ui and WRL_CharDB.ui.x then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", WRL_CharDB.ui.x, WRL_CharDB.ui.y)
    else
        f:SetPoint("CENTER")
    end

    Theme:Fill(f, Theme.c.bg0, true, "frame")

    -- Header ---------------------------------------------------------------
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 0, 0); header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(64)
    Theme:Fill(header, Theme.c.headerBg or Theme.c.bg1, false, "header")

    local title = Theme:Header(header, "ROGUELITE", 22)
    title:SetPoint("TOPLEFT", 18, -14)

    local subtitle = Theme:Text(header, 11, Theme.c.fg2)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetText("run. die. contribute. unlock.")

    local close = Theme:Button(header, "Close", 60, 22)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() f:Hide() end)

    local settings = CreateFrame("Button", nil, header)
    settings:SetSize(24, 22)
    settings:SetPoint("RIGHT", close, "LEFT", -6, 0)
    settings.bg = settings:CreateTexture(nil, "BACKGROUND")
    settings.bg:SetAllPoints(settings)
    Theme:ApplyButtonBackground(settings, "normal")
    settings.icon = settings:CreateTexture(nil, "ARTWORK")
    settings.icon:SetPoint("CENTER", 0, 0)
    settings.icon:SetSize(16, 16)
    settings.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    settings:SetScript("OnClick", function()
        if ns.SettingsPopup then
            ns.SettingsPopup:Toggle()
        end
    end)
    settings:SetScript("OnEnter", function(self)
        Theme:ApplyButtonBackground(self, "hover")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Settings")
        GameTooltip:AddLine("Open addon preferences.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    settings:SetScript("OnLeave", function(self)
        Theme:ApplyButtonBackground(self, "normal")
        GameTooltip:Hide()
    end)
    self.settingsButton = settings

    -- Right-side header stats (lifetime total, bank char, current char).
    self.statsTotal = Theme:Text(header, 12, Theme.c.gold)
    self.statsTotal:SetPoint("BOTTOMRIGHT", -18, 4)
    self.statsTotal:SetWidth(210)
    self.statsTotal:SetJustifyH("RIGHT")

    self.statsBank = Theme:Text(header, 11, Theme.c.fg2)
    self.statsBank:SetPoint("TOPRIGHT", close, "BOTTOMRIGHT", 0, -3)
    self.statsBank:SetWidth(280)
    self.statsBank:SetJustifyH("RIGHT")
    self.statsBank:SetWordWrap(false)

    -- Tab bar --------------------------------------------------------------
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    tabBar:SetHeight(32)
    tabBar:SetFrameLevel(f:GetFrameLevel() + 10)
    Theme:Fill(tabBar, Theme.c.navBg or Theme.c.bg1, false, "nav")
    self.tabBar = tabBar

    self.tabs = {}
    local x = 12
    for _, key in ipairs(TABS) do
        local tabKey = key
        local t = Theme:Tab(tabBar, TAB_LABELS[key])
        t:SetPoint("LEFT", tabBar, "LEFT", x, 0)
        t:SetFrameLevel(tabBar:GetFrameLevel() + 1)
        t:RegisterForClicks("LeftButtonUp")
        t:SetScript("OnClick", function() M:ShowTab(tabKey) end)
        self.tabs[tabKey] = t
        x = x + 118
    end

    -- Content area ---------------------------------------------------------
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    body:SetFrameLevel(f:GetFrameLevel() + 1)
    Theme:Fill(body, Theme.c.bg0, false, "body")
    self.body = body

    -- Each tab panel is a child frame on `body`, hidden by default. Tabs
    -- register themselves during their own Init() below.
    self.panels = {}

    self.frame = f
    self.header = header

    -- Build each panel.
    if ns.Tab_Run          then ns.Tab_Run:Init(body) end
    if ns.Tab_Achievements then ns.Tab_Achievements:Init(body) end
    if ns.Tab_Legacy       then ns.Tab_Legacy:Init(body) end
    if ns.Tab_Rewards      then ns.Tab_Rewards:Init(body) end

    -- Default tab.
    local lastTab = (WRL_CharDB.ui and WRL_CharDB.ui.lastTab) or "Run"
    if lastTab == "Contributions" or lastTab == "Tiers" then
        lastTab = "Legacy"
    elseif lastTab == "Requests" or lastTab == "NewRun" then
        lastTab = "Rewards"
    elseif lastTab == "Rules" then
        lastTab = "Run"
    end
    self:ShowTab(lastTab)
    self:RefreshHeader()

    f:Hide()

    -- Minimap button -------------------------------------------------------
    self:CreateMinimapButton()

    -- Keep header stats fresh every time window opens.
    f:SetScript("OnShow", function() M:RefreshHeader(); M:RefreshCurrentTab() end)
end

function M:RegisterPanel(key, panel)
    self.panels[key] = panel
    panel:Hide()
    panel:SetAllPoints(self.body)
end

function M:RefreshHeader()
    if not self.statsTotal or not self.statsBank then return end

    local total = ns.Database:TotalContributed()
    self.statsTotal:SetText("Lifetime  " .. ns.Tiers:FormatMoney(total))
    local bank = WRL_DB.bankCharacter
    if bank then
        local isBank = ns.Database:IsBankCharacter()
        local status, label = isBank and "self" or "unknown", nil
        if ns.BankStatus then
            status, label = ns.BankStatus:Status(bank)
        end
        local color = "|cff9a948a"
        if status == "online" or status == "self" then
            color = "|cff7ab27a"
        elseif status == "offline" then
            color = "|cffb85c5c"
        end
        local tag = isBank and "this character" or (label or "Unknown")
        self.statsBank:SetText(("Bank: %s  %s[%s]|r"):format(bank, color, tag))
    else
        self.statsBank:SetText("|cffb85c5cNo bank set|r - /wrl setbank Name-Realm")
    end
end

function M:ShowTab(key)
    if not self.panels[key] then
        -- Panel hasn't registered (module missing?). Fall back to first available.
        for _, k in ipairs(TABS) do
            if self.panels[k] then key = k; break end
        end
    end
    for k, panel in pairs(self.panels) do panel:Hide() end
    for k, tab in pairs(self.tabs) do tab:SetSelected(k == key) end
    if self.panels[key] then self.panels[key]:Show() end
    WRL_CharDB.ui = WRL_CharDB.ui or {}
    WRL_CharDB.ui.lastTab = key
    self._activeTab = key
    if self.panels[key] and self.panels[key].Refresh then self.panels[key]:Refresh() end
end

function M:RefreshCurrentTab()
    if not self.panels then return end

    local key = self._activeTab
    if key and self.panels[key] and self.panels[key].Refresh then
        self.panels[key]:Refresh()
    end
end

function M:RefreshTheme()
    if not self.frame then return end
    local Theme = ns.Theme
    Theme:Fill(self.frame, Theme.c.bg0, true, "frame")
    Theme:Fill(self.header, Theme.c.headerBg or Theme.c.bg1, false, "header")
    if self.tabBar then Theme:Fill(self.tabBar, Theme.c.navBg or Theme.c.bg1, false, "nav") end
    if self.body then Theme:Fill(self.body, Theme.c.bg0, false, "body") end
    if self.settingsButton and self.settingsButton.bg then
        Theme:ApplyButtonBackground(self.settingsButton, "normal")
    end
    if self.statsTotal then
        self.statsTotal:SetTextColor(Theme.c.gold[1], Theme.c.gold[2], Theme.c.gold[3], 1)
    end
    if self.statsBank then
        self.statsBank:SetTextColor(Theme.c.fg2[1], Theme.c.fg2[2], Theme.c.fg2[3], 1)
    end
    for key, tab in pairs(self.tabs or {}) do
        if tab.SetSelected then tab:SetSelected(key == self._activeTab) end
    end
    if ns.SettingsPopup and ns.SettingsPopup.Refresh then
        ns.SettingsPopup:Refresh()
    end
    self:RefreshHeader()
    self:RefreshCurrentTab()
end

function M:Toggle()
    if not self.frame then self:Init() end
    if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

-- Small visual nudge when a new request comes in. Flashes the tab's label.
function M:Notify(tabKey)
    local t = self.tabs and self.tabs[tabKey]
    if not t then return end
    local color = ns.Theme.c.goldH
    t.label:SetTextColor(color[1], color[2], color[3], 1)
    -- Revert after 3s (or next selection).
    C_Timer.After(3, function()
        if t._selected then
            t.label:SetTextColor(ns.Theme.c.fg[1], ns.Theme.c.fg[2], ns.Theme.c.fg[3], 1)
        else
            t.label:SetTextColor(ns.Theme.c.fg2[1], ns.Theme.c.fg2[2], ns.Theme.c.fg2[3], 1)
        end
    end)
end

-- Minimap button -----------------------------------------------------------
function M:CreateMinimapButton()
    local btn = CreateFrame("Button", "WRL_MinimapButton", Minimap)
    btn:SetSize(24, 24)
    btn:SetFrameStrata("MEDIUM")
    btn:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -4, -4)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", btn, "TOPLEFT", -6, 6)
    bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 6, -6)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    icon:SetTexture("Interface\\AddOns\\WoWRoguelite\\WRL_MinimapIcon.png")
    btn.icon = icon

    btn:SetScript("OnClick", function() M:Toggle() end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("WoW Roguelite")
        GameTooltip:AddLine("Click to open.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
