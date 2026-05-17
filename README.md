# WoW Roguelite

A rogue-lite progression layer for **WoW Classic: Burning Crusade Anniversary**. Pick one character as your **bank**; every other character is a hardcore **run**. Final death retires the run, but everything it contributes to the bank becomes spendable legacy budget that future runs can draw on for starter kits.

> **Status:** v0.2.9.2 — core tracking, UI, run lifecycle, request pipeline, and final-run vendor liquidation. Mail and trade fulfillment is assisted: the addon pre-fills forms and contribution currency, but Blizzard's addon API won't let it press Send for you.

> **Development note:** This project was built with AI assistance, with human direction, review, and testing throughout.

---

## For Players

> This section is the canonical user-facing description and is mirrored to the CurseForge project page. If you're editing the README, edit here and copy the rendered text over.

### Core loop

One character is your bank. Every other character is a run. When a run dies for good, its carried gold (and the value it could have vendored) flows back to the bank and becomes part of your lifetime contribution total. That total turns into spendable legacy budget you allocate into permanent unlock tracks — **Storage** (better starter bags), **Stipend** (starter gold), and **Fate** (extra lives) — that new runs can request as starter kits.

The bank itself is infrastructure, not a run. It can freely handle storage, mail, trading, the auction house, travel, and reward fulfillment.

### Install

Install via CurseForge (recommended), or copy the `WoWRoguelite` folder into:

```text
World of Warcraft\_anniversary_\Interface\AddOns\
```

so the final path is `...\AddOns\WoWRoguelite\WoWRoguelite.toc`. Enable the addon at the character-select screen and `/reload` in-game to confirm. You should see `[Roguelite] v0.2.9.2 loaded.` in chat.

### Quick start

1. On the character you want as your bank: `/wrl setbank`.
2. Roll a new character — that's your first run.
3. Type `/wrl` to open the main window.
4. Use the **Legacy** tab to spend any available budget, the **Rewards** tab to request unlocked starter kits, and the **Current Run** tab to track in-progress state.

### How a run works

**On a run character.** Open `/wrl` → **Legacy** to review lifetime contributions and spend available legacy budget into Storage, Stipend, and Fate. Open `/wrl` → **Rewards**, tick any unlocked legacy rewards you want sent to you, and click **Send Request**. The addon whispers your bank character; if the bank is offline, the mail fallback at any mailbox carries the same payload and the bank picks it up on next login.

**On your bank character.** Open `/wrl` → **Rewards** to see incoming kits with a shopping list. At a mailbox, **Fulfill via Mail** pre-fills name, subject, and gold; drag items into the attachment slots and press Send. Or open a Trade window with the requester and **Load into Trade** to step through the manual checklist.

**On death (non-bank characters).** If you have lives left from Fate unlocks, you get a soft popup and carry on. On a final death, the addon snapshots your carried currency plus vendor value. Visit a vendor and click **WRL: Sell All** to confirm and automatically sell vendorable bag contents plus equipped gear. At a mailbox the contribution mail is pre-filled in currency only, reserving 30c for postage; press Send when ready. If you defer or close the prompt, the **Current Run** tab has a **Prepare Contribution Mail** button and `/wrl contribute` reopens it. The character is then marked **retired** and further play won't be credited.

### Profiles, rules, boons, and burdens

Built-in profiles cover the common shapes of run: **Casual Roguelite**, **Banked Hardcore**, **Solo Self Found**, **Ironman**. Apply one with `/wrl profile <id>` or via the gear → Settings popup. Individual rule toggles and the per-run **boon / burden** modifiers live in the same Settings popup; rule taints and warnings are logged per character and viewable with `/wrl rules log`.

### Legacy unlocks

Lifetime contributions become spendable legacy budget. Spending budget does not reduce the lifetime total — it just records how much of that total has been allocated into permanent unlock tracks.

| Track   | Costs                         | Grants                                  |
| ------- | ----------------------------- | --------------------------------------- |
| Storage | 3g, 10g, 25g, 75g, 250g, 750g | Better starter bags and storage support |
| Stipend | 3g, 10g, 25g, 75g, 250g, 750g | Starter gold at each purchased rank     |
| Fate    | 25g, 750g                     | +1 extra life at ranks 3 and 6          |

You can buy two ranks of Storage, come back for Stipend rank one, then later keep filling out every track. Eventually everything can be unlocked.

### Slash commands

```text
Window
  /wrl                  toggle the main window
  /wrl request          jump to the Rewards tab

Bank identity
  /wrl setbank          mark the current character as the bank
  /wrl setbank NAME     set an external bank character by Name-Realm
  /wrl bank             show the current bank character

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
  /wrl theme <id>       set UI theme (classic, dark, gw2, grant, isabella)

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
- `grant` — jewel purples primary, greens secondary.
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
