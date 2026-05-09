-- WoWRoguelite.lua
-- Bootstrap / namespace / slash commands.
--
-- Each addon file gets two params: ADDON_NAME and a private table we all share.
-- We hang everything off that private table (ns.*) so nothing leaks into _G.

local ADDON_NAME, ns = ...

ns.name        = ADDON_NAME
ns.version     = "0.1.0"
ns.commPrefix  = "WRL_COMM" -- must be <= 16 chars for RegisterAddonMessagePrefix

-- Module registration helper. Modules call ns:NewModule("Name") and attach
-- functions to the returned table; other modules read them via ns.Name.
function ns:NewModule(name)
    local m = self[name] or {}
    self[name] = m
    return m
end

-- Print helper (quiet, prefixed). Color: GW2-ish gold.
local PREFIX = "|cffc0a060[Roguelite]|r "
function ns:Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

-- Debug gate: set WRL_DB.debug = true via slash command to enable.
function ns:Debug(msg, ...)
    if not (WRL_DB and WRL_DB.debug) then return end
    if select("#", ...) > 0 then msg = msg:format(...) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff808080[WRL]|r " .. tostring(msg))
end

-- Unit identity: "Player-Realm". Stable across logins; used as primary key.
function ns:UnitKey(unit)
    unit = unit or "player"
    local name, realm = UnitName(unit)
    if not name then return nil end
    if not realm or realm == "" then realm = GetRealmName() end
    -- Collapse spaces in realm name — Blizzard does this in cross-realm IDs.
    realm = realm:gsub("%s+", "")
    return name .. "-" .. realm
end

-- Central event frame. Individual modules register callbacks on ns:On(event, cb).
local events = CreateFrame("Frame")
local handlers = {}
events:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do list[i](...) end
end)

function ns:On(event, cb)
    if not handlers[event] then
        handlers[event] = {}
        local ok, err = pcall(events.RegisterEvent, events, event)
        if not ok then
            ns:Debug("Could not register event %s: %s", tostring(event), tostring(err))
        end
    end
    table.insert(handlers[event], cb)
end

-- PLAYER_LOGIN fires once and guarantees SavedVariables are loaded. We do
-- the real init there instead of ADDON_LOADED so all modules see a ready DB.
ns:On("PLAYER_LOGIN", function()
    ns.Database:Init()
    ns.Settings:Init()     -- must follow Database (reads WRL_DB); precedes all consumers
    ns.Run:Init()          -- must follow Database (reads records); precedes Death
    ns.Rules:Init()        -- must follow Settings (reads rule toggles); precedes event-driven modules
    ns.Boons:Init()        -- must follow Rules/Settings; re-applies selected burden rules
    ns.Tiers:Init()
    ns.LegacyUnlocks:Init()
    ns.Vendor:Init()
    ns.Contributions:Init() -- must follow Database + Vendor; used by Death
    ns.Achievements:Init()  -- must follow Contributions/Run/Rules/Tiers for criteria checks
    ns.Comm:Init()
    ns.Requests:Init()
    ns.Death:Init()
    ns.Export:Init()        -- after data modules; before UI

    -- Advance "fresh" characters to "active" now that all modules are ready.
    ns.Run:ActivateCurrentRunIfNeeded()

    ns.Theme:Init()
    ns.MainFrame:Init()

    ns:Print("v%s loaded. Type /wrl to open.", ns.version)
end)

