# Theme Persistence And TOC Currency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make theme selection feel durable and immediate, and stop WoW from flagging the addon as out of date on TBC Anniversary.

**Architecture:** Keep `WRL_DB.settings.uiTheme` as the persisted account-wide setting, but refresh built UI frames immediately after theme changes so the visible UI matches the saved value. Update TOC metadata to the current TBC 2.5.5 interface number and add a small metadata/version check so this does not regress silently.

**Tech Stack:** WoW Classic/TBC Lua addon APIs, `.toc` addon metadata, existing Lua test harness under `Tests/`.

---

## Root Cause

Theme persistence storage is present: `Core/Settings.lua` merges `uiTheme` into `WRL_DB.settings`, and `UI/Theme.lua:SetTheme()` writes `ns.Settings:Set("uiTheme", themeId)`. The existing `Tests/ThemeSelection.test.lua` passes, so the stored setting path itself is not currently broken.

The user-facing problem is that `SetTheme()` only updates `Theme.c`; existing frames, textures, buttons, and font strings built from the old colors are not fully repainted unless `/reload` or a fresh login rebuilds them. `UI/SettingsPopup.lua:169-171` even prints that reload is needed. That makes a saved choice look unreliable, especially when switching characters or logging out after seeing the old colors remain.

The out-of-date warning is direct: `WoWRoguelite.toc:1` declares `## Interface: 20504`. Current Burning Crusade Classic / TBC Anniversary uses interface `20505`; Warcraft Wiki’s TOC format page lists TBC as `20505`, and its Patch 2.5.5 page lists interface `.toc` as `20505`.

Sources:
- `https://warcraft.wiki.gg/wiki/TOC_format`
- `https://warcraft.wiki.gg/wiki/Patch_2.5.5`

## File Structure

- Modify: `UI/Theme.lua`
  - Make `SetTheme()` optionally refresh the current UI after applying a new active theme.
  - Add a helper that notifies `MainFrame` and `SettingsPopup` consistently.
- Modify: `UI/MainFrame.lua`
  - Expand `RefreshTheme()` so visible top-level elements, tab labels, and active panel surfaces are recolored enough to avoid stale-theme confusion.
- Modify: `UI/SettingsPopup.lua`
  - Refresh the popup’s own frame/header/dropdowns/toggles after theme changes.
  - Update copy so selecting a theme no longer tells players reload is always required.
- Modify: `WoWRoguelite.toc`
  - Change `## Interface: 20504` to `## Interface: 20505`.
  - Keep version metadata consistent with release docs if desired.
- Modify: `README.md`
  - Update install/release snippets if the visible version changes.
- Create: `Tests/TocMetadata.test.lua`
  - Assert the TOC interface is current for TBC Anniversary.

## Task 1: Add Metadata Regression Test

**Files:**
- Create: `Tests/TocMetadata.test.lua`
- Modify: `WoWRoguelite.toc`

- [ ] **Step 1: Write failing TOC interface test**

Create `Tests/TocMetadata.test.lua`:

```lua
local function readFile(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

local toc = readFile("WoWRoguelite.toc")
local interface = toc:match("##%s*Interface:%s*([^\r\n]+)")
if interface ~= "20505" then
    error(("expected WoWRoguelite.toc Interface 20505, got %s"):format(tostring(interface)), 2)
end

print("TocMetadata.test.lua: ok")
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `lua Tests/TocMetadata.test.lua`

Expected: FAIL with `expected WoWRoguelite.toc Interface 20505, got 20504`.

- [ ] **Step 3: Update TOC interface**

Change `WoWRoguelite.toc`:

```toc
## Interface: 20505
```

- [ ] **Step 4: Run the metadata test and confirm it passes**

Run: `lua Tests/TocMetadata.test.lua`

Expected: PASS.

## Task 2: Make Theme Changes Repaint Immediately

**Files:**
- Modify: `UI/Theme.lua`
- Modify: `UI/MainFrame.lua`
- Modify: `UI/SettingsPopup.lua`
- Modify: `Tests/ThemeSelection.test.lua`

- [ ] **Step 1: Add failing test for refresh notification**

In `Tests/ThemeSelection.test.lua`, add a test harness flag:

```lua
local refreshed = false
ns.MainFrame = {
    RefreshTheme = function()
        refreshed = true
    end,
}
```

Add a test:

```lua
local function testSetThemeRefreshesVisibleUi()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()
    local refreshed = false
    ns.MainFrame = { RefreshTheme = function() refreshed = true end }

    local ok = ns.Theme:SetTheme("dark")

    assertEqual(ok, true, "dark theme selection succeeds")
    assertEqual(refreshed, true, "theme selection refreshes visible UI")
