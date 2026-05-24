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
- New runs can request unlocked Storage, Stipend, and Fate rewards from the bank.

## What The Addon Tracks

- current run state
- bank character assignment
- account-wide contribution totals
- unlocked legacy rewards
- request and fulfillment flow between run and bank
- manual loan cap, debt, and repayment accounting
- roguelite rule profiles
- optional boons and burdens for a run
- retirements, rule logs, and exports

## Main Features

### Latest Update: v0.3.7 - Loans Prototype

- The bank Dashboard now includes a manual Loans Desk with cap, debt, available borrow room, borrower, and recent loan activity.
- Loan cap is based on the highest purchased Legacy rank: `floor(rank * 3 / 2)` gold.
- Borrowing is enforced by linked account while receipts keep the borrower character for audit.
- Contribution credit now repays outstanding account debt first; only overflow becomes normal contribution progress.
- `/wrl loan`, `/wrl loan borrow`, `/wrl loan repay`, and `/wrl simloan` support prototype testing and fallback entry.

### Bank And Run Structure

Set one character as your bank with `/wrl setbank`. The bank is treated as infrastructure, not as a run, so it can handle storage, mail, trading, and reward fulfillment.

### Account-Wide Progression

When a run dies permanently, the addon tracks its final contribution and adds it to your lifetime total. At a vendor, use **WRL: Sell All** to confirm and liquidate vendorable bags plus equipped gear. At a mailbox, use **WRL: Contribute** to prepare the currency-only handoff to the bank. That total becomes spendable budget for permanent legacy unlocks.

### Starter Reward Requests

On a new run, spend budget on the Legacy tab, then open the Rewards tab, choose an unlocked starter reward, and prepare a request mail for the bank. On the bank character, open the Rewards tab to see what is needed and fulfill it by mail or trade.

### Loans Prototype

Loans are fully manual. The addon records the loan paperwork and shows debt/cap visibility, but it does not mail, trade, or move gold. The bank can record a loan after handing gold over manually, and repayments are accounted for before normal contribution credit.

### Profiles, Rules, And Run Modifiers

Choose from built-in profiles like Casual Roguelite, Banked Hardcore, Solo Self Found, and Ironman. You can also customize individual rule toggles and set boons and burdens from Settings under Run Modifiers.

### Export And Audit Tools

Use `/wrl export` to generate a compact summary of a run or your account state for sharing, logging, or troubleshooting.

## Reward Philosophy

The addon is designed to make each run feel connected to the last one.

You are not just deleting characters and starting over. You are building a lineage:

- Storage: better bags
- Stipend: starter gold
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
