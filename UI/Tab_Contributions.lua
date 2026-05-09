-- UI/Tab_Contributions.lua
-- Shows each character with class icon, status, level, and lifetime contribution.
-- Supports per-character favorites that sort to the top.
-- Archived characters (same name, different generation) are shown with a
-- "(prev.)" indicator so players can track deleted-and-recreated slots.

local ADDON_NAME, ns = ...
local Tab = ns:NewModule("Tab_Contributions")

local ROW_H = 54   -- tall enough for class icon + two text lines

-- ── Class icon sprite sheet ────────────────────────────────────────────────
-- TBC Classic uses a single 256×256 sprite sheet.  Each class occupies a
-- 64×64 (= 0.25 × 0.25) tile.  Layout, row by row:
--   Row 0: Warrior · Mage · Rogue · Druid
--   Row 1: Hunter  · Shaman · Priest · Warlock
--   Row 2: Paladin (only one in row 2 for TBC)
local CLASS_ICON_TEX = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CLASS_ICON_TCOORDS = {
    WARRIOR  = {0,    0.25, 0,    0.25},
    MAGE     = {0.25, 0.5,  0,    0.25},
    ROGUE    = {0.5,  0.75, 0,    0.25},
    DRUID    = {0.75, 1,    0,    0.25},
    HUNTER   = {0,    0.25, 0.25, 0.5 },
    SHAMAN   = {0.25, 0.5,  0.25, 0.5 },
    PRIEST   = {0.5,  0.75, 0.25, 0.5 },
    WARLOCK  = {0.75, 1,    0.25, 0.5 },
    PALADIN  = {0,    0.25, 0.5,  0.75},
}

local function applyClassIcon(tex, class)
    local coords = class and CLASS_ICON_TCOORDS[class]
    if coords then
        tex:SetTexture(CLASS_ICON_TEX)
        tex:SetTexCoord(unpack(coords))
    else
        -- Unknown class: generic question mark
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function classColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return {c.r, c.g, c.b, 1} end
    return ns.Theme.c.fg
end

-- ── Row builder ───────────────────────────────────────────────────────────
local function buildRow(content, Theme)
    local r = CreateFrame("Frame", nil, content)
    r:SetHeight(ROW_H)

    -- ── Class icon (32×32, left side, vertically centred) ──
    r.classIcon = r:CreateTexture(nil, "ARTWORK")
    r.classIcon:SetSize(32, 32)
    r.classIcon:SetPoint("LEFT", 8, 0)

    r.statusOuter = r:CreateTexture(nil, "BORDER")
    r.statusOuter:SetSize(14, 14)
    r.statusOuter:SetPoint("BOTTOMRIGHT", r.classIcon, "BOTTOMRIGHT", 4, -4)
    r.statusOuter:SetTexture("Interface\\Buttons\\WHITE8X8")
    r.statusOuter:SetVertexColor(0, 0, 0, 0.85)

    r.statusDot = r:CreateTexture(nil, "ARTWORK")
    r.statusDot:SetSize(10, 10)
    r.statusDot:SetPoint("CENTER", r.statusOuter, "CENTER")
    r.statusDot:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- ── Name + level (top text line) ──
    -- Written as a single formatted string so name and level stay on one line
    -- without needing dynamic anchor math.
    r.nameText = Theme:Text(r, 13, Theme.c.fg)
    r.nameText:SetPoint("TOPLEFT", 46, -8)
    r.nameText:SetWidth(228)
    r.nameText:SetJustifyH("LEFT")
    r.nameText:SetWordWrap(false)

    -- ── Race · Class · status (bottom text line) ──
    r.metaText = Theme:Text(r, 10, Theme.c.fg2)
    r.metaText:SetPoint("BOTTOMLEFT", 46, 8)
    r.metaText:SetWidth(228)
    r.metaText:SetJustifyH("LEFT")
    r.metaText:SetWordWrap(false)

    -- ── Favorite toggle ──
    r.favBtn = CreateFrame("Button", nil, r)
    r.favBtn:SetSize(22, 22)
    r.favBtn:SetPoint("LEFT", 280, 0)   -- just right of the name/meta block

    r.favIcon = r.favBtn:CreateTexture(nil, "ARTWORK")
    r.favIcon:SetSize(16, 16)
    r.favIcon:SetPoint("CENTER")
    r.favIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    r.favIcon:SetVertexColor(0.55, 0.55, 0.55, 0.45)

    -- ── Progress bar (contribution relative to leaderboard max) ──
    r.bar = Theme:ProgressBar(r, 230, 6)
    r.bar:SetPoint("RIGHT", -152, 2)

    -- ── Gold amount (right-aligned) ──
    r.amount = Theme:Text(r, 12, Theme.c.gold)
    r.amount:SetPoint("TOPRIGHT", -12, -8)
    r.amount:SetWidth(132)
    r.amount:SetJustifyH("RIGHT")
    r.amount:SetWordWrap(false)

    -- Generation badge (shown only for archived / previous chars)
    r.genBadge = Theme:Text(r, 9, Theme.c.fg2)
    r.genBadge:SetPoint("BOTTOMRIGHT", -12, 8)
    r.genBadge:SetJustifyH("RIGHT")
    r.genBadge:SetWidth(132)

    return r
