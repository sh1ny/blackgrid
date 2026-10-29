# Tasks

Every group follows the "Dart and Flutter code" section of `AGENTS.md`. Skills per group: 1 `dart-add-unit-test`, `dart-write-documentation`; 2 `dart-add-unit-test`, `dart-write-documentation`, `flutter-add-widget-test`; 3 `flutter-add-widget-test`, `dart-write-documentation`, `dart-use-pattern-matching`; 4 `flutter-add-widget-test`. Use hand-written fakes and the existing harnesses (`test/support/map_widget_harness.dart`, the `_Assets` loader pattern in `test/ui/map_marker_painting_test.dart`), and no sleeps. Agents never launch the app against the game. The user checks the look in the app.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Each applicable category is one icon tile | Tiles for the current map | test/ui/marker_preferences_test.dart | shows one labelled tile per saveable map key plus Saved pins | green |
| Each applicable category is one icon tile | Tiles are the same size | test/ui/marker_preferences_test.dart | every tile has the same size whatever its label | green |
| Each applicable category is one icon tile | Unsaveable category gets no tile | test/ui/map_screen_test.dart | unsaveable marker key gets no tile and stays drawn | green |
| Each applicable category is one icon tile | Map with no markers | test/ui/marker_preferences_test.dart | map without markers shows only the Saved pins tile | green |
| Category keys have fixed player-facing labels | Labels for known keys | test/domain/marker_categories_test.dart | known keys have their player-facing labels | green |
| Category keys have fixed player-facing labels | Every known key is labelled | test/domain/marker_categories_test.dart | every icon key has a unique non-empty label | green |
| Category keys have fixed player-facing labels | Every saveable key has a label | test/domain/marker_categories_test.dart | labelled keys equal markerCategories without Labels | green |
| Tiles follow a fixed grouped order | Grouped order | test/domain/marker_categories_test.dart | markerPreferenceKeys orders keys by group | green |
| Tiles follow a fixed grouped order | Map order does not matter | test/domain/marker_categories_test.dart | markerPreferenceKeys ignores input order and drops unknown keys | green |
| Clicking a tile shows or hides its category | Hide one category | test/ui/marker_preferences_test.dart | clicking a shown tile hides its category | green |
| Clicking a tile shows or hides its category | Show it again | test/ui/marker_preferences_test.dart | clicking a hidden tile shows its category | green |
| Clicking a tile shows or hides its category | Click while saving | test/ui/marker_preferences_test.dart | tiles ignore clicks while settings are saving | green |
| Tile state does not rely on colour alone | Shown and hidden tiles differ without colour | test/ui/marker_preferences_test.dart | shown tile has a check mark and hidden tile is dimmed | green |
| Tile state does not rely on colour alone | Semantics reflect the state | test/ui/marker_preferences_test.dart | tile semantics are a toggle with label and state | green |
| Tiles draw the map's badge and its fallback | Icon tile matches the map | test/ui/marker_preferences_test.dart | loaded tile draws the category glyph in its role colour | green |
| Tiles draw the map's badge and its fallback | Icons still loading | test/ui/marker_preferences_test.dart | tiles draw fallback badges and toggle while icons load | green |
| Tiles draw the map's badge and its fallback | One icon failed | test/ui/marker_preferences_test.dart | a failed icon draws the fallback badge only on its tile | green |
| Bulk, search and quest controls keep working | Hide all then Show all | test/ui/map_screen_test.dart | marker search survives show/hide-all and dimmed targets remain eligible | green |
| Bulk, search and quest controls keep working | Show all keeps other maps' choices | test/ui/map_screen_test.dart | Show all keeps saved entries of keys the map does not show | green |
| Bulk, search and quest controls keep working | Bulk action with an unsaveable category | test/ui/map_screen_test.dart | Hide all never saves an unsaveable key and settings reload | green |
| Bulk, search and quest controls keep working | Search dims without hiding | test/ui/map_screen_test.dart | marker search survives show/hide-all and dimmed targets remain eligible | green |
| Bulk, search and quest controls keep working | Quest filter keeps tiles | test/ui/map_screen_test.dart | quest filters leave tile states unchanged | green |
| Marker lists use the category labels | List subtitle uses the label | test/maps/map_viewport_test.dart | visible-markers list shows the category label | green |
| Marker lists use the category labels | Unknown key in the list | test/maps/map_viewport_test.dart | visible-markers list shows an unlabelled key as is | green |

## 1. Category labels and order

