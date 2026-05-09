# Legacy Unlock Tracks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single linear reward ladder with spendable account-wide Fate, Storage, and Stipend unlock tracks.

**Architecture:** Add a focused `Core/LegacyUnlocks.lua` module that owns track definitions, available-budget math, and unlock state. Keep reward contents in `Core/Rewards.lua`; requests continue to fulfill merged bundle IDs, but bundle IDs now come from unlocked legacy nodes rather than selected tier rows.

**Tech Stack:** WoW Classic Lua addon modules, SavedVariables, existing Lua harness tests in `Tests/`.

---

### Task 1: Core Legacy Economy

**Files:**
- Create: `Tests/LegacyUnlocks.test.lua`
- Create: `Core/LegacyUnlocks.lua`
- Modify: `Core/Database.lua`
- Modify: `WoWRoguelite.toc`
- Modify: `WoWRoguelite.lua`

- [ ] Write failing tests for default unlock state, available budget, next-rank unlocking, overspend rejection, active bundle IDs, and reset behavior.
- [ ] Run `lua Tests/LegacyUnlocks.test.lua` and confirm it fails because `Core/LegacyUnlocks.lua` is missing.
- [ ] Add `Core/LegacyUnlocks.lua` with `TrackDefs`, `GetRank`, `Spent`, `AvailableBudget`, `CanUnlock`, `Unlock`, `ActiveBundleIds`, and `ResetUnlocks`.
- [ ] Add schema fields `legacyUnlocks` and `legacySpent` in `Core/Database.lua`.
- [ ] Load and initialize `LegacyUnlocks` before `Rewards` consumers.
- [ ] Re-run `lua Tests/LegacyUnlocks.test.lua` and confirm it passes.

### Task 2: Reward Bundles And Request Compatibility

**Files:**
- Modify: `Core/Rewards.lua`
- Modify: `Core/Requests.lua`
- Modify: `Core/Database.lua`

- [ ] Add bundle definitions for `storage_1..6`, `stipend_1..6`, and `fate_1..2`.
- [ ] Keep old `tier_*_base` fallback bundles for compatibility with old pending requests.
- [ ] Teach request fulfillment receipts and claim tracking to treat requested IDs as generic unlock bundle IDs, while preserving `tierIds` field names for wire compatibility.
- [ ] Add tests or extend `LegacyUnlocks.test.lua` to verify active bundle merging produces Storage + Stipend + Fate contents.

### Task 3: Tiers Tab Unlock Board

**Files:**
- Modify: `UI/Tab_Tiers.lua`

- [ ] Replace the linear current/next tier display with account budget summary and three track columns.
- [ ] Show each node as locked, unlockable, or unlocked based on `LegacyUnlocks`.
- [ ] Add click handlers that call `LegacyUnlocks:Unlock(trackId)`, refresh the tab, and refresh the header.

### Task 4: New Run Request Flow

**Files:**
- Modify: `UI/Tab_NewRun.lua`

- [ ] Replace manual tier selection with a read-only active starter kit built from `LegacyUnlocks:ActiveNodes()`.
- [ ] Send a request containing all currently active unlocked node IDs.
- [ ] Keep claimed tracking so a run cannot request the same unlocked node bundle repeatedly.

### Task 5: Docs And Verification

**Files:**
- Modify: `README.md`
- Modify: `CURSEFORGE_DESCRIPTION.md`
- Modify: `SMOKE_TEST.md`

- [ ] Update docs from linear tier ladder to Fate / Storage / Stipend tracks.
- [ ] Run all Lua tests in `Tests/`.
- [ ] Search for stale wording such as “Tier ladder (v1)” and update user-facing references.
