# WoW Roguelite Changelog

## v0.3.5

- Add the Bank Dashboard **Resale Desk** for curated quest-useful goods such as Chunk of Boar Meat and Goretusk Liver.
- Price resale goods with a simple vendor-price-doubled rule and catalog fallback minimums.
- Add manual resale receipt recording through Dashboard actions and `/wrl resale sold ITEM_ID QTY [BUYER]`.
- Add `/wrl simresale` for local Resale Desk testing without stocking real bag or bank items first.
- Keep resale fully manual: the addon lists, prices, and records, but never trades, mails, auctions, or vendors items.
- Add regression coverage for catalog lookup, pricing, inventory aggregation, receipts, Dashboard wiring, and slash commands.

## v0.3.4

- Add full item-availability lines to Bank Desk request readiness so bankers can see ready and missing stacks together.
- Add gold availability lines to Bank Desk and fulfillment mail prep instead of only reporting missing totals.
- Add an item checklist to prepared reward mail bodies so manual attachments are easier to verify before pressing Send.
- Increase Bank Desk section heading/body text sizes for cleaner scanning in the dashboard.
- Add regression coverage for Bank Desk readiness lines and prepared fulfillment mail checklist output.

## v0.3.3

- Move boons and burdens out of the Rewards tab and into Settings under a dedicated **Run Modifiers** section.
- Simplify the run-side Rewards tab into a guided request flow with an unlocked reward dropdown and **Prepare Mail** action.
- Keep bank-side Rewards fulfillment available as the detailed request browser while the Dashboard remains the primary Bank Desk surface.
- Harden reward request and fulfillment mail body prefill across Classic mail-frame timing differences.
- Expand prepared reward mail body details with requested item lines so banker handoffs are easier to verify.
- Update smoke-test and public docs so testers know where to request rewards and where to configure run modifiers.

## v0.3.2

- Upgrade the bank character Dashboard into the active Bank Desk fulfillment surface, with an active request summary, account label, reward IDs, readiness state, missing item details, and missing gold details.
- Add a Dashboard **Next Request** control so the banker can cycle pending/preparing requests without opening the Rewards tab.
- Add `/wrl simrequest [Character-Realm] [RewardId,RewardId]` for local Bank Desk testing without needing a second requester online.
- Make Dashboard **Prepare Mail**, **Mark Fulfilled**, and **Assign Account** operate on the active Bank Desk request.
- Make reward mail preparation report success/failure to callers while preserving the manual Send boundary.
- Keep the Rewards tab available as the detailed request browser and backup workflow.
- Add regression coverage for active request cycling, Bank Desk readiness lines, and mail preparation state changes.

## v0.3.1

- Rename the visible Current Run tab to Dashboard while preserving the internal Run panel and saved-tab migration.
- Add the first Bank Desk dashboard for bank characters, with pending request attention, account-grouped contribution board, recent ledger lines, and fulfillment action buttons.
- Add account grouping storage and helpers for manual tester/player labels, character-to-account links, and account-level contribution rollups.
- Store account metadata on new contribution receipts, reward requests, and fulfillment receipts while keeping character-level detail intact.
- Add dry banker flavor to prepared reward mail while preserving Blizzard's manual Send boundary.
- Add `/wrl account LABEL Character-Realm` for assigning tester characters to account labels.
- Add regression coverage for account migration/linking, account rollups, Dashboard labeling, and Bank Desk summaries.

## v0.3.0b

- Add Havok and Rabid as always-available UI themes.
- Retune Rabid toward a stronger blue base with cooler blue-purple accents.
- Make GW2 UI theme availability tolerate Classic client addon-enable API timing/signature differences so saved GW2 selections can activate on first login.
- Fix the GW2 UI theme texture paths so the skin loads upstream `.png` assets instead of falling back to color-only surfaces.
- Resolve GW2 UI texture roots from the active enabled flavor, including TBC/Mainline/Vanilla/Mists/Wrath installs.

## v0.3.0 - Contributions Done, Next Up BANKING

