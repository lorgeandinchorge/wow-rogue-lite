# WoW Roguelite

WoW Roguelite is a rogue-lite progression layer for **WoW Classic: Burning Crusade Anniversary**.

Pick one character as your **bank**. Every other character is a hardcore **run**. Final death retires the run, but what it contributes to the bank becomes spendable legacy budget that future characters can use for starter kits.

It is part hardcore challenge, part account progression, and part self-made metagame.

## Latest Update: v0.5.0

- Cuts the first 0.5 multiplayer tester build around co-op visibility and shared awareness rather than shared party authority.
- Expands the Dashboard co-op panel with readiness hints, party request milestones, contribution milestones, soft-death/final-death signals, and warning-first roster ordering.
- Keeps reward fulfillment runner-authoritative through ACK2 verification: valid banker receipts can auto-confirm locally, while mismatches and unsupported clients stay reviewable.
- Adds clearer `/wrl simparty` sample data for local tester inspection without a second client.
- Known limit: co-op visibility does not provide shared bank ownership, formal sessions, party-wide rule enforcement, or cross-client control.

## Core Loop

One character is your bank. Every other character is a run. When a run dies for good, its carried gold and vendorable value flow back to the bank and become part of your lifetime contribution total.

That total turns into spendable legacy budget you allocate into permanent unlock tracks:

- **Storage Vault**: better starter bags and storage support
- **Starter Stipend**: starter gold
- **Alchemist's Table**: healing potions
- **Fate Loom**: extra lives

New runs can request unlocked rewards as starter kits. The bank itself is infrastructure, not a run, so it can freely handle storage, mail, trading, auction house work, travel, loans, resale stock, and reward fulfillment.

## Install

Install via CurseForge, or copy the `WoWRoguelite` folder into:

```text
World of Warcraft\_anniversary_\Interface\AddOns\
```

The final path should be:

```text
...\AddOns\WoWRoguelite\WoWRoguelite.toc
```

Enable the addon at the character-select screen and `/reload` in-game to confirm. You should see `[Roguelite] v0.5.0 loaded.` in chat.

## Quick Start

1. On the character you want as your bank: `/wrl setbank`.
2. Roll a new character. That is your first run.
3. Type `/wrl` to open the main window.
4. Use **Legacy** to spend available budget.
5. Use **Rewards** to prepare a starter-kit request mail.
6. Use **Dashboard** to track the current run, bank desk, co-op status, loans, resale, and contribution prep.

## How A Run Works

**On a run character.** Open `/wrl` -> **Legacy** to review lifetime contributions and spend available legacy budget into Storage Vault, Starter Stipend, Alchemist's Table, and Fate Loom. Open `/wrl` -> **Rewards**, choose one unlocked starter reward from the dropdown, and click **Prepare Mail** at a mailbox. The addon fills a request letter for your bank character; you still press Send manually. The Dashboard also shows your current loan cap, outstanding debt, remaining borrow room, and co-op visibility status.

**On your bank character.** Open `/wrl` -> **Dashboard** to use the Requisitions Desk: active request readiness, Banker Summary, aggregate Needed Supplies, account summaries, character contribution rows, loan balances, quest-goods resale inventory, recent ledger activity, and fulfillment actions. Use **Next Request** to cycle the request queue. At a mailbox, **Prepare Mail** pre-fills name, subject, body, and gold; drag items into the attachment slots and press Send. Or open **Rewards** for the detailed request list and trade checklist.

**On death.** If a non-bank run has lives left from Fate Loom unlocks, you get a soft popup and continue. Death sounds are selectable under gear **Settings** -> **Death Sound** and can be previewed with the adjacent **Play** button. On a final death, the addon snapshots carried currency plus vendor value and lists captured item stacks with vendor sell value. Visit a vendor and click **WRL: Sell All** to confirm and sell vendorable bag contents plus equipped gear. At a mailbox, click **WRL: Contribute** in the mail header to prepare the currency-only contribution mail, reserving 30c for postage. If you defer or close the prompt, the **Dashboard** tab has **Prepare Contribution Mail** and `/wrl contribute` reopens it.

After final death, the character is marked **retired**. Retirement is soft: the addon does not delete the character or block play, but further play is not credited.

## Co-op Awareness

Group with other players who have WRL enabled. The Dashboard automatically shows a compact **Co-op Run** section with nearby WRL party/raid members, their run state, level, lives, readiness hints, party request milestones, contribution milestones, and recent soft-death/final-death/revive events.

This is visibility and co-op awareness, not shared party authority. Each player's local rules decide death outcomes, each runner confirms request fulfillment locally, and the bank/economy model remains local or bank-based. Guild discovery is lightweight presence only. Gold, unlock ownership, banking, loans, resale, and economy progression are not shared across clients.

## Profiles, Rules, Boons, And Burdens

Built-in profiles cover common run shapes:

- **Casual Roguelite**
- **Banked Hardcore**
- **Solo Self Found**
- **Ironman**

