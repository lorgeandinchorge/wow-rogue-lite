# WoW Roguelite

A rogue-lite progression layer for **WoW Classic: Burning Crusade Anniversary**. Pick one character as your **bank**; every other character is a hardcore **run**. Final death retires the run, but everything it contributes to the bank becomes spendable legacy budget that future runs can draw on for starter kits.

> **Status:** v0.4.1. Core tracking, UI, run lifecycle, request pipeline, final-run vendor liquidation, mailbox contribution prep, character contribution board, GW2 UI texture-backed theme loading, configurable resale pricing, manual loan accounting, bank reporting, post-retirement achievement lockout, Settings reset controls, and optional dungeon/battleground death ignores are in place. The Legacy tab now includes refreshed Stipend values, an Alchemist's Table potion track, talent-style unlock nodes, an Unlocks available progress readout, and an Available Legacy Rewards summary.

> **Development note:** This project was built with AI assistance, with human direction, review, and testing throughout.

---

## For Players

> This section is the canonical user-facing description and is mirrored to the CurseForge project page. If you're editing the README, edit here and copy the rendered text over.

### Core loop

One character is your bank. Every other character is a run. When a run dies for good, its carried gold (and the value it could have vendored) flows back to the bank and becomes part of your lifetime contribution total. That total turns into spendable legacy budget you allocate into permanent unlock tracks — **Storage Vault** (better starter bags), **Starter Stipend** (starter gold), **Alchemist's Table** (healing potions), and **Fate Loom** (extra lives) — that new runs can request as starter kits.

The bank itself is infrastructure, not a run. It can freely handle storage, mail, trading, the auction house, travel, and reward fulfillment.

### Install

Install via CurseForge (recommended), or copy the `WoWRoguelite` folder into:

```text
World of Warcraft\_anniversary_\Interface\AddOns\
```

so the final path is `...\AddOns\WoWRoguelite\WoWRoguelite.toc`. Enable the addon at the character-select screen and `/reload` in-game to confirm. You should see `[Roguelite] v0.4.1 loaded.` in chat.

### Quick start

1. On the character you want as your bank: `/wrl setbank`.
2. Roll a new character — that's your first run.
3. Type `/wrl` to open the main window.
4. Use the **Legacy** tab to spend any available budget, the **Rewards** tab to prepare a starter-kit request mail, and the **Dashboard** tab to track in-progress state.

For Requisitions Desk testing, `/wrl simrequest Tester-Realm 101` creates a local simulated pending request without needing another player online. `/wrl simresale` creates simulated resale stock for the Resale Desk, `/wrl simloan Tester-Realm 1` creates a local 1g loan record, `/wrl bankreport` prints compact bank status, `/wrl needed` prints aggregate missing supplies, and the Dashboard clear buttons ask before hiding ledger rows or removing simulated resale stock.

### How a run works

**On a run character.** Open `/wrl` → **Legacy** to review lifetime contributions and spend available legacy budget into Storage Vault, Starter Stipend, Alchemist's Table, and Fate Loom. Open `/wrl` → **Rewards**, choose an unlocked starter reward from the dropdown, and click **Prepare Mail** at a mailbox. The addon fills a request letter for your bank character; you still press Send manually. The Dashboard also shows your current loan cap, outstanding debt, and remaining borrow room.

**On your bank character.** Open `/wrl` → **Dashboard** to use the Requisitions Desk: active request readiness, Banker Summary, aggregate Needed Supplies, account summaries, character contribution rows, loan balances, quest-goods resale inventory, recent ledger activity, and fulfillment actions. Use **Next Request** to cycle the request queue. Use **Record Loan** or `/wrl loan borrow Character-Realm GOLD` after manually handing out gold; the addon records the paperwork but does not move gold. Use **Next Resale Item** and **Record 1 Sold** to manually record curated resale goods like Chunk of Boar Meat or Goretusk Liver. Resale pricing defaults to Auto: TSM DBMarket when available, then double vendor, then catalog fallback, and rows label the source as TSM, vendor, fallback, or unpriced; change it under gear **Settings** -> **Pricing**. At a mailbox, **Prepare Mail** pre-fills name, subject, body, and gold; drag items into the attachment slots and press Send. Or open **Rewards** for the detailed request list and trade checklist.

The **Rewards** tab is intentionally request-only for run characters: choose one unlocked starter reward from the dropdown and use **Prepare Mail** at a mailbox. Boons and burdens are configured under gear **Settings** -> **Run Modifiers** before the reward request.

