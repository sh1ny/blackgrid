# Tasks

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| latest-accepted-scan → Map shows scans in its one decision card | No separate panel | `test/ui/latest_scan_card_test.dart` | latest-accepted-scan: No separate panel | red |
| latest-accepted-scan → Map shows scans in its one decision card | Scan accepted with Map open | `test/ui/latest_scan_card_test.dart` | latest-accepted-scan: Scan accepted with Map open | red |
| latest-accepted-scan → Map shows scans in its one decision card | Scan fenced with Map open | `test/ui/latest_scan_card_test.dart` | a fenced scan with Map open changes nothing | green |
| map-controls → The map takes the main column | Wide and narrow windows | `test/ui/map_workspace_controls_test.dart` | map-controls: Wide and narrow windows | red |
| map-controls → The map takes the main column | Inspector closes over a loaded map | `test/ui/map_workspace_controls_test.dart` | map-controls: Inspector closes over a loaded map | green |
| map-controls → Debug information stays off the Map screen | Normal use | `test/ui/map_workspace_controls_test.dart` | map-controls: Normal use | red |
| map-controls → Debug information stays off the Map screen | Settings cannot be saved | `test/ui/map_workspace_controls_test.dart` | map-controls: Settings cannot be saved | red |
| map-controls → Debug information stays off the Map screen | Selected pin shows no debug text | `test/ui/map_workspace_controls_test.dart` | map-controls: Selected pin shows no debug text | green |
| map-controls → Map picker switches the map by hand | Choosing a map | `test/ui/map_workspace_controls_test.dart` | map-controls: Choosing a map | green |
| map-controls → Map picker switches the map by hand | Picker while saving | `test/ui/map_workspace_controls_test.dart` | map-controls: Picker while saving | green |
| map-controls → Read latest screenshot is in the picker | Reading the latest screenshot | `test/ui/map_workspace_controls_test.dart` | map-controls: Reading the latest screenshot | green |
| map-controls → Read latest screenshot is in the picker | No screenshot folder | `test/ui/map_workspace_controls_test.dart` | map-controls: No screenshot folder | green |
| map-controls → Read latest screenshot is in the picker | A read is running | `test/ui/map_workspace_controls_test.dart` | map-controls: A read is running | green |
| map-controls → Read latest screenshot is in the picker | Empty folder | `test/ui/map_workspace_controls_test.dart` | map-controls: Empty folder | green |
| map-controls → Read latest screenshot is in the picker | Screenshot cannot be read | `test/ui/map_workspace_controls_test.dart` | map-controls: Screenshot cannot be read | green |
| map-controls → Read latest screenshot is in the picker | Screenshot folder is unavailable | `test/ui/map_workspace_controls_test.dart` | map-controls: Screenshot folder is unavailable | green |
| map-controls → Read latest screenshot is in the picker | Superseded read | `test/application/map_session_controller_test.dart` | map-controls: Superseded read | green |
| map-controls → Floor control sits beside the picker | Choosing a floor | `test/ui/map_workspace_controls_test.dart` | map-controls: Choosing a floor | green |
| map-controls → Floor control sits beside the picker | Map with no floors | `test/ui/map_workspace_controls_test.dart` | map-controls: Map with no floors | green |
| map-controls → Floor control sits beside the picker | Artwork unavailable | `test/ui/map_workspace_controls_test.dart` | map-controls: Artwork unavailable | green |
| map-controls → Map actions stay on the map | Actions are reachable | `test/ui/map_workspace_controls_test.dart` | map-controls: Actions are reachable | green |
| map-controls → Map actions stay on the map | No position or no artwork | `test/ui/map_workspace_controls_test.dart` | map-controls: No position or no artwork | green |
| map-controls → Map actions stay on the map | Keyboard on an on-map control | `test/ui/map_workspace_controls_test.dart` | map-controls: Keyboard on an on-map control | green |
| map-controls → This raid lists the matched extracts | Matched extracts | `test/ui/map_inspector_test.dart` | map-controls: Matched extracts | red |
| map-controls → This raid lists the matched extracts | No reading | `test/ui/map_inspector_test.dart` | map-controls: No reading | red |
| map-controls → This raid lists the matched extracts | Matched extract is hidden | `test/ui/map_inspector_test.dart` | map-controls: Matched extract is hidden | red |
| map-controls → This raid lists the matched extracts | Matched extract outside the view | `test/ui/map_inspector_test.dart` | map-controls: Matched extract outside the view | red |
| map-controls → This raid lists the matched extracts | Choosing an off-view row | `test/ui/map_inspector_test.dart` | map-controls: Choosing an off-view row | red |
| map-controls → This raid lists the matched extracts | Choosing an in-view row | `test/ui/map_inspector_test.dart` | map-controls: Choosing an in-view row | red |
| map-controls → This raid lists the matched extracts | Selected pin gives way | `test/ui/map_inspector_test.dart` | map-controls: Selected pin gives way | red |
| map-controls → This raid lists the matched extracts | Age advances | `test/ui/map_inspector_test.dart` | map-controls: Age advances | red |
| map-controls → This raid lists the matched extracts | Later non-panel screenshot | `test/ui/map_inspector_test.dart` | map-controls: Later non-panel screenshot | red |
| map-controls → Pins section manages this map's pins | Pins listed | `test/ui/map_inspector_test.dart` | map-controls: Pins listed | red |
| map-controls → Pins section manages this map's pins | No pins | `test/ui/map_inspector_test.dart` | map-controls: No pins | red |
| map-controls → Pins section manages this map's pins | Removal while saving | `test/ui/map_inspector_test.dart` | map-controls: Removal while saving | red |
| map-controls → A selected pin has an action bar on the map | Pin selected | `test/ui/map_workspace_controls_test.dart` | map-controls: Pin selected | green |
| map-controls → A selected pin has an action bar on the map | Pin closed | `test/ui/map_workspace_controls_test.dart` | map-controls: Pin closed | green |
| map-controls → A selected pin has an action bar on the map | Actions while saving | `test/ui/map_workspace_controls_test.dart` | map-controls: Actions while saving | green |
| map-marker-icons → Category colours keep their meaning and contrast | Valid palette passes | `test/tool/markers/icon_set_test.dart` | palette: starting D7 palette passes | green |
| map-marker-icons → Category colours keep their meaning and contrast | Required role broken fails | `test/tool/markers/icon_set_test.dart` | palette: required danger and pin roles are enforced | green |
| map-marker-icons → Category colours keep their meaning and contrast | Reserved hue or low contrast fails | `test/tool/markers/icon_set_test.dart` | map-marker-icons: Reserved hue or low contrast fails | green |
| map-marker-icons → Category colours keep their meaning and contrast | Amber role fails | `test/tool/markers/icon_set_test.dart` | map-marker-icons: Amber role fails | green |
| map-marker-icons → Category colours keep their meaning and contrast | Low-saturation grey near amber passes | `test/tool/markers/icon_set_test.dart` | map-marker-icons: Low-saturation grey near amber passes | green |
| map-marker-icons → The map draws each marker as its category's icon badge | Marker with an icon draws its badge | `test/ui/map_marker_painting_test.dart` | loaded icons: a PmcExtracts marker paints a 24 px exit-green badge with its glyph and no dot | green |
| map-marker-icons → The map draws each marker as its category's icon badge | Hazard zone keeps its outline and draws its icon | `test/ui/map_marker_painting_test.dart` | a HazardZones marker paints its red polygon, then its danger badge | green |
| map-marker-icons → The map draws each marker as its category's icon badge | Unknown filter key falls back | `test/ui/map_marker_painting_test.dart` | map-marker-icons: Unknown filter key falls back | green |
| map-marker-icons → Marker states keep their meaning on the badge | Selected marker grows | `test/maps/map_marker_icons_test.dart` | map-marker-icons: Selected marker grows | green |
| map-marker-icons → Marker states keep their meaning on the badge | Highlighted exit draws cyan | `test/maps/map_marker_icons_test.dart` | highlighted uses cyan and selectedDiameter | green |
| map-marker-icons → Marker states keep their meaning on the badge | Dimmed marker fades as a whole | `test/maps/map_marker_icons_test.dart` | dimmed sets opacity 0.22 | green |
| map-marker-icons → Marker states keep their meaning on the badge | Dimmed and highlighted together | `test/maps/map_marker_icons_test.dart` | all eight flag permutations | green |
| map-marker-icons → Marker states keep their meaning on the badge | Selected and highlighted together | `test/maps/map_marker_icons_test.dart` | map-marker-icons: Selected and highlighted together | green |
| map-marker-icons → Marker states keep their meaning on the badge | Selected marker in the light room | `test/maps/map_marker_icons_test.dart` | map-marker-icons: Selected marker in the light room | green |
| map-marker-icons → Saved pins draw the pin icon | Pin draws its icon | `test/ui/map_marker_painting_test.dart` | a saved pin paints a light-blue CustomPins badge | green |
| map-marker-icons → Saved pins draw the pin icon | Pin not matching the search dims | `test/ui/map_marker_painting_test.dart` | a pin not matching the search paints at 0.22 alpha | green |
| map-marker-icons → Saved pins draw the pin icon | Pins hidden | `test/ui/map_marker_painting_test.dart` | CustomPins off paints no pin badge | green |
| map-marker-icons → Saved pins draw the pin icon | Selected pin is Ember | `test/ui/map_marker_painting_test.dart` | map-marker-icons: Selected pin is Ember | green |
| map-marker-icons → Missing or failed icons never block the map | Fallback colours without a manifest | `test/maps/map_marker_icons_test.dart` | map-marker-icons: Fallback colours without a manifest | green |
| map-marker-icons → Missing or failed icons never block the map | Icons still loading | `test/maps/map_marker_icons_test.dart` | before open() completes every key has no glyph; completion notifies once | green |
| map-marker-icons → Missing or failed icons never block the map | One icon fails to decode | `test/maps/map_marker_icons_test.dart` | a throwing icon load leaves only that key on the fallback | green |
| map-marker-icons → Missing or failed icons never block the map | Manifest unreadable | `test/maps/map_marker_icons_test.dart` | a $name manifest leaves every key on its fallback colour and logs the manifest | green |
| map-marker-popups → Summaries reflect prepared marker facts | Quest and container | `test/maps/marker_presentation_test.dart` | quest objective and container show prepared names | green |
| map-marker-popups → Summaries reflect prepared marker facts | Linked extract and lock | `test/maps/marker_presentation_test.dart` | linked extract item count switch and lock key facts | green |
| map-marker-popups → Summaries reflect prepared marker facts | Missing or misleading fields | `test/maps/marker_presentation_test.dart` | missing malformed and misleading facts are not invented | green |
| map-marker-popups → Summaries reflect prepared marker facts | Boss chance scope | `test/maps/marker_presentation_test.dart` | boss wide chance is a percentage not a location chance | green |
| map-marker-popups → Summaries reflect prepared marker facts | Fractional boss chance | `test/maps/marker_presentation_test.dart` | map-marker-popups: Fractional boss chance | green |
| map-marker-popups → Summaries reflect prepared marker facts | Chance near the ends | `test/maps/marker_presentation_test.dart` | map-marker-popups: Chance near the ends | green |
| map-marker-popups → Summaries reflect prepared marker facts | Refreshed marker facts | `test/maps/marker_popup_test.dart` | refreshed marker selection shows new facts without a request | green |
| map-rail → Map saved-file inputs starts collapsed | Collapsed on first show | `test/ui/map_diagnostics_test.dart` | map-rail: Collapsed on first show | red |
| map-rail → Map saved-file inputs starts collapsed | Expanding shows the inputs | `test/ui/map_diagnostics_test.dart` | map-rail: Expanding shows the inputs | red |
| map-rail → Map saved-file inputs starts collapsed | Status lines use labels | `test/ui/map_diagnostics_test.dart` | map-rail: Status lines use labels | red |
| map-rail → Map saved-file inputs starts collapsed | Collapsing keeps settings | `test/ui/map_diagnostics_test.dart` | map-rail: Collapsing keeps settings | red |
| map-rail → Map saved-file inputs starts collapsed | Pending screenshot while collapsed | `test/ui/map_diagnostics_test.dart` | map-rail: Pending screenshot while collapsed | red |
| map-rail → Collapsed section does no periodic work | No ticking while collapsed | `test/ui/map_diagnostics_test.dart` | map-rail: No ticking while collapsed | red |
| map-rail → Collapsed section does no periodic work | Age resumes on expand | `test/ui/map_diagnostics_test.dart` | map-rail: Age resumes on expand | red |
| map-zone-labels → Name labels are coloured by faction | Each faction draws its own colour | `test/ui/map_zone_labels_test.dart` | map-zone-labels: Each faction draws its own colour | green |
| map-zone-labels → Name labels are coloured by faction | Palette rule rejects a bad label colour | `test/domain/map_zone_style_test.dart` | map-zone-labels: Palette rule rejects a bad label colour | green |
| map-zone-labels → Name labels are coloured by faction | Highlighted extract keeps its faction name colour | `test/ui/map_zone_labels_test.dart` | a raid-highlighted Scav extract keeps its Scav label colour | green |
| map-zone-labels → Zone outlines use their category colour | Categories draw their own outline colours | `test/ui/map_zone_labels_test.dart` | map-zone-labels: Categories draw their own outline colours | green |
| map-zone-labels → Zone outlines use their category colour | Icons not loaded yet | `test/ui/map_zone_labels_test.dart` | map-zone-labels: Icons not loaded yet | green |
| map-zone-labels → Zone outlines use their category colour | Selected outline is Ember | `test/ui/map_zone_labels_test.dart` | map-zone-labels: Selected outline is Ember | green |
| marker-preferences → Each applicable category is one marker row | Rows for the current map | `test/ui/marker_preferences_test.dart` | marker-preferences: Rows for the current map | red |
| marker-preferences → Each applicable category is one marker row | Unsaveable category gets no row | `test/ui/marker_preferences_test.dart` | marker-preferences: Unsaveable category gets no row | red |
| marker-preferences → Each applicable category is one marker row | Map with no markers | `test/ui/marker_preferences_test.dart` | marker-preferences: Map with no markers | red |
| marker-preferences → Rows follow a fixed grouped order | Grouped order | `test/ui/marker_preferences_test.dart` | marker-preferences: Grouped order | red |
| marker-preferences → Rows follow a fixed grouped order | Map order does not matter | `test/ui/marker_preferences_test.dart` | marker-preferences: Map order does not matter | red |
| marker-preferences → Clicking a row shows or hides its category | Hide one category | `test/ui/marker_preferences_test.dart` | marker-preferences: Hide one category | red |
| marker-preferences → Clicking a row shows or hides its category | Click while saving | `test/ui/marker_preferences_test.dart` | marker-preferences: Click while saving | red |
| marker-preferences → Row state does not rely on colour alone | Shown and hidden rows differ | `test/ui/marker_preferences_test.dart` | marker-preferences: Shown and hidden rows differ | red |
| marker-preferences → Row state does not rely on colour alone | Semantics reflect the state | `test/ui/marker_preferences_test.dart` | marker-preferences: Semantics reflect the state | red |
| marker-preferences → Rows draw the map's badge and its fallback | Icon row matches the map | `test/ui/marker_preferences_test.dart` | marker-preferences: Icon row matches the map | red |
| marker-preferences → Rows draw the map's badge and its fallback | Icons still loading | `test/ui/marker_preferences_test.dart` | marker-preferences: Icons still loading | red |
| marker-preferences → Bulk, search and quest controls keep working | Hide all then Show all | `test/ui/marker_preferences_test.dart` | marker-preferences: Hide all then Show all | red |
| marker-preferences → Bulk, search and quest controls keep working | Show all keeps other maps' choices | `test/ui/marker_preferences_test.dart` | marker-preferences: Show all keeps other maps' choices | red |
| marker-preferences → Bulk, search and quest controls keep working | Bulk action with an unsaveable category | `test/ui/marker_preferences_test.dart` | marker-preferences: Bulk action with an unsaveable category | red |
| marker-preferences → Bulk, search and quest controls keep working | Search dims without hiding | `test/ui/marker_preferences_test.dart` | marker-preferences: Search dims without hiding | red |
| marker-preferences → Bulk, search and quest controls keep working | Quest filter keeps tiles | `test/ui/marker_preferences_test.dart` | marker-preferences: Quest filter keeps tiles | red |
| marker-preferences → Bulk, search and quest controls keep working | Active trader absent from the map | `test/ui/marker_preferences_test.dart` | marker-preferences: Active trader absent from the map | red |
| scanner-evidence → Scanner workspace omits configuration rail | Scanner functions remain reachable without the old rail | `test/ui/scanner_screen_test.dart` | scanner-evidence: Scanner functions remain reachable without the old rail | green |
| verdict-presentation → One plate per verdict | Each verdict has its style | `test/ui/verdict_plate_test.dart` | each verdict has its plate style in both rooms | green |
| verdict-presentation → One plate per verdict | Verdicts differ without colour | `test/ui/verdict_plate_test.dart` | Keep, Flea and Price unavailable differ by fill and border | green |
| verdict-presentation → One plate per verdict | No plate is drawn in the accent | `test/ui/verdict_plate_test.dart` | no plate uses accent or accent-text | green |
| verdict-presentation → One-line verdict reason | Keep names the need that decided it | `test/domain/verdict_reason_test.dart` | Keep names the first actionable need with its count | green |
| verdict-presentation → One-line verdict reason | Keep with an unknown count | `test/domain/verdict_reason_test.dart` | Keep with an unknown count has no number | green |
| verdict-presentation → One-line verdict reason | Keep for later names the future need | `test/domain/verdict_reason_test.dart` | Keep for later names the first future need | green |
| verdict-presentation → One-line verdict reason | Check names the first open question | `test/domain/verdict_reason_test.dart` | Check with only found in raid open names it | green |
| verdict-presentation → One-line verdict reason | Check picks questions in a fixed order | `test/domain/verdict_reason_test.dart` | Check names the first open input in the fixed order | green |
| verdict-presentation → One-line verdict reason | Check wording for each open input | `test/domain/verdict_reason_test.dart` | Check wording for each open input | green |
| verdict-presentation → One-line verdict reason | Found in raid unknown outranks the needs it leaves open | `test/domain/verdict_reason_test.dart` | found in raid outranks an unresolved found-in-raid need | green |
| verdict-presentation → One-line verdict reason | Flea and Trader compare the prices | `test/domain/verdict_reason_test.dart` | Flea compares gross prices with the best trader | green |
| verdict-presentation → One-line verdict reason | Trader for each way the engine reaches it | `test/domain/verdict_reason_test.dart` | Trader wording for each engine path | green |
| verdict-presentation → One-line verdict reason | Flea with no trader offer | `test/domain/verdict_reason_test.dart` | Flea with no trader offer | green |
| verdict-presentation → One-line verdict reason | Price unavailable | `test/domain/verdict_reason_test.dart` | Price unavailable wording | green |
| verdict-presentation → One-line verdict reason | A long reason at the narrowest card | `test/ui/shell_test.dart` | long catalog reason wraps fully inside the shared strip | green |
| workspace-shell → Inspector preserves the workspace | Docked details | `test/ui/shell_test.dart` | workspace-shell: Docked details | green |
| workspace-shell → Inspector preserves the workspace | Resize with open details | `test/ui/shell_test.dart` | workspace-shell: Resize with open details | green |
| workspace-shell → Inspector preserves the workspace | Scanner history leads the inspector | `test/ui/shell_test.dart` | workspace-shell: Scanner history leads the inspector | green |
| workspace-shell → Inspector preserves the workspace | Initial inspector state follows window width | `test/ui/shell_test.dart` | workspace-shell: Initial inspector state follows window width | green |
| workspace-shell → Inspector preserves the workspace | Map inspector holds working lists | `test/ui/shell_test.dart` | workspace-shell: Map inspector holds working lists | red |

