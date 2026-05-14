# WoW Roguelite Changelog

## v0.2.3

- Add durable final contribution mail metadata with `WRL-CONTRIB:` subjects and body IDs.
- Fill final contribution mail copper more reliably across Classic money input widgets.
- Credit received final contribution mail from the bank inbox once, using a contribution-mail ledger to avoid duplicate totals.
- Add Classic and GW2-style texture skins for major UI surfaces and buttons while keeping the Dark theme flat.
- Add regression coverage for contribution mail filling, bank-side contribution crediting, and theme texture selection.

## v0.2.2

- Consolidate top-level UI into Current Run, Achievements, Legacy, and Rewards tabs.
- Move rule profiles, rule toggles, and recent rule logs into the gear Settings popup.
- Refresh the default theme with a BetterBags-style Classic WoW palette and move the previous default dark palette to the Dark theme.
- Update reward/request docs and smoke-test guidance for the consolidated tabs.

## v0.2.1

- Add Grant and Isabella personal UI themes.
- Generate slash-command theme help from the theme registry so future theme IDs stay in sync.
- Document that the project was built with AI assistance under human direction, review, and testing.

## v0.2.0

- Fix final-death retire popup formatting on Classic clients that only pass two text arguments through `StaticPopup_Show`.
- Track player GUIDs so future same-name/same-class rerolls archive the old character record instead of reusing it.
- Credit sold equipped gear value after final death up to the recorded maximum potential contribution.
- Warn when a final contribution is below the 30c mail postage cost.
- Simplify bank presence wording from "Online (addon)" to "Online" and stop passive status refreshes from whisper-pinging offline bank characters.

## v0.1.9

- Fix an early bank-status refresh crash before the main window header widgets are built.
- Add `C_Container` bag API fallback for clients where legacy container globals are unavailable.

## v0.1.8

- Add a full-screen final-death overlay that appears after corpse recovery or on login for pending deaths.
- Keep final-death bookkeeping durable while dead or ghosted, then continue into the existing mail/skip retirement flow after the death screen.
- Fix same-name rerolls so old memorials do not block the current character generation from creating its own memorial.
- Re-open the retire contribution popup for acknowledged but still-pending deaths until the run is mailed or skipped.
- Add death-screen compatibility coverage for Classic clients without keyboard propagation APIs.

## v0.1.7

- Capture last attacker name and damage type from combat log before PLAYER_DEAD fires.
- Record sourceName and environmentalType in death memorials and deathLog context entries.
- Fix combat-log event parsing: correctly skip destFlags/destRaidFlags before suffix arguments.
- Add 6 new DeathFlow tests covering combat source capture, environmental death, stale attacker timeout, duplicate PLAYER_DEAD guard, missing map APIs, and memorial context propagation.

## v0.1.6

- Reconcile final death on world entry, player flag changes, and revive/body recovery events.
- Finalize any active non-bank run with no lives remaining, even if the character is no longer dead or ghosted.
- Add Classic API fallbacks for dead/ghost detection.
- Show a banker-focused overview on bank characters instead of normal run status details.

## v0.1.5

- Detect missed final deaths on login/reload when a run character is already dead or ghosted.
- Show a clearer final-death next-steps popup with mailbox guidance.
- Snapshot carried money, bag vendor value, equipped gear vendor value, and maximum possible contribution on death.
- Display contribution-pending final deaths as retired in run/contribution status views.
- Block retired or dead characters from requesting new starter rewards.

## v0.1.4

- Add addon-whisper bank presence detection so off-account online bankers can show as online.
- Refresh the default and GW2-inspired themes with stronger GW2-style visual direction.
- Make theme changes refresh open addon windows immediately.
- Update TBC Anniversary interface metadata to 20505.

## v0.1.3

- Improve GW2 UI theme detection across current GW2 UI flavors and modern addon APIs.
- Recognize GW2 UI Mainline, TBC, Vanilla, Classic, Mists, and Wrath variants.

## v0.1.2

- Detect GW2 UI TBC and other GW2 UI variants for theme availability.
- Remove repeat reward claim settings and rule toggles; claimed rewards are always one-time per character.
- Keep already-claimed rewards filtered from new run requests.

## v0.1.1

- Release packaging refresh for automated CurseForge publishing.
- No gameplay changes from v0.1.0.

## v0.1.0

- Initial CurseForge-ready release.
- Adds the core bank/run roguelite loop.
- Tracks lifetime contributions and legacy unlock spending.
- Supports Storage, Stipend, and Fate starter rewards.
- Adds bank-side request fulfillment by assisted mail or trade.
- Adds Classic, dark, and optional GW2-inspired UI themes.