end
```

- [ ] **Step 2: Run the theme test and confirm it fails**

Run: `lua Tests/ThemeSelection.test.lua`

Expected: FAIL because `SetTheme()` does not notify `MainFrame:RefreshTheme()`.

- [ ] **Step 3: Add a theme change notifier**

In `UI/Theme.lua`, add:

```lua
function Theme:NotifyThemeChanged()
    if ns.MainFrame and ns.MainFrame.RefreshTheme then
        ns.MainFrame:RefreshTheme()
    end
    if ns.SettingsPopup and ns.SettingsPopup.RefreshTheme then
        ns.SettingsPopup:RefreshTheme()
    elseif ns.SettingsPopup and ns.SettingsPopup.Refresh then
        ns.SettingsPopup:Refresh()
    end
end
```

Update `SetTheme()`:

```lua
local prior = self.activeThemeId
self:ApplyConfiguredTheme()
if prior ~= self.activeThemeId then
    self:NotifyThemeChanged()
end
return true
```

- [ ] **Step 4: Expand MainFrame refresh coverage**

In `UI/MainFrame.lua:218-232`, keep the existing top-level refresh and add direct recoloring for:

```lua
if self.statsTotal then self.statsTotal:SetTextColor(Theme.c.gold[1], Theme.c.gold[2], Theme.c.gold[3], 1) end
if self.statsBank then self.statsBank:SetTextColor(Theme.c.fg2[1], Theme.c.fg2[2], Theme.c.fg2[3], 1) end
for key, tab in pairs(self.tabs or {}) do
    if tab.SetSelected then tab:SetSelected(key == self._activeTab) end
end
```

Then call `self:RefreshHeader()` and `self:RefreshCurrentTab()` as it already does.

- [ ] **Step 5: Add SettingsPopup refresh helper**

In `UI/SettingsPopup.lua`, add:

```lua
function Popup:RefreshTheme()
    if not self.frame then return end
    local Theme = ns.Theme
    Theme:Fill(self.frame, Theme.c.bg0, true)
    if self.themeLabel then setTextColor(self.themeLabel, Theme.c.goldH, 1) end
    if self.deathLabel then setTextColor(self.deathLabel, Theme.c.goldH, 1) end
    if self.optionsLabel then setTextColor(self.optionsLabel, Theme.c.goldH, 1) end
    self:Refresh()
end
```

Store the popup header as `self.header` during `Init()` and recolor it too:

```lua
self.header = header
```

```lua
if self.header then Theme:Fill(self.header, Theme.c.bg1, false) end
```

- [ ] **Step 6: Update theme selection copy**

In `UI/SettingsPopup.lua:169-171`, change the print to:

```lua
ns:Print("UI theme set to %s.", itemLabel)
```

In `WoWRoguelite.lua` slash command theme success copy, change:

```lua
ns:Print("UI theme set to %s.", ns.Theme:ThemeLabel(themeId))
```

- [ ] **Step 7: Run theme tests**

Run: `lua Tests/ThemeSelection.test.lua`

Expected: PASS.

## Task 3: Manual Verification

**Files:**
- Verify: `WoWRoguelite.toc`
- Verify: `UI/Theme.lua`
- Verify: `UI/MainFrame.lua`
- Verify: `UI/SettingsPopup.lua`

- [ ] **Step 1: Addon list**

Open the WoW addons list on TBC Anniversary.

Expected: WoW Roguelite no longer appears out of date when the client is on interface `20505`.

- [ ] **Step 2: Theme immediate update**

Open `/wrl`, gear button, change from Classic to Dark.

Expected: header, popup, tab labels, and visible panel surfaces update without requiring `/reload`.

- [ ] **Step 3: Theme persistence across logout**

Set Dark, log out cleanly, log back in, open `/wrl`.

Expected: `/wrl settings` prints `uiTheme = dark`, and the UI opens in Dark immediately.

- [ ] **Step 4: GW2 fallback behavior**

With GW2 UI disabled, select GW2 if unavailable should be blocked. With GW2 UI enabled, selecting GW2 should persist `uiTheme = gw2`; if GW2 UI later disappears, the selected setting remains `gw2` while active palette falls back to Dark.

## Self-Review

- Spec coverage: Covers both newly reported symptoms: theme not appearing to stay, and WoW out-of-date metadata.
- Placeholder scan: No placeholder implementation steps remain.
- Type consistency: `NotifyThemeChanged`, `RefreshTheme`, `SetTheme`, and `uiTheme` are named consistently across tasks.
