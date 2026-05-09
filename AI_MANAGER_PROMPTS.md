# WoW Roguelite AI Manager Prompts

This file turns the addon roadmap into assignable implementation prompts for:

- **Codex**: best for integration, architecture guardrails, final code review, and end-to-end consistency.
- **Claude Sonnet 4.6**: best for careful design, schema thinking, edge-case analysis, and writing focused implementation plans.
- **Cursor Auto**: best for editing across the codebase once the design is clear, especially UI wiring and repetitive Lua changes.

Use these prompts in order unless you intentionally change the roadmap. The ordering is chosen to reduce redundancy: first establish stable data contracts, then rule/toggle architecture, then UI and quality-of-life features.

## Universal Prompt Addendum

Append this section to every AI prompt below.

```text
Important working rules:

- Work inside this project only: C:\Users\Paulius\Documents\Claude\Projects\WoW Roguelite\WoWRoguelite
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
```

## Current Architecture Snapshot

Existing files:

```text
WoWRoguelite.lua
WoWRoguelite.toc
Core/Database.lua
Core/Tiers.lua
Core/Vendor.lua
Core/Comm.lua
Core/Requests.lua
Core/Death.lua
UI/Theme.lua
UI/MainFrame.lua
UI/Tab_Contributions.lua
UI/TierDisplay.lua
UI/Tab_Tiers.lua
UI/Tab_Requests.lua
UI/Tab_NewRun.lua
```

Target architecture over time:

```text
Core/Database.lua
Core/Settings.lua
Core/Run.lua
Core/Rules.lua
Core/Rewards.lua
Core/Contributions.lua
Core/Tiers.lua
Core/Vendor.lua
Core/Comm.lua
Core/Requests.lua
Core/Death.lua

UI/Tab_Run.lua
UI/Tab_Rules.lua
UI/Tab_Requests.lua
UI/Tab_Tiers.lua
UI/Tab_Contributions.lua
UI/Tab_NewRun.lua
```

Do not create all target files at once unless the task requires it. The goal is incremental structure.

---

# Step 1: Run State Model

**Owner:** Claude Sonnet 4.6  
**Backup/Integrator:** Codex  
**Priority:** Highest  
**Depends on:** Nothing

## Goal

Design and implement a central run lifecycle model so all later systems can reason about the current character without duplicating status logic.

Current status is mostly `"alive"` / `"retired"`. Replace that with a richer but backward-compatible model:

- `fresh`
- `active`
- `dead_pending_contribution`
- `retired`
- `archived`

## Likely Files

- `Core/Database.lua`
- `Core/Death.lua`
- new optional `Core/Run.lua`
- `WoWRoguelite.toc`
- `WoWRoguelite.lua`
- UI files only if needed for labels

## Prompt

```text
Implement Step 1: Run State Model for the WoW Roguelite addon.

First inspect Core/Database.lua, Core/Death.lua, WoWRoguelite.lua, and WoWRoguelite.toc. Then add a central run lifecycle model with states: fresh, active, dead_pending_contribution, retired, archived.

Preferred approach:
- Add Core/Run.lua if it keeps lifecycle code cleaner.
- Keep Database.lua responsible for persistence and migrations.
- Keep Death.lua responsible for reacting to PLAYER_DEAD and mailbox events, but move generic run-state decisions into Run.lua.
- Preserve backward compatibility with existing records whose status is "alive" or "retired".
- Make archived records resolve to archived state when rec.isArchived is true.
- Ensure new characters get a sensible initial state.
- Add helpers like:
  - ns.Run:GetState(recOrKey)
  - ns.Run:SetState(key, state, reason)
  - ns.Run:IsPlayable(recOrKey)
  - ns.Run:IsRetired(recOrKey)
  - ns.Run:ActivateCurrentRunIfNeeded()
- Ensure PLAYER_LOGIN initializes the module in the right order.
- Ensure final death transitions to dead_pending_contribution before contribution mail, then retired after contribution is credited or skipped.
- Avoid changing tier/reward behavior in this step.

Acceptance checks:
- Existing SavedVariables with status="alive" still work.
- Existing retired characters still show as retired.
- Archived records still sort/display correctly.
- A final death no longer jumps straight past the pending contribution concept.
- No nil module calls during PLAYER_LOGIN.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 2: Claim Tracking

**Owner:** Cursor Auto  
**Backup/Integrator:** Codex  
**Priority:** Highest  
**Depends on:** Step 1

## Goal

Prevent repeat starter-kit requests and create a clean data structure for future toggles.

## Data Shape

Per character record:

```lua
claimedTiers = {
    [tierId] = {
        when = timestamp,
        requestId = "...",
        fulfilledBy = "Bank-Realm",
        method = "mail" or "trade" or "manual",
    }
}
```

## Likely Files

- `Core/Database.lua`
- `Core/Requests.lua`
- `UI/Tab_NewRun.lua`
- `UI/Tab_Requests.lua`

## Prompt

```text
Implement Step 2: Claim Tracking.