- Complete the final contribution loop with always-available vendor liquidation and mailbox contribution helpers.
- Make the merchant `WRL: Sell All` button refresh directly from vendor open timing, with command fallbacks still available.
- Add a mailbox `WRL: Contribute` button in the mail header, keep it aligned with the mailbox lifecycle, and preserve the manual Send requirement.
- Harden late-frame and open/close timing behavior for merchant and mail UI buttons so testers do not need to buy, sell, or run slash commands to wake the controls.
- Add regression coverage for merchant open refreshes, mailbox contribution placement, mailbox hide behavior, and contribution button click recovery.

## v0.2.9.2

- Make the vendor `WRL: Sell All` button appear whenever a merchant is open, regardless of run state.
- Keep the private confirmation dialog before selling vendorable bag contents and equipped gear.
- Keep `/wrl sellfinal` and `/wrl vendorfinal` as command fallbacks for the same vendor sell prompt.
- Update regression coverage and user-facing copy for the always-visible vendor button.

## v0.2.9.1

- Keep the final-run vendor button visible for dead pending runs even when item sell prices are not cached at merchant-open time.
- Add `/wrl sellfinal` and `/wrl vendorfinal` as tester-friendly ways to open the same final-run vendor sell prompt.
- Move the final-run sell-plan check to click/command time and print a clear message when no vendorable items are found.
- Add regression coverage for cold item-cache merchant opens and the new vendor sell slash commands.

## v0.2.9

- Fix the final-run vendor button so it appears even when Blizzard's `MerchantFrame` loads after WRL initialization.
- Replace the vendor sell confirmation StaticPopup with a private WRL confirmation frame to avoid tainting Blizzard's quit/logout dialog path.
- Improve final-death source capture on Classic clients that require `CombatLogGetCurrentEventInfo()`, reducing `Slain by Unknown` deaths when live combat-log context is available.
- Add regression coverage for late merchant-frame button creation and both direct and `CombatLogGetCurrentEventInfo()` combat-log capture paths.

## v0.2.8

- Add a vendor-only `WRL: Sell Final Run` button for characters in `dead_pending_contribution`.
- Require confirmation before automatically selling vendorable bag contents and equipped gear.
- Keep the run pending after vendor liquidation so the existing `/wrl contribute` mail flow still handles currency-only contribution and manual Send.
- Add regression coverage for merchant button visibility, sell planning, skipped items, and equipped-gear sale execution.

## v0.2.7

- Fix final contribution send-credit accounting so prefilled gold, silver, and copper are all counted.
- Add a field-readback fallback for prepared contribution mail when the durable outbox amount is missing.
- Refresh the send-mail frame after contribution prefill so reopening `/wrl contribute` is more reliable when the send tab is already open.
- Add regression coverage for the `1s 11c` style fallback case that previously credited only copper.

## v0.2.6

- Change final contribution mail to a currency-only flow that assumes the player sells vendorable bags and gear first.
- Automatically pre-fill the pending final contribution at the mailbox, reserving 30c for postage.
- Add a Current Run button and `/wrl contribute` command to reopen pending final contribution mail preparation.
- Change the retire popup's secondary action to defer contribution instead of permanently skipping it.
- Add regression coverage for currency-only contribution mail, postage reservation, and the recovery action.

## v0.2.5

- Fix final-death popup formatting through a safe single-message StaticPopup path.
- Centralize bag item API compatibility for Classic clients that expose `C_Container` instead of legacy container globals.
- Prevent early bank-status updates from refreshing main-window UI before header widgets exist.
- Add regression coverage for popup formatting, early bank-status refreshes, and `C_Container` request inventory scans.

## v0.2.4

- Add a contribution amount confirmation popup before final-death mail is created.
- Parse player-entered gold, silver, and copper amounts and fill all Classic mail money widgets consistently.
- Cap contribution mail copper to the character's current carried money to avoid impossible pre-fill amounts.
- Fix incoming reward request tab notifications to highlight the consolidated Rewards tab.
- Add regression coverage for contribution amount entry, gold/silver/copper mail filling, explicit zero contributions, and Rewards tab notification wiring.

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

- Add Graham and Isabella personal UI themes.
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
