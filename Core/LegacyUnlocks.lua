-- Core/LegacyUnlocks.lua
-- Account-wide spendable legacy progression. Lifetime contributions create a
-- budget; players spend that budget into Storage, Stipend, and Fate tracks.

local ADDON_NAME, ns = ...
local L = ns:NewModule("LegacyUnlocks")

local function g(gold) return gold * 10000 end

local TRACK_ORDER = { "storage", "stipend", "fate" }

local TRACK_DEFS = {
    storage = {
        id = "storage",
        name = "Storage",
        blurb = "Bags and space for cleaner starts.",
        nodes = {
            { rank = 1, nodeId = 101, cost = g(3),   bundleId = "storage_1", name = "Satchel Start" },
            { rank = 2, nodeId = 102, cost = g(10),  bundleId = "storage_2", name = "Traveler Space" },
            { rank = 3, nodeId = 103, cost = g(25),  bundleId = "storage_3", name = "Campaign Bags" },
            { rank = 4, nodeId = 104, cost = g(75),  bundleId = "storage_4", name = "Deep Run Packs" },
            { rank = 5, nodeId = 105, cost = g(250), bundleId = "storage_5", name = "Outland Packs" },
            { rank = 6, nodeId = 106, cost = g(750), bundleId = "storage_6", name = "Legacy Haul" },
        },
    },
    stipend = {
        id = "stipend",
        name = "Stipend",
        blurb = "Starter gold for training, travel, and setup choices.",
        nodes = {
            { rank = 1, nodeId = 201, cost = g(3),   bundleId = "stipend_1", name = "Seed Purse" },
            { rank = 2, nodeId = 202, cost = g(10),  bundleId = "stipend_2", name = "Training Fund" },
            { rank = 3, nodeId = 203, cost = g(25),  bundleId = "stipend_3", name = "Mount Prep" },
            { rank = 4, nodeId = 204, cost = g(75),  bundleId = "stipend_4", name = "Campaign Fund" },
            { rank = 5, nodeId = 205, cost = g(250), bundleId = "stipend_5", name = "Epic Reserve" },
            { rank = 6, nodeId = 206, cost = g(750), bundleId = "stipend_6", name = "Legacy Treasury" },
        },
    },
    fate = {
        id = "fate",
        name = "Fate",
        blurb = "Rare extra-life milestones. Powerful, expensive, and sparse.",
        nodes = {
            { rank = 1, nodeId = 301, cost = g(25),  bundleId = "fate_1", name = "Second Thread", milestone = 3 },
            { rank = 2, nodeId = 302, cost = g(750), bundleId = "fate_2", name = "Last Thread", milestone = 6 },
        },
    },
}

local nodeById = {}
local nodeTrackById = {}
for _, trackId in ipairs(TRACK_ORDER) do
    for _, node in ipairs(TRACK_DEFS[trackId].nodes) do
        nodeById[node.nodeId] = node
        nodeTrackById[node.nodeId] = trackId
    end
end

local function ensureState()
    WRL_DB = WRL_DB or {}
    WRL_DB.legacyUnlocks = WRL_DB.legacyUnlocks or {}
    for _, trackId in ipairs(TRACK_ORDER) do
        if WRL_DB.legacyUnlocks[trackId] == nil then
            WRL_DB.legacyUnlocks[trackId] = 0
        end
    end
    WRL_DB.legacySpent = math.max(0, math.floor(WRL_DB.legacySpent or 0))
end

local function copyNode(node)
    local out = {}
    for k, v in pairs(node or {}) do out[k] = v end
    return out
end

function L:Init()
    ensureState()
end

function L:TrackOrder()
    return TRACK_ORDER
end

function L:TrackDef(trackId)
    return TRACK_DEFS[trackId]
end

function L:TrackDefs()
    return TRACK_DEFS
end

function L:NodeById(nodeId)
    nodeId = tonumber(nodeId)
    return nodeId and nodeById[nodeId] or nil
end

function L:TrackIdForNode(nodeId)
    nodeId = tonumber(nodeId)
    return nodeId and nodeTrackById[nodeId] or nil
end

function L:GetRank(trackId)
    ensureState()
    return math.max(0, math.floor(WRL_DB.legacyUnlocks[trackId] or 0))
end

function L:MaxRank(trackId)
    local def = TRACK_DEFS[trackId]
    return def and #def.nodes or 0
end

function L:Spent()
    ensureState()
    return WRL_DB.legacySpent or 0
end

function L:AvailableBudget()
    ensureState()
    local total = 0
    if ns.Database and ns.Database.TotalContributed then
        total = ns.Database:TotalContributed() or 0
    elseif WRL_DB then
        total = WRL_DB.totalContributed or 0
    end
    return math.max(0, math.floor(total - self:Spent()))
end

function L:NextNode(trackId)
    local def = TRACK_DEFS[trackId]
    if not def then return nil end
    return def.nodes[self:GetRank(trackId) + 1]
end

function L:CanUnlock(trackId)
    local node = self:NextNode(trackId)
    if not node then return false, "max_rank" end
    if self:AvailableBudget() < (node.cost or 0) then
        return false, "insufficient_budget", node
    end
    return true, nil, node
end

function L:Unlock(trackId)
    local ok, reason, node = self:CanUnlock(trackId)
    if not ok then return false, reason, node end
    ensureState()
    WRL_DB.legacyUnlocks[trackId] = self:GetRank(trackId) + 1
    WRL_DB.legacySpent = self:Spent() + (node.cost or 0)
    return true, nil, copyNode(node)
end

function L:ResetUnlocks()
    WRL_DB.legacyUnlocks = {}
    for _, trackId in ipairs(TRACK_ORDER) do
        WRL_DB.legacyUnlocks[trackId] = 0
    end
    WRL_DB.legacySpent = 0
end

function L:ActiveNodes()
    ensureState()
    local out = {}
    for _, trackId in ipairs(TRACK_ORDER) do
        local def = TRACK_DEFS[trackId]
        local rank = math.min(self:GetRank(trackId), #def.nodes)
        for i = 1, rank do
            local node = copyNode(def.nodes[i])
            node.trackId = trackId
            node.trackName = def.name
            out[#out + 1] = node
        end
    end
    return out
end

function L:ActiveNodeIds()
    local out = {}
    for _, node in ipairs(self:ActiveNodes()) do
        out[#out + 1] = node.nodeId
    end
    return out
end

function L:BundleIdsForNodeIds(nodeIds)
    local out = {}
    for _, nodeId in ipairs(nodeIds or {}) do
        local node = self:NodeById(nodeId)
        if node and node.bundleId then
            out[#out + 1] = node.bundleId
        end
    end
    return out
end
