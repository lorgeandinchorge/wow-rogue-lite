# GW2 Theme Style Design

## Goal

Refresh WoW Roguelite's visual themes so the default theme feels cleaner and more modern, while the GW2 UI theme has a stronger Guild Wars 2-inspired identity.

## Decisions

- The existing `classic` theme becomes the new standard/default visual style.
- The new default style follows the mockup direction **A. Conservative Tune**:
  - dark neutral panels instead of heavy parchment-brown
  - readable warm foreground text
  - restrained gold underline and border accents
  - minimal visual drama so it works for all players
- The `gw2` theme follows the mockup direction **C. Heroic GW2 Skin**:
  - red-black header treatment
  - richer metallic gold accents
  - warmer dark panel surfaces
  - more expressive styling, but still practical for dense addon screens
- Existing users keep their stored `WRL_DB.settings.uiTheme` value.
- New installs continue to use the `classic` theme ID, but that ID now points to the refreshed conservative dark look.

## Scope

In scope:

- Update palette values in `UI/Theme.lua`.
- Add theme-aware styling tokens if needed for header, panels, rows, and accent lines.
- Keep the implementation based on simple WoW-safe textures and colors.
- Refresh open UI windows immediately using the existing theme refresh path.
- Update theme tests to reflect the new default behavior and preserve saved theme behavior.

Out of scope:

- Importing or depending on GW2 UI internal artwork.
- Changing layout structure of every tab.
- Adding new theme IDs.
- Migrating existing users from one theme ID to another.
- Reworking the full widget system beyond what is needed for the style pass.

## Theme Behavior

### Default `classic`

`classic` remains the selected default for new installs. Its visual language changes from parchment-inspired to the conservative dark style shown in the mockup.

Expected feel:

- clean addon utility surface
- dark charcoal background
- slightly lifted dark row panels
- soft gold emphasis
- no red heroic treatment

This makes the default look more polished without assuming the player uses GW2 UI.

### `dark`

`dark` remains available as the plainer neutral dark option. It should stay cooler and quieter than the refreshed `classic` theme.

Expected feel:

- neutral dark
- minimal warmth
- less gold prominence than `classic`

### `gw2`

`gw2` remains gated behind GW2 UI detection. When available and selected, it uses the heroic red-black-gold direction.

Expected feel:

- strongest personality of the three themes
- warm red-black top surfaces
- metallic gold highlights
- smoky dark body panels
- readable text and clear status colors

If GW2 UI is not detected, the existing fallback behavior remains: selected `gw2` falls back to active `dark` while preserving the stored selected value.

## Implementation Notes

The current theme system centralizes colors in `UI/Theme.lua` under `PALETTES`. The first implementation pass should start there:

- Retune `PALETTES.classic.c`.
- Retune `PALETTES.gw2.c`.
- Keep `PALETTES.dark.c` mostly stable.

If palette-only changes are not enough to carry the GW2 style, add optional palette fields such as:

```lua
headerBg
headerAccent
rowBg
rowAccent
```

Then update `Theme:Fill()` and the main frame/header construction to use those optional fields when present. Keep defaults backwards-compatible so existing code can still pass `Theme.c.bg0`, `Theme.c.bg1`, and similar fields.

The visual refresh should not add new dependencies or require GW2 UI texture paths. This keeps the addon resilient if GW2 UI changes its internal file layout.

## Testing

Automated tests:

- `Tests/ThemeSelection.test.lua` should still confirm:
  - default selected theme is `classic`
  - saved theme IDs remain selected after init
  - GW2 availability and fallback behavior still work
  - theme changes refresh visible UI

Manual visual checks:

- New install opens with the refreshed conservative default.
- `dark` still looks distinct from `classic`.
- `gw2` selected with GW2 UI enabled shows the heroic red-black-gold treatment.
- `gw2` selected without GW2 UI enabled falls back to `dark`.
- Text remains readable in the main header, tabs, rows, settings popup, and request/new-run cards.

## Risks

- Renaming theme IDs would break stored settings, so this design keeps existing IDs.
- Over-styling the GW2 theme could reduce readability on dense tabs; the implementation should preserve contrast first.
- Palette-only styling may not fully match the mockup. If that happens, add small optional theme tokens rather than rewriting every tab.

## Acceptance Criteria

- New players see the Conservative Tune-inspired style by default.
- Players who choose `gw2` see the Heroic GW2-inspired style when GW2 UI is available.
- Existing saved theme selections continue to work.
- All Lua tests pass.
- The addon uses simple colors/textures and does not depend on GW2 UI private assets.
