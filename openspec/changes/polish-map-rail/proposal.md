# Proposal

## Why

The Map rail opens with "Map saved-file inputs", a block of about twenty developer-facing status lines (log and screenshot folder states, file timestamps, raid-panel enum names), right under the Active map picker. In a raid the player reads the map and the decision card, not that block, yet it pushes the card and Marker preferences down the rail. This change serves milestone **M4.5 - player-facing polish, item icons and own map markers** (change 1 of 7) and closes its first exit criterion: "Map saved-file inputs sits at the bottom of the rail, collapsed by default." The agent proves the widget state; the in-raid read is a user check.

The roadmap also lists "the Active map picker on its own row". `add-map-scan-snapshot` (M4) already delivered that: it removed the "Latest accepted scan" panel, and the Active map panel now holds the rail's first row alone (`lib/ui/map_screen.dart:343-368`). This change keeps that row and pins it with a test, but does not rework it.

## What Changes

- The Map rail's order becomes: Active map, the decision card, Marker preferences, Manual item search, then Map saved-file inputs, last.
- Map saved-file inputs becomes a collapsible section, collapsed by default. A collapsed section shows only its title row. One click expands it to today's content, including the Follow logs switch and the Read Latest button.
- While the section is collapsed, its content is not built, so the once-a-second saved-file age timer does not run.
- The expanded or collapsed state lasts for the session: it survives switching between Map and Scanner and a resize across the compact-layout breakpoint (1100 px). It is not saved to settings, so every launch starts collapsed.
- No status line, label or behaviour inside the section changes. `plain-language-pass` (M4.5 change 7) rewrites those strings.

## Capabilities

### New Capabilities
- `map-rail`: what the Map screen's side rail shows, in what order, and which sections start collapsed.

### Modified Capabilities
None. No existing spec covers the Map rail's layout. `latest-accepted-scan` requires that no "Latest accepted scan" panel is shown and that the Active map picker and the decision card are. This change keeps both.

## Impact

- `lib/ui/map_screen.dart`: the rail `ListView` is reordered, and the saved-file inputs panel is wrapped in a collapsible section. `_MapInputStatus` itself is unchanged.
- `lib/ui/theme.dart`: possibly a collapsible variant of `GridPanel`, so the section keeps the rail's panel look. design.md decides.
- Tests:
  - `test/ui/map_screen_test.dart`: the tests that reach Read Latest and Follow logs (`:17`, `:88`, `:216`) must expand the section first.
  - New widget tests cover: the order; collapsed by default; the state kept across a tab switch and the layout breakpoint; and no age timer while collapsed.
  - `test/widget_test.dart`, `test/ui/scanner_screen_test.dart` and `test/ui/latest_scan_card_test.dart` keep their Active map assertions.
- No data, API, settings schema or dependency changes. No live-game check is needed for the agent-verified part. The in-raid read stays with the user (AGENTS.md).
- Unblocks `add-item-icons` (M4.5 change 2), which needs this change.