Tests are offline only. No task launches or inspects a game, and no task sets `BLACKGRID_NO_GAMES_RUNNING`. The milestone's look and geometry checks that only the owner can judge are decided at milestone close, as the proposal states, so they are not tasks here.

## 1. Record the colour decision

- [x] 1.1 Write `docs/adr/0039-amber-on-the-map-means-selected.md`, with `Supersedes: 0023` in part: selection draws Ember and wins over highlight, the amber band (hue 25-60 degrees, saturation 10% or more) is reserved, the new quest, loot and Scav label values, the 0.08 OKLab floor and the fallback neutral. Do not edit ADR-0023. Verify the file exists with status accepted.
- [x] 1.2 Add 0039 to the ADR index in `openspec/architecture.md` and mark 0023's row as superseded in part. Verify with `openspec validate restyle-map-workspace --strict`.

## 2. Palette and selection colour

- [x] 2.1 Write failing tests for the amber band in `tool/markers/icon_set.dart` and the label palette: the rows `Reserved hue or low contrast fails`, `Amber role fails`, `Low-saturation grey near amber passes` and `Palette rule rejects a bad label colour`, plus a test that holds the shipped roles and labels to the 0.08 OKLab floor. Verify they fail on the amber band and the old values.
- [x] 2.2 Add the amber band to the set check and the label test; change quest to `#C5E063` and loot to `#7ED9C6` in `assets/map_markers/manifest.json`, and the Scav label to `#F59AB8` in `labelColourFor`. Verify `test/tool/markers` and `test/domain/map_zone_style_test.dart` pass and flip those rows green.
- [x] 2.3 Write failing tests for `Selected marker grows`, `Selected and highlighted together`, `Selected marker in the light room`, `Selected pin is Ember`, `Selected outline is Ember`, `Unknown filter key falls back`, `Fallback colours without a manifest`, `Icons not loaded yet`, `Each faction draws its own colour`, `Categories draw their own outline colours`, and a test pinning `mapSelectionColour` to `EmberColors.dark.accent`. Verify each fails for the expected colour.
- [x] 2.4 Add the `mapSelectionColour` literal in `lib/maps/map_palette.dart`; make `paintMarkerBadge`'s resolver take selected before highlight before role, give `_outline` and the popup leader line the same colour, and set the fallback to `#C9CDBF`. Update the existing tests that pinned gold or role colours for selection. Verify `test/maps/map_marker_icons_test.dart`, `test/ui/map_marker_painting_test.dart` and `test/ui/map_zone_labels_test.dart` pass and flip the rows green, including re-running the green rows of `map-marker-icons` and `map-zone-labels`.

