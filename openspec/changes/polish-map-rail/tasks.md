# Tasks

Each implementer packet carries:
- AGENTS.md "Dart and Flutter code";
- the skills `flutter-add-widget-test`, `dart-add-unit-test` and `dart-write-documentation`.

Every check is offline (`mise run analyze`, `mise run test`). No task launches Blackgrid or needs the game.

Shared test helpers live in `test/support/map_widget_harness.dart`:
- `showMapInputsHeader(tester)` scrolls the rail. It calls `scrollUntilVisible` on the `Scrollable` under `PageStorageKey('map-rail-scroll')` until the "Map saved-file inputs" header (`Key('map-inputs-toggle')`) is built, and asserts the header is found.
- `expandMapInputs(tester)` calls `showMapInputsHeader`, taps the header and pumps.

Every collapsed-state assertion calls `showMapInputsHeader` first, so no absence check can pass vacuously (design Risks / Trade-offs). `pumpMapFixture` pumps the whole `BlackgridApp`, so the shell's `nav-scanner` and `nav-map` keys switch tabs. A new launch is a `pumpWidget` of a new `BlackgridApp(key: UniqueKey(), ...)` on the same services.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Rail order puts raid-time sections first | Wide layout order | test/ui/map_rail_test.dart | wide rail orders Active map, card, markers, search, inputs | red |
| Rail order puts raid-time sections first | Compact layout order | test/ui/map_rail_test.dart | compact rail keeps the same order with inputs last | red |
| Rail order puts raid-time sections first | Active map row stays alone | test/ui/map_rail_test.dart | Active map row stays alone with an accepted scan | green |
| Map saved-file inputs starts collapsed | Collapsed on first show | test/ui/map_rail_test.dart | inputs section starts collapsed | red |
| Map saved-file inputs starts collapsed | Expanding shows the inputs | test/ui/map_rail_test.dart | expanding shows status, Follow logs and a working Read Latest | red |
| Map saved-file inputs starts collapsed | Collapsing keeps settings | test/ui/map_rail_test.dart | expand then collapse keeps Follow logs and the maps | red |
| Map saved-file inputs starts collapsed | Pending screenshot while collapsed | test/ui/map_rail_test.dart | pending screenshot keeps the section collapsed | red |
| Collapsed section does no periodic work | No ticking while collapsed | test/ui/map_rail_test.dart | collapsed section does not mount the saved-file status | red |
| Collapsed section does no periodic work | Age resumes on expand | test/ui/map_rail_test.dart | expanding shows the saved evidence age | red |
| Expansion state lasts for the session only | Survives a tab switch | test/ui/map_rail_test.dart | expansion survives Scanner and back | red |
| Expansion state lasts for the session only | Survives a layout change | test/ui/map_rail_test.dart | expansion survives the compact breakpoint | red |
| Expansion state lasts for the session only | New launch starts collapsed | test/ui/map_rail_test.dart | a new app starts collapsed | red |

"Active map row stays alone" starts green. `add-map-scan-snapshot` already delivered it, and this change only pins it with a test.

## 1. Collapsible panel widget

- [x] 1.1 Write `test/ui/collapsible_grid_panel_test.dart` before the widget exists. These are extra tests, with no test map row. They prove that:
  - the child is not built while collapsed and is built when expanded;
  - tapping the header calls `onExpandedChanged` with the negated flag;
  - the header carries `toggleKey`;
  - its semantics report a button with the expanded state and the title as the label;
  - the title and icon render as in `GridPanel`.

  Verify that `mise run test -- test/ui/collapsible_grid_panel_test.dart` fails to compile because `CollapsibleGridPanel` does not exist.