Inspect Database.lua, Requests.lua, Tab_NewRun.lua, and Tab_Requests.lua. Add per-character claimed tier tracking so each run character can only claim each unlocked tier once unless a future setting explicitly allows repeats.

Requirements:
- Add claimedTiers to new character records.
- Lazy-migrate existing records by adding claimedTiers = {} when missing.
- Add Database or Rewards helper functions:
  - HasClaimedTier(characterKey, tierId)
  - MarkTierClaimed(characterKey, tierId, claimInfo)
  - ClaimedTierIds(characterKey)
- Update New Run UI so claimed tiers are visually disabled or labelled "CLAIMED".
- Prevent Send Request from including claimed tiers.
- Update request fulfillment so Mark Fulfilled records claims for the requester.
- If the requester record is not available on the bank account, store enough receipt data on the request anyway and do not error.
- Do not remove current request flow or mail/trade helper behavior.

Acceptance checks:
- A character cannot request the same tier twice through the UI.
- If a duplicate request already exists, bank-side fulfillment does not crash.
- Claim state survives reload.
- Existing characters without claimedTiers migrate safely.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 3: Contribution Receipts

**Owner:** Claude Sonnet 4.6  
**Backup/Integrator:** Codex  
**Priority:** Highest  
**Depends on:** Step 1

## Goal

Stop relying on one optimistic pending contribution value. Add auditable receipts with confidence levels.

## Data Shape

```lua
contributionReceipts = {
    {
        id = "...",
        characterKey = "...",
        when = timestamp,
        amount = copper,
        source = "final_contribution",
        confidence = "verified" or "estimated" or "manual",
        preMoney = copper,
        postMoney = copper,
        estimatedBagValue = copper,
        note = "...",
    }
}
```

## Likely Files

- `Core/Database.lua`
- optional `Core/Contributions.lua`
- `Core/Death.lua`
- `Core/Vendor.lua`
- contribution UI if simple

## Prompt

```text
Implement Step 3: Contribution Receipts.

Inspect Database.lua, Death.lua, Vendor.lua, and any run-state changes from Step 1. Add receipt-based contribution accounting while preserving existing totalContributed and per-character contributed fields.

Preferred approach:
- Add Core/Contributions.lua if it keeps accounting separate.
- Database remains the persistence layer.
- Existing Database:AddContribution should either delegate to Contributions or create a receipt itself.

Requirements:
- Add an account-wide contributionReceipts array or per-character receipts with a clear accessor. Choose the simpler approach that avoids duplication.
- Every contribution should create a receipt with id, characterKey, when, amount, source, confidence, and note.
- Preserve rec.history for existing UI, but make it derive from or mirror receipts.
- On final death, snapshot:
  - player money at death
  - estimated bag vendor value
  - total estimated liquid value
- On mail send success, compare current GetMoney against the death/mail snapshot where possible.
- Mark confidence as estimated when the addon cannot prove attached items.
- Avoid over-crediting more than the recorded death estimate.
- Keep behavior playable: if the addon cannot verify, it should still let the player record an estimated contribution with clear labeling.

Acceptance checks:
- Existing contribution totals are not lost.
- New contributions create receipts.
- Final death contribution cannot be credited repeatedly.
- Receipt confidence is visible in data and ready for UI.
- No protected mail automation is introduced.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 4: Request Fulfillment Receipts

**Owner:** Cursor Auto  
**Backup/Integrator:** Codex  
**Priority:** High  
**Depends on:** Step 2

## Goal

Make bank fulfillment auditable and resilient if addon whispers fail.

## Data Shape

```lua
fulfillment = {
    when = timestamp,
    banker = "Bank-Realm",
    requester = "Run-Realm",
    requestId = "...",
    tierIds = {1, 2},
    items = {{ id = 4496, qty = 2, note = "..." }},
    gold = 5000,
    extraLives = 0,
    method = "mail" or "trade" or "manual",
    status = "fulfilled",
}
```

## Likely Files

- `Core/Requests.lua`
- `Core/Comm.lua`
- `Core/Database.lua`
- `UI/Tab_Requests.lua`

## Prompt

```text
Implement Step 4: Request Fulfillment Receipts.