## 3. Spawn chance

- [x] 3.1 Write failing tests for `Fractional boss chance` and `Chance near the ends` (whole percent; 1-99% for values in the open interval). Implement in `lib/maps/marker_presentation.dart`. Verify `test/maps/marker_presentation_test.dart` passes, flip those rows green, and re-run the green `map-marker-popups` rows.

## 4. Controller and watcher support

- [x] 4.1 Change `ScreenshotDirectoryWatcher.readLatest` to return a sealed result (found, empty, unavailable, discarded), test first in `test/data/screenshot_directory_watcher_test.dart`, with a case for each path that returns null today. A missing or inaccessible folder, an unreadable, oversized or changing file, and the no-folder-bound path are unavailable; a closed watcher or moved generation is discarded. Verify the file passes.
- [x] 4.2 Make `MapSessionController.readLatest` return an outcome (applied, no screenshot, unavailable, superseded), test first in `test/application/map_session_controller_test.dart`. Keep the `order` check as well as the context check, and report superseded for either. Verify `map-controls: Superseded read` passes and flip it green.
- [x] 4.3 Add the raid match time to `MapSessionController`, test first in the same file: set where a screenshot sets the highlights, unchanged by the re-match in `_refreshEvidenceForMap`, cleared in `_invalidate`, retained across a later screenshot with no panel. Verify the file passes.
- [x] 4.4 Add to `MapController` the non-culled accessor of raid-matched projections and `revealMarker(id)`, test first in a new `test/application/map_controller_test.dart`: eligible by category, floor and map only; independent of pan and zoom; pans at the same zoom only when off view; ignores an id that is no longer eligible. Verify the file passes.

