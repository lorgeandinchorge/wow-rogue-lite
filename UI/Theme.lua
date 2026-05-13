-- UI/Theme.lua
-- Theme registry and widget constructors.
--
-- Palette (sRGB):
--   bg0   deepest main frame fill
--   bg1   card / panel
--   bg2   elevated: buttons, tab bar
--   bg3   hover
--   fg    primary text
--   fg2   secondary text
--   gold  accent / borders / active tab
--   goldH hover gold
--   red   #b85c5c  (error / retired)
--   green #7ab27a  (success / alive)
--
-- Rendering notes:
--   - We don't use textured backdrops. Flat color via SetColorTexture gives the
--     clean GW2 look. A 1px gold line is emulated with a 1-tall texture at top
--     or bottom of the frame (cheap and crisp at all UI scales).
--   - Fonts: default FRIZQT__ keeps things readable; for headers we use
--     MORPHEUS_.TTF (shipped by Blizzard) to approximate GW2's display face.

local ADDON_NAME, ns = ...
local Theme = ns:NewModule("Theme")

local PALETTES = {
    classic = {
        id = "classic",
        label = "Classic WoW",
        c = {
            bg0       = {0.135, 0.082, 0.045, 0.98},
            bg1       = {0.205, 0.140, 0.075, 1.00},
            bg2       = {0.300, 0.215, 0.120, 1.00},
            bg3       = {0.420, 0.310, 0.170, 1.00},
            headerBg  = {0.240, 0.145, 0.070, 1.00},
            navBg     = {0.105, 0.060, 0.035, 1.00},
            rowBg     = {0.185, 0.120, 0.065, 1.00},
            rowAccent = {0.960, 0.780, 0.360, 0.65},
            fg        = {0.980, 0.895, 0.680, 1.00},
            fg2       = {0.760, 0.640, 0.460, 1.00},
            gold      = {1.000, 0.820, 0.360, 1.00},
            goldH     = {1.000, 0.930, 0.520, 1.00},
            red       = {0.790, 0.260, 0.180, 1.00},
            green     = {0.365, 0.690, 0.420, 1.00},
        },
    },
    dark = {
        id = "dark",
        label = "Dark",
        c = {
            bg0       = {0.045, 0.047, 0.055, 0.98},
            bg1       = {0.095, 0.098, 0.112, 1.00},
            bg2       = {0.145, 0.150, 0.170, 1.00},
            bg3       = {0.220, 0.225, 0.250, 1.00},
            headerBg  = {0.105, 0.105, 0.120, 1.00},
            navBg     = {0.072, 0.075, 0.086, 1.00},
            rowBg     = {0.105, 0.108, 0.122, 1.00},
            rowAccent = {0.780, 0.650, 0.360, 0.55},
            fg        = {0.925, 0.895, 0.820, 1.00},
            fg2       = {0.650, 0.620, 0.560, 1.00},
            gold      = {0.780, 0.650, 0.360, 1.00},
            goldH     = {0.930, 0.800, 0.480, 1.00},
            red       = {0.760, 0.305, 0.300, 1.00},
            green     = {0.410, 0.690, 0.460, 1.00},
        },
    },
    gw2 = {
        id = "gw2",
        label = "GW2 UI",
        requiresAddon = { kind = "gw2ui" },
        c = {
            bg0       = {0.035, 0.034, 0.036, 0.98},
            bg1       = {0.090, 0.082, 0.078, 1.00},
            bg2       = {0.155, 0.135, 0.115, 1.00},
            bg3       = {0.255, 0.205, 0.155, 1.00},
            headerBg  = {0.270, 0.120, 0.105, 1.00},
            navBg     = {0.055, 0.052, 0.055, 1.00},
            rowBg     = {0.120, 0.090, 0.080, 1.00},
            rowAccent = {0.850, 0.620, 0.230, 0.70},
            fg        = {0.965, 0.900, 0.790, 1.00},
            fg2       = {0.675, 0.610, 0.540, 1.00},
            gold      = {0.850, 0.620, 0.230, 1.00},
            goldH     = {1.000, 0.780, 0.350, 1.00},
            red       = {0.780, 0.250, 0.200, 1.00},
            green     = {0.460, 0.700, 0.460, 1.00},
        },
    },
    grant = {
        id = "grant",
        label = "Grant",
        c = {
            bg0       = {0.070, 0.060, 0.100, 0.98},
            bg1       = {0.125, 0.105, 0.170, 1.00},
            bg2       = {0.175, 0.135, 0.245, 1.00},
            bg3       = {0.245, 0.190, 0.335, 1.00},
            headerBg  = {0.255, 0.185, 0.430, 1.00},
            navBg     = {0.055, 0.048, 0.080, 1.00},
            rowBg     = {0.125, 0.105, 0.170, 1.00},
            rowAccent = {0.486, 0.310, 0.839, 0.70},
            fg        = {0.935, 0.910, 0.970, 1.00},
            fg2       = {0.680, 0.640, 0.735, 1.00},
            gold      = {0.486, 0.310, 0.839, 1.00},
            goldH     = {0.640, 0.465, 0.960, 1.00},
            red       = {0.780, 0.300, 0.355, 1.00},
            green     = {0.263, 0.659, 0.427, 1.00},
        },
    },
    isabella = {
        id = "isabella",
        label = "Isabella",
        c = {
            bg0       = {0.085, 0.060, 0.095, 0.98},
            bg1       = {0.155, 0.105, 0.155, 1.00},
            bg2       = {0.230, 0.140, 0.205, 1.00},
            bg3       = {0.325, 0.195, 0.285, 1.00},
            headerBg  = {0.445, 0.225, 0.360, 1.00},
            navBg     = {0.070, 0.050, 0.080, 1.00},
            rowBg     = {0.155, 0.105, 0.155, 1.00},
            rowAccent = {0.851, 0.365, 0.624, 0.70},
            fg        = {0.970, 0.910, 0.945, 1.00},
            fg2       = {0.735, 0.640, 0.695, 1.00},
            gold      = {0.851, 0.365, 0.624, 1.00},
            goldH     = {1.000, 0.485, 0.755, 1.00},
            red       = {0.805, 0.285, 0.360, 1.00},
            green     = {0.208, 0.714, 0.678, 1.00},
        },
    },
}