Inspect Requests.lua, Comm.lua, Database.lua, and Tab_Requests.lua. Add durable fulfillment receipts whenever a bank marks a request fulfilled.

Requirements:
- Store fulfillment details on the request itself and in an account-wide fulfillment history if reasonable.
- Capture bundle details from ns.Requests:Bundle(req): tierIds, items, gold, extraLives.
- Capture method. If the user clicked BeginMailFulfillment, method should become mail. If LoadActiveTrade was used, method should become trade. Otherwise manual.
- Mark requester tier claims using Step 2 helpers when possible.
- Send ACK with enough information for the requester to update outgoing status. If existing comm protocol is too simple, version it carefully or add a new op like ACK2.
- Do not break old ACK handling.
- Update Requests UI to show fulfilled receipts or at least status/details for recent fulfilled requests.

Acceptance checks:
- Mark Fulfilled creates a receipt.
- Bank-side request status survives reload.
- Requester outgoing status updates when ACK arrives.
- If ACK does not arrive, bank-side history is still complete.
- Claim tracking is updated only once per tier.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 5: Settings Module

**Owner:** Claude Sonnet 4.6  
**Backup/Integrator:** Codex  
**Priority:** High  
**Depends on:** Steps 1-2

## Goal

Create the toggle foundation before adding rule logic.

## Likely Files

- new `Core/Settings.lua`
- `Core/Database.lua`
- `WoWRoguelite.toc`
- `WoWRoguelite.lua`

## Prompt

```text
Implement Step 5: Settings Module.

Add a Core/Settings.lua module that owns account-wide settings, per-character run settings, and profile selection. Do not implement rule event behavior yet; this step is only the settings foundation.

Requirements:
- Account-wide defaults live in WRL_DB.settings.
- Per-character run overrides live in WRL_CharDB.runSettings or the current character record, whichever better matches existing architecture.
- Add helpers:
  - ns.Settings:Get(pathOrKey, default)
  - ns.Settings:Set(pathOrKey, value)
  - ns.Settings:GetRuleEnabled(ruleId)
  - ns.Settings:SetRuleEnabled(ruleId, enabled)
  - ns.Settings:GetProfile()
  - ns.Settings:ApplyProfile(profileId)
- Define initial profiles:
  - casual_roguelite
  - banked_hardcore
  - solo_self_found
  - ironman
  - custom
- Profiles should only set configuration values. They must not create separate logic paths.
- Include settings for:
  - allowRepeatClaims
  - allowBankRewards
  - announceDeaths
  - rule toggles placeholder table
- Add migrations safely.
- Initialize module during PLAYER_LOGIN before systems that consume settings.

Acceptance checks:
- New installs receive defaults.
- Existing installs migrate without data loss.
- Applying a profile updates settings predictably.
- No UI is required yet, but slash/debug helpers are acceptable if useful.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 6: Rules Module And Taint Log

**Owner:** Claude Sonnet 4.6  
**Backup/Integrator:** Codex  
**Priority:** High  
**Depends on:** Step 5

## Goal

Add modular rule detection with toggleable behavior and persistent logs.

## Rule Result Types

- `allowed`
- `warned`
- `blocked`
- `tainted`

## Initial Rules

- no_auction_house
- no_mail_except_bank
- no_trade_except_bank
- no_grouping
- no_dungeon_repeats
- no_repeat_claims

## Prompt

```text
Implement Step 6: Rules Module And Taint Log.

