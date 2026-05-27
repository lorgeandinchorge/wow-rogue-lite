# WoW Roguelite Tester Guide

This version of the smoke test is meant to be shared with external testers.

Please focus on whether the addon feels stable, understandable, and usable in normal play. You do not need to test every edge case.

## What This Addon Does

WoW Roguelite turns your account into a run-based progression system:

- Pick one character as your bank.
- Every other character is a run character.
- When a run dies for good, that character retires.
- Retired runs contribute value to the bank.
- Lifetime contributions become budget for starter-kit unlocks.
- New runs can request unlocked Storage, Stipend, Alchemist's Table, and Fate rewards from the bank.

## Before You Start

1. Install the addon in `World of Warcraft\_classic_\Interface\AddOns\WoWRoguelite`.
2. Enable Lua errors if you know how. If not, that is fine.
3. Use at least two characters if possible:
   - one bank character
   - one run character
4. If you can, test on a fresh SavedVariables setup first.

## Commands You May Need

```text
/wrl
/wrl help
/wrl setbank
/wrl bank
/wrl dashboard
/wrl account LABEL Character-Realm
/wrl bankreport
/wrl needed
/wrl simrequest Character-Realm 101,201
/wrl simresale
/wrl simresale clear
/wrl resale
/wrl resale sold 769 1 Tester-Realm
/wrl settings
/wrl profile list
/wrl rules
/wrl export
/wrl contribute
/wrl sellfinal
/reload
```

## What I Need Feedback On Most

Please prioritize these:

1. Does the addon load cleanly with no errors?
2. Is the UI understandable?
3. Can you set a bank character without confusion?
4. Can a run character request rewards successfully?
5. Can the bank character view and fulfill requests?
6. Does death and retirement behave correctly?
7. Does anything feel misleading, clunky, or unclear?

## Fast Test Pass

If you only have 10 to 15 minutes, please do this section.

### 1. Load And Open

- [ ] Log in with the addon enabled.
  Expected: no visible errors, and chat shows the addon loaded.

- [ ] Run `/wrl`.
  Expected: the main window opens.

- [ ] Run `/wrl help`.
  Expected: slash commands print without errors.

- [ ] Click through every tab once.
  Expected: each tab opens and displays content without breaking.

### 2. Bank Setup

- [ ] On your bank character, run `/wrl setbank`.
  Expected: the addon confirms that character as the bank.

- [ ] Run `/wrl bank`.
  Expected: the correct bank character is shown.

- [ ] Open the addon on a different character.
  Expected: the same bank is visible account-wide.

### 3. Rewards Flow

- [ ] Open the addon on a non-bank character.
  Expected: the run character can view Dashboard, Achievements, Legacy, and Rewards cleanly.

- [ ] Open the Rewards tab.
  Expected: it clearly explains this is where starter reward request mail is prepared.

- [ ] Open the Legacy tab and unlock an affordable Storage, Stipend, Alchemist's Table, or Fate node if budget is available.
  Expected: available budget decreases, the node becomes unlocked, **Unlocks available** increments, and the UI refreshes cleanly.

- [ ] Open gear Settings and find **Run Modifiers**.
  Expected: boons and burdens appear there, not inside the Rewards tab.

- [ ] In gear Settings, switch from **Options** to **Resets**.
  Expected: separate confirmed reset controls appear for achievements, legacy progression, and ledger/economy data.

- [ ] If rewards are unlocked, choose one from the Rewards dropdown and click **Prepare Mail** at a mailbox.
  Expected: the request mail is prepared cleanly and final Send remains manual.

### 4. Requisitions Desk / Rewards Flow

- [ ] On the bank character, open the Dashboard tab.
  Expected: the Requisitions Desk shows an active request, readiness details, Banker Summary, Needed Supplies, Account Summary, character contribution rows, Resale Desk goods, Loans Desk, and recent ledger activity.

- [ ] If you do not have a live request, run `/wrl simrequest Tester-Realm 101`.
  Expected: the Requisitions Desk receives a simulated pending request for testing.

- [ ] If there are multiple pending/preparing requests, click **Next Request**.
  Expected: the active request changes without leaving the Dashboard.

- [ ] Run `/wrl bankreport`.
  Expected: banker summary lines print pending/ready requests, missing item lines, resale rows, outstanding loan total, recent ledger count, and pricing source status.

- [ ] Run `/wrl needed`.
  Expected: aggregate needed supplies print by item with requested, available, missing, request count, and any tailor-made or TSM DBMarket hints.

- [ ] If a requester is unassigned, use **Assign Account** or `/wrl account LABEL Character-Realm`.
  Expected: the requester is assigned to that account label and future request/ledger lines use the label.

