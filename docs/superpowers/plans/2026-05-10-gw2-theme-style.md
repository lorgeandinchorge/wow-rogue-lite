# GW2 Theme Style Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `classic` the new conservative dark default style and make `gw2` use the approved heroic red-black-gold GW2-inspired direction.

**Architecture:** Keep existing theme IDs and saved setting behavior. Extend palette tables with optional semantic surface tokens, then update the shared frame/popup construction to use those tokens where they exist. Most tab content continues using existing `Theme.c.bg*`, `fg*`, and accent fields so the change stays small.

**Tech Stack:** WoW Classic/TBC Lua addon UI APIs, `UI/Theme.lua` palette registry, existing Lua tests in `Tests/ThemeSelection.test.lua`.

---

### Task 1: Theme Palette Regression Tests

**Files:**
- Modify: `Tests/ThemeSelection.test.lua`

- [ ] **Step 1: Write failing tests**

Add two tests:

```lua
local function testClassicPaletteIsConservativeDarkDefault()
    useCAddOns = false
    addonEnabled = false
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    assertEqual(ns.Theme:GetActiveThemeId(), "classic", "classic remains the default active theme")
    assertEqual(ns.Theme.c.bg0[1], 0.045, "classic default bg0 red channel is dark neutral")
    assertEqual(ns.Theme.c.headerBg[1], 0.105, "classic default has conservative dark header token")
    assertEqual(ns.Theme.c.gold[1], 0.780, "classic default has restrained gold accent")
end

local function testGw2PaletteUsesHeroicSurfaceTokens()
    useCAddOns = false
    addonEnabled = true
    addonId = "GW2_UI"
    addonTitle = "GW2 UI"
    local ns = resetHarness()

    local ok = ns.Theme:SetTheme("gw2")

    assertEqual(ok, true, "gw2 theme can be selected")
    assertEqual(ns.Theme.c.headerBg[1], 0.270, "gw2 header has warm red channel")
    assertEqual(ns.Theme.c.headerBg[2], 0.120, "gw2 header has restrained green channel")
    assertEqual(ns.Theme.c.gold[1], 0.850, "gw2 uses stronger metallic gold")
end
```

- [ ] **Step 2: Run test and confirm failure**

Run: `lua Tests/ThemeSelection.test.lua`

Expected: FAIL because `headerBg` is nil and old `classic` palette still uses parchment-brown values.

### Task 2: Implement Theme Tokens And Palettes

**Files:**
- Modify: `UI/Theme.lua`

- [ ] **Step 1: Retune `classic`**

Change `PALETTES.classic.c` to the conservative dark values:

```lua
bg0      = {0.045, 0.047, 0.055, 0.98}
bg1      = {0.095, 0.098, 0.112, 1.00}
bg2      = {0.145, 0.150, 0.170, 1.00}
bg3      = {0.220, 0.225, 0.250, 1.00}
headerBg = {0.105, 0.105, 0.120, 1.00}
navBg    = {0.072, 0.075, 0.086, 1.00}
rowBg    = {0.105, 0.108, 0.122, 1.00}
rowAccent = {0.780, 0.650, 0.360, 0.55}
fg       = {0.925, 0.895, 0.820, 1.00}
fg2      = {0.650, 0.620, 0.560, 1.00}
gold     = {0.780, 0.650, 0.360, 1.00}
goldH    = {0.930, 0.800, 0.480, 1.00}
red      = {0.760, 0.305, 0.300, 1.00}
green    = {0.410, 0.690, 0.460, 1.00}
```

- [ ] **Step 2: Retune `gw2`**

Change `PALETTES.gw2.c` to the heroic values:

```lua
bg0      = {0.035, 0.034, 0.036, 0.98}
bg1      = {0.090, 0.082, 0.078, 1.00}
bg2      = {0.155, 0.135, 0.115, 1.00}
bg3      = {0.255, 0.205, 0.155, 1.00}
headerBg = {0.270, 0.120, 0.105, 1.00}
navBg    = {0.055, 0.052, 0.055, 1.00}
rowBg    = {0.120, 0.090, 0.080, 1.00}
rowAccent = {0.850, 0.620, 0.230, 0.70}
fg       = {0.965, 0.900, 0.790, 1.00}
fg2      = {0.675, 0.610, 0.540, 1.00}
gold     = {0.850, 0.620, 0.230, 1.00}
goldH    = {1.000, 0.780, 0.350, 1.00}
red      = {0.780, 0.250, 0.200, 1.00}
green    = {0.460, 0.700, 0.460, 1.00}
```

- [ ] **Step 3: Keep `dark` distinct**

Do not change the `dark` palette except to add optional tokens only if tests or code require them.

- [ ] **Step 4: Run theme tests**

Run: `lua Tests/ThemeSelection.test.lua`

Expected: PASS for palette and existing selection behavior.

### Task 3: Apply Semantic Tokens To Shared Chrome

**Files:**
- Modify: `UI/MainFrame.lua`
- Modify: `UI/SettingsPopup.lua`

- [ ] **Step 1: Use header/nav tokens in MainFrame**

In `UI/MainFrame.lua`, use:

```lua
Theme:Fill(header, Theme.c.headerBg or Theme.c.bg1, false)
Theme:Fill(tabBar, Theme.c.navBg or Theme.c.bg1, false)
Theme:Fill(body, Theme.c.bg0, false)
```

Update `RefreshTheme()` with the same token-aware fills.

- [ ] **Step 2: Use header token in SettingsPopup**

In `UI/SettingsPopup.lua`, use:

```lua
Theme:Fill(header, Theme.c.headerBg or Theme.c.bg1, false)
```

Update `RefreshTheme()` similarly.

- [ ] **Step 3: Run theme tests**

Run: `lua Tests/ThemeSelection.test.lua`

Expected: PASS.

### Task 4: Full Verification

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run all Lua tests**

Run:

```powershell
Get-ChildItem Tests -Filter *.test.lua | ForEach-Object { lua $_.FullName }
```

Expected: every test file prints `ok`.

- [ ] **Step 2: Manual visual check**

In game, select `classic`, `dark`, and `gw2`:

- `classic` should look like the Conservative Tune mockup.
- `dark` should remain cooler and quieter.
- `gw2` should show the Heroic GW2 Skin direction when GW2 UI is detected.