end

-- ── Init ─────────────────────────────────────────────────────────────────
function Tab:Init(parent)
    if self.panel then return end
    local Theme = ns.Theme

    local p = CreateFrame("Frame", nil, parent)
    self.panel = p
    ns.MainFrame:RegisterPanel("Contributions", p)

    local title = Theme:Header(p, "Contributions", 16)
    title:SetPoint("TOPLEFT", 20, -18)

    local hint = Theme:Text(p, 11, Theme.c.fg2)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetText("Lifetime totals per character. Click the star to favorite.")

    -- Column header bar
    local cols = CreateFrame("Frame", nil, p)
    cols:SetPoint("TOPLEFT",  20, -72)
    cols:SetPoint("TOPRIGHT", -20, -72)
    cols:SetHeight(16)

    local colChar = Theme:Text(cols, 10, Theme.c.goldH)
    colChar:SetPoint("LEFT", 46, 0)
    colChar:SetText("Character")

    local colProgress = Theme:Text(cols, 10, Theme.c.goldH)
    colProgress:SetPoint("RIGHT", -300, 0)
    colProgress:SetText("Progress")

    local colGold = Theme:Text(cols, 10, Theme.c.goldH)
    colGold:SetPoint("RIGHT", -12, 0)
    colGold:SetText("Contributed")
    colGold:SetJustifyH("RIGHT")

    Theme:Divider(p, "TOPLEFT", "TOPRIGHT", 0, -92, 0.2)

    -- Scrollable list
    local scroll, content = Theme:ScrollArea(p)
    scroll:SetPoint("TOPLEFT",     20, -102)
    scroll:SetPoint("BOTTOMRIGHT", -20,  16)
    content:SetSize(720, 1)
    self.scroll  = scroll
    self.content = content
    self.rows    = {}

    -- Empty-state message (shown when roster is empty)
    self.empty = Theme:Text(content, 12, Theme.c.fg2)
    self.empty:SetPoint("TOPLEFT", 8, -16)
    self.empty:SetText("No characters recorded yet.")
    self.empty:Hide()

    -- Wire the panel so MainFrame:ShowTab / RefreshCurrentTab can reach us.
    -- (Those methods call self.panels[key]:Refresh() on the raw Frame, so we
    -- attach the function here rather than relying on Tab module dispatch.)
    p.Refresh = function() Tab:Refresh() end

    -- Prime state immediately (panel is hidden but frame state is set correctly).
    Tab:Refresh()
end