local THEME_ORDER = { "classic", "dark", "gw2", "grant", "isabella" }
local GW2_UI_ADDON_IDS = {
    "GW2_UI",
    "GW2_UI_Mainline",
    "GW2_UI_TBC",
    "GW2_UI_Vanilla",
    "GW2_UI_Classic",
    "GW2_UI_Mists",
    "GW2_UI_Wrath",
}

Theme.palettes = PALETTES
Theme.themeOrder = THEME_ORDER
Theme.c = PALETTES.classic.c

local FONT_BODY    = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_HEADER  = "Fonts\\MORPHEUS.TTF"
-- Some locales don't ship MORPHEUS; fall back silently.
if not CreateFont then -- defensive; only true in non-WoW env
elseif not (MORPHEUS_FONT or true) then FONT_HEADER = FONT_BODY end

local function getAddonInfo(addonNameOrIndex)
    local api = C_AddOns
    local fn = api and api.GetAddOnInfo or GetAddOnInfo
    if not fn then return nil end

    local ok, name, title, notes, loadable, reason, security, newVersion = pcall(fn, addonNameOrIndex)
    if not ok or reason == "MISSING" then return nil end
    return name, title, notes, loadable, reason, security, newVersion
end

local function getAddonEnableState(addonName)
    if C_AddOns and C_AddOns.GetAddOnEnableState then
        local ok, state = pcall(C_AddOns.GetAddOnEnableState, addonName, "player")
        if ok then return state end
        ok, state = pcall(C_AddOns.GetAddOnEnableState, addonName)
        if ok then return state end
    end

    if GetAddOnEnableState then
        local ok, state = pcall(GetAddOnEnableState, "player", addonName)
        if ok then return state end
        ok, state = pcall(GetAddOnEnableState, addonName)
        if ok then return state end
    end

    return nil
end

