-- Core/Export.lua
-- Export and audit helpers for /wrl export commands.
--
-- Builds compact, human-readable summaries of the current run character or
-- account state, suitable for posting to Discord or a manual leaderboard.
--
-- A lightweight checksum is appended to each export as an "audit hint" so
-- readers can detect accidental edits.  It is NOT anti-cheat; the label says
-- so explicitly.  Re-computing the same checksum from the same fields gives
-- the same hex string every time (stable for unchanged data).
--
-- Public entry points (called from WoWRoguelite.lua slash handler):
--   ns.Export:DoRunExport([key])  → /wrl export run
--   ns.Export:DoAccountExport()   → /wrl export account
--
-- Both functions print a short preview to chat and open a copyable popup
-- frame so the player can Ctrl+A / Ctrl+C the full text.

local ADDON_NAME, ns = ...
local E = ns:NewModule("Export")

-- ── Internal utilities ────────────────────────────────────────────────────────

-- Convert copper amount to a human-readable "Xg Ys Zc" string.
local function copperToGold(c)
    c = math.max(0, math.floor(c or 0))
    local g  = math.floor(c / 10000)
    local s  = math.floor((c % 10000) / 100)
    local cp = c % 100
    if g > 0 then
        return string.format("%dg %ds %dc", g, s, cp)
    elseif s > 0 then
        return string.format("%ds %dc", s, cp)
    else
        return string.format("%dc", cp)
    end
end

-- Deterministic 24-bit polynomial hash.
-- Stable for the same input; not cryptographic and not anti-cheat.
local function computeChecksum(str)
    local h = 5381
    for i = 1, #str do
        h = (h * 33 + str:byte(i)) % 16777216   -- keep within 24-bit range
    end
    return string.format("%06x", h)
end

-- Format a Unix timestamp as YYYY-MM-DD; returns "?" for nil/zero.
local function fmtDate(ts)
    if not ts or ts == 0 then return "?" end
    return date and date("%Y-%m-%d", ts) or tostring(ts)
end

-- Taint count for a character key; safe when Rules module is absent.
local function getTaintCount(key)
    if not key then return 0 end
    if ns.Rules and ns.Rules.TaintCount then
        return ns.Rules:TaintCount(key) or 0
    end
    -- Manual fallback if Rules module is not loaded.
    local rec = ns.Database and ns.Database:GetCharacter(key)
    if not rec or type(rec.ruleLog) ~= "table" then return 0 end
    local n = 0
    for _, e in ipairs(rec.ruleLog) do
        if e and e.result == "tainted" then n = n + 1 end
    end
    return n
end

-- Resolve a claimed reward name. New saves use legacy node IDs; old saves may
-- still have tier IDs.
local function tierName(tierId)
    if ns.LegacyUnlocks and ns.LegacyUnlocks.NodeById then
        local node = ns.LegacyUnlocks:NodeById(tierId)
        local trackId = ns.LegacyUnlocks.TrackIdForNode and ns.LegacyUnlocks:TrackIdForNode(tierId)
        local track = trackId and ns.LegacyUnlocks:TrackDef(trackId)
        if node and track then
            return ("%s %d - %s"):format(track.name or trackId, node.rank or 0, node.name or "Unlock")
        end
    end
    if ns.Tiers and ns.Tiers.Definitions then
        for _, t in ipairs(ns.Tiers:Definitions()) do
            if t.id == tierId then return t.name end
        end
    end
    return "Reward " .. tostring(tierId)
end

-- Split a newline-separated string into a sequential Lua table.
local function splitLines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

-- Gather contribution receipt summary: count, totalCopper, lastReceipt.
-- Falls back to rec.history when the Contributions module is absent so old
-- records without receipts still produce reasonable output.
local function contributionSummary(key)
    local receipts = {}
    if ns.Contributions and ns.Contributions.ForCharacter then
        receipts = ns.Contributions:ForCharacter(key) or {}
    else
        local rec = ns.Database and ns.Database:GetCharacter(key)
        if rec and type(rec.history) == "table" then
            for _, h in ipairs(rec.history) do
                if h then
                    receipts[#receipts + 1] = {
                        amount     = h.copper     or 0,
                        when       = h.when       or 0,
                        source     = h.source     or "legacy",
                        confidence = h.confidence or "estimated",
                    }
                end
            end
        end
    end
    local total, last = 0, nil
    for _, r in ipairs(receipts) do
        total = total + (r.amount or 0)
        if not last or (r.when or 0) > (last.when or 0) then last = r end
    end
    return #receipts, total, last
