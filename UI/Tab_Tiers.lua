-- UI/Tab_Tiers.lua
-- Three-track legacy unlock board: Storage, Stipend, and Fate.

local ADDON_NAME, ns = ...
local Tab = ns:NewModule("Tab_Tiers")

local NODE_H = 74
local TRACK_W = 224
local TRACK_GAP = 14

local function setTextColor(fs, color, alpha)
    fs:SetTextColor(color[1], color[2], color[3], alpha or 1)
end

local function nodeRewardSummary(node)
    local bundle = ns.Rewards and ns.Rewards:BuildRewardForTierIds({ node.nodeId }, nil)
        or { items = {}, gold = 0, extraLives = 0 }
    local parts = {}
    for _, it in ipairs(bundle.items or {}) do
        parts[#parts + 1] = ("%dx %s"):format(it.qty or 1, it.note or ("item:" .. tostring(it.id)))
    end
    if (bundle.gold or 0) > 0 then
        parts[#parts + 1] = ns.Tiers:FormatMoney(bundle.gold)
    end
    if (bundle.extraLives or 0) > 0 then
        parts[#parts + 1] = ("+%d life"):format(bundle.extraLives)
    end
    if #parts == 0 then return "No reward configured." end
    return table.concat(parts, "  -  ")
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

    return r
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
    return f
end

function Tab:Init(parent)
    if self.panel then return end
    local Theme = ns.Theme

    local p = CreateFrame("Frame", nil, parent)
    self.panel = p
    ns.MainFrame:RegisterPanel("Tiers", p)

    local title = Theme:Header(p, "Legacy Unlocks", 16)
    title:SetPoint("TOPLEFT", 20, -18)

    self.summary = Theme:Text(p, 11, Theme.c.fg2)
    self.summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    self.summary:SetWidth(720)
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

    self.tracks = {}
    local x = 0
    for _, trackId in ipairs(ns.LegacyUnlocks:TrackOrder()) do
        local track = buildTrack(content, Theme)
        track:SetPoint("TOPLEFT", content, "TOPLEFT", x, 0)
        self.tracks[trackId] = track
        x = x + TRACK_W + TRACK_GAP
    end

    p.Refresh = function() Tab:Refresh() end
    self:Refresh()
end

function Tab:Refresh()
    if not self.panel then return end
    local Theme = ns.Theme
    local L = ns.LegacyUnlocks
    if not L then return end

    local total = ns.Database and ns.Database:TotalContributed() or (WRL_DB and WRL_DB.totalContributed) or 0
    local spent = L:Spent()
    local available = L:AvailableBudget()
    self.summary:SetText(
        ("Lifetime: %s   |   Spent: %s   |   Available: %s")
            :format(ns.Tiers:FormatMoney(total), ns.Tiers:FormatMoney(spent), ns.Tiers:FormatMoney(available)))

    local maxY = 0
    for _, trackId in ipairs(L:TrackOrder()) do
        local def = L:TrackDef(trackId)
        local track = self.tracks[trackId]
        local rank = L:GetRank(trackId)
        local maxRank = L:MaxRank(trackId)
        track.title:SetText(def.name)
        track.rank:SetText(("%d / %d"):format(rank, maxRank))
        track.blurb:SetText(def.blurb or "")

        local y = 44
        for i, node in ipairs(def.nodes or {}) do
            if not track.rows[i] then
                track.rows[i] = buildNode(track, Theme)
                track.rows[i]:SetScript("OnClick", function(row)
                    local n = row._node
                    if not n then return end
                    local ok, reason = L:Unlock(row._trackId)
                    if ok then
                        ns:Print("Unlocked %s: %s.", def.name, n.name or ("Rank " .. tostring(n.rank)))
                        Tab:Refresh()
                        if ns.MainFrame and ns.MainFrame.RefreshHeader then
                            ns.MainFrame:RefreshHeader()
                        end
                    elseif reason == "insufficient_budget" then
                        ns:Print("Not enough legacy budget for %s.", n.name or def.name)
                    elseif reason == "max_rank" then
                        ns:Print("%s is already maxed.", def.name)
                    end
                end)
            end

            local row = track.rows[i]
            local unlocked = i <= rank
            local nextAvailable = i == rank + 1
            local affordable = nextAvailable and L:AvailableBudget() >= (node.cost or 0)

            row._node = node
            row._trackId = trackId
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
            row.cost:SetText(ns.Tiers:FormatMoney(node.cost or 0))
            row.reward:SetText(nodeRewardSummary(node))
            setTextColor(row.title, unlocked and Theme.c.fg or Theme.c.fg2, unlocked and 1 or 0.95)
            setTextColor(row.reward, Theme.c.fg2, unlocked and 1 or 0.82)

            y = y + NODE_H + 6
        end
        for i = #(def.nodes or {}) + 1, #track.rows do
            track.rows[i]:Hide()
        end
        track:SetHeight(y)
        if y > maxY then maxY = y end
    end

    self.content:SetHeight(math.max(420, maxY + 8))
    self.content:SetWidth(720)
    if self.scroll and self.scroll.UpdateScrollChildRect then
        self.scroll:UpdateScrollChildRect()
    end
end
