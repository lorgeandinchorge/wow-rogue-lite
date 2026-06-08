# WoW Roguelite Changelog

## v0.5.1

- Condense the Dashboard co-op block into a compact **Team Pulse** summary with nearby party count, readiness buckets, recent signal count, and warning-first roster rows.
- Promote the most recent important party signal to a single **Last critical** line for quick-glance deaths, revives, requests, and contribution milestones.
- Keep request and contribution milestones compact under **Requests** and **Contrib**, with one short visibility-only footer instead of repeated explanatory copy.
- Simplify the empty co-op state to player-facing copy: **Waiting for party...**

## v0.5.0

- Cut the first 0.5 multiplayer tester build around co-op visibility and shared awareness rather than shared party authority.
- Expand the Dashboard co-op panel with readiness hints, warning-first roster ordering, party request milestones, contribution milestones, and death-signal visibility.
- Keep reward fulfillment runner-authoritative through ACK2 verification: valid banker receipts can auto-confirm locally, while mismatches and unsupported clients stay reviewable.
- Add `/wrl simparty` tester sample labeling plus simulated request, contribution, soft-death, and final-death signals so testers can inspect the Dashboard without a second client.
- Document known tester limits: no shared bank ownership, no formal session host, no cross-client control, local death/rule outcomes remain local, and mail/trade actions still require player confirmation.

## v0.4.2a

- Fix Resale Desk row clearing so real scanned inventory can be dismissed from the desk instead of immediately redrawing.
- Stop unmatched resale stock from inheriting a phantom active requester or requested quantity.
- Add runner-side ACK2 verification for reward requests, with banker validation, duplicate suppression, local auto-claiming, and manual review fallback.

## v0.4.2

- Add lightweight auto co-op awareness for party/raid groups, with compact WRL roster state, recent co-op event feed, and guild discovery pings.
- Add co-op event broadcasts for soft deaths, final deaths, and revive returns while keeping shared economy/progression out of scope.
- Extend addon-message routing beyond bank whispers with scoped party/raid/guild sends and regression coverage.

## v0.4.1c

- Add a **Play** button beside the Settings death-sound picker so players can preview the selected sound.
- Rename death-sound choices to slightly off-brand labels such as **Dark Fates** while keeping the bundled files and saved setting IDs stable.
- Add regression coverage for death-sound preview playback and Settings preview-button wiring.

## v0.4.1b

- Remove an unused legacy icon asset from the packaged addon.
- Remove the duplicate Dark Souls death sound file and redundant **Dark Souls Alt** Settings option.
- Keep death-sound regression coverage focused on the shipped sound choices.

## v0.4.1a

- Include the Legacy layout polish that re-anchors the **Permanent Unlocks** title below **Available Legacy Rewards**.
- Keep the Legacy tab's availability summary and permanent-unlock board from visually colliding after refreshes.
- Add regression coverage for the permanent-unlock title anchor.

## v0.4.1

- Add Settings toggles to ignore WoW Roguelite death handling in dungeons and battlegrounds separately.
- Keep ignored dungeon and battleground deaths from consuming lives, creating memorials, playing death sounds, incrementing death counts, or opening final-contribution prompts.
- Preserve ignored corpse states until the player revives so zoning or reloading after an exempt death does not retroactively retire the run.
- Add regression coverage for ignored instance deaths, the Settings toggles, and release metadata.

## v0.4.0b

- Continue the 0.4 Legacy Revamp with talent-style circular unlock nodes, connector lines, and an **Available Legacy Rewards** summary.
- Rename Legacy tracks to Storage Vault, Starter Stipend, Alchemist's Table, and Fate Loom, with two-word rank titles across the board.
- Increase Alchemist's Table potion grants to five potions per unlocked rank.
- Add selectable death sounds under Settings, defaulting to Dark Fates, with Off and Random options.
- Expand achievements with 10-level milestones through 70, death-decade milestones, `Insert Coin` for the first extra life used, and death-count milestones for 1, 10, 50, and 100 deaths.

## v0.4.0a

- Polish the Legacy permanent-unlock surface so Storage, Stipend, Alchemist's Table, and Fate line up side by side with vertical square-tile progress ladders.
- Add a simple **Unlocks available: X / Y** readout under Permanent Unlocks for quick progress scanning.
- Move detailed reward previews into tile tooltips to keep the main Legacy view readable.
- Add regression coverage for the side-by-side vertical unlock layout and availability summary.

## v0.4.0

