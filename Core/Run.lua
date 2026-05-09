-- Core/Run.lua
-- Central run lifecycle state machine.
--
-- Valid states (stored in rec.status):
--   fresh                     – character registered but run not yet started
--   active                    – run is live; player is actively playing
--   dead_pending_contribution – final death reached; awaiting mail-to-bank or skip
--   retired                   – run permanently ended; contribution credited or skipped
--
-- "archived" is a derived state: never stored in rec.status.
--   It resolves from rec.isArchived == true and overrides whatever rec.status says.
--
-- Backward compatibility:
--   Stored status = "alive"   → GetState returns "active"
--   Stored status = "retired" → GetState returns "retired"
--   rec.isArchived == true    → GetState returns "archived" (overrides all)

local ADDON_NAME, ns = ...
local R = ns:NewModule("Run")

-- States that are valid for writing into rec.status.
-- "archived" is derived, never written directly.
local STORABLE_STATES = {
    fresh                    = true,
    active                   = true,
    dead_pending_contribution = true,
    retired                  = true,
}

-- Resolve a record (or character key string) to a canonical state string.
-- ALWAYS use this instead of reading rec.status directly.
function R:GetState(recOrKey)
    local rec = self:_toRec(recOrKey)
    if not rec then return nil end

    -- Archived flag takes priority over everything.
    if rec.isArchived then return "archived" end

    local s = rec.status

    -- Normalize legacy "alive" to active.
    if s == "alive" then return "active" end

    -- Known storable states pass through as-is.
    if STORABLE_STATES[s] then return s end

    -- Unknown / nil → assume active (safe default for alive-ish records).
    return "active"
end

-- Write a new state to a character record.
-- `reason` is an optional short string stored for debugging; not surfaced in UI.
-- Returns true on success, false if the write was refused.
function R:SetState(key, state, reason)
    if not STORABLE_STATES[state] then
        ns:Debug("Run:SetState – unknown state '%s' for '%s'", tostring(state), tostring(key))
        return false
    end

    local rec = ns.Database:GetCharacter(key)
    if not rec then
        ns:Debug("Run:SetState – no record for key '%s'", tostring(key))
        return false
    end

    -- Never overwrite the archived flag via SetState.
    if rec.isArchived then
        ns:Debug("Run:SetState – refused: record is archived")
        return false
    end

    local prev = self:GetState(rec)
    rec.status        = state
    rec.stateUpdatedAt = time()
    rec.stateReason   = reason or ""
    ns:Debug("Run state %s → %s (reason=%s)", tostring(prev), state, tostring(reason))
    if ns.Achievements and ns.Achievements.OnRunStateChanged then
        ns.Achievements:OnRunStateChanged(key, state, prev, reason)
    end
    return true
end

-- Returns true if the character can still earn roguelite progression credit.
-- dead_pending_contribution is NOT playable; the run is over, waiting on mail.
function R:IsPlayable(recOrKey)
    local s = self:GetState(recOrKey)
    return s == "fresh" or s == "active"
end

-- Returns true if the run is permanently over (contribution done or skipped).
-- Does NOT return true for dead_pending_contribution.
function R:IsRetired(recOrKey)
    return self:GetState(recOrKey) == "retired"
end

-- Called after all modules initialise on PLAYER_LOGIN.
-- Advances a "fresh" character to "active" so downstream modules see a clean
-- playable state without each needing to handle "fresh" as a special case.
-- Idempotent — safe to call multiple times.
function R:ActivateCurrentRunIfNeeded()
    local key = ns:UnitKey(); if not key then return end
    local rec = ns.Database:GetCurrentCharacter(); if not rec then return end
    if self:GetState(rec) == "fresh" then
        self:SetState(key, "active", "login_activate")
    end
end

-- Internal: coerce either a record table or a character key string to a record.
function R:_toRec(recOrKey)
    if type(recOrKey) == "table"  then return recOrKey end
    if type(recOrKey) == "string" then return ns.Database:GetCharacter(recOrKey) end
    return nil
end

function R:Init()
    -- No event registration needed at this time.
    -- Modules that need state information call R:GetState() or R:IsPlayable().
end
