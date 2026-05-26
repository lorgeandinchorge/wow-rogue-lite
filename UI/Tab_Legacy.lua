-- UI/Tab_Legacy.lua
-- Account-wide legacy economy: contribution history plus permanent unlocks.

local ADDON_NAME, ns = ...
local Tab = ns:NewModule("Tab_Legacy")

local NODE_H = 74
local ROW_H = 54
local TRACK_W = 340
local TRACK_GAP = 18
local TRACK_COLS = 2
local TRACK_ROW_GAP = 22

local CLASS_ICON_TEX = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CLASS_ICON_TCOORDS = {
    WARRIOR = {0, 0.25, 0, 0.25},
    MAGE = {0.25, 0.5, 0, 0.25},
    ROGUE = {0.5, 0.75, 0, 0.25},
    DRUID = {0.75, 1, 0, 0.25},
    HUNTER = {0, 0.25, 0.25, 0.5},
    SHAMAN = {0.25, 0.5, 0.25, 0.5},
    PRIEST = {0.5, 0.75, 0.25, 0.5},
    WARLOCK = {0.75, 1, 0.25, 0.5},
    PALADIN = {0, 0.25, 0.5, 0.75},
}

local function setTextColor(fs, color, alpha)
    fs:SetTextColor(color[1], color[2], color[3], alpha or 1)
end

local function money(copper)
    if ns.Tiers and ns.Tiers.FormatMoney then
        return ns.Tiers:FormatMoney(copper or 0)
    end
    return tostring(copper or 0)
end

local function applyClassIcon(tex, class)
    local coords = class and CLASS_ICON_TCOORDS[class]
    if coords then
        tex:SetTexture(CLASS_ICON_TEX)
        tex:SetTexCoord(unpack(coords))
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function classColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b, 1 } end
    return ns.Theme.c.fg
end