**On death (non-bank characters).** If you have lives left from Fate Loom unlocks, you get a soft popup and carry on. Death sounds are selectable under gear **Settings** -> **Death Sound** and default to Dark Souls. On a final death, the addon snapshots your carried currency plus vendor value and lists the captured item stacks with their vendor sell value. Visit a vendor and click **WRL: Sell All** to confirm and automatically sell vendorable bag contents plus equipped gear. At a mailbox, click **WRL: Contribute** in the mail header to prepare the currency-only contribution mail, reserving 30c for postage; press Send when ready. If you defer or close the prompt, the **Dashboard** tab has a **Prepare Contribution Mail** button and `/wrl contribute` reopens it. The character is then marked **retired** and further play won't be credited.

### Profiles, rules, and run modifiers

Built-in profiles cover the common shapes of run: **Casual Roguelite**, **Banked Hardcore**, **Solo Self Found**, **Ironman**. Apply one with `/wrl profile <id>` or via the gear → Settings popup. Individual rule toggles and the per-run **boon / burden** modifiers live in the same Settings popup; rule taints and warnings are logged per character and viewable with `/wrl rules log`.

Settings also includes a **Resets** surface for confirmed account-section resets: achievements only, legacy progression only, or ledger/economy data. These resets are separate so testers can restart one drawer of progression without wiping characters, requests, memorials, UI settings, pricing preferences, or rule profiles.

### Legacy unlocks

Lifetime contributions become spendable legacy budget. Spending budget does not reduce the lifetime total — it just records how much of that total has been allocated into permanent unlock tracks.

| Track   | Costs                         | Grants                                  |
| ------- | ----------------------------- | --------------------------------------- |
| Storage Vault     | 3g, 10g, 25g, 75g, 250g, 750g | Better starter bags and storage support |
| Starter Stipend   | 3g, 10g, 25g, 75g, 250g, 750g | Starter gold grants of 1g, 5g, 10g, 25g, 100g, and 350g |
| Alchemist's Table | 3g, 10g, 25g, 75g, 250g, 750g | Five healing potions per rank, from Minor through Super |
| Fate Loom         | 25g, 750g                     | +1 extra life at ranks 3 and 6          |

You can buy two ranks of Storage Vault, come back for Starter Stipend rank one, then later keep filling out every track. Eventually everything can be unlocked. The Legacy tab shows Storage Vault, Starter Stipend, Alchemist's Table, and Fate Loom as talent-style rank nodes plus an **Unlocks available: X / Y** summary and an **Available Legacy Rewards** list of the starter kit pieces you have unlocked so far.

### Loans prototype

Loans are banker-operated and manual. The addon records who borrowed, which linked account owns the debt, and how much cap remains; it does not mail or trade gold. The account borrow cap is based on the highest purchased Legacy rank across the unlock tracks: `floor(rank * 3 / 2)` gold, so rank 1 allows 1g and rank 2 allows 3g. Fate uses its purchased rank for this calculation.

When a character with outstanding account debt contributes money, the addon applies that credit to loan repayment first. Only money above the remaining debt becomes normal contribution progress.

Banker reports show that debt-first behavior at account level: contribution totals, active debt, available borrow room, resale purchases, and fulfillment counts are shown together so the bank can see what is owed before celebrating any shiny new contribution credit.

### Slash commands

```text
Window
  /wrl                  toggle the main window
  /wrl dashboard        jump to the Dashboard tab
  /wrl request          jump to the Rewards tab

Bank identity
  /wrl setbank          mark the current character as the bank
  /wrl setbank NAME     set an external bank character by Name-Realm
  /wrl bank             show the current bank character
  /wrl account L C-R    assign Character-Realm to account label L
  /wrl bankreport       print banker summary lines
  /wrl needed           print aggregate needed supplies
  /wrl loan             show loan desk status
  /wrl loan borrow C-R AMT
                        record a manual loan
  /wrl loan repay C-R AMT
                        record a manual loan repayment
  /wrl simloan C-R AMT  simulate a manual loan for testing
  /wrl simresale        simulate resale stock for testing
  /wrl simresale IDS    simulate stock, e.g. 769:4,723:2
  /wrl resale           show bank resale catalog inventory
  /wrl resale cod ID QTY BUYER
                        prepare resale COD mail
  /wrl resale sold ID QTY [BUYER]
                        record a manual resale receipt

Run lifecycle
  /wrl contribute       reopen pending final-contribution mail prep
  /wrl sellfinal        open vendor sell-all prompt
  /wrl vendorfinal      alias for /wrl sellfinal

Configuration
  /wrl settings         print current settings to chat
  /wrl profile          show active profile
  /wrl profile list     list available profiles
  /wrl profile <id>     apply a profile
  /wrl rules            list rules and their enabled state
  /wrl rules log        print recent taint/warn log entries
  /wrl theme            show the active UI theme
  /wrl theme <id>       set UI theme (classic, dark, gw2, havok, rabid, grant/Graham, isabella)

Export
  /wrl export           export current run summary (copyable popup)
  /wrl export run       same as /wrl export
  /wrl export account   export account-wide legacy summary

Maintenance
  /wrl reqrefresh       refresh bag item indicators
  /wrl debug            toggle debug logging
  /wrl reset confirm    wipe ALL addon data (cannot be undone)
  /wrl help             print this command list
```