Inspect Settings.lua, Database.lua, Requests.lua, Death.lua, and main event patterns. Add Core/Rules.lua with modular rule definitions and a persistent warning/taint log.

Requirements:
- Rule definitions should be data-driven objects with id, name, description, default, severity, events, and handler.
- Rules read enabled/disabled state from ns.Settings.
- Add a per-character log for rule events:
  - when
  - ruleId
  - result
  - detail
  - zone/subzone if useful
- Add helper functions:
  - ns.Rules:IsEnabled(ruleId)
  - ns.Rules:Log(ruleId, result, detail)
  - ns.Rules:GetLog(characterKey)
  - ns.Rules:HasTaints(characterKey)
- Implement soft addon-only behavior:
  - For AH/mail/trade/group/dungeon events, warn and log.
  - Where safe and allowed by API, close frames for blocked rules, but do not depend on closure as enforcement.
  - Never attempt server-side enforcement.
- Integrate no_repeat_claims with Step 2 claim tracking.
- Make all rules toggleable.

Acceptance checks:
- Opening AH with rule enabled creates a log entry and warning.
- Opening mailbox with no_mail_except_bank enabled warns/logs but still allows bank contribution/reward workflows where appropriate.
- Joining a party with no_grouping enabled warns/logs.
- Disabled rules do nothing.
- Taint logs survive reload.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 7: Rules/Profile UI

**Owner:** Cursor Auto  
**Backup/Integrator:** Codex  
**Priority:** High  
**Depends on:** Steps 5-6

## Goal

Make toggles usable. This is key to the addon's long-term quality.

## Likely Files

- new `UI/Tab_Rules.lua`
- `UI/MainFrame.lua`
- `UI/Theme.lua` if helper controls are needed
- `WoWRoguelite.toc`

## Prompt

```text
Implement Step 7: Rules/Profile UI.

Inspect MainFrame.lua, Theme.lua, existing tab files, Settings.lua, and Rules.lua. Add a Rules tab where players can select a profile and toggle individual rules.

Requirements:
- Add "Rules" to the main tab list.
- UI should show current profile.
- Provide buttons or selectable rows for profiles:
  - Casual Roguelite
  - Banked Hardcore
  - Solo Self Found
  - Ironman
  - Custom
- Show individual rule toggles with name, short description, enabled state, and severity.
- Toggling any individual rule should switch profile to Custom.
- Include settings toggles for death announcements, bank rewards, and repeat claims if present.
- Show current character taint count and recent rule log entries.
- Follow the existing UI style. Do not introduce a new visual framework.
- Ensure text does not overflow existing 780x480 frame.

Acceptance checks:
- Rules tab opens without Lua errors.
- Profile selection updates settings.
- Individual toggles persist after reload.
- Recent taints/warnings are visible.
- Existing tabs still work.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 8: Current Run Tab

**Owner:** Cursor Auto  
**Backup/Integrator:** Codex  
**Priority:** High  
**Depends on:** Steps 1-3 and 6

## Goal

Create the primary daily-use screen for the current character.

## Prompt

```text
Implement Step 8: Current Run Tab.

Inspect MainFrame.lua, Theme.lua, Database.lua, Run.lua, Rules.lua, Requests.lua, and Contributions.lua if present. Add UI/Tab_Run.lua and make it the first/default tab if appropriate.

The tab should show:
- Current character name, class, level, realm.
- Run state: fresh, active, dead_pending_contribution, retired, archived.
- Lives remaining.
- Active profile/rules summary.
- Claimed rewards.
- Pending outgoing request if any.
- Estimated contribution value from money + vendorable bags.
- Recent contribution receipts.
- Recent taint/warning log entries.
- Death history if retired.

Requirements:
- Use existing Theme helpers.
- Do not create nested cards inside cards.
- Keep it readable in the existing frame size.
- If data is missing because previous steps are not present, add graceful fallback text instead of throwing errors.
- Add Refresh wiring like other tabs.

