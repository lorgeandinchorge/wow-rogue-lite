# WoW Roguelite Changelog

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
