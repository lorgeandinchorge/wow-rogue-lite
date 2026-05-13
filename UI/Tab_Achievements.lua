-- UI/Tab_Achievements.lua
-- Account-wide achievement browser backed by Core/Achievements.lua.

local ADDON_NAME, ns = ...
local Tab = ns:NewModule("Tab_Achievements")

local EARNED_H = 70
local LOCKED_H = 50

local function fmtWhen(ts)
    if not ts then return "Unknown date" end
    if date then return date("%Y-%m-%d %H:%M", ts) end
    return tostring(ts)
end

local function shortCharacter(key)
    if not key or key == "" then return nil end
    return key:gsub("%-", " - ")
end

local function setColor(fs, color, alpha)
    fs:SetTextColor(color[1], color[2], color[3], alpha or 1)
end

local function buildEarnedRow(parent, Theme)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(EARNED_H)
    Theme:Fill(r, Theme.c.bg1, false)

    r.marker = r:CreateTexture(nil, "ARTWORK")
    r.marker:SetSize(10, 10)
    r.marker:SetPoint("TOPLEFT", 10, -12)
    r.marker:SetColorTexture(Theme.c.gold[1], Theme.c.gold[2], Theme.c.gold[3], 1)

    r.name = Theme:Text(r, 13, Theme.c.fg)
    r.name:SetPoint("TOPLEFT", r.marker, "TOPRIGHT", 8, 1)
    r.name:SetWidth(320)
    r.name:SetJustifyH("LEFT")

    r.date = Theme:Text(r, 10, Theme.c.gold)
    r.date:SetPoint("TOPRIGHT", -12, -11)
    r.date:SetWidth(180)
    r.date:SetJustifyH("RIGHT")

    r.description = Theme:Text(r, 10, Theme.c.fg2)
    r.description:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -6)
    r.description:SetWidth(470)
    r.description:SetJustifyH("LEFT")

    r.character = Theme:Text(r, 10, Theme.c.fg2)
    r.character:SetPoint("BOTTOMRIGHT", -12, 10)
    r.character:SetWidth(220)
    r.character:SetJustifyH("RIGHT")

    return r
end

local function buildLockedRow(parent, Theme)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(LOCKED_H)
    Theme:Fill(r, Theme.c.bg1, false)

    r.marker = r:CreateTexture(nil, "ARTWORK")
    r.marker:SetSize(10, 10)
    r.marker:SetPoint("TOPLEFT", 10, -12)
    r.marker:SetColorTexture(Theme.c.fg2[1], Theme.c.fg2[2], Theme.c.fg2[3], 0.55)

    r.name = Theme:Text(r, 12, Theme.c.fg2)
    r.name:SetPoint("TOPLEFT", r.marker, "TOPRIGHT", 8, 1)
    r.name:SetWidth(300)
    r.name:SetJustifyH("LEFT")

    r.requirement = Theme:Text(r, 10, Theme.c.fg2)
    r.requirement:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -6)
    r.requirement:SetWidth(650)
    r.requirement:SetJustifyH("LEFT")

    return r
end

function Tab:Init(parent)
    if self.panel then return end
    local Theme = ns.Theme

    local p = CreateFrame("Frame", nil, parent)
    self.panel = p
    ns.MainFrame:RegisterPanel("Achievements", p)

    local title = Theme:Header(p, "Achievements", 16)
    title:SetPoint("TOPLEFT", 20, -18)

    self.summary = Theme:Text(p, 11, Theme.c.fg2)
    self.summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    self.summary:SetWidth(560)
    self.summary:SetJustifyH("LEFT")

    Theme:Divider(p, "TOPLEFT", "TOPRIGHT", 0, -58, 0.2)

    local scroll, content = Theme:ScrollArea(p)
    scroll:SetPoint("TOPLEFT", 20, -76)
    scroll:SetPoint("BOTTOMRIGHT", -20, 16)
    content:SetSize(720, 1)
    self.scroll = scroll
    self.content = content

    self.earnedTitle = Theme:Text(content, 12, Theme.c.goldH)
    self.lockedTitle = Theme:Text(content, 12, Theme.c.goldH)
    self.emptyEarned = Theme:Text(content, 11, Theme.c.fg2)
    self.emptyEarned:SetText("No achievements earned yet.")
    self.emptyLocked = Theme:Text(content, 11, Theme.c.fg2)
    self.emptyLocked:SetText("No visible locked achievements.")

    self.earnedRows = {}
    self.lockedRows = {}

    p.Refresh = function() Tab:Refresh() end
    self:Refresh()
