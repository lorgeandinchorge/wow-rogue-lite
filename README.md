# WoW Roguelite

A rogue-lite addon for **WoW Classic: Burning Crusade (Anniversary)**. Pick one character as your **bank**; every other character is a **run**. Runs are hardcore: one final death and the character is retired, but everything they contribute to the bank becomes legacy budget for **Storage**, **Stipend**, and **Fate** unlocks that future runs can request as starter kits.

> Status: **first draft (v0.2.2)**: core tracking, UI, and request pipeline. Automatic mail/trade fulfillment is partially assisted: the addon pre-fills forms and tells you exactly what to drag, but Blizzard's addon API won't let it click Send for you.

> Development note: This project was built with AI assistance, with human direction, review, and testing throughout.

## Install

1. Copy the `WoWRoguelite` folder into `World of Warcraft\_classic_\Interface\AddOns\` so the full path is `...\AddOns\WoWRoguelite\WoWRoguelite.toc`.
2. Enable it at the character select screen.
3. `/reload` in-game to verify it loaded. You'll see `[Roguelite] v0.2.2 loaded.` in chat.

## Publish releases

This repo includes a GitHub Actions release workflow. Push a version tag matching the TOC version to build and publish the CurseForge package:

```powershell
git tag v0.2.2
git push origin v0.2.2
```

To enable automatic CurseForge uploads, set `CF_API_KEY` as a GitHub repository secret and `CF_PROJECT_ID` as a GitHub repository variable.

## First-time setup

On your designated bank character:

```text
/wrl setbank
```

This marks that character as the bank. Bank characters are out-of-run infrastructure and may handle storage, mail, trading, Auction House work, travel, deaths, and fulfillment freely.

## How a run works

**On a new character:**

- Open `/wrl` -> **Legacy** to review lifetime contribution history and spend available legacy budget into Storage, Stipend, and Fate.
- Open `/wrl` -> **Rewards**.
- Tick any unlocked legacy rewards you want sent to you.
- Click **Send Request**. This addon-whispers your bank character.
- If the bank is offline, use the mail fallback at any mailbox; the bank picks it up on next login.

**On your bank character:**

- Open `/wrl` -> **Rewards** to see incoming kits with a shopping list.
- Go to a mailbox and click **Fulfill via Mail**: name, subject, and gold pre-fill; drag items into attachment slots; press Send.
- Or open a **Trade** window with the requester and click **Load into Trade** for the manual trade checklist.

**On death (non-bank characters):**

- If you have lives left from Fate unlocks, you get a soft popup and can carry on.
- On final death, the addon snapshots your carried gold plus vendor value and offers to pre-fill a mail to the bank.
- The character is marked **retired**; further play will not be credited.

## Legacy unlocks

Lifetime contributions become spendable legacy budget. Spending budget does not reduce the lifetime total; it records how much of that total has been allocated into permanent unlock tracks.

| Track | Costs | Grants |
|------|-------|--------|
| Storage | 3g, 10g, 25g, 75g, 250g, 750g | Better starter bags and storage support |
| Stipend | 3g, 10g, 25g, 75g, 250g, 750g | Starter gold at each purchased rank |
| Fate | 25g, 750g | +1 extra life at ranks 3 and 6 |

You can buy two ranks of Storage, come back for Stipend rank one, then later keep filling out every track. Eventually everything can be unlocked.

Tune these in `Core/LegacyUnlocks.lua` and `Core/Rewards.lua`.

## Slash commands

```text
/wrl                - toggle the main window
/wrl setbank        - designate the current character as the bank
/wrl bank           - show which character is currently the bank
/wrl request        - jump to the Rewards tab
/wrl theme          - show the current UI theme
/wrl theme classic  - use the Classic WoW / BetterBags-style default theme
/wrl theme dark     - use the former dark default theme
/wrl theme gw2      - use the GW2 UI theme when GW2 UI is installed/enabled
/wrl theme grant    - use the Grant purple/green theme
/wrl theme isabella - use the Isabella pink/teal theme
/wrl debug          - toggle debug logging
/wrl reset confirm  - wipe saved data (cannot be undone)
```

## UI themes

Open `/wrl` and click the gear button near **Close** to choose the account-wide UI theme, or use `/wrl theme <id>`.

- `classic` is the default Classic WoW / BetterBags-style theme.
- `dark` is the former dark default theme.
- `gw2` uses the addon's GW2-inspired palette and is selectable only when [GW2 UI](https://github.com/Mortalknight/GW2_UI), including the TBC flavor, is installed and enabled.
- `grant` uses jewel purples as the primary accent with greens as the secondary accent.
- `isabella` uses jewel pinks as the primary accent with teals as the secondary accent.

Theme changes apply immediately to open addon windows.

## File layout

```text
WoWRoguelite/
├── WoWRoguelite.toc           addon manifest
├── WoWRoguelite.lua           bootstrap, slash commands, module registry
├── Core/
│   ├── Database.lua           SavedVariables schema + character records
│   ├── Tiers.lua              money formatting + legacy compatibility helpers
│   ├── LegacyUnlocks.lua      Storage, Stipend, and Fate unlock economy
│   ├── Rewards.lua            reward bundle definitions and filters
│   ├── Vendor.lua             vendor-value calculation
│   ├── Comm.lua               addon-whisper protocol between characters
│   ├── Requests.lua           request queue + mail/trade fulfillment
│   └── Death.lua              PLAYER_DEAD handler + retirement flow
└── UI/
    ├── Theme.lua              palette + widget constructors
    ├── MainFrame.lua          main window + tabs + minimap button
    ├── Tab_Legacy.lua         account legacy economy + contributor roster
    `-- Tab_Rewards.lua        role-aware requests and fulfillment
```

## Known limits

- **Send button not automated.** Blizzard does not let addons press Send on mail or Trade. The addon pre-fills everything and shows the shopping list; you confirm.
- **Contribution accounting is still estimated for items.** On final death the addon snapshots carried gold and bag vendor value, then on `MAIL_SEND_SUCCESS` credits only the gold and bag value that actually left the character since the snapshot.
- **Cross-realm addon whispers** are not guaranteed in BC; the mail fallback path exists for this reason.
- **Retirement is soft.** The addon marks a character retired but does not delete them or block play; it just stops crediting further contributions.

## Next steps / backlog

- Add a manual reconciliation UI for rare cases where a final contribution mail needs adjustment.
- Gather-helper tooltip on item icons in bags, showing "needed for request from X".
- Per-character class tint on the contribution bars.
- Sound/toast on incoming request.
- Config panel for legacy unlock costs and reward items.
- Export run history as CSV for players who want to chart their own progress.
