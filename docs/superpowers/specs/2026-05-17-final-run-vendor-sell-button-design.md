# Final Run Vendor Sell Button Design Brief

## Goal

Add a vendor-only WRL button that appears after a character has reached final death and is waiting to make their final contribution. The button lets the player confirm once, then automatically sells all vendorable inventory items and equipped gear so the existing currency-only contribution mail flow has the money it needs.

## Player Experience

When a dead run reaches a vendor, the merchant frame shows a clear WRL action: `Sell Final Run`.

Clicking the button opens a confirmation popup. The popup explains that WRL will sell all vendorable bag contents and equipped gear for this dead pending run, shows the estimated bag value, equipped gear value, current money, and expected contribution after postage, then asks the player to confirm.

After confirmation, WRL sells the items automatically, prints a short result message, and directs the player to go to a mailbox. The existing `/wrl contribute` and mailbox prefill flow remains responsible for sending currency to the bank. WRL still does not auto-click Send.

## Visibility Rules

The button appears only when all of these are true:

- the merchant frame is open
- the current character is not the bank
- the current run state is `dead_pending_contribution`
- at least one vendorable bag item or equipped item is detected

The button hides for active runs, soft deaths with lives remaining, retired or archived characters, bank characters, and non-vendor interactions.

## Selling Behavior

On confirm, WRL sells:

- all vendorable inventory and bag items
- all vendorable equipped gear

Items with no vendor value, unknown sell price, or no cached item info are skipped. WRL should not attempt to sell quest/no-value items. If an item is locked or temporarily unavailable, it is skipped and reported in a concise summary.

The sale should happen only from `dead_pending_contribution`; this is the main safety rail that prevents accidental gear liquidation on living runs.

## Architecture

Add a small merchant-facing module, likely `Core/Merchant.lua`, loaded after `Core/Vendor.lua`.

Responsibilities:

- listen for merchant open/close events
- create and place the WRL button on the merchant frame
- decide whether the button is visible
- build a sell plan from `Core/Vendor.lua` snapshot data
- show the confirmation popup
- execute the confirmed sale
- print a final summary and point back to the mailbox flow

Extend `Core/Vendor.lua` only where useful for reusable scan/planning helpers. Keep sell execution in the merchant module so snapshot/accounting code stays separate from destructive vendor actions.

## Contribution Flow Integration

The existing death state and mail flow stay intact:

- final death still transitions to `dead_pending_contribution`
- death snapshot still records current money, bag value, equipped gear value, and maximum potential
- the vendor button helps turn that estimate into carried money
- mailbox contribution still prepares a currency-only mail to the bank
- the player still manually presses Send
- mail-send crediting still uses the prepared mail amount

## Error Handling

WRL should fail soft and explain briefly:

- no pending final contribution: hide the button
- no vendorable items found: hide the button or print a short message if clicked after stale UI state
- merchant closes mid-sale: stop and print that the sale was interrupted
- item info not cached: skip affected items and report that some items could not be valued
- protected or unavailable item operation: skip that item and include it in the summary

## Tests

Add focused coverage for:

- button visibility only during `dead_pending_contribution` at a merchant
- button hidden for bank, active, retired, archived, and soft-death characters
- sell plan includes vendorable bag items and equipped gear
- sell plan skips no-value and unknown-price items
- confirmation path calls the sale executor
- sale result leaves the character pending contribution and does not mark the run retired

Manual in-game smoke test:

- die permanently on a test run
- revive and visit a vendor
- confirm the WRL sell button appears
- confirm the popup value estimate matches the death/vendor estimate
- confirm sale liquidates bags and equipped gear
- go to a mailbox and verify `/wrl contribute` still pre-fills currency and waits for manual Send
