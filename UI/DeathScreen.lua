-- UI/DeathScreen.lua
-- Hardcore-style "YOU DIED" overlay shown when the player returns to their
-- corpse after a final death (or on login when a pending un-acknowledged
-- memorial exists).
--
-- The frame is a single full-screen modal anchored to UIParent.  We build it
-- lazily on first Show() so the bootstrap path is cheap when nobody dies.
--
-- Continue button:
--   * marks the memorial acknowledged (via the onContinue callback supplied
--     by Core/Death.lua),
--   * hides the overlay,
--   * chains into the existing WRL_RETIRE_CONFIRM popup so the contribution
--     mail/skip flow proceeds as before.

local ADDON_NAME, ns = ...
local DS = ns:NewModule("DeathScreen")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function classRGB(class)
    local cc = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if cc then return cc.r or 1, cc.g or 1, cc.b or 1 end
    -- Fallback: warm gold.
    return 1.00, 0.82, 0.00
end

local function titleCase(s)
    if not s or s == "" then return s end
    return s:sub(1, 1):upper() .. s:sub(2):lower()
end

local function shortName(memorial)
    local key = memorial and memorial.characterKey or ""
    return key:match("^([^%-]+)") or key
end

local function causeOfDeath(memorial)
    if not memorial then return "Unknown" end
    if memorial.sourceName and memorial.sourceName ~= "" then
        return memorial.sourceName
    end
    if memorial.environmentalType and memorial.environmentalType ~= "" then
        return titleCase(memorial.environmentalType)
    end
    return "Unknown"
end

-- ── Frame construction ───────────────────────────────────────────────────────

local function buildFrame(self)
    if self.frame then return self.frame end
    if not CreateFrame or not UIParent then return nil end

    local Theme = ns.Theme
    local FONT_BODY   = (STANDARD_TEXT_FONT) or "Fonts\\FRIZQT__.TTF"
    -- MORPHEUS gives the ominous serif look familiar to Hardcore players.
    local FONT_HEADER = "Fonts\\MORPHEUS.TTF"

    local f = CreateFrame("Frame", "WRL_DeathScreen", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetAllPoints(UIParent)
    f:EnableMouse(true)        -- swallow clicks so the world UI is blocked
    f:Hide()

    -- Solid black backdrop. We build it manually so we don't depend on the
    -- BackdropTemplateMixin which differs across Classic flavours.
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.92)
    f._bg = bg

    -- Top accent line
    local topLine = f:CreateTexture(nil, "BORDER")
    topLine:SetColorTexture(0.78, 0.18, 0.18, 0.85)
    topLine:SetHeight(2)
    topLine:SetPoint("TOPLEFT", 0, -120)
    topLine:SetPoint("TOPRIGHT", 0, -120)
    f._topLine = topLine

    -- Bottom accent line
    local botLine = f:CreateTexture(nil, "BORDER")
    botLine:SetColorTexture(0.78, 0.18, 0.18, 0.85)
    botLine:SetHeight(2)
    botLine:SetPoint("BOTTOMLEFT", 0, 120)
    botLine:SetPoint("BOTTOMRIGHT", 0, 120)
    f._botLine = botLine

    -- "YOU DIED" headline
    local headline = f:CreateFontString(nil, "OVERLAY")
    headline:SetFont(FONT_HEADER, 64, "OUTLINE")
    headline:SetTextColor(0.90, 0.18, 0.18, 1)
    headline:SetText("YOU DIED")
    headline:SetPoint("CENTER", f, "CENTER", 0, 160)
    f._headline = headline

    -- Sub-headline
    local sub = f:CreateFontString(nil, "OVERLAY")
    sub:SetFont(FONT_BODY, 16, "")
    sub:SetTextColor(0.78, 0.74, 0.66, 1)
    sub:SetText("Your run is over.")
    sub:SetPoint("TOP", headline, "BOTTOM", 0, -8)
    f._sub = sub

    -- Character name (class-coloured)
    local name = f:CreateFontString(nil, "OVERLAY")
    name:SetFont(FONT_HEADER, 36, "OUTLINE")
    name:SetText("Adventurer")
    name:SetPoint("TOP", sub, "BOTTOM", 0, -36)
    f._name = name

    -- Race / class line
    local raceClass = f:CreateFontString(nil, "OVERLAY")
    raceClass:SetFont(FONT_BODY, 18, "")
    raceClass:SetTextColor(0.85, 0.82, 0.74, 1)
    raceClass:SetPoint("TOP", name, "BOTTOM", 0, -10)
    f._raceClass = raceClass

    -- Level + zone
    local levelZone = f:CreateFontString(nil, "OVERLAY")
    levelZone:SetFont(FONT_BODY, 16, "")
    levelZone:SetTextColor(0.70, 0.66, 0.60, 1)
    levelZone:SetPoint("TOP", raceClass, "BOTTOM", 0, -6)
    f._levelZone = levelZone

    -- Killed by
    local killedBy = f:CreateFontString(nil, "OVERLAY")
    killedBy:SetFont(FONT_BODY, 18, "")
    killedBy:SetTextColor(0.90, 0.55, 0.55, 1)
    killedBy:SetPoint("TOP", levelZone, "BOTTOM", 0, -28)
    f._killedBy = killedBy

    -- Last words (italic feel via small + dimmer colour)
    local lastWords = f:CreateFontString(nil, "OVERLAY")
    lastWords:SetFont(FONT_BODY, 14, "")
    lastWords:SetTextColor(0.65, 0.60, 0.55, 1)
    lastWords:SetWidth(700)
    lastWords:SetJustifyH("CENTER")
    lastWords:SetPoint("TOP", killedBy, "BOTTOM", 0, -16)
    f._lastWords = lastWords

    -- Lives used + tier hint
    local stats = f:CreateFontString(nil, "OVERLAY")
    stats:SetFont(FONT_BODY, 13, "")
    stats:SetTextColor(0.55, 0.52, 0.48, 1)
    stats:SetPoint("TOP", lastWords, "BOTTOM", 0, -28)
    f._stats = stats

    -- Continue button (built via Theme:Button when available, else inline).
    local btn
    if Theme and Theme.Button then
        btn = Theme:Button(f, "Continue", 200, 36)
    else
        btn = CreateFrame("Button", nil, f)
        btn:SetSize(200, 36)
        local bbg = btn:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints(btn)
        bbg:SetColorTexture(0.18, 0.18, 0.20, 1)
        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetFont(FONT_BODY, 14, "")
        label:SetText("Continue")
        label:SetPoint("CENTER")
        label:SetTextColor(0.95, 0.92, 0.84, 1)
    end
    btn:SetPoint("BOTTOM", f, "BOTTOM", 0, 180)
    f._btn = btn

    btn:SetScript("OnClick", function()
        DS:Hide()
        local cb = self._onContinue
        self._onContinue = nil
        if type(cb) == "function" then
            -- pcall so a faulty callback can never strand the player on the
            -- death screen with no way out.
            local ok, err = pcall(cb)
            if not ok and ns.Debug then ns:Debug("DeathScreen continue cb error: %s", tostring(err)) end
        end
    end)

    -- Esc key support when the client exposes keyboard propagation controls.
    if f.EnableKeyboard and f.SetPropagateKeyboardInput then
        f:EnableKeyboard(true)
        f:SetPropagateKeyboardInput(true)
        f:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then
                -- Don't propagate Esc when we consume it.
                f:SetPropagateKeyboardInput(false)
                btn:GetScript("OnClick")(btn)
            else
                f:SetPropagateKeyboardInput(true)
            end
        end)
    end

    self.frame = f
    return f
