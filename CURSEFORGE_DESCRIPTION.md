# WoW Roguelite

WoW Roguelite is a run-based progression addon for WoW Classic.

You choose one character to act as your bank. Every other character becomes a run. When a run ends, its contribution helps fund the next generation. Over time, your account builds a legacy bank that unlocks stronger starter kits for future characters.

It is part hardcore challenge, part account progression, and part self-made metagame.

## Core Idea

- One character is your bank.
- Other characters are runs.
- Final death retires a run.
- Retired runs contribute value back into the account.
- Lifetime contributions become spendable legacy budget.
- New runs can request unlocked Storage, Stipend, Alchemist's Table, and Fate rewards from the bank.

## What The Addon Tracks

- current run state
- bank character assignment
- account-wide contribution totals
- unlocked legacy rewards
- request and fulfillment flow between run and bank
- bank reporting, aggregate supplies, and resale ledgers
- manual loan cap, debt, and repayment accounting
- roguelite rule profiles
- optional boons and burdens for a run
- retirements, rule logs, and exports

## Main Features

### Latest Update: v0.4.0b - Legacy Revamp Completion

- Legacy unlocks now use a talent-board style layout with connected unlock nodes and clearer owned, available, and locked states.
- **Available Legacy Rewards** summarizes your currently unlocked starter-kit pieces: bags, gold, potions, and extra lives.
- Alchemist's Table rewards now grant potions in multiples of five.
- Death sounds are selectable under Settings, with Dark Souls as the default plus Off and Random options.
- Achievement coverage now includes 10-level milestones, death-decade milestones, Insert Coin, and total-death milestones.

### Bank And Run Structure

Set one character as your bank with `/wrl setbank`. The bank is treated as infrastructure, not as a run, so it can handle storage, mail, trading, and reward fulfillment.

### Account-Wide Progression

When a run dies permanently, the addon tracks its final contribution and adds it to your lifetime total. At a vendor, use **WRL: Sell All** to confirm and liquidate vendorable bags plus equipped gear. At a mailbox, use **WRL: Contribute** to prepare the currency-only handoff to the bank. That total becomes spendable budget for permanent legacy unlocks.

### Starter Reward Requests

On a new run, spend budget on the Legacy tab, then open the Rewards tab, choose an unlocked starter reward, and prepare a request mail for the bank. On the bank character, open the Rewards tab to see what is needed and fulfill it by mail or trade.

### Loans Prototype

Loans are fully manual. The addon records the loan paperwork and shows debt/cap visibility, but it does not mail, trade, or move gold. The bank can record a loan after handing gold over manually, and repayments are accounted for before normal contribution credit.

### Banker Reporting

The bank Dashboard is the main work surface for final fulfillment: Requisitions Desk, Banker Summary, Needed Supplies, Account Summary, Contribution Board, Loans Desk, Resale Desk, and Recent Ledger all live together so the banker can see what is ready, what is missing, what is owed, and what was recently handled.

### Profiles, Rules, And Run Modifiers

Choose from built-in profiles like Casual Roguelite, Banked Hardcore, Solo Self Found, and Ironman. You can also customize individual rule toggles and set boons and burdens from Settings under Run Modifiers.

Settings also includes confirmed resets for core account sections: achievements, legacy progression, and ledger/economy data.

### Export And Audit Tools

Use `/wrl export` to generate a compact summary of a run or your account state for sharing, logging, or troubleshooting.

## Reward Philosophy

The addon is designed to make each run feel connected to the last one.

You are not just deleting characters and starting over. You are building a lineage:

- Storage: better bags
- Stipend: starter gold
- Alchemist's Table: healing potions
- Fate: rare extra lives

Each death still matters, but it also helps push the account forward.

## Important Limitation

Because of Blizzard API restrictions, the addon cannot click protected buttons for you. It can prepare mail and trade actions, show the shopping list, and assist with fulfillment, but the player must still confirm the final send or trade manually.

## Slash Commands

```text
/wrl
/wrl help
/wrl setbank
/wrl bank
/wrl settings
/wrl profile
/wrl rules
/wrl export
/wrl contribute
/wrl bankreport
/wrl needed
/wrl loan
/wrl loan borrow
/wrl loan repay
/wrl simloan
/wrl sellfinal
```

## Good Fit If You Want

- a self-imposed hardcore progression mode
- account-wide persistence between runs
- a bank-driven legacy system
- more structure for reroll-heavy play
- a personal roguelite layer on top of WoW Classic

## Early Version Note

This project is still in an early version, so feedback on bugs, rough edges, and confusing UI is especially helpful.