- [ ] Run `/wrl simresale`, then `/wrl resale`.
  Expected: the Resale Desk prints simulated catalog goods, including count, price, and a source label such as TSM, vendor, or fallback.

- [ ] Run `/wrl simloan Tester-Realm 1`, then `/wrl bankreport`.
  Expected: the Loans Desk and banker summary show outstanding debt, and Account Summary shows debt beside contribution and resale activity.

- [ ] Use **Next Resale Item** and **Record 1 Sold**, or run `/wrl resale sold 769 1 Tester-Realm` if you have Chunk of Boar Meat.
  Expected: the addon records a manual resale receipt and recent ledger activity updates; it does not move, mail, trade, auction, or vendor items.

- [ ] Click the Resale Desk clear button.
  Expected: a confirmation popup appears before simulated resale stock and COD drafts are removed.

- [ ] Click the Recent Ledger clear button.
  Expected: a confirmation popup appears, current visible ledger activity is hidden, and later bank activity appears normally.

- [ ] Use the Recent Ledger search box after fulfillment, resale, or loan activity.
  Expected: matching ledger rows remain visible and resale rows include a compact price-source label when available.

- [ ] With a pending request selected by the Requisitions Desk, click **Prepare Mail** at a mailbox.
  Expected: the mail recipient, subject, body, and gold are prepared; ready and missing item/gold checklist details remain clear, with final Send still manual.

- [ ] On the bank character, open the Rewards tab.
  Expected: incoming requests still appear clearly for detailed review.

- [ ] Check whether the shopping list is understandable.
  Expected: needed items, gold, and actions are easy to follow.

- [ ] Try mail fulfillment or trade fulfillment if possible.
  Expected: the addon assists correctly, but still leaves final protected actions to the player.

### 5. Death / Retirement

- [ ] Die on a run character if practical.
  Expected: the addon handles the death state cleanly.

- [ ] If it is a final death, follow the retirement/contribution flow.
  Expected: **WRL: Sell All** appears at a vendor, **WRL: Contribute** appears at a mailbox, the character becomes retired after sending the contribution, and the contribution flow is understandable.

## Full Test Pass

If you want to go deeper, these are the main areas to cover.

### A. Stability

- [ ] No Lua errors during login, reload, tab switching, request flow, or death flow.
- [ ] `/reload` does not wipe or scramble data.
- [ ] Saved state persists after relog or reload.

### B. UI Clarity

- [ ] Text is readable.
- [ ] Buttons make sense.
- [ ] Tooltips help when needed.
- [ ] Nothing important is clipped or overlapping.

### C. Profiles And Rules

- [ ] Switching profiles works.
- [ ] The gear Settings popup reflects the selected profile.
- [ ] Individual rule toggles behave sensibly.
- [ ] Rule warnings are understandable when triggered.
- [ ] The Settings **Resets** surface is visible and each reset action asks for confirmation before clearing data.

### D. Rewards And Progression

- [ ] Lifetime, spent, and available budget look correct.
- [ ] Storage, Stipend, Alchemist's Table, and Fate line up side by side with vertical unlock ladders.
- [ ] The **Unlocks available: X / Y** summary matches purchased unlocks.
- [ ] Reward previews make sense in tile tooltips.
- [ ] Claimed or locked rewards are shown clearly.
- [ ] Repeat-claim behavior matches the UI.

### E. Requests

- [ ] Requests do not duplicate unexpectedly.
- [ ] Invalid/self-requests are blocked cleanly.
- [ ] Fulfilled requests do not double-credit rewards or lives.
- [ ] Bank-side bag/item guidance is useful.

### F. Legacy Contributions And Export

- [ ] Legacy contribution totals increase correctly.
- [ ] Receipts and history feel believable.
- [ ] Outstanding loans reduce future contribution credit before normal contribution progress increases.
- [ ] `/wrl export` works and produces readable output.

## Please Report These Immediately

- Addon does not load
- Window or tabs do not open
- Requests disappear or duplicate incorrectly
- Fulfillment gives the wrong rewards
- Extra lives are added more than once
- A bank character gets treated like a normal run
- Data is lost after `/reload` or relog
- Any Lua error

## Best Way To Send Feedback

Please include:

- what you were doing
- which character you were on
- what you expected
- what actually happened
- whether `/reload` fixed it
- screenshot or Lua error text if available

Use this template:

```text
Character:
Bank or run:
What I did:
What I expected:
What happened instead:
Can I reproduce it:
Lua error text:
Screenshot:
```

## Nice-To-Have Feedback

I also want soft feedback like:

- confusing wording
- unclear buttons
- features you expected but could not find
- parts of the flow that felt tedious
- anything that made the addon harder to trust

## Current Known Limitation

Blizzard does not allow addons to press protected buttons like Send Mail or Accept Trade. WoW Roguelite can prefill and assist, but the player must confirm the final action manually.