local function getNumAddOns()
    if C_AddOns and C_AddOns.GetNumAddOns then
        local ok, count = pcall(C_AddOns.GetNumAddOns)
        if ok then return count end
    end
    if GetNumAddOns then
        local ok, count = pcall(GetNumAddOns)
        if ok then return count end
    end
    return 0
end

local function addonEnabledById(addonName)
    local name, _, _, loadable, reason = getAddonInfo(addonName)
    if not name then return false end

    local state = getAddonEnableState(name)
    if state ~= nil then return state > 0 end

    return loadable ~= false and reason ~= "DISABLED"
end

local function normalizeAddonTitle(value)
    value = tostring(value or ""):lower()
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("[^%w]+", " ")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function addonTitleLooksLikeGW2UI(title)
    local normalized = normalizeAddonTitle(title)
    return normalized == "gw2 ui" or normalized:match("^gw2 ui ")
end

local function findEnabledGW2UIAddon()
    for _, addonName in ipairs(GW2_UI_ADDON_IDS) do
        if addonEnabledById(addonName) then return addonName end
    end

    for i = 1, getNumAddOns() do
        local name, title = getAddonInfo(i)
        if name and addonTitleLooksLikeGW2UI(title or name) and addonEnabledById(name) then
            return name
        end
    end
    return nil
end

local function isAddonEnabled(addonName)
    if not addonName then return true end
    if type(addonName) == "table" and addonName.kind == "gw2ui" then
        return findEnabledGW2UIAddon() ~= nil
    end
    return addonEnabledById(addonName)
end

function Theme:Init()
    self:ApplyConfiguredTheme()
    if ns.On then
        ns:On("ADDON_LOADED", function(addonName)
            if addonName == "GW2_UI" or addonTitleLooksLikeGW2UI(addonName) then
                self:RefreshAvailability()
            end
        end)
        ns:On("PLAYER_ENTERING_WORLD", function()
            self:RefreshAvailability()
        end)
    end
end

function Theme:HasGW2UI()
    return findEnabledGW2UIAddon() ~= nil
end

function Theme:IsThemeAvailable(themeId)
    local def = PALETTES[themeId]
    if not def then return false end
    return isAddonEnabled(def.requiresAddon)
end

function Theme:NormalizeThemeId(themeId)
    if PALETTES[themeId] then return themeId end
    return "classic"
end

function Theme:GetSelectedThemeId()
    local selected = ns.Settings and ns.Settings:Get("uiTheme", "classic") or "classic"
    return self:NormalizeThemeId(selected)
end

function Theme:GetActiveThemeId()
    local selected = self:GetSelectedThemeId()
    if selected == "gw2" and not self:IsThemeAvailable("gw2") then
        return "dark"
    end
    return selected
end

function Theme:ApplyConfiguredTheme()
    local active = self:GetActiveThemeId()
    self.activeThemeId = active
    self.c = PALETTES[active].c
    return active
end

function Theme:RefreshAvailability()
    local prior = self.activeThemeId
    local active = self:ApplyConfiguredTheme()
    if prior ~= active then
        self:NotifyThemeChanged()
    end
    return active
end

function Theme:NotifyThemeChanged()
    if ns.MainFrame and ns.MainFrame.RefreshTheme then
        ns.MainFrame:RefreshTheme()
    end
    if ns.SettingsPopup and ns.SettingsPopup.RefreshTheme then
        ns.SettingsPopup:RefreshTheme()
    elseif ns.SettingsPopup and ns.SettingsPopup.Refresh then
        ns.SettingsPopup:Refresh()
    end
end

function Theme:SetTheme(themeId)
    if not PALETTES[themeId] then
        return false, "unknown"
    end
    if not self:IsThemeAvailable(themeId) then
        return false, themeId == "gw2" and "gw2_unavailable" or "unavailable"
    end
    if ns.Settings and ns.Settings.Set then
        ns.Settings:Set("uiTheme", themeId)
    end
    local prior = self.activeThemeId
    self:ApplyConfiguredTheme()
    if prior ~= self.activeThemeId then
        self:NotifyThemeChanged()
    end
    return true
end