## 5. Controls on the map

- [x] 5.1 Write failing widget tests in `test/ui/map_workspace_controls_test.dart` for the `Map picker switches the map by hand`, `Read latest screenshot is in the picker` (except `Superseded read`), `Floor control sits beside the picker`, `Map actions stay on the map`, `A selected pin has an action bar on the map` and `The map takes the main column` rows, and `Selected pin shows no debug text`. Verify they fail because the controls are still in the toolbar.
- [x] 5.2 Replace the toolbar `Wrap` with viewport overlays in `MapWorkspace`: picker and floor control top left, action stack on the right edge, placed outside the `Focus` that owns `_key` and outside the `GestureDetector`. Add the `Read latest screenshot` item with its snackbars for the no screenshot and unavailable outcomes.
- [x] 5.3 Replace the strip below the viewport with the floating pin bar (label, Edit, Remove, Close), remove the instruction line, and draw the attribution as a bottom-left caption that does not overlap the bar. Add the `maps` listener that clears `_selectedPin` when a marker is selected from outside the workspace. Verify the group's tests pass, flip their rows green, and check the 960 px geometry test shows the overlays not overlapping each other.

## 6. Map inspector

- [ ] 6.1 Write failing widget tests in `test/ui/map_inspector_test.dart` for the `This raid lists the matched extracts` and `Pins section manages this map's pins` rows, using an injected clock for `Age advances`, and for `workspace-shell: Map inspector holds working lists` in `test/ui/shell_test.dart`. Verify they fail because `MapInspector` does not exist.
- [ ] 6.2 Rewrite `test/ui/marker_preferences_test.dart` to the row behaviour, with the `marker-preferences` rows. Verify they fail against the tile grid.
- [ ] 6.3 Implement `lib/ui/map_inspector.dart` with This raid (age refresh only while mounted with a match time), Markers as rows with filters, and Pins. Derive counts and trader chips once per `contentGeneration`. Rewrite `lib/ui/marker_preferences.dart` as rows and mount the inspector from the shell's Map branch (`lib/ui/shell.dart`). Verify the tests above pass and flip their rows green, then re-run the green `workspace-shell` rows.