`/roguelite` is an alias for `/wrl`.

### UI themes

Open `/wrl` and click the gear button to choose the account-wide theme, or use `/wrl theme <id>`.

- `classic` — Classic WoW / BetterBags-style palette (default).
- `dark` — the former dark default palette.
- `gw2` — GW2 UI-inspired palette; only available when [GW2 UI](https://github.com/Mortalknight/GW2_UI) (including the TBC flavor) is installed and enabled.
- `havok` — black surfaces with electric blue accents.
- `rabid` — strong blue surfaces with cooler blue-purple accents.
- `grant` / **Graham** — jewel purples primary, greens secondary.
- `isabella` — jewel pinks primary, teals secondary.

Theme changes apply immediately to open addon windows.

### Known limits

- **Send button not automated.** Blizzard does not let addons press Send on mail or Trade. The addon pre-fills everything and shows the shopping list; you confirm.
- **Contribution value assumes sell-first.** On final death the addon snapshots carried currency plus vendor value. The vendor-only **WRL: Sell All** button can sell vendorable bags plus equipped gear after confirmation. Mail contribution remains currency-only and reserves 30c for postage.
- **Cross-realm addon whispers** aren't guaranteed in TBC; the mail fallback path exists for this reason.
- **Retirement is soft.** The addon marks a character retired but doesn't delete them or block play; it just stops crediting further contributions.

---

## For Developers

### Architecture in three sentences

Every file receives the addon namespace as `local ADDON_NAME, ns = ...`. Modules register themselves with `ns:NewModule("Name")` and communicate through `ns.<ModuleName>`. A single shared event frame dispatches via `ns:On(event, callback)`, and real initialization happens on `PLAYER_LOGIN` so SavedVariables (`WRL_DB` account-wide, `WRL_CharDB` per-character) are guaranteed to be loaded first.

The `Core/` and `UI/` folders in this repo are the live source of truth for file layout. Start with `WoWRoguelite.toc` for load order, then `WoWRoguelite.lua` for initialization order and slash commands.

### Install from source

Copy the `WoWRoguelite` folder into:

```text
World of Warcraft\_anniversary_\Interface\AddOns\WoWRoguelite\
```

The folder must be named `WoWRoguelite` and contain `WoWRoguelite.toc` at its root.

### Tests

Tests are plain Lua and live under `Tests/`. They stub the WoW APIs they need and print `<test name>: ok` on success.

```bash
cd WoWRoguelite
lua Tests/DeathFlow.test.lua
lua Tests/RewardsTabWiring.test.lua
# ...etc.
```

The suite is the safety net for the death flow, reward bundle refactor, contribution credit, and tab wiring. Run the relevant tests before claiming a change is complete.

### Release process

Releases are tag-driven through `.github/workflows/release.yml`, which invokes the BigWigs packager and uploads to CurseForge. See [`RELEASE.md`](RELEASE.md) for the exact tagging sequence and the GitHub Actions secrets and variables it requires.

### Changelog

See [`CHANGELOG.md`](CHANGELOG.md) for release-by-release notes.

### License

All Rights Reserved (matching the CurseForge project listing).

---

## Maintainer notes

The **For Players** section above is the canonical user-facing description. When you change it, copy the rendered text into the CurseForge project description so the two surfaces stay in sync.

The CurseForge page may additionally lead with a short "Latest Update: vX.Y" highlight block — that lives only on CurseForge and is intentionally not duplicated here, since this repo already has `CHANGELOG.md` and the GitHub Releases page.

`CURSEFORGE_DESCRIPTION.md` is a working copy used for that mirroring step. It is excluded from the packaged release by `.pkgmeta` and is not what CurseForge displays — the CurseForge description is edited through the project's web UI.
