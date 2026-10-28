# Tasks

Every implementer packet carries AGENTS.md's "Dart and Flutter code" section and these skills: `dart-use-pattern-matching`, `dart-write-documentation`, `dart-add-unit-test`, `dart-run-static-analysis`; group 3 also `flutter-add-widget-test`. No task launches the app or the game.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| map-marker-icons → The map draws each marker as its category's icon badge | Marker with an icon draws its badge | test/ui/map_marker_painting_test.dart | `loaded icons: a PmcExtracts marker paints a 24 px exit-green badge with its glyph and no dot` | green |
| map-marker-icons → The map draws each marker as its category's icon badge | Hazard zone keeps its outline and draws its icon | test/ui/map_marker_painting_test.dart | `a HazardZones marker paints its red polygon, then its danger badge` | green |
| map-marker-icons → The map draws each marker as its category's icon badge | Unknown filter key falls back | test/maps/map_marker_icons_test.dart | `icon() is null for an unknown filter key and the style falls back to gold` + test/ui/map_marker_painting_test.dart `an unknown filter key paints a gold fallback dot while others paint glyphs` | green |
| map-marker-icons → Marker states keep their meaning on the badge | Selected marker grows | test/maps/map_marker_icons_test.dart | `markerBadgeStyle: selected uses selectedDiameter and the role colour` | green |
| map-marker-icons → Marker states keep their meaning on the badge | Highlighted exit draws cyan | test/maps/map_marker_icons_test.dart | `markerBadgeStyle: highlighted uses cyan and selectedDiameter` | green |
| map-marker-icons → Marker states keep their meaning on the badge | Dimmed marker fades as a whole | test/maps/map_marker_icons_test.dart | `markerBadgeStyle: dimmed sets opacity 0.22` + test/ui/map_marker_painting_test.dart `a dimmed marker paints disc, ring and glyph at 0.22 alpha` | green |
| map-marker-icons → Marker states keep their meaning on the badge | Dimmed and highlighted together | test/maps/map_marker_icons_test.dart | `markerBadgeStyle: all eight flag permutations` | green |
| map-marker-icons → Saved pins draw the pin icon | Pin draws its icon | test/ui/map_marker_painting_test.dart | `a saved pin paints a light-blue CustomPins badge` | green |
| map-marker-icons → Saved pins draw the pin icon | Pin not matching the search dims | test/ui/map_marker_painting_test.dart | `a pin not matching the search paints at 0.22 alpha` | green |
| map-marker-icons → Saved pins draw the pin icon | Pins hidden | test/ui/map_marker_painting_test.dart | `CustomPins off paints no pin badge` | green |
| map-marker-icons → Missing or failed icons never block the map | Fallback colours without a manifest | test/maps/map_marker_icons_test.dart | `fallback colours before the manifest loads` | green |
| map-marker-icons → Missing or failed icons never block the map | Icons still loading | test/maps/map_marker_icons_test.dart | `before open() completes every key has no glyph; completion notifies once` + test/ui/map_marker_painting_test.dart `the map repaints with glyphs when loading completes` | green |
| map-marker-icons → Missing or failed icons never block the map | One icon fails to decode | test/maps/map_marker_icons_test.dart | `a corrupt locks .vec leaves locks on the fallback in its role colour and logs the file once` | green |
| map-marker-icons → Missing or failed icons never block the map | Manifest unreadable | test/maps/map_marker_icons_test.dart | `a missing, non-JSON or wrong-schema manifest leaves every key on its fallback colour and logs the manifest` + `a throwing load never escapes open()` + test/ui/map_marker_painting_test.dart `with a failed manifest, tapping a marker still selects it` | green |
| map-marker-icons → The bundled icons are the compiled release set | Compiled files in step | test/tool/markers/compile_test.dart | `the committed release set's compiled files are in step` | green |
| map-marker-icons → The bundled icons are the compiled release set | SVG edited without recompiling | test/tool/markers/compile_test.dart | `compiledSetFailures names a stale compiled file` | green |
| map-marker-icons → The bundled icons are the compiled release set | Orphan compiled file | test/tool/markers/compile_test.dart | `compiledSetFailures names labels.vec as unexpected` | green |
| release-bundle-integrity → Bundled map marker icons are project-authored and recorded | Bundled icons match the recorded set | test/tool/vision/check_bundle_test.dart | `map-marker-icons passes on a bundle holding the manifest and every compiled icon` | green |
| release-bundle-integrity → Bundled map marker icons are project-authored and recorded | Unlisted icon file in the bundle | test/tool/vision/check_bundle_test.dart | `map-marker-icons names an unlisted .vec, .svg or .png as unexpected` | green |
| release-bundle-integrity → Bundled map marker icons are project-authored and recorded | Altered bundled icon | test/tool/vision/check_bundle_test.dart | `map-marker-icons names an altered compiled icon or manifest` | green |
| release-bundle-integrity → Bundled map marker icons are project-authored and recorded | Release set fails its own check | test/tool/vision/check_bundle_test.dart | `map-marker-icons reports the set check's failures for a stale hash and exits 1` | green |
| release-bundle-integrity → Bundled map marker icons are project-authored and recorded | Icons missing from the bundle | test/tool/vision/check_bundle_test.dart | `map-marker-icons names a missing directory or compiled icon` | green |

