# Step 12: Boon And Burden System — Implementation Design

**Author:** Claude Sonnet 4.6  
**Status:** Design only — implementation by Cursor Auto  
**Depends on:** Steps 1–8 (Database, Run, Settings, Rules, Requests, Tab_NewRun, Tab_Run)

---

## 1. Architecture Principle

Boons and burdens are **run-start configuration choices**, not a parallel system. They fold into three existing mechanisms:

| Concept | Existing system it reuses |
|---|---|
| Burden enforcement | `Core/Rules.lua` — each burden enables a rule ID |
| Boon reward effects | `Core/Requests.lua` — `R:Bundle()` calls `Boons:ApplyToBundle()` |
| Extra-life boon | `rec.livesRemaining` — already incremented by the mail/trade fulfillment path |
| Persistence | `rec.boons` / `rec.burdens` on the character record in `WRL_DB.characters` |
| Lock signal | `next(rec.claimedTiers) ~= nil` — locked when the first tier reward is claimed |

One new file (`Core/Boons.lua`) owns definitions and helpers. No existing module is rewritten.

---

## 2. Data Shapes

### 2.1 Per-character record additions

Added to `newCharRecord()` in `Database.lua` and lazy-migrated in `Database:Init()`:

```lua
rec.boons   = {}   -- [boonId]   = { selectedAt = timestamp }
rec.burdens = {}   -- [burdenId] = { selectedAt = timestamp }
```

Keyed by ID for O(1) lookup. `selectedAt` is recorded so the memorial (Step 11) can include active modifiers at time of death.

### 2.2 Schema version

Bump `SCHEMA_VERSION` from `7` → `8` in `Database.lua`.

Migration block:

```lua
if WRL_DB.schema < 8 then
    for _, rec in pairs(WRL_DB.characters or {}) do
        rec.boons   = rec.boons   or {}
        rec.burdens = rec.burdens or {}
    end
end
```

Also add to the lazy-migration loop in `Database:EnsureCharacter()`:

```lua
if rec.boons   == nil then rec.boons   = {} end
if rec.burdens == nil then rec.burdens = {} end
```

### 2.3 Boon definition shape (in `Core/Boons.lua`)

```lua
{
    id          = "one_extra_life",
    name        = "One Extra Life",
    description = "Your starter reward includes one additional life.",
    -- Reward effect fields (mutually exclusive with each other, any can be nil/0):
    livesBonus  = 1,          -- added to bundle.extraLives in ApplyToBundle
    goldBonus   = 0,          -- added to bundle.gold (copper)
    extraItems  = {},         -- { { id = itemId, qty = n, note = "..." } } appended to bundle.items
}
```

### 2.4 Burden definition shape (in `Core/Boons.lua`)

```lua
{
    id          = "no_auction_house",
    name        = "No Auction House",
    description = "Prohibits using the Auction House during your run.",
    ruleId      = "no_auction_house",   -- rules.lua rule this burden activates; nil if none
}
```

Burdens with a `ruleId` cause `Boons:ApplyBurdenRules()` to call `Settings:SetRuleEnabled(ruleId, true)`. Burdens without a `ruleId` are purely cosmetic/informational for now (future rule additions can wire them later).

---

## 3. Definitions

### 3.1 Initial boons (4)

| id | name | livesBonus | goldBonus | extraItems |
|---|---|---|---|---|
| `extra_starter_bag` | Extra Starter Bag | 0 | 0 | `{ id = 4496, qty = 1, note = "10-slot bag" }` |
| `potion_cache` | Potion Cache | 0 | 0 | `{ id = 858, qty = 5, note = "Minor Health Potion" }` |
| `profession_stipend` | Profession Stipend | 0 | 50000 | — (50s copper) |
| `one_extra_life` | One Extra Life | 1 | 0 | — |

Item IDs are Classic-era placeholders — Cursor Auto should verify against `Core/Tiers.lua` item IDs that are already in use and adjust as needed.

### 3.2 Initial burdens (5)

| id | name | ruleId |
|---|---|---|
| `no_auction_house` | No Auction House | `no_auction_house` |
| `no_non_bank_trade` | No Non-Bank Trade | `no_trade_except_bank` |
| `no_grouping` | No Grouping | `no_grouping` |
| `no_dungeon_repeats` | No Dungeon Repeats | `no_dungeon_repeats` |
| `white_green_only` | White/Green Gear Only | `white_green_only` *(new rule, see §5)* |