Acceptance checks:
- Tab opens on bank and run characters.
- Retired characters show retired state.
- Characters with taints show recent warnings.
- Bag value estimate does not error if item info is uncached.
- Other tabs remain functional.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 9: Bank Shopping List And Fulfillment Helper

**Owner:** Cursor Auto  
**Backup/Integrator:** Codex  
**Priority:** Medium-High  
**Depends on:** Steps 2 and 4

## Goal

Make manual bank fulfillment much smoother without protected automation.

## Prompt

```text
Implement Step 9: Bank Shopping List And Fulfillment Helper.

Inspect Requests.lua, Tab_Requests.lua, Vendor.lua, and Theme.lua. Improve the bank-side Requests tab with have/need counts and fulfillment readiness.

Requirements:
- Add helper to count requested item IDs in banker's bags.
- For each pending request, show:
  - item name/note
  - required qty
  - available qty
  - missing qty
  - gold required
  - whether the bank has enough gold
- Visually distinguish fulfillable vs missing.
- Preserve existing Fulfill via Mail, Load into Trade, Mark Fulfilled, and Cancel buttons.
- Do not attempt to press protected Send/Trade confirmation buttons.
- Add clear chat output listing missing items when fulfillment begins.

Acceptance checks:
- Pending requests show have/need counts.
- Missing items do not crash the UI.
- Gold availability is checked.
- Existing mail/trade helper flow still works.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 10: Bag Highlighting For Needed Items

**Owner:** Cursor Auto  
**Backup/Integrator:** Codex  
**Priority:** Medium  
**Depends on:** Step 9

## Goal

Highlight items in bags that are needed for pending bank requests.

## Prompt

```text
Implement Step 10: Bag Highlighting For Needed Items.

Inspect Requests.lua and WoW bag frame APIs available in this addon style. Add a lightweight bag highlight or tooltip enhancement for bank characters with pending requests.

Requirements:
- When the current character is the bank and has pending requests, identify item IDs needed for fulfillment.
- Add tooltip text on bag items: "Needed for Roguelite request: X".
- If safe and simple, add a subtle border/highlight on standard ContainerFrame item buttons.
- Do not depend on one specific bag addon.
- Avoid errors if Bagnon/other bag addons replace frames.
- Provide a slash/debug refresh if needed.
- Keep implementation isolated, preferably Core/Requests helper plus small UI hook.

Acceptance checks:
- Tooltips on needed items show request info.
- No errors when bags open/close.
- Nothing happens on non-bank characters.
- If bag button frames are not available, tooltip-only fallback still works.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 11: Death Announcements And Memorials

**Owner:** Claude Sonnet 4.6  
**Backup/Integrator:** Cursor Auto for UI polish  
**Priority:** Medium  
**Depends on:** Steps 1, 3, 5, and 6

## Goal

Borrow the strongest emotional/community feature from Hardcore addons: death becomes an event.

## Prompt

```text
Implement Step 11: Death Announcements And Memorials.

Inspect Death.lua, Settings.lua, Rules.lua, Contributions.lua, and Database.lua. Add configurable final-death reports and saved memorial entries.

Requirements:
- On final death, create a memorial entry:
  - character key
  - class/race/level
  - zone/subzone
  - timestamp
  - run state
  - active profile
  - taint count
  - contribution estimate
  - claimed rewards
  - lives used
- Add settings for announcement destination:
  - off
  - local only
  - party
  - guild
- Respect the setting. Default should be local only or off; do not spam by default.
- Add a short, tasteful chat message for final death.
- Do not announce soft deaths if extra lives remain unless a setting enables that.
- Make data available for UI, but full memorial UI can be a later task.

Acceptance checks:
- Final death creates one memorial entry.
- Duplicate PLAYER_DEAD events do not create duplicate memorials.
- Announcement setting is respected.
- Retired characters keep their memorial data after reload.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 12: Boon And Burden System

**Owner:** Claude Sonnet 4.6 for design, Cursor Auto for implementation  
**Backup/Integrator:** Codex  
**Priority:** Medium  
**Depends on:** Steps 5-8

## Goal

Turn toggles into roguelite gameplay choices.

## Prompt For Claude Sonnet 4.6

```text
Design Step 12: Boon And Burden System.

