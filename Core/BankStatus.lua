-- Core/BankStatus.lua
-- Best-effort online status for the configured bank character.

local ADDON_NAME, ns = ...
local B = ns:NewModule("BankStatus")

local PRESENCE_TTL = 90
local PING_COOLDOWN = 30
local seenAtByKey = {}
local pingedAtByKey = {}

local function stripRealm(key)
    return (key and key:match("^([^-]+)")) or key
end

local function normName(name)
    if not name then return nil end
    return tostring(name):lower():gsub("%s+", "")
end

local function sameCharacter(a, b)
    if not a or not b then return false end
    local an = normName(stripRealm(a))
    local bn = normName(stripRealm(b))
    return an ~= nil and an == bn
end

local function now()
    return time and time() or 0
end

local function guildStatus(bankKey)
    if not bankKey then return nil end
    if GuildRoster then GuildRoster() end
    local n = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if sameCharacter(name, bankKey) then
            return online and "online" or "offline", "guild"
        end
    end
    return nil
end

local function friendStatus(bankKey)
    if not bankKey then return nil end
    local n = GetNumFriends and GetNumFriends() or 0
    for i = 1, n do
        local name, _, _, _, connected = GetFriendInfo(i)
        if sameCharacter(name, bankKey) then
            return connected and "online" or "offline", "friends"
        end
    end
    return nil
end

function B:MarkSeen(bankKey, when)
    if not bankKey or bankKey == "" then return end
    seenAtByKey[normName(bankKey)] = when or now()
    if ns.Debug then
        ns:Debug("BankStatus: saw addon presence from %s", tostring(bankKey))
    end
    self:NotifyChanged()
end

function B:Ping(bankKey)
    if not bankKey or bankKey == "" then return false end
    if ns.Database and ns.Database.IsBankCharacter and ns.Database:IsBankCharacter() then return false end
    local key = normName(bankKey)
    local t = now()
    if pingedAtByKey[key] and (t - pingedAtByKey[key]) < PING_COOLDOWN then return false end
    pingedAtByKey[key] = t
    if ns.Debug then
        ns:Debug("BankStatus: pinging %s for addon presence", tostring(bankKey))
    end
    if ns.Comm and ns.Comm.SendPresencePing then
        return ns.Comm:SendPresencePing(bankKey)
    end
    return false
end

function B:Init()
    if ns.On then
        ns:On("GUILD_ROSTER_UPDATE", function() self:NotifyChanged() end)
        ns:On("FRIENDLIST_UPDATE", function() self:NotifyChanged() end)
        ns:On("PLAYER_ENTERING_WORLD", function()
            if GuildRoster then GuildRoster() end
            self:NotifyChanged()
        end)
    end
end

function B:NotifyChanged()
    if ns.MainFrame and ns.MainFrame.RefreshHeader then
        ns.MainFrame:RefreshHeader()
    end
    if ns.MainFrame and ns.MainFrame.RefreshCurrentTab then
        ns.MainFrame:RefreshCurrentTab()
    end
end

function B:Status(bankKey)
    bankKey = bankKey or (WRL_DB and WRL_DB.bankCharacter)
    if not bankKey or bankKey == "" then
        return "missing", "No bank set"
    end
    if ns.Database and ns.Database.IsBankCharacter and ns.Database:IsBankCharacter() then
        return "self", "This character"
    end

    local status, source = guildStatus(bankKey)
    if status then
        return status, status == "online" and "Online (guild)" or "Offline (guild)", source
    end

    status, source = friendStatus(bankKey)
    if status then
        return status, status == "online" and "Online (friends)" or "Offline (friends)", source
    end

    local seenAt = seenAtByKey[normName(bankKey)]
    if seenAt and (now() - seenAt) <= PRESENCE_TTL then
        return "online", "Online (addon)", "addon"
    end

    self:Ping(bankKey)
    return "unknown", "Unknown"
end

function B:IsProbablyOnline(bankKey)
    local status = self:Status(bankKey)
    return status == "online" or status == "self"
end

function B:ShouldOfferMailFallback(bankKey)
    local status = self:Status(bankKey)
    return status == "offline" or status == "unknown"
end