- Start the Legacy and Achievements pass with a refreshed Legacy economy surface.
- Rebalance Stipend rewards to the new 1g, 5g, 10g, 25g, 100g, and 350g grant ladder while preserving existing unlock costs.
- Add the **Alchemist's Table** Legacy track, granting two healing potions per rank from Minor Healing Potion through Super Healing Potion.
- Wrap the Legacy unlock section into a two-column grid so Storage, Stipend, Alchemist's Table, and Fate all remain visible.
- Add regression coverage for Stipend values, Alchemist's Table potion rewards, and the four-track Legacy layout.

## v0.3.8b

- Move Account Summary assignment actions onto the relevant rows so Unassigned rows open targeted assignment when there is one obvious character.
- Add a Local Account rename action that updates the default account label without moving linked characters.
- Keep account assignment and rename changes reflected in Account Summary and Recent Ledger while preserving receipt backfill behavior.

## v0.3.8a

- Prevent dead, contribution-pending, retired, or archived run characters from earning normal achievements after the run is over.
- Keep the final-death achievement eligible during the final-death transition.
- Add a Settings **Resets** surface with separate confirmed resets for achievements, legacy progression, and ledger/economy data.
- Add regression coverage for achievement eligibility, reset helper behavior, and Settings reset wiring.

## v0.3.8

- Add a compact **Banker Summary** to the bank Dashboard with pending/ready request counts, missing item lines, resale row count, outstanding loan total, recent ledger count, and pricing-source status.
- Add aggregate **Needed Supplies** reporting across actionable requests, with requested/available/missing totals, request counts, tailor-made starter bag hints, and optional TSM DBMarket hints.
- Add account-level banking summary rows that combine contribution totals, outstanding loan debt, borrow room, resale purchases, and fulfillment counts.
- Add `/wrl bankreport` and `/wrl needed` slash-command fallbacks for banker status and aggregate supply reporting.
- Add short resale pricing labels (`TSM`, `vendor`, `fallback`, `unpriced`) to inventory rows, COD drafts, sale receipts, and ledger details while keeping TradeSkillMaster optional.
- Give the Recent Ledger real fixed columns with visible separators so Time, Type, Who, Account, Amount, and Detail stay readable in-game.
- Bump docs, metadata, and regression coverage for the v0.3.8 final banking/reporting push.

## v0.3.7

- Add a manual **Loans Desk** prototype to the bank Dashboard with account-level cap, debt, available borrow room, borrower, and latest activity.
- Add loan receipts for borrow and repayment records, enforced by linked account while preserving borrower character detail.
- Calculate loan cap from highest purchased Legacy rank across Storage, Stipend, and Fate using `floor(rank * 3 / 2)` gold.
- Apply contribution credit to outstanding loan debt first, with only overflow becoming normal contribution progress.
- Add runner Dashboard loan status lines for cap, outstanding debt, and available borrow room.
- Add `/wrl loan`, `/wrl loan borrow`, `/wrl loan repay`, and `/wrl simloan` commands for prototype testing and fallback entry.
- Add regression coverage for cap math, account-level debt, repayment overflow, account reassignment, ledger visibility, Dashboard loan copy, slash commands, and TOC load order.

## v0.3.6

- Add configurable Resale Desk pricing with Auto, TSM DBMarket only, and local fallback modes.
- Make Auto pricing use TSM DBMarket when available, then double vendor, then catalog fallback.
- Store resale price source metadata on inventory rows, COD drafts, and sale receipts.
- Add a Settings **Pricing** section for choosing the Resale Desk pricing source.
- Rename the visible Bank Desk dashboard surface to **Requisitions Desk**.
- Add regression coverage for resale pricing modes, settings defaults, source labels, strict TSM handling, and dashboard copy.

## v0.3.5c

- Add an optional TSM DBMarket adapter for request readiness hints while keeping TradeSkillMaster fully optional.
- Label tailor-made starter bags in Bank Desk, fulfillment mail, chat checklists, and needed-item tooltips.
- Show captured bag and equipped-gear vendor value lines in the final-death contribution popup.
- Bump docs and metadata for the v0.3.5c readiness/intake hotfix.

## v0.3.5b

- Add a Settings **Font** section with Default, Readable Sans, Large, and Extra Large profiles for reading accessibility.
- Apply font profile changes immediately to open addon UI through the shared Theme text helpers.
- Add regression coverage for font profile defaults, selection, rejection, and refresh behavior.

## v0.3.5a

- Fix Bank Dashboard right-gutter layout so section borders, row actions, Resale Desk controls, and Recent Ledger content stay clear of the scrollbar.
- Change the Contribution Board from account labels to character rows with generation, level, total contribution, and share columns.
- Add confirmation prompts before clearing the Resale Desk and the Recent Ledger.
- Make Recent Ledger clearing hide the current visible feed with a timestamp cutoff while keeping contribution, fulfillment, and resale receipts intact.
- Add regression coverage for character contribution rows, dashboard geometry constants, clear confirmations, and ledger clear behavior.

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