function Theme:ThemeList()
    local out = {}
    for i, id in ipairs(THEME_ORDER) do
        local def = PALETTES[id]
        out[i] = {
            id = id,
            label = def.label,
            available = self:IsThemeAvailable(id),
            active = self:GetActiveThemeId() == id,
            selected = self:GetSelectedThemeId() == id,
        }
    end
    return out
end

function Theme:ThemeLabel(themeId)
    local def = PALETTES[themeId]
    return def and def.label or tostring(themeId)
end

function Theme:ThemeUsageText()
    return table.concat(THEME_ORDER, " | ")
end

function Theme:ThemeSentenceText()
    local count = #THEME_ORDER
    if count == 0 then return "" end
    if count == 1 then return THEME_ORDER[1] end
    if count == 2 then return THEME_ORDER[1] .. " or " .. THEME_ORDER[2] end

    local out = {}
    for i = 1, count - 1 do
        out[#out + 1] = THEME_ORDER[i]
    end
    return table.concat(out, ", ") .. ", or " .. THEME_ORDER[count]
end

function Theme:NextAvailableTheme(themeId)
    themeId = self:NormalizeThemeId(themeId)
    local start = 1
    for i, id in ipairs(THEME_ORDER) do
        if id == themeId then start = i; break end
    end
    for offset = 1, #THEME_ORDER do
        local id = THEME_ORDER[((start + offset - 1) % #THEME_ORDER) + 1]
        if self:IsThemeAvailable(id) then return id end
    end
    return "classic"
end

-- Fill a frame with a flat color. If border == true, adds a 1px gold top/bottom line.
function Theme:Fill(frame, color, border)
    color = color or self.c.bg1
    local tex = frame._fill or frame:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(frame)
    tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    frame._fill = tex

    if border then
        local top = frame._borderTop or frame:CreateTexture(nil, "BORDER")
        top:SetColorTexture(self.c.gold[1], self.c.gold[2], self.c.gold[3], 0.6)
        top:SetPoint("TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", 0, 0); top:SetHeight(1)
        frame._borderTop = top

        local bot = frame._borderBot or frame:CreateTexture(nil, "BORDER")
        bot:SetColorTexture(self.c.gold[1], self.c.gold[2], self.c.gold[3], 0.6)
        bot:SetPoint("BOTTOMLEFT", 0, 0); bot:SetPoint("BOTTOMRIGHT", 0, 0); bot:SetHeight(1)
        frame._borderBot = bot
    end
end

-- Thin horizontal divider at a given relative anchor.
function Theme:Divider(parent, anchorPoint, relPoint, xOff, yOff, alpha)
    local d = parent:CreateTexture(nil, "ARTWORK")
    d:SetColorTexture(self.c.fg2[1], self.c.fg2[2], self.c.fg2[3], alpha or 0.25)
    d:SetHeight(1)
    d:SetPoint("LEFT",  parent, anchorPoint or "TOPLEFT",  xOff or 12,  yOff or -30)
    d:SetPoint("RIGHT", parent, relPoint   or "TOPRIGHT", -12, yOff or -30)
    return d
end

function Theme:Text(parent, size, color, font)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font or FONT_BODY, size or 12, "")
    local col = color or self.c.fg
    fs:SetTextColor(col[1], col[2], col[3], col[4] or 1)
    return fs
end

function Theme:Header(parent, text, size)
    local fs = self:Text(parent, size or 18, self.c.fg, FONT_HEADER)
    fs:SetText(text or "")
    return fs
end

-- Minimalist button: flat bg2 rect, bg3 on hover, 1px gold underline on hover.
function Theme:Button(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, height or 24)

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(b)
    b.bg:SetColorTexture(self.c.bg2[1], self.c.bg2[2], self.c.bg2[3], 1)

    b.underline = b:CreateTexture(nil, "BORDER")
    b.underline:SetColorTexture(self.c.gold[1], self.c.gold[2], self.c.gold[3], 0.9)
    b.underline:SetHeight(1)
    b.underline:SetPoint("BOTTOMLEFT", 0, 0)
    b.underline:SetPoint("BOTTOMRIGHT", 0, 0)
    b.underline:Hide()

    b.label = self:Text(b, 12, self.c.fg)
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.label:SetText(label or "")

    b:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(Theme.c.bg3[1], Theme.c.bg3[2], Theme.c.bg3[3], 1)
        self.underline:Show()
        self.label:SetTextColor(Theme.c.goldH[1], Theme.c.goldH[2], Theme.c.goldH[3], 1)
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(Theme.c.bg2[1], Theme.c.bg2[2], Theme.c.bg2[3], 1)
        self.underline:Hide()
        self.label:SetTextColor(Theme.c.fg[1], Theme.c.fg[2], Theme.c.fg[3], 1)
    end)
    return b
end

-- Progress bar: gold fill on bg2 background, optional text overlay.
function Theme:ProgressBar(parent, width, height)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(width or 200, height or 8)

    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints(p)
    p.bg:SetColorTexture(self.c.bg2[1], self.c.bg2[2], self.c.bg2[3], 1)

    p.fill = p:CreateTexture(nil, "ARTWORK")
    p.fill:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    p.fill:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
    p.fill:SetWidth(1)
    p.fill:SetColorTexture(self.c.gold[1], self.c.gold[2], self.c.gold[3], 1)

    function p:SetProgress(pct)
        pct = math.max(0, math.min(1, pct or 0))
        local w = math.max(1, math.floor(self:GetWidth() * pct))
        self.fill:SetWidth(w)
    end

    return p
end

-- Status dot (alive/retired indicator).
function Theme:StatusDot(parent, state)
    local d = parent:CreateTexture(nil, "OVERLAY")
    d:SetSize(8, 8)
    local color = (state == "retired") and self.c.red or self.c.green
    d:SetColorTexture(color[1], color[2], color[3], 1)
    return d
end

-- Tab pill with underline selection indicator. Call :SetSelected(bool).
function Theme:Tab(parent, label)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(110, 28)

    t.label = self:Text(t, 13, self.c.fg2)
    t.label:SetPoint("CENTER")
    t.label:SetText(label or "")

    t.underline = t:CreateTexture(nil, "BORDER")
    t.underline:SetColorTexture(self.c.gold[1], self.c.gold[2], self.c.gold[3], 1)
    t.underline:SetHeight(2)
    t.underline:SetPoint("BOTTOMLEFT", 8, 0)
    t.underline:SetPoint("BOTTOMRIGHT", -8, 0)
    t.underline:Hide()

    function t:SetSelected(sel)
        self._selected = sel
        if sel then
            self.label:SetTextColor(Theme.c.fg[1], Theme.c.fg[2], Theme.c.fg[3], 1)
            self.underline:Show()
        else
            self.label:SetTextColor(Theme.c.fg2[1], Theme.c.fg2[2], Theme.c.fg2[3], 1)
            self.underline:Hide()
        end
    end

    t:SetScript("OnEnter", function(self)
        if not self._selected then
            self.label:SetTextColor(Theme.c.fg[1], Theme.c.fg[2], Theme.c.fg[3], 1)
        end
    end)
    t:SetScript("OnLeave", function(self)
        if not self._selected then
            self.label:SetTextColor(Theme.c.fg2[1], Theme.c.fg2[2], Theme.c.fg2[3], 1)
        end
    end)

    return t
end

-- Scrollable child area. Returns (scrollFrame, contentFrame).
-- Content is fixed-width to parent, height is grown by the caller.
local scrollId = 0
function Theme:ScrollArea(parent)
    scrollId = scrollId + 1
    local name = "WRL_ScrollArea" .. tostring(scrollId)
    local sf = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        if range <= 0 then return end
        local step = (delta > 0) and -30 or 30
        local nextValue = math.max(0, math.min(range, self:GetVerticalScroll() + step))
        self:SetVerticalScroll(nextValue)
        local bar = _G[name .. "ScrollBar"]
        if bar then bar:SetValue(nextValue) end
    end)

    local bar = _G[name .. "ScrollBar"]
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, -16)
        bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 16)
    end

    return sf, content
end