end

-- ── Public API ───────────────────────────────────────────────────────────────

--- Show the death-screen overlay populated from `memorial`.
---@param memorial   table  Memorial entry from WRL_DB.memorials
---@param snap       table  Death snapshot (preMoney/bag/gear/totalLiquid)
---@param rec        table  Character record
---@param onContinue function  Called when the player clicks Continue
function DS:Show(memorial, snap, rec, onContinue)
    if not memorial then return end
    local f = buildFrame(self)
    if not f then return end

    -- Already visible: refresh data and rebind callback (don't double-open).
    self._onContinue = onContinue

    local class = memorial.class or (rec and rec.class) or "UNKNOWN"
    local race  = memorial.race  or (rec and rec.race)  or "Unknown"
    local level = memorial.level or (rec and rec.levelCurrent) or 0
    local zone  = (memorial.zone ~= "" and memorial.zone) or "an unknown land"

    f._name:SetText(shortName(memorial))
    do
        local r, g, b = classRGB(class)
        f._name:SetTextColor(r, g, b, 1)
    end

    f._raceClass:SetFormattedText("%s %s", titleCase(race), titleCase(class))
    f._levelZone:SetFormattedText("Level %d  ·  %s", level, zone)
    f._killedBy:SetFormattedText("Slain by %s", causeOfDeath(memorial))

    if memorial.lastWords and memorial.lastWords ~= "" then
        f._lastWords:SetFormattedText("Last words: \"%s\"", memorial.lastWords)
        f._lastWords:Show()
    else
        f._lastWords:SetText("")
        f._lastWords:Hide()
    end

    local lives = memorial.livesUsed or 1
    local livesLabel = (lives == 1) and "life" or "lives"
    local liquid = (snap and snap.totalLiquid) or memorial.contributionEstimate or 0
    local liquidStr = (ns.Tiers and ns.Tiers.FormatMoney)
        and ns.Tiers:FormatMoney(liquid)
        or (tostring(liquid) .. "c")
    f._stats:SetFormattedText("%d %s used  ·  carried value: %s", lives, livesLabel, liquidStr)

    f:Show()
    if f.Raise then f:Raise() end
end

--- Hide the overlay if currently shown.
function DS:Hide()
    if self.frame then self.frame:Hide() end
end

--- Returns true when the death screen overlay is currently visible.
function DS:IsShown()
    return self.frame and self.frame:IsShown() and true or false
end

function DS:Init()
    -- Lazy: the frame is built on first Show().  Init is only here so the
    -- bootstrap call in WoWRoguelite.lua matches the pattern used by the
    -- other UI modules.
end
