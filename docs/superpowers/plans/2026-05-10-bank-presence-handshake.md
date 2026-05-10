# Bank Presence Handshake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a run character detect that an off-account banker is online when the banker is not discoverable through guild roster or character friends.

**Architecture:** Keep guild/friend roster checks as the first, cheap status sources, then add a lightweight addon-whisper presence handshake for the `unknown` case. `Core/BankStatus.lua` owns cached presence state and UI refreshes; `Core/Comm.lua` transports `PING`/`PONG` messages alongside the existing request protocol.

**Tech Stack:** WoW Classic/TBC Lua addon APIs, existing `WRLv1` addon-whisper protocol in `Core/Comm.lua`, existing Lua test harness under `Tests/`.

---

## Root Cause

`Core/BankStatus.lua` only checks `GetGuildRosterInfo` and `GetFriendInfo`. If the configured bank is on another account and is not visible in those local rosters, `Status()` falls through to `return "unknown", "Unknown"` at `Core/BankStatus.lua:87`.

The request channel in `Core/Comm.lua` already uses addon whispers to the configured bank, but status detection never sends a presence probe or consumes a presence reply. This is why the UI can remain `Unknown` even when the banker is online with the addon loaded.

## File Structure

- Modify: `Core/BankStatus.lua`
  - Add cached presence state keyed by bank character.
  - Add `Ping(bankKey)`, `MarkSeen(bankKey)`, and timeout-aware status logic.
  - Trigger pings from `Status()`/UI refresh without spamming.
- Modify: `Core/Comm.lua`
  - Add protocol ops `PING` and `PONG`.
  - Reply to pings on the bank character.
  - Notify `BankStatus` when a pong arrives from the configured bank.
- Modify: `Tests/BankStatus.test.lua`
  - Cover unknown roster status becoming `online` after a pong.
  - Cover stale presence expiring back to `unknown`.
- Create: `Tests/CommPresence.test.lua`
  - Verify non-bank characters send `PING`.
  - Verify bank characters reply with `PONG`.
  - Verify a run character marks the bank as seen on `PONG`.

## Task 1: Add BankStatus Presence Cache

**Files:**
- Modify: `Core/BankStatus.lua`
- Modify: `Tests/BankStatus.test.lua`

- [ ] **Step 1: Add failing tests for active and stale presence**

Append tests to `Tests/BankStatus.test.lua` that set guild and friend counts to zero, call `ns.BankStatus:MarkSeen("Bank-Realm", 100)`, and assert `Status("Bank-Realm")` returns `online, "Online (addon)"` while `time()` is within the freshness window. Add a second test where `time()` is past the freshness window and assert the status returns `unknown, "Unknown"`.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run: `lua Tests/BankStatus.test.lua`

Expected: FAIL because `MarkSeen` does not exist yet.

- [ ] **Step 3: Implement minimal cache helpers**

In `Core/BankStatus.lua`, add constants and a cache near the top:

```lua
local PRESENCE_TTL = 90
local PING_COOLDOWN = 30
local seenAtByKey = {}
local pingedAtByKey = {}
```

Add helpers:

```lua
local function now()
    return time and time() or 0
end

function B:MarkSeen(bankKey, when)
    if not bankKey or bankKey == "" then return end
    seenAtByKey[normName(bankKey)] = when or now()
    self:NotifyChanged()
end

function B:Ping(bankKey)
    if not bankKey or bankKey == "" then return false end
    if ns.Database and ns.Database.IsBankCharacter and ns.Database:IsBankCharacter() then return false end
    local key = normName(bankKey)
    local t = now()
    if pingedAtByKey[key] and (t - pingedAtByKey[key]) < PING_COOLDOWN then return false end
    pingedAtByKey[key] = t
    if ns.Comm and ns.Comm.SendPresencePing then
        return ns.Comm:SendPresencePing(bankKey)
    end
    return false
end
```

In `Status()`, after friend status fails and before returning unknown, check:

```lua
local seenAt = seenAtByKey[normName(bankKey)]
if seenAt and (now() - seenAt) <= PRESENCE_TTL then
    return "online", "Online (addon)", "addon"
end
self:Ping(bankKey)
return "unknown", "Unknown"
```

- [ ] **Step 4: Run the focused test and confirm it passes**

Run: `lua Tests/BankStatus.test.lua`

Expected: PASS.

## Task 2: Add Comm PING/PONG Transport

**Files:**
- Modify: `Core/Comm.lua`
- Create: `Tests/CommPresence.test.lua`

- [ ] **Step 1: Write failing transport tests**

Create `Tests/CommPresence.test.lua` with a harness for `Core/Comm.lua` that stubs `C_ChatInfo.SendAddonMessage`, `ns.Database:IsBankCharacter()`, `ns:UnitKey()`, and `ns.BankStatus:MarkSeen()`.

Verify:

```lua
ns.Comm:SendPresencePing("Bank-Realm")
-- expected sent message: prefix WRL_COMM, text WRLv1|PING|Player-Realm, channel WHISPER, target Bank-Realm
```