All five burdens map to rule IDs. The first four exist in `Rules.lua` already. The fifth needs a new lightweight rule definition added there (see §5).

---

## 4. Module: `Core/Boons.lua`

**Load position in TOC:** after `Core/Rules.lua`, before `Core/Requests.lua`.

```lua
Core/Rules.lua
Core/Boons.lua      -- NEW
Core/Tiers.lua
```

### 4.1 Public API

```lua
-- Returns true when boons/burdens are locked for this character.
-- Lock condition: at least one tier has been claimed OR run is retired/archived.
ns.Boons:IsLocked(charKey)  → bool

-- Returns the boon/burden definition tables (for UI iteration).
ns.Boons:BoonDefs()   → ordered list of boon def tables
ns.Boons:BurdenDefs() → ordered list of burden def tables

-- Returns definition for a single id, or nil.
ns.Boons:GetBoonDef(boonId)     → def or nil
ns.Boons:GetBurdenDef(burdenId) → def or nil

-- Test if a boon/burden is currently selected.
ns.Boons:HasBoon(charKey, boonId)     → bool
ns.Boons:HasBurden(charKey, burdenId) → bool

-- Replace the full boon or burden selection for a character.
-- Returns false (no-op) when IsLocked() is true.
-- Immediately calls ApplyBurdenRules() after a burden change.
ns.Boons:SetBoons(charKey, boonIdList)     → true | false
ns.Boons:SetBurdens(charKey, burdenIdList) → true | false

-- Mutates `bundle` in-place by adding boon effects for the requester.
-- Called from R:Bundle(req) immediately after bundleForTiers().
ns.Boons:ApplyToBundle(bundle, charKey)

-- Enable rule IDs in Settings for all active burdens on this character.
-- Called on login (Init) and whenever SetBurdens() succeeds.
-- Additive only — never disables rules the player turned on separately.
ns.Boons:ApplyBurdenRules(charKey)

-- Module init. Called from WoWRoguelite.lua PLAYER_LOGIN block.
ns.Boons:Init()
```

### 4.2 `IsLocked` implementation

```lua
function Boons:IsLocked(charKey)
    charKey = charKey or ns:UnitKey()
    local rec = ns.Database and ns.Database:GetCharacter(charKey)
    if not rec then return true end           -- unknown char = treat as locked
    if next(rec.claimedTiers or {}) then return true end  -- any claim = locked
    local state = ns.Run and ns.Run:GetState(rec) or rec.status
    return state == "retired" or state == "archived"
end
```

### 4.3 `ApplyToBundle` implementation

```lua
function Boons:ApplyToBundle(bundle, charKey)
    if not charKey or not bundle then return end
    local rec = ns.Database and ns.Database:GetCharacter(charKey)
    if not rec or not rec.boons then return end

    for boonId in pairs(rec.boons) do
        local def = boonById[boonId]
        if def then
            if (def.livesBonus or 0) > 0 then
                bundle.extraLives = (bundle.extraLives or 0) + def.livesBonus
            end
            if (def.goldBonus or 0) > 0 then
                bundle.gold = (bundle.gold or 0) + def.goldBonus
            end
            for _, it in ipairs(def.extraItems or {}) do
                -- De-duplicate by item ID, summing qty.
                local found = false
                for _, existing in ipairs(bundle.items) do
                    if existing.id == it.id then
                        existing.qty = existing.qty + it.qty
                        found = true; break
                    end
                end
                if not found then
                    bundle.items[#bundle.items + 1] = { id = it.id, qty = it.qty, note = it.note }
                end
            end
        end
    end
end
```

### 4.4 `Init` (called on PLAYER_LOGIN)

```lua
function Boons:Init()
    local key = ns:UnitKey()
    if key then self:ApplyBurdenRules(key) end
end
```

This re-applies burden rules each login so a player who selected burdens before Step 12 was installed doesn't lose them.

---

## 5. Rules.lua addition: `white_green_only`

Add one entry to `RULE_DEFS` in `Core/Rules.lua`. It is **programmatic only** (no WoW event subscription) — the same pattern as `no_repeat_claims`. Automated detection of equipped item quality on every equip event is complex and deferred; this burden is logged/advisory for now.

