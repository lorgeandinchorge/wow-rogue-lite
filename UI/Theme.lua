-- UI/Theme.lua
-- Guild Wars 2 inspired minimalist dark theme.
--
-- Palette (sRGB):
--   bg0   #0e0e10  (deepest, main frame fill)
--   bg1   #1c1c1f  (card / panel)
--   bg2   #2a2a2e  (elevated: buttons, tab bar)
--   bg3   #3a3a3f  (hover)
--   fg    #e6e0d4  (primary text)
--   fg2   #9a948a  (secondary text)
--   gold  #c0a060  (accent / borders / active tab)
--   goldH #e0c080  (hover gold)
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

Theme.c = {
    bg0   = {0.055, 0.055, 0.063, 0.97},
    bg1   = {0.110, 0.110, 0.122, 1.00},
    bg2   = {0.165, 0.165, 0.180, 1.00},
    bg3   = {0.228, 0.228, 0.247, 1.00},
    fg    = {0.902, 0.878, 0.831, 1.00},
    fg2   = {0.604, 0.580, 0.541, 1.00},
    gold  = {0.753, 0.627, 0.376, 1.00},
    goldH = {0.878, 0.753, 0.502, 1.00},
    red   = {0.722, 0.361, 0.361, 1.00},
    green = {0.478, 0.698, 0.478, 1.00},
}

local FONT_BODY    = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_HEADER  = "Fonts\\MORPHEUS.TTF"
-- Some locales don't ship MORPHEUS; fall back silently.
if not CreateFont then -- defensive; only true in non-WoW env
elseif not (MORPHEUS_FONT or true) then FONT_HEADER = FONT_BODY end

function Theme:Init()
    -- Nothing dynamic. All constructors below are pure helpers.
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
