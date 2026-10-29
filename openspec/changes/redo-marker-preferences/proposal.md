# Proposal

## Why

The Marker preferences panel on the Map rail lists each marker category as a `FilterChip` labelled with its raw filter key (`PmcExtracts`, `lootLoose`, `stationaryWeapons`), sorted by that key (`lib/ui/map_screen.dart:463-483`, `:307`). A player in a raid has to decode developer names and cannot match a chip to the marker it hides. Since `add-map-marker-icons`, every category draws its own Blackgrid-authored badge on the map, so the panel can show the same badge the player sees on the map.

This change serves milestone **M4.5 - player-facing polish, item icons and own map markers** (change 5 of 7, needs `add-map-marker-icons`, which is merged). It closes the exit criterion "Marker preferences is a uniform grid of clickable icon tiles with player-facing labels. Show all, Hide all, search and the quest filters keep working." It also feeds "Player-facing strings use plain language: no raw enum names or internal category keys", which `plain-language-pass` (change 7) finishes.

## What Changes

- The category chips become a grid of tiles that are all the same size. Each tile shows the category's map badge (the same disc, ring and glyph the map draws, from `MapMarkerIcons`) above a player-facing label. Clicking anywhere on a tile shows or hides that category, as the chip did.
- A shown tile draws its badge at full opacity with a check mark. A hidden tile draws the badge dimmed, with no check mark and a muted label, so the state does not rely on colour alone. Each tile is announced as a toggle with its label and its state.
- A fixed table of player-facing labels covers every marker category key (for example `PmcExtracts` → "PMC extracts", `lootLoose` → "Loose loot", `CustomPins` → "Saved pins"). The tiles follow a fixed order that groups related categories (extracts, quests, danger, spawns, loot, utility, then saved pins), replacing the sort by raw key. Only keys Blackgrid can save as a preference get a tile, and Show all and Hide all write only those. Today the chips and bulk buttons would also write a key the map carries that settings cannot store, which the settings loader then rejects on the next launch. A marker with such a key stays drawn.
- Until the icons are loaded, or when one fails, the tile draws the same fallback badge the map uses (ring and centre dot), so the grid never waits on the icons.
- The same labels replace the raw key in the "Visible map markers and pins" list subtitle and in each marker's map semantics label (`lib/ui/map_workspace.dart:148`, `:739`).
- No other behaviour changes. Search, the quest name and trader filters, Show all and Hide all (apart from the saveable-key limit above), Save marker filters, the saved `markerFilters` keys and the panel's place in the rail stay as they are.

## Capabilities

### New Capabilities
- `marker-preferences`: what the Map rail's Marker preferences panel shows and how a player shows or hides marker categories: the icon tile grid, the player-facing category labels and their order, the tile states and fallback, and the bulk and search controls that sit with them.

### Modified Capabilities
- None. `map-rail` fixes only the panel's place in the rail, which does not change. `map-marker-icons` defines the badge, which the tiles reuse without changing.

## Impact

- `lib/ui/map_screen.dart`: the Marker preferences panel builds the tile grid instead of the chips.
- New player-facing label and order table for marker category keys, next to `markerCategories` in `lib/domain/`.
- `lib/maps/map_marker_icons.dart` and `lib/ui/map_workspace.dart`: the badge drawing moves into one shared function used by the map painter and the tiles, so the two cannot drift apart.
- `lib/ui/map_workspace.dart`: the marker list subtitle and marker semantics labels use the label table.
- Tests: label and order unit tests; tile widget tests (state, toggle, fallback, Show all and Hide all); existing tests that find chips by raw key (`test/ui/map_screen_test.dart`, `test/maps/map_viewport_test.dart`) find tiles by label instead.
- No settings format, data, dependency or bundle change.