- [x] 1.2 Add `CollapsibleGridPanel` to `lib/ui/theme.dart` (design D2):
  - `title`, `icon`, `expanded`, `onExpandedChanged`, optional `toggleKey` and `child`;
  - the same frame and header as `GridPanel`, plus a chevron;
  - the header is one `InkWell` keyed with `toggleKey`, with `Semantics(button: true, expanded: ...)`;
  - the child is built only when expanded, with no animation;
  - `///` docs on the class and every parameter.

  Leave `GridPanel` unchanged. Verify that 1.1's tests pass and `mise run analyze` is clean.

## 2. Map rail order and collapsed inputs

- [ ] 2.1 Add `showMapInputsHeader` and `expandMapInputs` to `test/support/map_widget_harness.dart`, as described above. Write the red tests in `test/ui/map_rail_test.dart` for every `red` row of the test map:
  - **Order:** compare `tester.getRect(...).top` of the five sections, found by their titles, after scrolling each into view, in the wide layout (`1912×823`) and in the compact layout (`760×900`).
  - **Collapsed on first show:** after `showMapInputsHeader`, no `Logs:`/`Screenshots:` text, no Follow logs `SwitchListTile`, no `Read Latest`, and `find.byKey(Key('map-input-status'))` finds nothing.
  - **Expanding:** Read Latest reads the fixture screenshot, as in `test/ui/map_screen_test.dart:17-60`.
  - **Collapsing:** with Follow logs off, expand, then collapse. Settings read back from the database are unchanged, and so are `maps.selectedMapId` and the stored manual map.
  - **Pending:** put the session in a processing state the way `map_screen_test.dart:88` does. The section stays collapsed, and expanding shows the processing line.
  - **Ticking:** with a saved screenshot that has a modification time, the status is absent while collapsed. After expanding, the `Saved evidence age` line is shown.
  - **Session:**
    - expand, tap `nav-scanner` then `nav-map`, and the section is still expanded;
    - expand, set `tester.view.physicalSize` to `760×900` and pump, and the section is still expanded;
    - pump a new `BlackgridApp(key: UniqueKey())`, and the section is collapsed.

  Also write the green "Active map row stays alone" test. Accept a scan (`publishTargetedScan` from `test/ui/support/scan_ui_support.dart`) and check that:
  - no `GridPanel` other than Active map overlaps the Active map rect vertically within the rail;
  - no "Latest accepted scan" text is shown.

  Verify that `mise run test -- test/ui/map_rail_test.dart` fails on the red rows for the right reason (the order assertion fails, or `Key('map-inputs-toggle')` is not found) and that the green row passes.
- [ ] 2.2 Change `lib/ui/map_screen.dart`:
  - `MapScreen` becomes a `StatefulWidget` owning `_inputsExpanded = false` (design D1).
  - Reorder the rail (design D4).
  - Wrap `_MapInputStatus(key: const Key('map-input-status'), ...)` in a `CollapsibleGridPanel` titled "Map saved-file inputs" with `toggleKey: const Key('map-inputs-toggle')` (designs D2 and D3).
  - Change no string, fixed height or `_MapInputStatus` code.

  Verify that every row of the test map passes, and flip the red rows green.
- [ ] 2.3 Update the existing tests that reach the section's content to call `expandMapInputs` first:
  - `test/ui/map_screen_test.dart`: the Read Latest tests at `:17` and `:88`, and the manual map authority test at `:216`;
  - any other test that `mise run test` shows failing on a `Logs:`, `Manual map`, `Follow logs` or `Read Latest` finder.

  Keep every assertion. Delete none. Verify that `mise run test -- test/ui/map_screen_test.dart test/ui/latest_scan_card_test.dart test/ui/scanner_screen_test.dart test/widget_test.dart` passes.

## 3. Integration checks

- [ ] 3.1 Run `dart format` on the changed files, then `mise run analyze` and `mise run test`. Verify that both pass, with no new analyzer warnings.

## Workflow follow-up

- User check (M4.5 exit criterion 1, the in-raid read): the user confirms in a raid that the Map rail reads well, with saved-file inputs at the bottom and collapsed. This stays unverified until the user reports it. No agent performs it.