## 7. Diagnostics and the rail's removal

- [ ] 7.1 Move the `map-rail` behaviour tests to `test/ui/map_diagnostics_test.dart` against a public `MapDiagnostics` in a collapsed section at the end of the Settings dialog; add the Save marker filters control to Settings. Verify they fail because the section does not exist.
- [ ] 7.2 Extract `MapDiagnostics` from `_MapInputStatus` into its own file, without Follow logs or Read Latest, and mount it in the Settings dialog, collapsed each time it opens. Add the Diagnostics row to DESIGN.md X12. Verify `test/ui/map_diagnostics_test.dart` and `test/ui/settings_dialog_test.dart` pass and flip the `map-rail` rows green.
- [ ] 7.3 Write failing tests for `Normal use`, `Settings cannot be saved`, `No separate panel` and `Scan accepted with Map open` against the Map with no rail. Remove the rail from `MapScreen`, delete `lib/ui/manual_controls.dart` and its tests, and delete or move what `test/ui/map_rail_test.dart` still covers. Verify the rows turn green and re-run the green `latest-accepted-scan`, `scanner-evidence` and `verdict-presentation` rows.

## 8. Integration

- [ ] 8.1 Confirm every test map row is green, each with a test by that name. Verify by listing rows still marked red and finding none.
- [ ] 8.2 Run `dart format`, `mise run analyze` and `mise run test`. Verify all pass offline, with no game running and none launched.
- [ ] 8.3 Run `openspec validate restyle-map-workspace --strict` and `mise run release-notes -- --check openspec/changes/restyle-map-workspace/proposal.md`. Verify both pass.
