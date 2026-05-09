-- UI/Tab_Run.lua
-- Current run overview for the logged-in character with nil-safe fallbacks.

local ADDON_NAME, ns = ...
local Tab = ns:NewModule("Tab_Run")

local function shortName(full)
    return (full and full:match("^([^-]+)")) or full or "Unknown"
end

local function withRealm(key)
    local n, r = key and key:match("^([^%-]+)%-(.+)$")
    return n or key or "Unknown", r or (GetRealmName and GetRealmName() or "Unknown")
end

local function fmtWhen(ts)
    if not ts then return "Unknown" end
    if date then return date("%m-%d %H:%M", ts) end
    return tostring(ts)
end

local function classLabel(classToken)
    if not classToken or classToken == "" then return "Unknown" end
    return classToken:sub(1, 1) .. classToken:sub(2):lower()
end

local function stateLabel(state)
    if state == "fresh" then return "|cffc0a060fresh|r" end
    if state == "active" then return "|cff7ab27aactive|r" end
    if state == "dead_pending_contribution" then return "|cffffff00dead_pending_contribution|r" end
    if state == "retired" then return "|cffb85c5cretired|r" end
    if state == "archived" then return "|cffb07828archived|r" end
    return "|cff9a948aunknown|r"
end

local function isRequestPending(status)
    return status == "sent" or status == "pending" or status == "gathering"
end

local function newestPendingOutgoing()
    local outgoing = WRL_CharDB and WRL_CharDB.outgoing
    if type(outgoing) ~= "table" then return nil end
    local best = nil
    for _, req in ipairs(outgoing) do
        if req and isRequestPending(req.status) then
            if (not best) or ((req.when or 0) > (best.when or 0)) then
                best = req
            end
        end
    end
    return best
end