## 1. Compiled release set (design D1)

- [x] 1.1 Write `test/tool/markers/compile_test.dart` against a small synthetic set from `test/tool/markers/support/icon_set_fixture.dart` (candidate scope, 2 icons): an in-step set passes, a stale `.vec` is named, a missing `.vec` is named, `labels.vec` is named unexpected, an invalid set makes the CLI exit 1 and write nothing, and compiling the same SVG twice gives equal bytes. Also `the committed release set's compiled files are in step`, over `assets/map_markers/manifest.json`. Verify they fail because `tool/markers/compile.dart` does not exist yet.
- [x] 1.2 Implement `tool/markers/compile.dart`: `compiledSetFailures(IconSet set)` and a CLI `[<manifest>]` (default `assets/map_markers/manifest.json`). The CLI runs `checkIconSet`, compiles each icon with `compileIconSvg` into `compiled/<stem>.vec` through a `.tmp` file and a rename, and deletes other files in `compiled/`. Document it with `///`. Verify the synthetic-set tests pass.
- [x] 1.3 Run `dart run tool/markers/compile.dart` to generate the 19 committed `assets/map_markers/compiled/*.vec` files. Add `assets/map_markers/manifest.json` and `assets/map_markers/compiled/` to `pubspec.yaml` assets, and nothing else under `assets/map_markers/`. Verify that the committed-set sync test passes, that `git check-attr text assets/map_markers/compiled/pmc_extracts.vec` reports `unset`, and that `git status` shows no stray `.tmp`. Flip the three D1 rows green.

## 2. Marker icon loader and badge style (design D2, D4, D6)

- [x] 2.1 Write `test/maps/map_marker_icons_test.dart`. Use an injected `load` that serves a manifest and `.vec` bytes compiled in the test from tiny synthetic SVGs with `compileIconSvg`, with no production asset sizes. Wrap the async decode in `tester.runAsync`. Cover:
  - `markerBadgeStyle` over all eight selected/highlighted/dimmed permutations, with and without a role colour;
  - the fallback colour table before the manifest loads;
  - `icon()` returning `null` for an unknown key;
  - no glyph before `open()` completes, and exactly one notification when it does;
  - a second `open()` returning the same future;
  - a corrupt `locks` `.vec` leaving `locks` on the fallback in its role colour, recorded once in `failures`;
  - a missing manifest, a non-JSON manifest and a `schemaVersion: 2` manifest leaving every key on its fallback;
  - a `load` that throws a non-`FormatException` error never escaping `open()` (review S4);
  - `dispose()` during `open()` disposing made images and never notifying afterwards;
  - `MapMarkerIcons.disabled()` never calling `load`.

  Verify they fail because the file under test is missing.
- [x] 2.2 Implement `lib/maps/map_marker_icons.dart`: `MapMarkerIcons`, `MapMarkerIcons.disabled()`, `MarkerBadgeGeometry`, `MarkerIcon`, `markerBadgeStyle` and the fallback colour table. The glyph is rasterized at 64 × 64 px with `toImageSync` and the picture disposed afterwards. `open()` catches every error per step. Logging uses `debugPrint` as D6 specifies. Define the fallback colours as constants in this file, with no import from `lib/ui/` (review S3). Use a sealed result or switch patterns for the parse where they fit. Add `///` docs on the public API. Verify `test/maps/map_marker_icons_test.dart` passes and flip its rows green.