end

-- Return the most-recent memorial for a character key, or nil.
local function getMemorial(key)
    if not key or not WRL_DB or not WRL_DB.memorials then return nil end
    local found
    for _, m in pairs(WRL_DB.memorials) do
        if m and m.characterKey == key then
            if not found or (m.timestamp or 0) > (found.timestamp or 0) then
                found = m
            end
        end
    end
    return found
end

-- ── Run export ────────────────────────────────────────────────────────────────

-- Build and return the full formatted run-export string for `key`.
-- All field accesses are nil-safe so old records with missing optional fields
-- do not produce errors.
function E:FormatRunExport(key)
    key = key or ns:UnitKey()
    if not key then
        return "[Export error: could not determine character key]"
    end

    local rec = ns.Database:GetCharacter(key)
    if not rec then
        return string.format("[Export error: no record found for '%s']", key)
    end

    local lines = {}
    local function add(s) lines[#lines + 1] = s or "" end

    add("=== WRL Run Export ===")
    add(string.format("Version:    %s", ns.version or "?"))
    add(string.format("Character:  %s", key))
    add(string.format("Class:      %s", rec.class or "?"))
    add(string.format("Race:       %s", rec.race  or "?"))
    add(string.format("Level:      %d", rec.levelCurrent or rec.levelAtCreate or 1))
    add(string.format("State:      %s",
        (ns.Run and ns.Run:GetState(rec)) or rec.status or "?"))

    -- Profile name.
    local profile = "?"
    if ns.Settings and ns.Settings.GetProfile then
        profile = ns.Settings:GetProfile() or "?"
    elseif WRL_DB and WRL_DB.settings then
        profile = WRL_DB.settings.profile or "?"
    end
    add(string.format("Profile:    %s", profile))

    -- Comma-list of enabled rule IDs (empty → "none").
    local ruleList = {}
    if ns.Rules and ns.Rules.Definitions then
        for _, def in ipairs(ns.Rules:Definitions()) do
            if ns.Rules:IsEnabled(def.id) then
                ruleList[#ruleList + 1] = def.id
            end
        end
    end
    add(string.format("Rules:      %s",
        #ruleList > 0 and table.concat(ruleList, ", ") or "none"))

    add(string.format("Taints:     %d", getTaintCount(key)))
    add(string.format("Lives left: %d", rec.livesRemaining or 1))

    -- Claimed rewards.
    add("")
    add("-- Claimed Rewards --")
    local claimedIds = ns.Database:ClaimedTierIds(key)
    if claimedIds and #claimedIds > 0 then
        table.sort(claimedIds)
        local names = {}
        for _, tid in ipairs(claimedIds) do
            names[#names + 1] = tierName(tid)
        end
        add(table.concat(names, ", "))
    else
        add("(none)")
    end

    -- Contribution receipts summary.
    add("")
    add("-- Contributions --")
    local count, total, lastR = contributionSummary(key)
    add(string.format("Total:    %s  (%d receipt%s)",
        copperToGold(total), count, count == 1 and "" or "s"))
    if lastR then
        add(string.format("Last:     %s  source=%s  [%s]",
            copperToGold(lastR.amount or 0),
            lastR.source     or "?",
            lastR.confidence or "?"))
    end
    -- Show rec.contributed separately when it diverges from the receipt sum
    -- (this can happen with pre-receipt legacy history entries).
    if (rec.contributed or 0) ~= total then
        add(string.format("Credited: %s  (record total)", copperToGold(rec.contributed or 0)))
    end

    -- Memorial / death data.
    local memorial = getMemorial(key)
    if memorial then
        add("")
        add("-- Memorial --")
        add(string.format("Zone:     %s / %s",
            (memorial.zone    ~= "" and memorial.zone)    or "?",
            (memorial.subzone ~= "" and memorial.subzone) or "?"))
        add(string.format("Date:     %s  Level: %d",
            fmtDate(memorial.timestamp), memorial.level or 0))
        add(string.format("Taints:   %d  Lives used: %d",
            memorial.taintCount or 0, memorial.livesUsed or 0))
        add(string.format("Est. contribution: %s",
            copperToGold(memorial.contributionEstimate or 0)))
    elseif rec.deathLog and #rec.deathLog > 0 then
        -- Pre-Step-11 record: no formal memorial, but death log exists.
        add("")
        add("-- Death Log --")
        for i, d in ipairs(rec.deathLog) do
            add(string.format("  [%d] %s  level %d  %s",
                i, fmtDate(d.when), d.level or 0, d.zone or "?"))
        end
    end

    -- Account-wide total for easy cross-character context.
    add("")
    add(string.format("Account total contributed: %s",
        copperToGold(WRL_DB and WRL_DB.totalContributed or 0)))

    -- Checksum is computed over the body assembled so far, then appended.
    -- The hint line itself is NOT included in the checksum input so re-computing
    -- it from the body text (minus the last line) always gives the same value.
    local body = table.concat(lines, "\n")
    add("")
    add(string.format("[Audit hint: %s  (checksum over fields above — not anti-cheat)]",
        computeChecksum(body)))

    return table.concat(lines, "\n")
end

-- ── Account export ────────────────────────────────────────────────────────────

-- Build and return the full formatted account-export string.
function E:FormatAccountExport()
    local lines = {}
    local function add(s) lines[#lines + 1] = s or "" end

    add("=== WRL Account Export ===")
    add(string.format("Version:           %s", ns.version or "?"))
    add(string.format("Bank:              %s",
        (WRL_DB and WRL_DB.bankCharacter) or "not set"))
    add(string.format("Total Contributed: %s",
        copperToGold(WRL_DB and WRL_DB.totalContributed or 0)))

    local profile = "?"
    if ns.Settings and ns.Settings.GetProfile then
        profile = ns.Settings:GetProfile() or "?"
    elseif WRL_DB and WRL_DB.settings then
        profile = WRL_DB.settings.profile or "?"
    end
    add(string.format("Profile:           %s", profile))

    local achCount = 0
    if WRL_DB and WRL_DB.achievements then
        for _ in pairs(WRL_DB.achievements) do achCount = achCount + 1 end
    end
    add(string.format("Achievements:      %d", achCount))

    -- Characters summary sorted by contribution (highest first).
    add("")
    add("-- Run Characters --")
    local chars = {}
    if WRL_DB and WRL_DB.characters then
        for _, rec in pairs(WRL_DB.characters) do
            chars[#chars + 1] = rec
        end
        table.sort(chars, function(a, b)
            return (a.contributed or 0) > (b.contributed or 0)
        end)
    end
    if #chars == 0 then
        add("  (none)")
    else
        for _, rec in ipairs(chars) do
            local state = (ns.Run and ns.Run.GetState)
                and ns.Run:GetState(rec)
                or (rec.status or "?")
            local arch = rec.isArchived and " [archived]" or ""
            add(string.format("  %s  %s/%s  lvl%d  %s  taint=%d  %s%s",
                rec.key or "?",
                rec.class or "?",
                rec.race  or "?",
                rec.levelCurrent or rec.levelAtCreate or 1,
                state,
                getTaintCount(rec.key or ""),
                copperToGold(rec.contributed or 0),
                arch))
        end
    end

    -- Memorials summary, newest first.
    add("")
    add("-- Memorials --")
    local memList = {}
    if WRL_DB and WRL_DB.memorials then
        for _, m in pairs(WRL_DB.memorials) do
            if m then memList[#memList + 1] = m end
        end
        table.sort(memList, function(a, b)
            return (a.timestamp or 0) > (b.timestamp or 0)
        end)
    end
    if #memList == 0 then
        add("  (none)")
    else
        for _, m in ipairs(memList) do
            local name = (m.characterKey or "?"):match("^([^%-]+)") or m.characterKey
            add(string.format("  %s (%s/%s lvl%d)  fell in %s  [%s]",
                name or "?",
                m.class or "?",
                m.race  or "?",
                m.level or 0,
                (m.zone ~= "" and m.zone) or "?",
                fmtDate(m.timestamp)))
        end
    end

    -- Checksum over body; appended as the last line.
    local body = table.concat(lines, "\n")
    add("")
    add(string.format("[Audit hint: %s  (checksum over fields above — not anti-cheat)]",
        computeChecksum(body)))

    return table.concat(lines, "\n")
end

-- ── Copyable popup frame ──────────────────────────────────────────────────────
-- A small movable Frame containing a scrollable EditBox.  The player can
-- click inside, press Ctrl+A to select all, then Ctrl+C to copy.
-- Built lazily on first use; no global state during PLAYER_LOGIN.

local copyFrame

local function buildCopyFrame()
    local Theme = ns.Theme

    local f = CreateFrame("Frame", "WRLExportCopyFrame", UIParent)
    f:SetSize(530, 340)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)

    -- Background using the addon's Theme helpers for visual consistency.
    Theme:Fill(f, Theme.c.bg0, true)

    -- Title bar text.
    local title = Theme:Text(f, 11, Theme.c.fg2)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    title:SetText(
        "|cffc0a060[WRL Export]|r  " ..
        "Click inside, Ctrl+A, Ctrl+C to copy  " ..
        "|cff606060(drag to move  •  Esc or Close to dismiss)|r")

    -- Close button.
    local closeBtn = Theme:Button(f, "Close", 60, 20)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- UIPanelScrollFrameTemplate provides the standard Blizzard scrollbar.
    local sf = CreateFrame("ScrollFrame", "WRLExportScrollFrame", f,
        "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     10, -28)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28,   8)

    -- Multi-line EditBox inside the scroll child.
    local eb = CreateFrame("EditBox", "WRLExportEditBox", sf)
    eb:SetWidth(490)
    eb:SetHeight(1)          -- height auto-grows with SetMultiLine content
    eb:SetMultiLine(true)
    eb:SetMaxLetters(0)      -- no character cap
    eb:SetAutoFocus(false)   -- don't steal keyboard focus on open
    eb:SetFontObject("ChatFontNormal")
    -- Match the body text colour to Theme fg.
    local fg = Theme.c.fg
    eb:SetTextColor(fg[1], fg[2], fg[3], fg[4] or 1)

    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        f:Hide()
    end)
    -- Clicking into the box focuses it and selects all for easy copy.
    eb:SetScript("OnMouseDown", function(self)
        self:SetFocus()
        self:HighlightText()
    end)

    sf:SetScrollChild(eb)
    f.editBox    = eb
    f.scrollFrame = sf
    return f
end

function E:ShowCopyFrame(text)
    if not copyFrame then
        copyFrame = buildCopyFrame()
    end
    copyFrame.editBox:SetText(text or "")
    copyFrame:Show()
    copyFrame.editBox:SetFocus()
    copyFrame.editBox:HighlightText()
end

-- ── Public slash-command entry points ─────────────────────────────────────────

-- /wrl export  or  /wrl export run
function E:DoRunExport(key)
    local text = self:FormatRunExport(key)
    ns:Print("Run export ready — see popup to copy.")
    -- Print the first 6 non-empty lines as a quick in-chat preview.
    local count = 0
    for _, line in ipairs(splitLines(text)) do
        if count >= 6 then break end
        if line ~= "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff808080  " .. line .. "|r")
            count = count + 1
        end
    end
    self:ShowCopyFrame(text)
end

-- /wrl export account
function E:DoAccountExport()
    local text = self:FormatAccountExport()
    ns:Print("Account export ready — see popup to copy.")
    local count = 0
    for _, line in ipairs(splitLines(text)) do
        if count >= 6 then break end
        if line ~= "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff808080  " .. line .. "|r")
            count = count + 1
        end
    end
    self:ShowCopyFrame(text)
end

-- Init is called during PLAYER_LOGIN.  The popup frame is built lazily on
-- first use so there's nothing to do here at boot time.
function E:Init()
end