Verify:

```lua
ns.Comm:Receive("WRLv1|PING|Run-Realm", "Run-Realm", "WHISPER")
-- when current character is the bank, expected PONG whisper back to Run-Realm
```

Verify:

```lua
ns.Comm:Receive("WRLv1|PONG|Bank-Realm", "Bank-Realm", "WHISPER")
-- expected ns.BankStatus:MarkSeen("Bank-Realm")
```

- [ ] **Step 2: Run the new test and confirm it fails**

Run: `lua Tests/CommPresence.test.lua`

Expected: FAIL because `SendPresencePing` and `PING`/`PONG` handling do not exist yet.

- [ ] **Step 3: Implement presence ops**

In `Core/Comm.lua`, add:

```lua
local function sendWhisper(target, msg)
    if C2_ChatInfo and C2_ChatInfo.SendAddonMessage then
        return C2_ChatInfo.SendAddonMessage(prefix, msg, "WHISPER", target)
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        return C_ChatInfo.SendAddonMessage(prefix, msg, "WHISPER", target)
    elseif SendAddonMessage then
        SendAddonMessage(prefix, msg, "WHISPER", target)
        return true
    end
    return false
end

function C:SendPresencePing(bankCharKey)
    local fromKey = ns:UnitKey()
    if not bankCharKey or not fromKey then return false end
    return sendWhisper(bankCharKey, encode("PING", fromKey))
end

function C:SendPresencePong(toKey)
    local fromKey = ns:UnitKey()
    if not toKey or not fromKey then return false end
    return sendWhisper(toKey, encode("PONG", fromKey))
end
```

In `Receive()`, before `REQ` handling:

```lua
if op == "PING" then
    if ns.Database and ns.Database.IsBankCharacter and ns.Database:IsBankCharacter() then
        self:SendPresencePong(payload)
    end
    return
elseif op == "PONG" then
    if ns.BankStatus and ns.BankStatus.MarkSeen then
        ns.BankStatus:MarkSeen(payload ~= "" and payload or sender)
    end
    return
end
```

- [ ] **Step 4: Refactor existing request/ack sends through `sendWhisper`**

Replace duplicate send branches in `SendRequest`, `SendAck`, and `SendAck2` with `sendWhisper(...)`. Keep existing printed messages and behavior.

- [ ] **Step 5: Run comm tests**

Run: `lua Tests/CommPresence.test.lua`

Expected: PASS.

## Task 3: Refresh UI From Presence Changes

**Files:**
- Modify: `Core/BankStatus.lua`
- Verify: `UI/MainFrame.lua`
- Verify: `UI/Tab_NewRun.lua`

- [ ] **Step 1: Confirm existing UI refresh hooks are enough**

Read `Core/BankStatus.lua:59-65`, `UI/MainFrame.lua:172-186`, and `UI/Tab_NewRun.lua:457-468`. Confirm `MarkSeen()` calls `NotifyChanged()`, and both header and New Run tab already call `Status()`.

- [ ] **Step 2: Add a small debug log for pings and pongs**

In `BankStatus:Ping()`, add:

```lua
ns:Debug("BankStatus: pinging %s for addon presence", tostring(bankKey))
```

In `BankStatus:MarkSeen()`, add:

```lua
ns:Debug("BankStatus: saw addon presence from %s", tostring(bankKey))
```

- [ ] **Step 3: Run all Lua tests**

Run:

```powershell
Get-ChildItem Tests -Filter *.test.lua | ForEach-Object { lua $_.FullName }
```

Expected: every test prints `ok`.

## Task 4: Manual In-Game Verification

**Files:**
- Verify only: `Core/BankStatus.lua`, `Core/Comm.lua`, `UI/MainFrame.lua`, `UI/Tab_NewRun.lua`

- [ ] **Step 1: Same-realm off-account online banker**

Log into the banker on account B with the addon enabled. Log into a run character on account A. Configure `/wrl setbank Bank-Realm`. Open `/wrl`.

Expected: header/New Run initially may show `Unknown`, then changes to `Online (addon)` after the ping/pong round trip.

- [ ] **Step 2: Offline banker**

Log out the banker. Reload the run character or wait past the presence TTL.

Expected: if the banker is not in guild/friends, status returns to `Unknown`; mail fallback remains available.

- [ ] **Step 3: Guild/friend banker still works**

Put the banker in guild or character friends and repeat.

Expected: `Online (guild)`, `Offline (guild)`, `Online (friends)`, or `Offline (friends)` still come from roster APIs and are not overwritten by stale addon presence.

## Self-Review

- Spec coverage: Covers the reported off-account unknown-online gap by adding addon-level presence detection.
- Placeholder scan: No placeholder implementation steps remain.
- Type consistency: `SendPresencePing`, `SendPresencePong`, `MarkSeen`, `Ping`, and `Status` are named consistently across tasks.