Apply one with `/wrl profile <id>` or through the gear -> Settings popup. Individual rule toggles and per-run **boon / burden** modifiers live in the same Settings popup. Rule taints and warnings are logged per character and viewable with `/wrl rules log`.

Settings also includes confirmed resets for achievements, legacy progression, and ledger/economy data, so testers can restart one part of progression without wiping everything.

## Legacy Unlocks

Lifetime contributions become spendable legacy budget. Spending budget does not reduce the lifetime total; it records how much of that total has been allocated into permanent unlock tracks.

| Track | Costs | Grants |
| --- | --- | --- |
| Storage Vault | 3g, 10g, 25g, 75g, 250g, 750g | Better starter bags and storage support |
| Starter Stipend | 3g, 10g, 25g, 75g, 250g, 750g | Starter gold grants of 1g, 5g, 10g, 25g, 100g, and 350g |
| Alchemist's Table | 3g, 10g, 25g, 75g, 250g, 750g | Five healing potions per rank, from Minor through Super |
| Fate Loom | 25g, 750g | +1 extra life at ranks 3 and 6 |

The Legacy tab shows these as talent-style rank nodes plus an **Unlocks available: X / Y** summary and an **Available Legacy Rewards** list of the starter kit pieces you have unlocked so far.

## Banker Tools

The bank Dashboard is the main work surface for fulfillment and accounting:

- Requisitions Desk
- Banker Summary
- Needed Supplies
- Account Summary
- Contribution Board
- Loans Desk
- Resale Desk
- Recent Ledger

Loans are fully manual. The addon records loan paperwork, cap, debt, repayment, and account ownership, but it does not mail, trade, or move gold. When a character with outstanding account debt contributes money, repayment is applied before normal contribution credit.

Resale is also manual. The bank can track curated quest-useful goods, use Auto pricing with optional TSM DBMarket support, prepare COD mail, and record sold stock.

## Slash Commands

```text
Window
  /wrl                  toggle the main window
  /wrl dashboard        jump to the Dashboard tab
  /wrl request          jump to the Rewards tab

Bank identity and tools
  /wrl setbank          mark the current character as the bank
  /wrl setbank NAME     set an external bank character by Name-Realm
  /wrl bank             show the current bank character
  /wrl account L C-R    assign Character-Realm to account label L
  /wrl bankreport       print banker summary lines
  /wrl needed           print aggregate needed supplies

Loans and resale
  /wrl loan             show loan desk status
  /wrl loan borrow C-R AMT
  /wrl loan repay C-R AMT
  /wrl simloan C-R AMT  simulate a manual loan for testing
  /wrl simresale        simulate resale stock for testing
  /wrl resale           show bank resale catalog inventory
  /wrl resale cod ID QTY BUYER
  /wrl resale sold ID QTY [BUYER]

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
  /wrl theme <id>       set UI theme

Export
  /wrl export           export current run summary
  /wrl export run       same as /wrl export
  /wrl export account   export account-wide legacy summary

Maintenance
  /wrl reqrefresh       refresh bag item indicators
  /wrl debug            toggle debug logging
  /wrl reset confirm    wipe ALL addon data
  /wrl help             print this command list
```

`/roguelite` is an alias for `/wrl`.

## UI Themes

Open `/wrl` and click the gear button to choose the account-wide theme, or use `/wrl theme <id>`.

- `classic`: Classic WoW / BetterBags-style palette
- `dark`: the former dark default palette
- `gw2`: GW2 UI-inspired palette, available when GW2 UI is installed and enabled
- `havok`: black surfaces with electric blue accents
- `rabid`: strong blue surfaces with cooler blue-purple accents
- `grant` / **Graham**: jewel purples primary, greens secondary
- `isabella`: jewel pinks primary, teals secondary

Theme changes apply immediately to open addon windows.

## Known Limits

- **Send button not automated.** Blizzard does not let addons press Send on mail or Trade. The addon pre-fills everything and shows the shopping list; you confirm.
- **Contribution value assumes sell-first.** On final death the addon snapshots carried currency plus vendor value. The vendor-only **WRL: Sell All** button can sell vendorable bags plus equipped gear after confirmation. Mail contribution remains currency-only and reserves 30c for postage.
- **Cross-realm addon whispers are not guaranteed in TBC.** The mail fallback path exists for this reason.
- **Co-op is visibility-only in v0.5.0.** Party members can see readiness, request/contribution milestones, and death signals, but WRL does not provide shared bank ownership, formal session hosting, party-wide rule enforcement, or remote control of another client's requests, deaths, loans, resale, mail, or trades.
- **Retirement is soft.** The addon marks a character retired but does not delete them or block play; it just stops crediting further contributions.

## Good Fit If You Want

- a self-imposed hardcore progression mode
- account-wide persistence between runs
- a bank-driven legacy system
- co-op awareness without shared economy ownership
- more structure for reroll-heavy play
- a personal roguelite layer on top of WoW Classic

## Early Version Note

This project is still in an early version, so feedback on bugs, rough edges, confusing UI, and awkward bank workflows is especially helpful.
