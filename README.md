# WoW Roguelite

A rogue-lite addon for **WoW Classic: Burning Crusade (Anniversary)**. Pick one character as your **bank**; every other character is a **run**. Runs are hardcore — one final death and the character is retired — but everything they contribute to the bank counts toward **tier unlocks** that future runs can request as starter kits (bags, potions, mount gold, flying, even an extra life).

> Status: **first draft (v0.1.0)** — core tracking, UI, and request pipeline. Automatic mail/trade fulfillment is partially assisted: the addon pre-fills forms and tells you exactly what to drag, but Blizzard's addon API won't let it click Send for you.

## Install

1. Copy the `WoWRoguelite` folder into
   `World of Warcraft\_classic_\Interface\AddOns\`
   so the full path is
   `...\AddOns\WoWRoguelite\WoWRoguelite.toc`.
2. Enable it at the character select screen.
3. `/reload` in-game to verify it loaded — you'll see `[Roguelite] v0.1.0 loaded.` in chat.

## Build release zip

From the addon project folder, run:

```powershell
.\Build-CurseForgeRelease.ps1
```

This creates `dist\WoWRoguelite-v0.1.0.zip`, with the addon files staged under a top-level `WoWRoguelite` folder for CurseForge or manual installation.

## First-time setup

On your designated bank character:

```
/wrl setbank
```

This marks that character as the bank (stored in account-wide `SavedVariables` so every other character on your account sees it).

Bank characters are out-of-run infrastructure. They are not subject to roguelite rules, death retirement, taint logging, boon/burden limits, or contribution restrictions; they may trade, mail, use the Auction House, group, travel, die, and respawn freely while stocking and fulfilling rewards.

## How a run works

**On a new character:**

- Open `/wrl` → **New Run** tab
- Tick any unlocked tier bundles you want sent to you
- Click **Send Request** — this addon-whispers your bank character
- If the bank is offline, use **Send via Mail (fallback)** at any mailbox; the bank picks it up on next login

**On your bank character:**

- Open `/wrl` → **Requests** tab — you'll see incoming kits with a shopping list
- Go to a mailbox, click **Fulfill via Mail**: name/subject/gold pre-fill; drag items into the attachment slots; press Send
- Or open a **Trade** window with the requester and click **Load into Trade**: the addon auto-adds items and money from your bags

**On death (non-bank characters):**

- If you have lives left (only Tier 4 grants any in v1), you get a soft popup — carry on
- On final death the addon snapshots your carried gold + vendor value and offers to pre-fill a mail to the bank
- The character is marked **retired**; further play won't be credited

## Slash commands

```
/wrl                - toggle the main window
/wrl setbank        - designate the current character as the bank
/wrl bank           - show which character is currently the bank
/wrl request        - jump to the New Run tab
/wrl debug          - toggle debug logging
/wrl reset confirm  - wipe saved data (cannot be undone)
```

## Tier ladder (v1)

| Tier | Name        | Threshold | Grants                                                         |
|------|-------------|-----------|----------------------------------------------------------------|
| 0    | Survivalist | 0g        | 2× 6-slot bags, 50s seed                                       |
| 1    | Adventurer  | 50g       | 2× 10-slot bags, 5× Lesser Healing Potions, 2g                 |
| 2    | Veteran     | 250g      | 2× 12-slot bags, Healing Potions, 40g mount stipend            |
| 3    | Champion    | 1000g     | 2× 14-slot bags, Superior Healing Potions, 600g epic fund      |
| 4    | Legend      | 5000g     | 2× 16-slot Netherweave, Super Healing Potions, 5000g flying    |
|      |             |           | **+1 life for next run**                                       |

Tune these in `Core/Tiers.lua`.

## File layout

```
WoWRoguelite/
├── WoWRoguelite.toc           addon manifest
├── WoWRoguelite.lua           bootstrap, slash commands, module registry
├── Core/
│   ├── Database.lua           SavedVariables schema + character records
│   ├── Tiers.lua              tier definitions + progress helpers
│   ├── Vendor.lua              vendor-value calculation
│   ├── Comm.lua                addon-whisper protocol between characters
│   ├── Requests.lua            request queue + mail/trade fulfillment
│   └── Death.lua               PLAYER_DEAD handler + retirement flow
└── UI/
    ├── Theme.lua               GW2-style palette + widget constructors
    ├── MainFrame.lua           main window + tabs + minimap button
    ├── Tab_Contributions.lua   per-character contribution bars
    ├── Tab_Tiers.lua           tier ladder progress
    ├── Tab_Requests.lua        bank-side pending requests
    └── Tab_NewRun.lua          requester-side kit selector
```

## Known limits of this first draft

- **Send button not automated.** Blizzard doesn't let addons press Send on mail or Trade — those are protected. The addon pre-fills everything and shows you the shopping list; you confirm.
- **Contribution accounting is still estimated for items.** On final death the addon snapshots carried gold and bag vendor value, then on `MAIL_SEND_SUCCESS` credits only the gold and bag value that actually left the character since the snapshot. Blizzard does not expose the exact sent attachments back to addons, so item value is still recorded as an estimate.
- **Cross-realm addon whispers** aren't guaranteed in BC; the mail-fallback path exists for this reason.
- **Retirement is soft.** The addon marks a character retired but doesn't delete them or block play — it just stops crediting further contributions. If you want hard deletion, that's on you.

## Next steps / backlog

- Add a manual reconciliation UI for rare cases where a final contribution mail needs adjustment.
- Gather-helper tooltip on item icons in bags, showing "needed for request from X".
- Per-character class tint on the contribution bars.
- Sound/toast on incoming request.
- Config panel for tier thresholds and reward items.
- Export run history as CSV for players who want to chart their own progress.