Inspect the current addon architecture after Steps 1-8. Produce a concise implementation design for boons and burdens that reuses Settings, Rules, Rewards/Requests, and Run state instead of adding a parallel system.

Design requirements:
- Boons and burdens are selected at run start.
- They are stored per character and should not silently change mid-run.
- Burdens can enable rules or add penalties.
- Boons can alter reward eligibility but cannot grant protected/server-side effects directly.
- Examples:
  - Boons: extra starter bag, potion cache, profession stipend, one extra life.
  - Burdens: no AH, no non-bank trade, no grouping, white/green gear only, no dungeon repeats.
- Include data shapes, module ownership, and UI placement.
- Include migration and edge cases.
- Keep the design small enough for Cursor Auto to implement in one pass.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

## Prompt For Cursor Auto

```text
Implement Step 12: Boon And Burden System using the design from Claude Sonnet 4.6.

Requirements:
- Add data definitions for boons and burdens.
- Store selected boons/burdens per character at run start.
- New Run or Current Run UI should allow choosing boons/burdens only before the run is active or before rewards are claimed.
- Burdens should map to existing rule toggles or per-run overrides.
- Boons should modify requestable bundles or lives through existing reward/request paths.
- Do not create server-side grant assumptions.
- Prevent changing boons/burdens after meaningful progress unless an explicit reset/debug path exists.

Acceptance checks:
- A fresh character can choose boons/burdens.
- Choices persist.
- Burdens affect rule behavior.
- Boons affect request/reward/life behavior through existing systems.
- Existing characters without choices still work.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 13: Reward Bundles Refactor

**Owner:** Claude Sonnet 4.6  
**Backup/Integrator:** Codex  
**Priority:** Medium-Low  
**Depends on:** Steps 2, 4, and 12

## Goal

Separate tier progression from reward contents so toggles and boons can modify rewards cleanly.

## Prompt

```text
Implement Step 13: Reward Bundles Refactor.

Inspect Tiers.lua, Requests.lua, Tab_Tiers.lua, Tab_NewRun.lua, and any boon/burden implementation. Refactor reward definitions so tiers unlock bundle IDs instead of directly owning all reward contents, while preserving current effective rewards.

Requirements:
- Add Core/Rewards.lua if not already present.
- Keep Tiers.lua focused on thresholds, names, blurbs, and unlocked bundle IDs.
- Rewards.lua owns bundle definitions and helper functions:
  - GetBundle(bundleId)
  - BundlesForTier(tierId)
  - BuildRewardForTierIds(tierIds, characterKey)
  - ApplyRewardModifiers(...)
- Preserve existing tier item/gold/life outputs after migration.
- Make settings possible for:
  - disableGoldRewards
  - disableExtraLives
  - bagsOnly
  - allowPotionRewards
- Update Requests.lua to use Rewards.lua instead of local bundleForTiers logic.
- Update UI summary functions to use Rewards helpers.

Acceptance checks:
- Current tiers still display the same rewards.
- Requests still produce the same bundles by default.
- Claim tracking still uses tier IDs correctly.
- Boon/burden reward modifiers have one central place to hook in.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 14: Legacy Achievements

**Owner:** Cursor Auto  
**Backup/Integrator:** Claude Sonnet 4.6 for achievement list review  
**Priority:** Medium-Low  
**Depends on:** Steps 1, 3, 6, and 11

## Goal

Add long-term goals without needing server changes.

## Prompt