-- Slash commands -------------------------------------------------------------
SLASH_WRL1 = "/wrl"
SLASH_WRL2 = "/roguelite"
SlashCmdList["WRL"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = rest or ""

    if cmd == "" or cmd == "show" or cmd == "toggle" then
        ns.MainFrame:Toggle()
    elseif cmd == "setbank" then
        ns.Database:SetBankCharacter(rest ~= "" and rest or ns:UnitKey())
    elseif cmd == "bank" then
        local key = WRL_DB and WRL_DB.bankCharacter
        ns:Print("Bank character: %s", key or "not set (use /wrl setbank Name-Realm)")
    elseif cmd == "request" then
        ns.MainFrame:ShowTab("NewRun")
    elseif cmd == "settings" then
        -- Print current account-wide settings to chat for debug inspection.
        local s = WRL_DB and WRL_DB.settings
        if not s then ns:Print("Settings not yet initialised."); return end
        ns:Print("=== Settings (profile: %s) ===", s.profile or "?")
        ns:Print("  allowRepeatClaims = %s", tostring(s.allowRepeatClaims))
        ns:Print("  allowBankRewards  = %s", tostring(s.allowBankRewards))
        ns:Print("  announceDeaths     = %s", tostring(s.announceDeaths))
        ns:Print("  announceSoftDeaths = %s", tostring(s.announceSoftDeaths))
        ns:Print("  uiTheme            = %s (active: %s)",
            tostring(s.uiTheme),
            ns.Theme and ns.Theme:GetActiveThemeId() or "?")
        if s.rules then
            local ruleLines = {}
            for ruleId, enabled in pairs(s.rules) do
                ruleLines[#ruleLines + 1] = string.format("    %s = %s", ruleId, tostring(enabled))
            end
            if #ruleLines > 0 then
                table.sort(ruleLines)
                ns:Print("  rules:")
                for _, line in ipairs(ruleLines) do ns:Print(line) end
            else
                ns:Print("  rules: (all defaults)")
            end
        end
    elseif cmd == "profile" then
        -- /wrl profile                → show current profile
        -- /wrl profile <id>           → apply named profile
        -- /wrl profile list           → list available profiles
        if rest == "" then
            ns:Print("Current profile: %s (%s)",
                ns.Settings:GetProfile(),
                ns.Settings:ProfileDisplayName(ns.Settings:GetProfile()))
        elseif rest == "list" then
            ns:Print("Available profiles:")
            for _, id in ipairs(ns.Settings:ProfileList()) do
                local active = (ns.Settings:GetProfile() == id) and " *" or ""
                ns:Print("  %s – %s%s", id, ns.Settings:ProfileDisplayName(id), active)
            end
        else
            if ns.Settings:ApplyProfile(rest) then
                ns:Print("Profile applied: %s (%s)", rest, ns.Settings:ProfileDisplayName(rest))
            end
        end
    elseif cmd == "rules" then
        -- /wrl rules              → show enabled rules for the current character
        -- /wrl rules log          → print recent taint/warn log entries
        -- /wrl rules log <key>    → print log for a specific character key
        if rest == "" then
            ns:Print("=== Rules (profile: %s) ===", ns.Settings:GetProfile())
            for _, def in ipairs(ns.Rules:Definitions()) do
                local on = ns.Rules:IsEnabled(def.id)
                ns:Print("  [%s] %s – %s",
                    on and "|cff00ff00ON|r" or "|cffaaaaaaOFF|r",
                    def.name,
                    def.description)
            end
            local taints = ns.Rules:TaintCount()
            ns:Print("Taint entries this character: %d", taints)
        elseif rest == "log" or rest:sub(1, 4) == "log " then
            local charKey = rest:match("^log%s+(.+)$") or ns:UnitKey()
            local log = ns.Rules:GetLog(charKey)
            if #log == 0 then
                ns:Print("No rule log entries for %s.", tostring(charKey))
            else
                ns:Print("=== Rule log: %s (%d entries) ===", charKey, #log)
                -- Print last 10 entries, newest last.
                local start = math.max(1, #log - 9)
                for i = start, #log do
                    local e = log[i]
                    local color = (e.result == "tainted" or e.result == "blocked") and "|cffff6060" or "|cffffff00"
                    ns:Print("  %s[%s]|r %s – %s (%s)",
                        color, e.result, e.ruleId, e.detail,
                        date and date("%H:%M", e.when) or tostring(e.when))
                end
            end
        else
            ns:Print("Usage: /wrl rules | /wrl rules log | /wrl rules log Name-Realm")
        end
    elseif cmd == "theme" then
        local themeId = rest:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if themeId == "" then
            ns:Print("Current UI theme: %s (active: %s)",
                ns.Theme:ThemeLabel(ns.Theme:GetSelectedThemeId()),
                ns.Theme:ThemeLabel(ns.Theme:GetActiveThemeId()))
            ns:Print("Usage: /wrl theme classic | dark | gw2")
        else
            local ok, reason = ns.Theme:SetTheme(themeId)
            if ok then
                ns:Print("UI theme set to %s. Reload UI to apply it fully.", ns.Theme:ThemeLabel(themeId))
                if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
                    ns.MainFrame:RefreshCurrentTab()
                end
            elseif reason == "gw2_unavailable" then
                ns:Print("GW2 UI theme requires the GW2_UI addon to be installed and enabled.")
            else
                ns:Print("Unknown theme %q. Use classic, dark, or gw2.", themeId)
            end
        end
    elseif cmd == "debug" then
        WRL_DB.debug = not WRL_DB.debug
        ns:Print("Debug: %s", WRL_DB.debug and "on" or "off")
    elseif cmd == "reqrefresh" or (cmd == "requests" and rest == "refresh") then
        if ns.Requests and ns.Requests.RefreshBagItemIndicators then
            ns.Requests:RefreshBagItemIndicators(true)
        else
            ns:Print("Requests module is not ready yet.")
        end
    elseif cmd == "reset" then
        if rest == "confirm" then
            wipe(WRL_DB); ns.Database:Init()
            ns:Print("Database wiped.")
        else
            ns:Print("This will wipe ALL Roguelite data. Type |cffff6060/wrl reset confirm|r to proceed.")
        end
    elseif cmd == "export" then
        -- /wrl export           → same as /wrl export run (current character)
        -- /wrl export run       → compact run summary + copyable popup
        -- /wrl export account   → account-wide legacy summary + copyable popup
        local sub = rest:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if sub == "" or sub == "run" then
            ns.Export:DoRunExport()
        elseif sub == "account" then
            ns.Export:DoAccountExport()
        else
            ns:Print("Usage: /wrl export | /wrl export run | /wrl export account")
        end
    elseif cmd == "help" then
        ns:Print("Commands:")
        ns:Print("  /wrl                - toggle window")
        ns:Print("  /wrl setbank        - mark current char as the bank")
        ns:Print("  /wrl setbank NAME   - set an external bank character")
        ns:Print("  /wrl bank           - show current bank char")
        ns:Print("  /wrl request        - open request builder (non-bank chars)")
        ns:Print("  /wrl settings       - print current settings to chat")
        ns:Print("  /wrl profile        - show active profile")
        ns:Print("  /wrl profile list   - list all profiles")
        ns:Print("  /wrl profile <id>   - apply a profile by ID")
        ns:Print("  /wrl rules          - list rules and enabled state")
        ns:Print("  /wrl rules log      - print recent taint/warn log entries")
        ns:Print("  /wrl theme <id>     - set UI theme: classic, dark, or gw2")
        ns:Print("  /wrl debug          - toggle debug logging")
        ns:Print("  /wrl reqrefresh     - refresh bag item indicators")
        ns:Print("  /wrl export         - export current run summary (opens popup)")
        ns:Print("  /wrl export run     - same as /wrl export")
        ns:Print("  /wrl export account - export account-wide legacy summary")
        ns:Print("  /wrl reset          - wipe ALL addon data (requires confirm)")
        ns:Print("  /wrl help           - show this message")
    else
        ns:Print("Unknown command: %q  —  type /wrl help for a list.", cmd)
    end
end