local function rulesSummary(maxRules)
    local defs = ns.Rules and ns.Rules.Definitions and ns.Rules:Definitions() or {}
    local enabled = {}
    for _, def in ipairs(defs) do
        if def and def.id and ns.Rules:IsEnabled(def.id) then
            enabled[#enabled + 1] = def.name or def.id
        end
    end
    table.sort(enabled)
    local out = {}
    if #enabled == 0 then
        out[1] = "Enabled rules: none"
        return out
    end
    out[1] = ("Enabled rules: %d"):format(#enabled)
    local n = math.min(maxRules or 3, #enabled)
    for i = 1, n do out[#out + 1] = " - " .. enabled[i] end
    if #enabled > n then out[#out + 1] = (" - ... and %d more"):format(#enabled - n) end
    return out
end

local function claimedSummary(rec, maxShown)
    local rows = {}
    local claims = rec and rec.claimedTiers
    if type(claims) ~= "table" or not next(claims) then
        rows[1] = "Claimed rewards: none"
        return rows
    end

    local entries = {}
    for tierId, info in pairs(claims) do
        entries[#entries + 1] = { tierId = tierId, info = info or {} }
    end
    table.sort(entries, function(a, b)
        return (a.info.when or 0) > (b.info.when or 0)
    end)

    rows[1] = ("Claimed rewards: %d"):format(#entries)
    local limit = math.min(maxShown or 4, #entries)
    for i = 1, limit do
        local e = entries[i]
        rows[#rows + 1] = (" - Tier %s (%s)"):format(tostring(e.tierId), fmtWhen(e.info.when))
    end
    if #entries > limit then
        rows[#rows + 1] = (" - ... and %d more"):format(#entries - limit)
    end
    return rows
end

local function activeBoonsSummary(rec)
    local rows = {}
    local boons = rec and rec.boons
    if not boons or not next(boons) then
        rows[1] = "Active boons: none"
        return rows
    end
    local names = {}
    for id in pairs(boons) do
        local def = ns.Boons and ns.Boons:GetBoonDef(id)
        names[#names + 1] = def and def.name or id
    end
    table.sort(names)
    rows[1] = ("Active boons: %d"):format(#names)
    for _, n in ipairs(names) do rows[#rows + 1] = " - " .. n end
    return rows
end

local function activeBurdensSummary(rec)
    local rows = {}
    local burdens = rec and rec.burdens
    if not burdens or not next(burdens) then
        rows[1] = "Active burdens: none"
        return rows
    end
    local names = {}
    for id in pairs(burdens) do
        local def = ns.Boons and ns.Boons:GetBurdenDef(id)
        names[#names + 1] = def and def.name or id
    end
    table.sort(names)
    rows[1] = ("Active burdens: %d"):format(#names)
    for _, n in ipairs(names) do rows[#rows + 1] = " - " .. n end
    return rows
end

local function bagEstimate()
    local money = GetMoney and (GetMoney() or 0) or 0
    local bagValue = 0
    if ns.Vendor and ns.Vendor.BagsSnapshot then
        local ok, val = pcall(function() return select(1, ns.Vendor:BagsSnapshot()) end)
        if ok and type(val) == "number" then
            bagValue = math.max(0, math.floor(val))
        end
    end
    return money, bagValue, money + bagValue
end

local function recentReceipts(charKey, maxShown)
    local rows = {}
    local list = (ns.Contributions and ns.Contributions.ForCharacter and ns.Contributions:ForCharacter(charKey)) or {}
    if #list == 0 then
        rows[1] = "Recent contribution receipts: none"
        return rows
    end
    table.sort(list, function(a, b) return (a.when or 0) > (b.when or 0) end)
    rows[1] = ("Recent contribution receipts: %d total"):format(#list)
    local limit = math.min(maxShown or 4, #list)
    for i = 1, limit do
        local r = list[i]
        rows[#rows + 1] = (" - %s | %s | %s"):format(
            fmtWhen(r.when),
            ns.Tiers and ns.Tiers.FormatMoney and ns.Tiers:FormatMoney(r.amount or 0) or tostring(r.amount or 0),
            r.confidence or "unknown")
    end
    return rows
end

local function recentRuleWarnings(charKey, maxShown)
    local rows = {}
    local log = (ns.Rules and ns.Rules.GetLog and ns.Rules:GetLog(charKey)) or {}
    local filtered = {}
    for _, e in ipairs(log) do
        if e and (e.result == "tainted" or e.result == "warned" or e.result == "blocked") then
            filtered[#filtered + 1] = e
        end
    end
    if #filtered == 0 then
        rows[1] = "Recent taint/warning entries: none"
        return rows
    end
    table.sort(filtered, function(a, b) return (a.when or 0) > (b.when or 0) end)
    rows[1] = ("Recent taint/warning entries: %d"):format(#filtered)
    local limit = math.min(maxShown or 4, #filtered)
    for i = 1, limit do
        local e = filtered[i]
        local detail = e.detail or ""
        if #detail > 42 then detail = detail:sub(1, 39) .. "..." end
        rows[#rows + 1] = (" - %s [%s] %s"):format(fmtWhen(e.when), e.result or "?", detail)
    end
    return rows
end

local function recentDeaths(rec, maxShown)
    local rows = {}
    local log = rec and rec.deathLog or nil
    if type(log) ~= "table" or #log == 0 then
        rows[1] = "Death history: none"
        return rows
    end
    rows[1] = ("Death history: %d"):format(#log)
    local startIdx = math.max(1, #log - (maxShown or 4) + 1)
    for i = #log, startIdx, -1 do
        local d = log[i]
        local zone = d.zone or "Unknown zone"
        local level = d.level or "?"
        rows[#rows + 1] = (" - %s | Lv%s | %s"):format(fmtWhen(d.when), tostring(level), zone)
    end
    return rows
end

local function achievementsSummary(maxShown)
    local rows = {}
    if not ns.Achievements or not ns.Achievements.VisibleDefinitions then
        rows[1] = "Achievements: unavailable"
        return rows
    end

    local defs = ns.Achievements:VisibleDefinitions()
    local earnedCount = ns.Achievements:EarnedCount()
    rows[1] = ("Achievements: %d / %d visible earned"):format(earnedCount, #defs)

    local earned = {}
    for _, def in ipairs(defs) do
        local entry = ns.Achievements:GetEarned(def.id)
        if entry then
            earned[#earned + 1] = { def = def, entry = entry }
        end
    end
    table.sort(earned, function(a, b)
        return (a.entry.when or 0) > (b.entry.when or 0)
    end)

    if #earned == 0 then
        rows[#rows + 1] = " - No achievements earned yet."
        return rows
    end

    local limit = math.min(maxShown or 5, #earned)
    for i = 1, limit do
        local item = earned[i]
        rows[#rows + 1] = (" - %s (%s)"):format(item.def.name, fmtWhen(item.entry.when))
    end
    if #earned > limit then
        rows[#rows + 1] = (" - ... and %d more"):format(#earned - limit)
    end
    return rows
end

local function writeLines(target, lines)
    for i = 1, #target do
        local fs = target[i]
        local txt = lines and lines[i]
        if txt and txt ~= "" then
            fs:SetText(txt)
            fs:Show()
        else
            fs:Hide()
        end
    end
end

function Tab:Init(parent)
    if self.panel then return end
    local Theme = ns.Theme

    local p = CreateFrame("Frame", nil, parent)
    self.panel = p
    ns.MainFrame:RegisterPanel("Run", p)

    local title = Theme:Header(p, "Current Run", 16)
    title:SetPoint("TOPLEFT", 20, -18)

    self.hint = Theme:Text(p, 11, Theme.c.fg2)
    self.hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    self.hint:SetText("Snapshot of your current character's run state and audit trail.")

    Theme:Divider(p, "TOPLEFT", "TOPRIGHT", 0, -54, 0.2)

    local left = CreateFrame("Frame", nil, p)
    left:SetPoint("TOPLEFT", 20, -64)
    left:SetPoint("BOTTOMLEFT", 20, 18)
    left:SetWidth(352)

    local right = CreateFrame("Frame", nil, p)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 16, 0)
    right:SetPoint("BOTTOMRIGHT", -20, 18)

    self.leftTitle = Theme:Text(left, 12, Theme.c.goldH)
    self.leftTitle:SetPoint("TOPLEFT", 0, 0)
    self.leftTitle:SetText("Run Snapshot")
    self.leftLines = {}
    for i = 1, 18 do
        local fs = Theme:Text(left, 11, Theme.c.fg)
        fs:SetWidth(348)
        fs:SetJustifyH("LEFT")
        if i == 1 then
            fs:SetPoint("TOPLEFT", self.leftTitle, "BOTTOMLEFT", 0, -8)
        else
            fs:SetPoint("TOPLEFT", self.leftLines[i - 1], "BOTTOMLEFT", 0, -4)
        end
        self.leftLines[i] = fs
    end

    local scroll, content = Theme:ScrollArea(right)
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    content:SetSize(372, 1)
    self.scroll = scroll
    self.content = content

    self.rightLines = {}
    local prev = nil
    for i = 1, 34 do
        local fs = Theme:Text(content, 10, Theme.c.fg2)
        fs:SetWidth(360)
        fs:SetJustifyH("LEFT")
        if i == 1 then
            fs:SetPoint("TOPLEFT", 0, -2)
        else
            fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4)
        end
        prev = fs
        self.rightLines[i] = fs
    end

    p.Refresh = function() Tab:Refresh() end
    Tab:Refresh()
end

function Tab:Refresh()
    if not self.panel then return end

    local key = ns:UnitKey()
    local rec = key and ns.Database and ns.Database.GetCharacter and ns.Database:GetCharacter(key) or nil
    if not key or not rec then
        writeLines(self.leftLines, {
            "Character: unavailable",
            "Run data has not initialized yet.",
        })
        writeLines(self.rightLines, {
            "Waiting for character record...",
        })
        self.content:SetHeight(80)
        self.scroll:SetVerticalScroll(0)
        return
    end

    local name, realm = withRealm(key)
    local runState = ns.Run and ns.Run.GetState and ns.Run:GetState(rec) or rec.status or "unknown"
    local level = rec.levelCurrent or rec.levelAtCreate or (UnitLevel and UnitLevel("player")) or "?"
    local lives = rec.livesRemaining or 0
    local profileId = (ns.Settings and ns.Settings.GetProfile and ns.Settings:GetProfile()) or "unknown"
    local profileName = (ns.Settings and ns.Settings.ProfileDisplayName and ns.Settings:ProfileDisplayName(profileId)) or profileId
    local pending = newestPendingOutgoing()
    local money, bags, total = bagEstimate()

    local left = {
        ("Character: |cffc0a060%s|r"):format(name),
        ("Class: %s"):format(classLabel(rec.class)),
        ("Level: %s"):format(tostring(level)),
        ("Realm: %s"):format(realm),
        ("Run state: %s"):format(stateLabel(runState)),
        ("Lives remaining: %d"):format(math.max(0, lives)),
        ("Profile: |cffc0a060%s|r"):format(profileName or "Unknown"),
    }

    local ruleBits = rulesSummary(3)
    for i = 1, #ruleBits do left[#left + 1] = ruleBits[i] end

    local claimBits = claimedSummary(rec, 4)
    for i = 1, #claimBits do left[#left + 1] = claimBits[i] end

    local boonBits = activeBoonsSummary(rec)
    for i = 1, #boonBits do left[#left + 1] = boonBits[i] end

    local burdenBits = activeBurdensSummary(rec)
    for i = 1, #burdenBits do left[#left + 1] = burdenBits[i] end

    left[#left + 1] = ("Estimated contribution now: %s"):format(ns.Tiers:FormatMoney(total))
    left[#left + 1] = (" - Money: %s"):format(ns.Tiers:FormatMoney(money))
    left[#left + 1] = (" - Vendorable bags: %s"):format(ns.Tiers:FormatMoney(bags))

    if pending then
        left[#left + 1] = ("Pending outgoing request: %s"):format(table.concat(pending.tierIds or {}, ", "))
        left[#left + 1] = (" - Status: %s | Sent: %s"):format(pending.status or "sent", fmtWhen(pending.when))
        left[#left + 1] = (" - Bank: %s"):format(shortName(pending.bank))
    else
        left[#left + 1] = "Pending outgoing request: none"
    end

    writeLines(self.leftLines, left)

    local right = {}
    right[#right + 1] = "|cffc0a060Legacy achievements|r"
    local achieves = achievementsSummary(6)
    for i = 1, #achieves do right[#right + 1] = achieves[i] end
    right[#right + 1] = ""
    right[#right + 1] = "|cffc0a060Recent contribution receipts|r"
    local receipts = recentReceipts(key, 5)
    for i = 1, #receipts do right[#right + 1] = receipts[i] end
    right[#right + 1] = ""
    right[#right + 1] = "|cffc0a060Recent taint/warning log entries|r"
    local warnings = recentRuleWarnings(key, 6)
    for i = 1, #warnings do right[#right + 1] = warnings[i] end

    if runState == "retired" or runState == "archived" then
        right[#right + 1] = ""
        right[#right + 1] = "|cffc0a060Death history|r"
        local deaths = recentDeaths(rec, 6)
        for i = 1, #deaths do right[#right + 1] = deaths[i] end
    end

    writeLines(self.rightLines, right)
    self.content:SetHeight(math.max(1, (#right * 16) + 20))
    self.scroll:SetVerticalScroll(0)
end