## 3. Painter and composition (design D2, D3, D4)

- [x] 3.1 Write `test/ui/map_marker_painting_test.dart` with the `paints` matcher, as `test/maps/map_scene_test.dart` uses it. Drive the map workspace with a small synthetic prepared map: one `PmcExtracts` marker, one `HazardZones` marker with an outline, one marker with an unknown filter key and one saved pin. Inject a `MapMarkerIcons` built from synthetic `.vec` bytes. Cover:
  - a loaded badge: a background disc, a ring in the role colour, and a glyph `drawImageRect` of 16 × 16 with no centre dot;
  - the hazard zone polygon painted before its badge;
  - the gold fallback dot for the unknown key;
  - a dimmed marker at 0.22 alpha;
  - the pin badge in light blue, the pin dimmed at 0.22 when it does not match the search, and no pin painted with `CustomPins` off;
  - a repaint with glyphs once loading completes;
  - with a failed manifest, a tap still selecting the marker.

  Verify they fail on today's ring painter.
- [x] 3.2 Change `_MapPainter` in `lib/ui/map_workspace.dart` to draw badges from `markerBadgeStyle` and `MapMarkerIcons`: disc, ring, tinted `drawImageRect`, or the fallback dot. Repaint on `Listenable.merge([maps, markerIcons])`. Keep hit radius 22, semantics, the browse list and the keyboard handling unchanged. Add `MapMarkerIcons? markerIcons` to `AppServices`, defaulting to `disabled()`. `AppServices.open()` passes `MapMarkerIcons()`, `initialize()` starts `open()` unawaited, and `dispose()` disposes it. Verify `test/ui/map_marker_painting_test.dart` passes and flip its rows green. Verify that `test/ui/map_screen_test.dart`, `test/ui/map_rail_test.dart` and `test/maps/` still pass.

## 4. Bundle check step (design D5)

- [x] 4.1 Add map-marker cases to `test/tool/vision/check_bundle_test.dart`. The `_Fixture` copies the committed manifest and compiled files into `data/flutter_assets/assets/map_markers/` of its synthetic bundle, so the existing cases keep passing. The marker cases cover:
  - a passing bundle;
  - an unlisted `compiled/skull_alt.vec`, `.svg` and `.png`;
  - an altered compiled icon, and an altered bundled manifest;
  - a set with a stale hash, through `--marker-icons` pointing at a temp copy of the set, failing with the set check's message and exit 1;
  - a missing directory and a missing compiled icon;
  - `--report` refusing the marker manifest path (review S2).

  Verify they fail on the current `checkBundle`.
- [x] 4.2 Implement the `map-marker-icons` step in `tool/vision/check_bundle.dart`, with a `markerManifestPath` parameter, a `--marker-icons` flag and the help text. Compile each icon once through a memoising `IconCompiler` passed to `checkIconSet`, and reuse those bytes for the comparison (review S1). Add the marker manifest to the report's protected files. Verify that `test/tool/vision/check_bundle_test.dart` passes, that it is not noticeably slower (compare the `flutter test` time for the file before and after), and flip the bundle rows green.

## 5. Docs and integration

- [x] 5.1 Update `openspec/architecture.md`'s `MapController + lib/maps/` row with the marker icon loader (`MapMarkerIcons`, bundled `assets/map_markers/manifest.json` and `compiled/*.vec`) and the bundle check's map-marker step. Update `docs/design/map-marker-icons/README.md` with a short "In the app" note: compiled files, the 16 px glyph at every size, highlighted markers keep the selected size, and `prompts/` is not bundled. Verify by reading the diff.
- [x] 5.2 Commit the carried-over `openspec/specwright.yaml` edit (the retired `kintsugimira` reviewer removed) as its own `chore` commit on this branch. Verify that `git show --stat HEAD` lists only that file.
- [x] 5.3 Run `dart format .`, `mise run analyze` and `mise run test`. Verify that all three are clean and every Test map row is green.
- [ ] 5.4 Record the user check as unverified in the PR description: the in-raid look of the icons on the map, including highlighted size, dimmed look and 24 px readability. Agents do not perform it (AGENTS.md). Verify that the PR body lists it under user checks.

## Workflow follow-up

- After apply: pre-ship review (`specwright-review`), then `specwright-pr` ship with run login KintsugiBot; archive on the branch after the PR is ready.