end

function Tab:_RefreshEarned(rows, startY)
    local Theme = ns.Theme
    self.earnedTitle:ClearAllPoints()
    self.earnedTitle:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -startY)
    self.earnedTitle:SetText("Earned")

    local y = startY + 24
    if #rows == 0 then
        for _, row in ipairs(self.earnedRows) do row:Hide() end
        self.emptyEarned:ClearAllPoints()
        self.emptyEarned:SetPoint("TOPLEFT", self.content, "TOPLEFT", 8, -y)
        self.emptyEarned:Show()
        return y + 36
    end
    self.emptyEarned:Hide()

    for i = #self.earnedRows + 1, #rows do
        self.earnedRows[i] = buildEarnedRow(self.content, Theme)
    end
    for i = #rows + 1, #self.earnedRows do self.earnedRows[i]:Hide() end

    for i, data in ipairs(rows) do
        local row = self.earnedRows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", self.content, "RIGHT", -16, 0)
        row:Show()

        row.name:SetText(data.name or data.id or "Achievement")
        row.description:SetText(data.description or "")
        row.date:SetText(fmtWhen(data.when))

        local character = shortCharacter(data.characterKey)
        row.character:SetText(character and ("Earned by " .. character) or "")
        setColor(row.name, Theme.c.fg, 1)
        setColor(row.description, Theme.c.fg2, 1)
        setColor(row.character, Theme.c.fg2, 0.9)

        y = y + EARNED_H + 6
    end

    return y + 12
end

function Tab:_RefreshLocked(rows, startY)
    local Theme = ns.Theme
    self.lockedTitle:ClearAllPoints()
    self.lockedTitle:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -startY)
    self.lockedTitle:SetText("Locked")

    local y = startY + 24
    if #rows == 0 then
        for _, row in ipairs(self.lockedRows) do row:Hide() end
        self.emptyLocked:ClearAllPoints()
        self.emptyLocked:SetPoint("TOPLEFT", self.content, "TOPLEFT", 8, -y)
        self.emptyLocked:Show()
        return y + 36
    end
    self.emptyLocked:Hide()

    for i = #self.lockedRows + 1, #rows do
        self.lockedRows[i] = buildLockedRow(self.content, Theme)
    end
    for i = #rows + 1, #self.lockedRows do self.lockedRows[i]:Hide() end

    for i, data in ipairs(rows) do
        local row = self.lockedRows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", self.content, "RIGHT", -16, 0)
        row:Show()

        row.name:SetText(data.name or data.id or "Achievement")
        row.requirement:SetText(data.requirement or data.description or "")
        setColor(row.name, Theme.c.fg2, 0.92)
        setColor(row.requirement, Theme.c.fg2, 0.82)

        y = y + LOCKED_H + 6
    end

    return y
end

function Tab:Refresh()
    if not self.panel then return end

    local browse = ns.Achievements and ns.Achievements.Browse and ns.Achievements:Browse()
        or { earnedCount = 0, visibleCount = 0, earned = {}, locked = {} }

    self.summary:SetText(("Earned: %d   |   Visible: %d")
        :format(browse.earnedCount or 0, browse.visibleCount or 0))

    local y = self:_RefreshEarned(browse.earned or {}, 0)
    y = self:_RefreshLocked(browse.locked or {}, y)

    self.content:SetHeight(math.max(360, y + 12))
    self.content:SetWidth(720)
    if self.scroll and self.scroll.UpdateScrollChildRect then
        self.scroll:UpdateScrollChildRect()
    end
end