local function nodeRewardSummary(node)
    local bundle = ns.Rewards and ns.Rewards:BuildRewardForTierIds({ node.nodeId }, nil)
        or { items = {}, gold = 0, extraLives = 0 }
    local parts = {}
    for _, it in ipairs(bundle.items or {}) do
        parts[#parts + 1] = ("%dx %s"):format(it.qty or 1, it.note or ("item:" .. tostring(it.id)))
    end
    if (bundle.gold or 0) > 0 then
        parts[#parts + 1] = money(bundle.gold)
    end
    if (bundle.extraLives or 0) > 0 then
        parts[#parts + 1] = ("+%d life"):format(bundle.extraLives)
    end
    if #parts == 0 then return "No reward configured." end
    return table.concat(parts, "  -  ")
end

local function buildTrack(parent, Theme)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(TRACK_W)

    f.title = Theme:Text(f, 14, Theme.c.goldH)
    f.title:SetPoint("TOPLEFT", 0, 0)

    f.rank = Theme:Text(f, 10, Theme.c.gold)
    f.rank:SetPoint("TOPRIGHT", 0, -2)
    f.rank:SetJustifyH("RIGHT")

    f.blurb = Theme:Text(f, 10, Theme.c.fg2)
    f.blurb:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.blurb:SetWidth(TRACK_W)
    f.blurb:SetJustifyH("LEFT")

    f.rows = {}
    f.spacers = {}
    return f
end

local function buildNode(parent, Theme)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(NODE_H)
    Theme:Fill(r, Theme.c.bg1, false)

    r.dot = r:CreateTexture(nil, "ARTWORK")
    r.dot:SetSize(10, 10)
    r.dot:SetPoint("TOPLEFT", 10, -12)

    r.title = Theme:Text(r, 12, Theme.c.fg)
    r.title:SetPoint("TOPLEFT", r.dot, "TOPRIGHT", 8, 1)
    r.title:SetWidth(TRACK_W - 98)
    r.title:SetJustifyH("LEFT")

    r.cost = Theme:Text(r, 10, Theme.c.gold)
    r.cost:SetPoint("TOPRIGHT", -10, -12)
    r.cost:SetJustifyH("RIGHT")

    r.reward = Theme:Text(r, 10, Theme.c.fg2)
    r.reward:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -5)
    r.reward:SetWidth(TRACK_W - 28)
    r.reward:SetJustifyH("LEFT")

    r.state = Theme:Text(r, 9, Theme.c.fg2)
    r.state:SetPoint("BOTTOMRIGHT", -10, 8)
    r.state:SetJustifyH("RIGHT")

    r:SetScript("OnClick", function(row)
        if not row._affordable or not row._trackId then return end
        local ok, reason, unlockedNode = ns.LegacyUnlocks:Unlock(row._trackId)
        if ok then
            ns:Print("Unlocked %s: %s.", row._trackName or "Legacy", unlockedNode.name or "Unlock")
            Tab:Refresh()
            if ns.MainFrame and ns.MainFrame.RefreshHeader then
                ns.MainFrame:RefreshHeader()
            end
        elseif reason == "insufficient_budget" then
            ns:Print("Not enough legacy budget for %s.", row._node and row._node.name or row._trackName or "Legacy")
        elseif reason == "max_rank" then
            ns:Print("%s is already maxed.", row._trackName or "Legacy")
        end
    end)

    return r
end

local function buildSpacer(parent, Theme)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(NODE_H)

    r.label = Theme:Text(r, 10, Theme.c.fg2)
    r.label:SetPoint("CENTER", r, "CENTER", 0, 0)
    r.label:SetAlpha(0.45)

    return r
end

local function buildRosterRow(content, Theme)
    local r = CreateFrame("Frame", nil, content)
    r:SetHeight(ROW_H)

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

    r.nameText = Theme:Text(r, 13, Theme.c.fg)
    r.nameText:SetPoint("TOPLEFT", 46, -8)
    r.nameText:SetWidth(228)
    r.nameText:SetJustifyH("LEFT")
    r.nameText:SetWordWrap(false)

    r.metaText = Theme:Text(r, 10, Theme.c.fg2)
    r.metaText:SetPoint("BOTTOMLEFT", 46, 8)
    r.metaText:SetWidth(228)
    r.metaText:SetJustifyH("LEFT")
    r.metaText:SetWordWrap(false)

    r.favBtn = CreateFrame("Button", nil, r)
    r.favBtn:SetSize(22, 22)
    r.favBtn:SetPoint("LEFT", 280, 0)

    r.favIcon = r.favBtn:CreateTexture(nil, "ARTWORK")
    r.favIcon:SetSize(16, 16)
    r.favIcon:SetPoint("CENTER")
    r.favIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    r.favIcon:SetVertexColor(0.55, 0.55, 0.55, 0.45)

    r.bar = Theme:ProgressBar(r, 230, 6)
    r.bar:SetPoint("RIGHT", -152, 2)

    r.amount = Theme:Text(r, 12, Theme.c.gold)
    r.amount:SetPoint("TOPRIGHT", -12, -8)
    r.amount:SetWidth(132)
    r.amount:SetJustifyH("RIGHT")
    r.amount:SetWordWrap(false)

    r.genBadge = Theme:Text(r, 9, Theme.c.fg2)
    r.genBadge:SetPoint("BOTTOMRIGHT", -12, 8)
    r.genBadge:SetJustifyH("RIGHT")
    r.genBadge:SetWidth(132)

    return r
end

function Tab:Init(parent)
    if self.panel then return end
    local Theme = ns.Theme

    local p = CreateFrame("Frame", nil, parent)
    self.panel = p
    ns.MainFrame:RegisterPanel("Legacy", p)

    local title = Theme:Header(p, "Legacy", 16)
    title:SetPoint("TOPLEFT", 20, -18)

    self.summary = Theme:Text(p, 11, Theme.c.fg2)
    self.summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    self.summary:SetWidth(560)
    self.summary:SetJustifyH("LEFT")

    self.resetBtn = Theme:Button(p, "Reset Unlocks", 116, 22)
    self.resetBtn:SetPoint("TOPRIGHT", -22, -18)
    self.resetBtn:SetScript("OnClick", function()
        if ns.LegacyUnlocks then
            ns.LegacyUnlocks:ResetUnlocks()
            ns:Print("Legacy unlocks reset. Lifetime contribution budget is available again.")
            Tab:Refresh()
            if ns.MainFrame and ns.MainFrame.RefreshHeader then
                ns.MainFrame:RefreshHeader()
            end
        end
    end)

    local scroll, content = Theme:ScrollArea(p)
    scroll:SetPoint("TOPLEFT", 20, -82)
    scroll:SetPoint("BOTTOMRIGHT", -20, 16)
    content:SetSize(720, 1)
    self.scroll = scroll
    self.content = content

    self.unlockTitle = Theme:Text(content, 12, Theme.c.goldH)
    self.unlockTitle:SetPoint("TOPLEFT", 0, 0)
    self.unlockTitle:SetText("Permanent Unlocks")

    self.tracks = {}
    local index = 1
    if ns.LegacyUnlocks and ns.LegacyUnlocks.TrackOrder then
        for _, trackId in ipairs(ns.LegacyUnlocks:TrackOrder()) do
            local track = buildTrack(content, Theme)
            track._gridIndex = index
            local col = (index - 1) % TRACK_COLS
            local rowBand = math.floor((index - 1) / TRACK_COLS)
            local x = col * (TRACK_W + TRACK_GAP)
            local y = 24 + rowBand * (44 + (NODE_H + 6) * 6 + TRACK_ROW_GAP)
            track:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
            self.tracks[trackId] = track
            index = index + 1
        end
    end

    self.rosterTitle = Theme:Text(content, 12, Theme.c.goldH)
    self.rosterHint = Theme:Text(content, 10, Theme.c.fg2)
    self.rosterHint:SetText("Contributor roster. Click the star to favorite.")

    self.colChar = Theme:Text(content, 10, Theme.c.goldH)
    self.colChar:SetText("Character")
    self.colProgress = Theme:Text(content, 10, Theme.c.goldH)
    self.colProgress:SetText("Progress")
    self.colGold = Theme:Text(content, 10, Theme.c.goldH)
    self.colGold:SetText("Contributed")
    self.colGold:SetJustifyH("RIGHT")

    self.rows = {}
    self.empty = Theme:Text(content, 12, Theme.c.fg2)
    self.empty:SetText("No characters recorded yet.")
    self.empty:Hide()

    p.Refresh = function() Tab:Refresh() end
    self:Refresh()
end

function Tab:_RefreshUnlocks(startY)
    local Theme = ns.Theme
    local L = ns.LegacyUnlocks
    if not L then return startY end

    local maxY = startY + 24
    for _, trackId in ipairs(L:TrackOrder()) do
        local def = L:TrackDef(trackId)
        local track = self.tracks[trackId]
        if def and track then
            local gridIndex = track._gridIndex or 1
            local col = (gridIndex - 1) % TRACK_COLS
            local rowBand = math.floor((gridIndex - 1) / TRACK_COLS)
            local x = col * (TRACK_W + TRACK_GAP)
            local baseY = startY + 24 + rowBand * (44 + (NODE_H + 6) * 6 + TRACK_ROW_GAP)

            track:ClearAllPoints()
            track:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -baseY)

            local rank = L:GetRank(trackId)
            local maxRank = L:MaxRank(trackId)
            track.title:SetText(def.name)
            track.rank:SetText(("%d / %d"):format(rank, maxRank))
            track.blurb:SetText(def.blurb or "")

            local y = 44
            local nodeIndex = 1
            local visualRows = trackId == "fate" and 6 or #(def.nodes or {})
            for visualRank = 1, visualRows do
                local node = (def.nodes or {})[nodeIndex]
                local nodeVisualRank = node and (node.milestone or node.rank) or nil
                local hasNode = node and nodeVisualRank == visualRank

                if not hasNode then
                    if not track.spacers[visualRank] then
                        track.spacers[visualRank] = buildSpacer(track, Theme)
                    end
                    local spacer = track.spacers[visualRank]
                    spacer:ClearAllPoints()
                    spacer:SetPoint("TOPLEFT", track, "TOPLEFT", 0, -y)
                    spacer:SetPoint("RIGHT", track, "RIGHT", 0, 0)
                    spacer.label:SetText(("Rank %d - No Fate unlock"):format(visualRank))
                    spacer:Show()
                    if track.rows[visualRank] then track.rows[visualRank]:Hide() end
                    y = y + NODE_H + 6
                else
                    if track.spacers[visualRank] then track.spacers[visualRank]:Hide() end
                    if not track.rows[visualRank] then
                        track.rows[visualRank] = buildNode(track, Theme)
                    end

                    local row = track.rows[visualRank]
                    local unlocked = nodeIndex <= rank
                    local nextAvailable = nodeIndex == rank + 1
                    local affordable = nextAvailable and L:AvailableBudget() >= (node.cost or 0)

                    row._node = node
                    row._trackId = trackId
                    row._trackName = def.name
                    row._affordable = affordable
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", track, "TOPLEFT", 0, -y)
                    row:SetPoint("RIGHT", track, "RIGHT", 0, 0)
                    row:Show()

                    if unlocked then
                        row:SetAlpha(1)
                        row.dot:SetColorTexture(Theme.c.green[1], Theme.c.green[2], Theme.c.green[3], 1)
                        row.state:SetText("UNLOCKED")
                        setTextColor(row.state, Theme.c.green, 1)
                    elseif affordable then
                        row:SetAlpha(1)
                        row.dot:SetColorTexture(Theme.c.gold[1], Theme.c.gold[2], Theme.c.gold[3], 1)
                        row.state:SetText("CLICK TO UNLOCK")
                        setTextColor(row.state, Theme.c.gold, 1)
                    elseif nextAvailable then
                        row:SetAlpha(0.78)
                        row.dot:SetColorTexture(Theme.c.fg2[1], Theme.c.fg2[2], Theme.c.fg2[3], 0.65)
                        row.state:SetText("NEED BUDGET")
                        setTextColor(row.state, Theme.c.fg2, 0.85)
                    else
                        row:SetAlpha(0.45)
                        row.dot:SetColorTexture(Theme.c.fg2[1], Theme.c.fg2[2], Theme.c.fg2[3], 0.45)
                        row.state:SetText("LOCKED")
                        setTextColor(row.state, Theme.c.fg2, 0.75)
                    end

                    row.title:SetText((node.milestone and ("Tier %d - %s") or ("Rank %d - %s"))
                        :format(node.milestone or node.rank, node.name or "Unlock"))
                    row.cost:SetText(money(node.cost or 0))
                    row.reward:SetText(nodeRewardSummary(node))
                    setTextColor(row.title, unlocked and Theme.c.fg or Theme.c.fg2, unlocked and 1 or 0.95)
                    setTextColor(row.reward, Theme.c.fg2, unlocked and 1 or 0.82)

                    nodeIndex = nodeIndex + 1
                    y = y + NODE_H + 6
                end
            end
            for i = visualRows + 1, #track.rows do track.rows[i]:Hide() end
            for i = visualRows + 1, #track.spacers do track.spacers[i]:Hide() end
            track:SetHeight(y)
            if baseY + y > maxY then maxY = baseY + y end
        end
    end

    return maxY
end

function Tab:_Roster()
    local roster = ns.Database and ns.Database.RosterSortedByContribution
        and ns.Database:RosterSortedByContribution()
        or {}

    local function liveScore(r)
        if r.isArchived then return 0 end
        local s = ns.Run and ns.Run.GetState and ns.Run:GetState(r) or r.status
        return (s == "fresh" or s == "active" or s == "dead_pending_contribution") and 1 or 0
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

    return roster
end

function Tab:_RefreshRoster(startY)
    local Theme = ns.Theme
    local roster = self:_Roster()

    self.rosterTitle:ClearAllPoints()
    self.rosterTitle:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -startY)
    self.rosterTitle:SetText("Contributor Roster")

    self.rosterHint:ClearAllPoints()
    self.rosterHint:SetPoint("TOPLEFT", self.rosterTitle, "BOTTOMLEFT", 0, -4)

    local colsY = startY + 42
    self.colChar:ClearAllPoints()
    self.colChar:SetPoint("TOPLEFT", self.content, "TOPLEFT", 46, -colsY)
    self.colProgress:ClearAllPoints()
    self.colProgress:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -300, -colsY)
    self.colGold:ClearAllPoints()
    self.colGold:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -28, -colsY)
    self.colGold:SetWidth(132)

    local max = 0
    for _, r in ipairs(roster) do
        if (r.contributed or 0) > max then max = r.contributed end
    end
    if max == 0 then max = 1 end

    local y = startY + 64
    if #roster == 0 then
        for _, row in ipairs(self.rows) do row:Hide() end
        self.empty:ClearAllPoints()
        self.empty:SetPoint("TOPLEFT", self.content, "TOPLEFT", 8, -y)
        self.empty:Show()
        return y + 60
    end
    self.empty:Hide()

    for i = #self.rows + 1, #roster do
        self.rows[i] = buildRosterRow(self.content, Theme)
    end
    for i = #roster + 1, #self.rows do
        self.rows[i]:Hide()
    end

    for i, rec in ipairs(roster) do
        local row = self.rows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", self.content, "RIGHT", -16, 0)
        row:Show()

        applyClassIcon(row.classIcon, rec.class)

        local runState = ns.Run and ns.Run.GetState and ns.Run:GetState(rec) or rec.status
        if rec.isArchived then
            row.statusDot:SetVertexColor(1, 0.62, 0.15, 1)
        elseif runState == "dead_pending_contribution" then
            row.statusDot:SetVertexColor(1, 0.86, 0.20, 1)
        elseif runState == "retired" then
            row.statusDot:SetVertexColor(1, 0.25, 0.25, 1)
        else
            row.statusDot:SetVertexColor(0.45, 1, 0.45, 1)
        end

        local baseName = rec.key and (rec.key:match("^([^%-]+)") or rec.key) or "Unknown"
        local level = rec.levelCurrent or rec.levelAtCreate or 0
        local nc = classColor(rec.class)
        row.nameText:SetTextColor(nc[1], nc[2], nc[3], 1)
        row.nameText:SetText(("%s  |cffb09040Lv %d|r"):format(baseName, level))

        local raceName = rec.race and (rec.race:sub(1, 1) .. rec.race:sub(2):lower()) or "?"
        local className = rec.class and (rec.class:sub(1, 1) .. rec.class:sub(2):lower()) or "?"
        local statusStr
        if rec.isArchived and runState == "retired" then
            statusStr = "|cffb85c5cretired|r |cffb07828- prev. char|r"
        elseif rec.isArchived then
            statusStr = "|cffb07828prev. char|r"
        elseif runState == "dead_pending_contribution" then
            statusStr = "|cffffff00retired - contribution pending|r"
        elseif runState == "retired" then
            statusStr = "|cffb85c5cretired|r"
        else
            statusStr = "|cff7ab27aalive|r"
        end
        row.metaText:SetText(("%s %s  -  %s"):format(raceName, className, statusStr))

        if (rec.generation or 1) > 1 or rec.isArchived then
            row.genBadge:SetText(("Gen %d"):format(rec.generation or 1))
        else
            row.genBadge:SetText("")
        end

        local uid = rec.uid or rec.key
        local isFav = ns.Database and ns.Database.IsFavorite and ns.Database:IsFavorite(uid)
        row.favIcon:SetVertexColor(
            isFav and Theme.c.gold[1] or 0.55,
            isFav and Theme.c.gold[2] or 0.55,
            isFav and Theme.c.gold[3] or 0.55,
            isFav and 1 or 0.35)

        local capturedUid = uid
        row.favBtn:SetScript("OnClick", function()
            ns.Database:ToggleFavorite(capturedUid)
            Tab:Refresh()
        end)

        row.bar:SetProgress((rec.contributed or 0) / max)
        row.amount:SetText(money(rec.contributed or 0))

        y = y + ROW_H + 4
    end

    return y
end

function Tab:Refresh()
    if not self.panel then return end
    local L = ns.LegacyUnlocks
    local total = ns.Database and ns.Database.TotalContributed and ns.Database:TotalContributed()
        or (WRL_DB and WRL_DB.totalContributed)
        or 0
    local spent = L and L:Spent() or 0
    local available = L and L:AvailableBudget() or math.max(0, total - spent)

    self.summary:SetText(("Lifetime contributed: %s   |   Legacy spent: %s   |   Available: %s")
        :format(money(total), money(spent), money(available)))

    local afterUnlocks = self:_RefreshUnlocks(0)
    local finalY = self:_RefreshRoster(afterUnlocks + 28)

    self.content:SetHeight(math.max(420, finalY + 8))
    self.content:SetWidth(720)
    if self.scroll and self.scroll.UpdateScrollChildRect then
        self.scroll:UpdateScrollChildRect()
    end
end