```lua
{
    id          = "white_green_only",
    name        = "White/Green Gear Only",
    description = "Only white (common) or green (uncommon) quality gear may be worn.",
    default     = false,
    severity    = "warn",
    events      = {},     -- programmatic; no automatic detection yet
    handler     = nil,
},
```

`ruleById["white_green_only"]` will be set. `Rules:IsEnabled("white_green_only")` works. The burden wires it on; future steps can add an event handler to `ITEM_EQUIPMENT_CHANGED` or `UNIT_INVENTORY_CHANGED` for detection.

---

## 6. Requests.lua patch

Replace the existing `R:Bundle()` with:

```lua
function R:Bundle(req)
    local bundle = bundleForTiers(req.tierIds)
    -- Apply boon reward modifiers for the requester (Step 12).
    if ns.Boons then
        ns.Boons:ApplyToBundle(bundle, req.from)
    end
    return bundle
end
```

This is the **only** change to `Requests.lua`. `FulfillmentReadiness`, `BeginMailFulfillment`, `LoadActiveTrade`, and `MarkFulfilled` all call `R:Bundle()` already, so they inherit boon effects automatically.

---

## 7. UI Placement

### 7.1 Tab_NewRun.lua — Boons & Burdens section

Insert a new section between `self.sectionLabel` ("Available Rank Rewards") and the tier scroll area. The section adds:

- A header label: **"Run Modifiers"**
- A sub-label: `"Locked once your first rank reward is claimed."`
- Two side-by-side sub-panels (each ~340px wide):
  - **Left — Boons** (up to 4 rows, one per boon)
  - **Right — Burdens** (up to 5 rows, one per burden)
- Each row: a small checkbox square + name + short description + toggle behavior
- When locked: rows render at 0.5 alpha, click does nothing, label shows `"LOCKED"`

**Layout approach:** mirror the existing `buildOptRow` pattern from the tier rows but at a smaller height (`~32px`). Keep `ROW_ICON_SIZE` and icon approach only for the tier section above.

**Lock enforcement:** `Tab:Refresh()` calls `ns.Boons:IsLocked(charKey)`. When true, all modifier rows are non-interactive.

**Scroll area adjustment:** the new section is fixed-height (does not scroll with the tiers). Adjust the scroll area's `SetPoint("TOPLEFT", ...)` anchor to account for the added height.

Estimated height of modifier section: `~32 * 5 + 28 (header) = ~190px`. The tier scroll area should be shrunk by this amount. Test that content still fits inside the 780×480 frame.

### 7.2 Tab_Run.lua — active modifier display

In `Tab:Refresh()`, add two lines to the `left` table after the profile/rules block:

```lua
local boonBits = activeBoonsSummary(rec)      -- helper below
for i = 1, #boonBits do left[#left + 1] = boonBits[i] end

local burdenBits = activeBurdensSummary(rec)  -- helper below
for i = 1, #burdenBits do left[#left + 1] = burdenBits[i] end
```

**`activeBoonsSummary(rec)` helper** (local function in Tab_Run.lua):

```lua
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
```

Same pattern for `activeBurdensSummary`.

---

## 8. TOC Load Order

```
# --- Core ---
Core/Database.lua
Core/Settings.lua
Core/Run.lua
Core/Rules.lua
Core/Boons.lua        ← insert here
Core/Tiers.lua
Core/Vendor.lua
Core/Contributions.lua
Core/Comm.lua
Core/Requests.lua
Core/Death.lua
```

`Boons.lua` must load after `Rules.lua` (uses `ruleById` indirectly via `Settings:SetRuleEnabled`) and before `Requests.lua` (which calls `Boons:ApplyToBundle`).

---

## 9. Migration & Edge Cases