```text
Implement Step 14: Legacy Achievements.

Inspect Database.lua, Run.lua, Rules.lua, Death.lua, Contributions.lua, and UI tabs. Add an addon-only achievement system for account/run milestones.

Requirements:
- Add achievement definitions as data objects with id, name, description, criteria helper, and hidden/visible flag.
- Store earned achievements account-wide with timestamp and characterKey.
- Initial achievements:
  - first_final_death
  - reach_level_10
  - reach_level_20
  - retire_above_level_30
  - contribute_10g_lifetime
  - contribute_100g_lifetime
  - no_taint_to_level_20
  - first_extra_life_used
  - first_legend_tier_unlock
- Evaluate achievements on login, level up, contribution, rule taint, and death.
- Add a simple Achievements section to Current Run or Tiers tab, or a new tab only if the UI remains manageable.

Acceptance checks:
- Achievements are awarded once.
- Existing characters can earn account-wide contribution achievements after login/evaluation.
- Achievement checks do not spam chat repeatedly.
- No server integration is assumed.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 15: Export And Audit Tools

**Owner:** Codex  
**Backup:** Claude Sonnet 4.6 for format review  
**Priority:** Low-Medium  
**Depends on:** Steps 1-4, 6, and 11

## Goal

Make runs shareable and semi-verifiable for Discord/manual leaderboards.

## Prompt

```text
Implement Step 15: Export And Audit Tools.

Add slash commands and serialization helpers for exporting the current run and account legacy summary.

Requirements:
- Add slash commands:
  - /wrl export
  - /wrl export run
  - /wrl export account
- Export should include compact data:
  - addon version
  - character key
  - class/race/level
  - run state
  - profile/rules
  - claimed rewards
  - contribution receipts summary
  - taint count
  - death/memorial data
  - totalContributed
- Output should be copyable from a popup/edit box if possible. Chat-only output is acceptable for first pass if concise.
- Add a lightweight checksum over exported fields to detect accidental edits. This is not anti-cheat; label it as an audit hint.
- Do not include excessive SavedVariables dumps or private account data.

Acceptance checks:
- /wrl export run produces a readable compact summary.
- /wrl export account works on bank and run characters.
- Export does not error on old records with missing optional fields.
- Checksum is stable for unchanged data.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Step 16: Final Integration Review

**Owner:** Codex  
**Priority:** Required after each 2-3 implementation steps

## Goal

Keep the addon coherent as multiple AIs touch it.

## Prompt

```text
Perform an integration review of the WoW Roguelite addon after recent AI edits.

Review priorities:
- TOC load order.
- PLAYER_LOGIN module init order.
- SavedVariables schema migrations.
- Duplicate logic across Database, Run, Rules, Rewards, Requests, and Contributions.
- Nil module references.
- UI tabs missing Refresh wiring.
- Old status="alive" compatibility.
- Claim tracking consistency.
- Contribution receipt consistency.
- Rule toggles actually respected.
- No protected automation introduced.
- No broad unrelated rewrites.

Use code-review style:
- Findings first, ordered by severity.
- Include file and line references.
- If safe and small, fix issues directly.
- If a fix requires a design decision, document the options.

Append the Universal Prompt Addendum from AI_MANAGER_PROMPTS.md.
```

---

# Recommended Assignment Flow

1. **Claude Sonnet 4.6**: Step 1, Step 3, Step 5, Step 6.
2. **Cursor Auto**: Step 2, Step 4, Step 7, Step 8.
3. **Codex**: Step 16 integration review.
4. **Cursor Auto**: Step 9, Step 10.
5. **Claude Sonnet 4.6**: Step 11, Step 12 design.
6. **Cursor Auto**: Step 12 implementation.
7. **Codex**: Step 16 integration review.
8. **Claude Sonnet 4.6**: Step 13.
9. **Cursor Auto**: Step 14.
10. **Codex**: Step 15 and final integration review.

## Why This Split Works

- Claude gets the schema-heavy and rules-heavy tasks where design mistakes would create long-term redundancy.
- Cursor gets the implementation-heavy and UI-heavy tasks where broad codebase editing is useful.
- Codex stays responsible for integration, consistency, and final sanity checks so the addon does not become three different coding styles stitched together.

## Non-Negotiable Design Rules

- Toggles are first-class. Rules, rewards, announcements, claims, and roguelite modifiers should be configurable.
- Presets are configuration shortcuts, not separate code paths.
- Request fulfillment must remain manual-confirmation friendly and respect WoW protected actions.
- Contribution accounting should be honest about confidence instead of pretending addon-only data is server proof.
- Every major event should be auditable: run start, rule taint, claim, request, fulfillment, death, contribution.
- Add systems incrementally. Do not refactor every file just because a new module exists.
