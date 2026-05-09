-- UI/Tab_Requests.lua
-- Role-aware request view:
--   * bank character sees incoming requests to fulfill
--   * run characters see only their own outgoing request status once a bank is set

local ADDON_NAME, ns = ...
local Tab = ns:NewModule("Tab_Requests")

local REQ_ROW_H = 148

local function shortName(full)
    return (full and full:match("^([^-]+)")) or full or "Unknown"
end

local function tierNames(tierIds)
    local byId = {}
    for _, t in ipairs(ns.Tiers:Definitions()) do
        byId[t.id] = t
    end
    local out = {}
    for _, id in ipairs(tierIds or {}) do
        local node = ns.LegacyUnlocks and ns.LegacyUnlocks.NodeById and ns.LegacyUnlocks:NodeById(id)
        local trackId = ns.LegacyUnlocks and ns.LegacyUnlocks.TrackIdForNode and ns.LegacyUnlocks:TrackIdForNode(id)
        local track = trackId and ns.LegacyUnlocks:TrackDef(trackId)
        local t = byId[id]
        if node and track then
            out[#out + 1] = ("%s %d"):format(track.name or trackId, node.rank or 0)
        else
            out[#out + 1] = t and t.name or ("Reward " .. tostring(id))
        end
    end
    if #out == 0 then
        return "No rewards selected"
    end
    return table.concat(out, ", ")
end

local function outgoingStatusLabel(status)
    if status == "fulfilled" then return "|cff7ab27aFulfilled|r" end
    if status == "cancelled" then return "|cffb85c5cCancelled|r" end
    if status == "gathering" then return "|cffc0a060Preparing|r" end
    if status == "sent" then return "|cffc0a060Sent|r" end
    return "|cff9a948aNot sent|r"
end

local function incomingStatusLabel(status)
    if status == "gathering" then return "|cffc0a060Preparing|r" end
    if status == "fulfilled" then return "|cff7ab27aFulfilled|r" end
    if status == "cancelled" then return "|cffb85c5cCancelled|r" end
    return "|cff9a948aPending|r"
end

local function formatFulfillmentMeta(f)
    if not f then return nil end
    local bits = {}
    bits[#bits + 1] = ("Method: %s"):format(f.method or "?")
    if f.banker then bits[#bits + 1] = ("Banker: %s"):format(shortName(f.banker)) end
    if f.gold and f.gold > 0 then
        bits[#bits + 1] = ("Gold: %s"):format(ns.Tiers:FormatMoney(f.gold))
    end
    if (f.extraLives or 0) > 0 then
        bits[#bits + 1] = ("Extra lives: %d"):format(f.extraLives)
    end
    local n = #(f.items or {})
    if n > 0 then bits[#bits + 1] = ("Items in bundle: %d stack(s)"):format(n) end
    return table.concat(bits, " | ")
end

local function readinessLabel(info)
    if not info then return "|cff9a948aReadiness unavailable|r" end
    if info.fulfillable then return "|cff7ab27aReady to fulfill|r" end
    return "|cffb85c5cMissing items or gold|r"
end

local function readinessLines(req, info)
    if not info then
        return "Could not compute availability."
    end
    local lines = {}
    for _, it in ipairs(info.items or {}) do
        local color = (it.missing > 0) and "|cffb85c5c" or "|cff7ab27a"
        lines[#lines + 1] = ("%s%s|r - need %d, have %d, missing %d"):format(
            color, it.name or ("item:" .. tostring(it.id)), it.required or 0, it.available or 0, it.missing or 0
        )
    end
    if #lines == 0 then
        lines[#lines + 1] = "|cff9a948aNo item stacks in this request.|r"
    end

    local requiredGold = info.requiredGold or 0
    local availableGold = info.availableGold or 0
    local missingGold = math.max(0, requiredGold - availableGold)
    local goldColor = (missingGold > 0) and "|cffb85c5c" or "|cff7ab27a"
    lines[#lines + 1] = ("%sGold: need %s, have %s, missing %s|r"):format(
        goldColor,
        ns.Tiers:FormatMoney(requiredGold),
        ns.Tiers:FormatMoney(availableGold),
        ns.Tiers:FormatMoney(missingGold)
    )
    return table.concat(lines, "\n")
end

local function buildRow(content, Theme)
    local r = CreateFrame("Frame", nil, content)
    r:SetHeight(REQ_ROW_H)
    Theme:Fill(r, Theme.c.bg1, false)

    r.requestor = Theme:Text(r, 13, Theme.c.fg)
    r.requestor:SetPoint("TOPLEFT", 14, -10)
    r.requestor:SetWidth(150)
    r.requestor:SetJustifyH("LEFT")

    r.requested = Theme:Text(r, 12, Theme.c.fg)
    r.requested:SetPoint("TOPLEFT", 178, -10)
    r.requested:SetWidth(330)
    r.requested:SetJustifyH("LEFT")

    r.meta = Theme:Text(r, 10, Theme.c.fg2)
    r.meta:SetPoint("TOPLEFT", r.requested, "BOTTOMLEFT", 0, -6)
    r.meta:SetWidth(330)
    r.meta:SetJustifyH("LEFT")

    r.readiness = Theme:Text(r, 10, Theme.c.fg2)
    r.readiness:SetPoint("TOPLEFT", r.meta, "BOTTOMLEFT", 0, -6)
    r.readiness:SetWidth(330)
    r.readiness:SetJustifyH("LEFT")

    r.sent = Theme:Text(r, 12, Theme.c.gold)
    r.sent:SetPoint("TOPLEFT", 532, -10)
    r.sent:SetWidth(90)
    r.sent:SetJustifyH("LEFT")

    r.sentMeta = Theme:Text(r, 10, Theme.c.fg2)
    r.sentMeta:SetPoint("TOPLEFT", r.sent, "BOTTOMLEFT", 0, -6)
    r.sentMeta:SetWidth(150)
    r.sentMeta:SetJustifyH("LEFT")

    r.btnMail = Theme:Button(r, "Fulfill via Mail", 140, 22)
    r.btnMail:SetPoint("BOTTOMRIGHT", -14, 10)

    r.btnTrade = Theme:Button(r, "Trade Checklist", 140, 22)
    r.btnTrade:SetPoint("BOTTOMRIGHT", r.btnMail, "BOTTOMLEFT", -6, 0)

    r.btnDone = Theme:Button(r, "Mark Fulfilled", 120, 22)
    r.btnDone:SetPoint("BOTTOMRIGHT", r.btnTrade, "BOTTOMLEFT", -6, 0)

    r.btnCancel = Theme:Button(r, "Cancel", 70, 22)
    r.btnCancel:SetPoint("BOTTOMRIGHT", r.btnDone, "BOTTOMLEFT", -6, 0)

    return r
end

local function setBankRow(row, req)
    local Theme = ns.Theme
    local ready = nil
    if req.status ~= "fulfilled" then
        ready = ns.Requests:FulfillmentReadiness(req)
    end

    if req.status == "fulfilled" then
        Theme:Fill(row, Theme.c.bg1, false)
    elseif ready and ready.fulfillable then
        Theme:Fill(row, { 0.110, 0.150, 0.122, 1.00 }, false)
    else
        Theme:Fill(row, { 0.165, 0.120, 0.120, 1.00 }, false)
    end

    row.requestor:SetText(("|cffc0a060%s|r"):format(shortName(req.from)))
    row.requested:SetText(tierNames(req.tierIds))
    local meta = { ("%s\nvia %s"):format(date("%H:%M %b-%d", req.when), req.via or "unknown") }
    if req.storedClaimReceipts and next(req.storedClaimReceipts) then
        meta[#meta + 1] = "|cff9a948aClaim receipts stored on request (requester not in this account roster).|r"
    end
    if req.status == "fulfilled" and req.fulfillment then
        meta[#meta + 1] = ("|cff7ab27aFulfilled %s|r"):format(date("%H:%M %b-%d", req.fulfilledAt or req.fulfillment.when or time()))
        local rm = formatFulfillmentMeta(req.fulfillment)
        if rm then meta[#meta + 1] = rm end
    end
    row.meta:SetText(table.concat(meta, "\n"))
    if req.status == "fulfilled" then
        row.readiness:SetText("|cff7ab27aFulfillment recorded.|r")
    else
        row.readiness:SetText(readinessLines(req, ready))
    end
    row.sent:SetText(incomingStatusLabel(req.status))
    if req.status == "fulfilled" then
        if req.fulfillment then
            row.sentMeta:SetText(formatFulfillmentMeta(req.fulfillment) or "Recorded on this account.")
        else
            row.sentMeta:SetText("Fulfilled (details on bank account).")
        end
    elseif ready then
        row.sentMeta:SetText(readinessLabel(ready))
    elseif req.note and req.note ~= "" then
        row.sentMeta:SetText(("Note: %s"):format(req.note))
    else
        row.sentMeta:SetText("Waiting on banker fulfillment.")
    end
    if req.status == "fulfilled" then
        row.btnMail:Hide()
        row.btnTrade:Hide()
        row.btnDone:Hide()
        row.btnCancel:Hide()
    else
        row.btnMail:Show()
        row.btnTrade:Show()
        row.btnDone:Show()
        row.btnCancel:Show()
    end
end

local function setOutgoingRow(row, req)
    ns.Theme:Fill(row, ns.Theme.c.bg1, false)
    row.requestor:SetText("|cffc0a060You|r")
    row.requested:SetText(tierNames(req.tierIds))
    local metaLines = { ("Bank: %s\n%s"):format(shortName(req.bank), date("%H:%M %b-%d", req.when)) }
    if req.fulfillment and req.fulfillment.when then
        metaLines[#metaLines + 1] = ("Ack: %s"):format(date("%H:%M %b-%d", req.fulfillment.when))
    end
    row.meta:SetText(table.concat(metaLines, "\n"))
    row.readiness:SetText("")
    row.sent:SetText(outgoingStatusLabel(req.status))
    if req.fulfillment then
        row.sentMeta:SetText(formatFulfillmentMeta(req.fulfillment) or ("Status: " .. tostring(req.status)))
    elseif req.note and req.note ~= "" then
        row.sentMeta:SetText("Note: " .. req.note)
    else
        row.sentMeta:SetText("Awaiting bank confirmation (or check banker's fulfillment history if offline).")
    end
    row.btnMail:Hide()
    row.btnTrade:Hide()
    row.btnDone:Hide()
    row.btnCancel:Hide()
end

function Tab:Init(parent)
    if self.panel then return end
    local Theme = ns.Theme
    local p = CreateFrame("Frame", nil, parent)
    self.panel = p
    ns.MainFrame:RegisterPanel("Requests", p)

    local title = Theme:Header(p, "Requests", 16)
    title:SetPoint("TOPLEFT", 20, -18)

    self.hint = Theme:Text(p, 11, Theme.c.fg2)
    self.hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    self.hint:SetWidth(720)
    self.hint:SetJustifyH("LEFT")

    self.columns = CreateFrame("Frame", nil, p)
    self.columns:SetPoint("TOPLEFT", 20, -72)
    self.columns:SetPoint("TOPRIGHT", -20, -72)
    self.columns:SetHeight(18)

    self.colRequestor = Theme:Text(self.columns, 10, Theme.c.goldH)
    self.colRequestor:SetPoint("LEFT", 8, 0)
    self.colRequestor:SetText("Requestor")

    self.colRequested = Theme:Text(self.columns, 10, Theme.c.goldH)
    self.colRequested:SetPoint("LEFT", 172, 0)
    self.colRequested:SetText("Requested")

    self.colSent = Theme:Text(self.columns, 10, Theme.c.goldH)
    self.colSent:SetPoint("LEFT", 526, 0)
    self.colSent:SetText("Sent")

    Theme:Divider(p, "TOPLEFT", "TOPRIGHT", 0, -94, 0.2)

    local scroll, content = Theme:ScrollArea(p)
    scroll:SetPoint("TOPLEFT", 20, -104)
    scroll:SetPoint("BOTTOMRIGHT", -20, 16)
    content:SetSize(720, 1)
    self.scroll = scroll
    self.content = content
    self.rows = {}

    self.empty = Theme:Text(content, 12, Theme.c.fg2)
    self.empty:SetPoint("TOPLEFT", 0, -10)
    self.empty:SetWidth(700)
    self.empty:SetJustifyH("LEFT")

    -- "No bank configured" overlay.
    --
    -- IMPORTANT: bankSetupTitle/Body are FontStrings (CreateFontString).
    -- FontStrings render during their *parent* frame's draw pass.  Child
    -- frames (like `scroll`) always draw AFTER the parent, so FontStrings
    -- parented directly to `p` are permanently buried behind `scroll`.
    --
    -- Fix: wrap the overlay in a real Frame created after `scroll` and given
    -- a FrameLevel above it.  Its own FontStrings will then render on top.
    local ov = CreateFrame("Frame", nil, p)
    ov:SetPoint("TOPLEFT",    scroll, "TOPLEFT",    0, 0)
    ov:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    ov:SetFrameLevel(scroll:GetFrameLevel() + 10)
    ov:Hide()
    self.bankSetupOverlay = ov

    self.bankSetupTitle = Theme:Header(ov, "No Bank Set Up", 20)
    self.bankSetupTitle:SetPoint("CENTER", ov, "CENTER", 0, 14)

    self.bankSetupBody = Theme:Text(ov, 12, Theme.c.fg2)
    self.bankSetupBody:SetPoint("TOP", self.bankSetupTitle, "BOTTOM", 0, -10)
    self.bankSetupBody:SetWidth(520)
    self.bankSetupBody:SetJustifyH("CENTER")

    self.bankSetupCmd = Theme:Text(ov, 11, Theme.c.gold)
    self.bankSetupCmd:SetPoint("TOP", self.bankSetupBody, "BOTTOM", 0, -8)
    self.bankSetupCmd:SetJustifyH("CENTER")
    self.bankSetupCmd:SetText("/wrl setbank Name-Realm")

    -- Wire the panel's .Refresh so MainFrame:ShowTab / RefreshCurrentTab can
    -- call it.  Those methods do: self.panels[key]:Refresh()  — where the value
    -- is the raw Frame `p`, not this Tab module.  Frames have no built-in
    -- Refresh; without this line the method guard always fails silently and
    -- Tab:Refresh() is never invoked from MainFrame at all.
    p.Refresh = function() Tab:Refresh() end

    -- Prime the initial state right now (panel is hidden but frame state is
    -- set correctly so it's ready the instant it becomes visible).
    Tab:Refresh()
end

function Tab:Refresh()
    if not self.panel then return end
    local Theme = ns.Theme
    local bank = WRL_DB and WRL_DB.bankCharacter
    local isBank = ns.Database:IsBankCharacter()

    if not bank then
        self.hint:SetText("")
        self.columns:Hide()
        for _, row in ipairs(self.rows) do row:Hide() end
        self.empty:Hide()
        self.bankSetupBody:SetText("Set up a bank to get this page working.")
        self.bankSetupOverlay:Show()
        self.content:SetHeight(1)
        return
    end

    self.columns:Show()
    self.bankSetupOverlay:Hide()

    local rows = nil
    local bankView = false
    if isBank then
        bankView = true
        rows = ns.Requests:BankRequestRows()
        self.hint:SetText("Incoming and recent fulfilled requests. Completed rows stay in the bank account history.")
    else
        WRL_CharDB = WRL_CharDB or {}
        rows = WRL_CharDB.outgoing or {}
        self.hint:SetText(("Your requests to |cffc0a060%s|r. This view only shows whether you sent one."):format(bank))
    end

    if #rows == 0 then
        for _, row in ipairs(self.rows) do row:Hide() end
        self.empty:Show()
        if bankView then
            self.empty:SetText("No one has sent a request yet.")
        else
            self.empty:SetText("You have not sent a request yet.")
        end
        self.content:SetHeight(120)
        return
    end

    self.empty:Hide()

    for i = #self.rows + 1, #rows do
        self.rows[i] = buildRow(self.content, Theme)
    end
    for i = #rows + 1, #self.rows do
        self.rows[i]:Hide()
    end

    local y = 0
    for i, req in ipairs(rows) do
        local row = self.rows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", self.content, "RIGHT", -16, 0)
        row:Show()

        if bankView then
            setBankRow(row, req)
            if req.status ~= "fulfilled" then
                row.btnMail:SetScript("OnClick", function()
                    ns.Requests:BeginMailFulfillment(req.id)
                end)
                row.btnTrade:SetScript("OnClick", function()
                    ns.Requests:LoadActiveTrade()
                end)
                row.btnDone:SetScript("OnClick", function()
                    ns.Requests:MarkFulfilled(req.id)
                    Tab:Refresh()
                end)
                row.btnCancel:SetScript("OnClick", function()
                    ns.Requests:SetStatus(req.id, "cancelled")
                    Tab:Refresh()
                end)
            end
        else
            setOutgoingRow(row, req)
        end

        y = y + REQ_ROW_H + 4
    end

    self.content:SetHeight(math.max(1, y))
end