| Scenario | Behaviour |
|---|---|
| Old character, no `rec.boons` / `rec.burdens` | Lazy-migrated to `{}` in both schema migration and `EnsureCharacter()`. No boons/burdens active. `IsLocked()` checks `claimedTiers`; if any exist, locked (correct). |
| Old character with claims, no boons chosen | Locked immediately. Read-only display in UI. |
| New character, no claims yet | Unlocked. Can freely pick boons/burdens before sending first request. |
| Player picks a burden that maps to an already-enabled rule | `SetRuleEnabled(ruleId, true)` is idempotent. No conflict. |
| Player picks a burden, then disables the rule in the Rules tab | The rule is disabled at the Settings level. On next login, `Boons:Init()` re-enables it. Within the session, the rule stays disabled until reload. Document this in the UI: "Burden rules re-apply on login." |
| Bank character | `IsLocked()` returns `true` for bank chars (they have no boons/burdens; `rec.claimedTiers` is typically empty but banks should not pick modifiers). Guard: also return `true` if `ns.Database:IsBankCharacter()`. |
| `one_extra_life` boon with off-account requester | `R:Bundle()` calls `ApplyToBundle(bundle, req.from)`. If the requester record doesn't exist on this account, `GetCharacter(req.from)` returns nil, `ApplyToBundle` is a no-op. The extra life is not applied. This is correct: off-account boons cannot be verified. Document in UI: "Boon effects require bank to have requester on same account." |
| Multiple boons all granting `extraItems` with same item ID | `ApplyToBundle` de-duplicates by ID and sums qty. Correct. |
| Character retired before choosing boons | `IsLocked()` catches `retired` state. UI shows read-only with no boons. |

---

## 10. Acceptance Checks (for Cursor Auto verification)

1. A fresh character with no claimed tiers can open Tab_NewRun and select boons/burdens. Choices persist after `/reload`.
2. After sending the first request (which triggers a claim on fulfillment), re-opening Tab_NewRun shows modifier rows at 50% alpha and non-interactive.
3. Selecting the `no_auction_house` burden and reloading causes `Rules:IsEnabled("no_auction_house")` to return `true`.
4. Selecting the `one_extra_life` boon and having the bank fulfill a request causes the bundle to include `extraLives = 1` (visible in the fulfillment chat output from `BeginMailFulfillment`).
5. Tab_Run left column shows active boons and burdens for the current character.
6. Old characters without `rec.boons` / `rec.burdens` load without Lua errors.
7. Bank character's Tab_NewRun modifier section is either hidden or fully locked.
8. Syntax pass: no undefined symbols (`ns.Boons` called before `Boons:Init()` is reachable), no duplicate function names, TOC includes `Core/Boons.lua` in the correct position.

---

## 11. What This Design Deliberately Excludes

- **No per-boon conflict checking** (e.g., no rule that says "you can't take both `potion_cache` and `profession_stipend`"). Add if the game design requires it; the lock signal is already in `IsLocked()`.
- **No server-side grant assumptions.** `one_extra_life` increments `rec.livesRemaining` through the normal `bundle.extraLives` path in `MarkFulfilled`/`BeginMailFulfillment`. The bank must manually fulfill as with any reward.
- **No automated gear-quality enforcement** for `white_green_only`. The rule is defined and wirable; detection is a follow-up.
- **No boon-count limit enforcement in code.** The definitions list 4 boons; the UI can choose to allow 0–4 picks or set a cap; the data layer is unconstrained.

---

## 12. Universal Prompt Addendum

Important working rules:

- Work inside this project only: `C:\Users\Paulius\Documents\Claude\Projects\WoW Roguelite\WoWRoguelite`
- This is a WoW Classic TBC addon. Respect Blizzard addon restrictions: do not attempt protected automation such as auto-clicking Send Mail, accepting trades, or changing server state.
- Preserve existing behavior unless the prompt explicitly asks to change it.
- Do not rewrite the whole addon. Make focused changes that fit the current module style.
- Before editing, inspect relevant files with search/read tools. Do not assume APIs or structures.
- Avoid duplicate systems. If a helper already exists, reuse or extend it.
- Keep SavedVariables migrations backward compatible. Never wipe existing user data.
- Add small comments only where they clarify non-obvious logic.
- If the answer or diff would be too large or truncated, stop generating prose and edit files directly. Then summarize changed files and key decisions.
- If you hit truncation, resume from the last completed file and explicitly say which file/function you are continuing.
- Do not leave placeholder code, TODO-only implementations, or half-wired UI.
- After implementation, run a syntax-oriented sanity pass by searching for missing module references, undefined obvious symbols, duplicate function names, and broken TOC ordering.
- Provide a concise final summary with: changed files, behavior added, migration notes, and manual in-game test steps.
- If uncertain about a WoW API, isolate the risky call behind a helper and add a fallback path rather than spreading assumptions through the codebase.