-- ── Refresh ───────────────────────────────────────────────────────────────
function Tab:Refresh()
    if not self.panel then return end
    local Theme = ns.Theme

    local roster = ns.Database:RosterSortedByContribution()

    -- Re-sort: favourites → alive/pending before retired/archived → contribution descending
    -- liveScore: 1 = run still ongoing (fresh/active/dead_pending), 0 = done or archived.
    local function liveScore(r)
        if r.isArchived then return 0 end
        local s = ns.Run:GetState(r)
        return (s == "retired") and 0 or 1
    end

    table.sort(roster, function(a, b)
        local aFav = ns.Database:IsFavorite(a.uid or a.key) and 1 or 0
        local bFav = ns.Database:IsFavorite(b.uid or b.key) and 1 or 0
        if aFav ~= bFav then return aFav > bFav end

        local aAlive = liveScore(a)
        local bAlive = liveScore(b)
        if aAlive ~= bAlive then return aAlive > bAlive end

        return (a.contributed or 0) > (b.contributed or 0)
    end)

    -- Progress-bar max (relative to highest contributor)
    local max = 0
    for _, r in ipairs(roster) do
        if (r.contributed or 0) > max then max = r.contributed end
    end
    if max == 0 then max = 1 end

    if #roster == 0 then
        for _, row in ipairs(self.rows) do row:Hide() end
        self.empty:Show()
        self.content:SetHeight(60)
        return
    end
    self.empty:Hide()

    -- Grow / shrink row pool
    for i = #self.rows + 1, #roster do
        self.rows[i] = buildRow(self.content, Theme)
    end
    for i = #roster + 1, #self.rows do
        self.rows[i]:Hide()
    end

    local y = 0
    for i, rec in ipairs(roster) do
        local row = self.rows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT",   self.content, "RIGHT",  -16, 0)
        row:Show()

        -- ── Class icon ────────────────────────────────────────────────────
        applyClassIcon(row.classIcon, rec.class)

        -- ── Status dot colour ─────────────────────────────────────────────
        --   green  = fresh / active (current generation)
        --   yellow = dead, pending contribution mail
        --   orange = archived (replaced by newer char of same name)
        --   red    = retired (run permanently over)
        local runState = ns.Run:GetState(rec)
        if rec.isArchived then
            row.statusDot:SetVertexColor(1, 0.62, 0.15, 1)
        elseif runState == "dead_pending_contribution" then
            row.statusDot:SetVertexColor(1, 0.86, 0.20, 1)
        elseif runState == "retired" then
            row.statusDot:SetVertexColor(1, 0.25, 0.25, 1)
        else
            row.statusDot:SetVertexColor(0.45, 1, 0.45, 1)
        end

        -- ── Name + level ──────────────────────────────────────────────────
        local baseName = rec.key:match("^([^%-]+)") or rec.key
        local level    = rec.levelCurrent or rec.levelAtCreate or 0
        local nc       = classColor(rec.class)
        row.nameText:SetTextColor(nc[1], nc[2], nc[3], 1)
        row.nameText:SetText(("%s  |cffb09040Lv %d|r"):format(baseName, level))

        -- ── Meta line ─────────────────────────────────────────────────────
        local raceName  = rec.race  and (rec.race:sub(1,1)  .. rec.race:sub(2):lower())  or "?"
        local className = rec.class and (rec.class:sub(1,1) .. rec.class:sub(2):lower()) or "?"
        local statusStr
        -- runState was resolved above for the dot colour; reuse it here.
        if rec.isArchived and runState == "retired" then
            statusStr = "|cffb85c5cretired|r |cffb07828· prev. char|r"
        elseif rec.isArchived then
            statusStr = "|cffb07828prev. char|r"
        elseif runState == "dead_pending_contribution" then
            statusStr = "|cffffff00pending contribution|r"
        elseif runState == "retired" then
            statusStr = "|cffb85c5cretired|r"
        else
            statusStr = "|cff7ab27aalive|r"
        end
        row.metaText:SetText(("%s %s  \194\183  %s"):format(raceName, className, statusStr))

        -- ── Generation badge ──────────────────────────────────────────────
        -- Only show "Gen N" when multiple records exist for the same name.
        if (rec.generation or 1) > 1 or rec.isArchived then
            row.genBadge:SetText(("Gen %d"):format(rec.generation or 1))
        else
            row.genBadge:SetText("")
        end

        -- ── Favourite star ────────────────────────────────────────────────
        local uid   = rec.uid or rec.key
        local isFav = ns.Database:IsFavorite(uid)

        row.favIcon:SetVertexColor(
            isFav and Theme.c.gold[1] or 0.55,
            isFav and Theme.c.gold[2] or 0.55,
            isFav and Theme.c.gold[3] or 0.55,
            isFav and 1 or 0.35)

        -- Capture uid in the closure so each button refers to its own rec.
        local capturedUid = uid
        row.favBtn:SetScript("OnClick", function()
            ns.Database:ToggleFavorite(capturedUid)
            Tab:Refresh()
        end)

        -- ── Bar + amount ──────────────────────────────────────────────────
        row.bar:SetProgress((rec.contributed or 0) / max)
        row.amount:SetText(ns.Tiers:FormatMoney(rec.contributed or 0))

        y = y + ROW_H + 4
    end

    self.content:SetHeight(math.max(1, y))
end