- [x] 1.1 Write `test/domain/marker_categories_test.dart` with the five domain rows of the test map: the labels for known keys, unique non-empty labels where only "Hazards", "Transits" and "Switches" equal their key, the labelled set equals `markerCategories` minus `Labels`, group order, and `markerPreferenceKeys` ignoring input order and dropping unknown keys (`Ziplines`). Also cover `markerCategoryLabel('Ziplines') == 'Ziplines'`. Verify it fails because `lib/domain/marker_categories.dart` does not exist.
- [x] 1.2 Add `lib/domain/marker_categories.dart` with the D1 table, `markerCategoryLabel` and `markerPreferenceKeys`, with `///` docs. Verify `mise run test -- test/domain/marker_categories_test.dart` passes and flip its five rows green.

## 2. Shared badge painter and the tile grid

- [x] 2.1 Move `_MapPainter._badge` (`lib/ui/map_workspace.dart:676-720`) into `paintMarkerBadge` with `MarkerBadgePaints` in `lib/maps/map_marker_icons.dart` (D2), with `///` docs, and make `_MapPainter` call it with its own paints. Verify `test/ui/map_marker_painting_test.dart` passes unchanged.
- [x] 2.2 Write `test/ui/marker_preferences_test.dart` for the nine grid rows in the test map: the tile set with no raw key text, equal tile sizes, Saved pins only, hide and show by click through the real `SettingsController`, inert while `busy`, check mark versus 22% badge and muted label, toggle semantics read once with label and state before and after a click, glyph tile versus fallback while loading (then a repaint after the loader notifies), and one failed icon (`locks`). Inject a loaded `MapMarkerIcons` through the `_Assets` loader pattern. Find tiles by `ValueKey('marker-tile-<key>')`. Verify it fails because the grid does not exist.
- [x] 2.3 Add `MarkerPreferencesGrid` in `lib/ui/marker_preferences.dart` per D3: fixed-size scaled tiles in a `Wrap`, an `InkWell` per tile with `Semantics(toggled, label, button, excludeSemantics: true)`, inert while `busy`, and a badge `CustomPainter` over `paintMarkerBadge` whose `shouldRepaint` compares the key, the shown state and the icons, repainting on `MapMarkerIcons`. Verify `test/ui/marker_preferences_test.dart` passes and flip its nine rows green.

## 3. Wire the grid into Marker preferences

- [x] 3.1 In `test/ui/map_screen_test.dart`, change the chip finder in "marker search survives show/hide-all and dimmed targets remain eligible" (`:172`) to the tile key. Add a step that checks every tile keeps its state while the search dims markers. Add "Show all keeps saved entries of keys the map does not show", "quest filters leave tile states unchanged", "unsaveable marker key gets no tile and stays drawn" and "Hide all never saves an unsaveable key and settings reload". The last one uses a prepared-map fixture with a `Ziplines` marker, clicks Hide all, reloads settings from the database, and expects `AppSettings` to parse with no `Ziplines` entry. In `test/maps/map_viewport_test.dart`, change `_showMarkerFilter` (`:56-80`) to find the tile key, leaving its assertions as they are. Verify the new and changed tests fail for the right reason: there is no tile, or the bulk write includes `Ziplines`.
- [x] 3.2 In `lib/ui/map_screen.dart`, replace the `FilterChip` `Wrap` (`:463-483`) with `MarkerPreferencesGrid`. Compute `markerPreferenceKeys(services.maps.applicableCategories)` once and use it for the grid and for Show all and Hide all (`:441`, D5). Leave search, the quest fields and Save marker filters as they are. Verify the 3.1 tests and `test/ui/map_rail_test.dart` pass, and flip the five map-screen rows green.

## 4. Labels in the marker list and map semantics

- [x] 4.1 In `test/maps/map_viewport_test.dart`, build the expected hazard semantics label at `:772` with `markerCategoryLabel`. Add "visible-markers list shows the category label", using a `lootLoose` marker, and "visible-markers list shows an unlabelled key as is". Verify the label test fails on the raw `lootLoose` subtitle.
- [x] 4.2 Use `markerCategoryLabel` in `lib/ui/map_workspace.dart:148` and `:739` (D4). Verify `test/maps/map_viewport_test.dart` passes and flip its two rows green.

## 5. Integration checks

- [x] 5.1 Run `dart format` on the changed files, then `mise run analyze` and `mise run test`. Verify both exit 0 and every test map row is green.
- [x] 5.2 Check that the panel no longer shows a raw category key: `rg -n "FilterChip" lib/ui/map_screen.dart` finds no marker chip, and `rg -n "filterKey\)" lib/ui/map_workspace.dart` finds no raw-key `Text` or semantics label. Note in the PR body the two non-blocking re-check notes from `review.md`: "Hide all then Show all" holds only for maps with saveable keys, and the tests find tiles by key and not by label.

## Workflow follow-up

- User check in the app (not agent-run): the grid's look and readability on Map, in the wide and the compact layout. This is the exit criterion's "user for the look". It stays unverified until the user reports it.
