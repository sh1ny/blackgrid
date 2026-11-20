# Tasks

Dart work follows the "Dart and Flutter code" section of `AGENTS.md`. Skills for every group: `flutter-add-widget-test`, `dart-add-unit-test`, `dart-write-documentation`, `dart-run-static-analysis` (`.claude/skills/<name>/SKILL.md`). Each scenario here is proved by a widget test, the cheapest layer that can measure layout and text. Use small synthetic catalogs and map packs from the existing test helpers.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| workspace-shell → Top bar keeps navigation and timers reachable | Wide navigation | test/ui/shell_test.dart | workspace-shell: Wide navigation | green |
| workspace-shell → Top bar keeps navigation and timers reachable | Narrow navigation and disabled timers | test/ui/shell_test.dart | workspace-shell: Narrow navigation and disabled timers | green |
| workspace-shell → Top bar keeps navigation and timers reachable | Anchored search results and explicit selection | test/ui/shell_test.dart | workspace-shell: Anchored search results and explicit selection | green |
| workspace-shell → Top bar keeps navigation and timers reachable | Wide tools alignment | test/ui/shell_test.dart | workspace-shell: Wide tools alignment (and its compact variants) | green |
| workspace-shell → Top bar keeps navigation and timers reachable | Tools reach the right edge on a very wide window | test/ui/shell_test.dart | workspace-shell: Tools reach the right edge on a very wide window | green |
| workspace-shell → Top bar keeps navigation and timers reachable | Segmented area switch | test/ui/shell_test.dart | workspace-shell: Segmented area switch | green |
| scan-correction → The offer fits in the answer strip without its own scroll bar | Full offer on a 1080p window | test/ui/scan_correction_card_test.dart | scan-correction: Full offer on a 1080p window | red |
| scan-correction → The offer fits in the answer strip without its own scroll bar | Results wrap as buttons | test/ui/scan_correction_card_test.dart | scan-correction: Results wrap as buttons | red |
| scan-correction → The offer fits in the answer strip without its own scroll bar | No results still says so | test/ui/scan_correction_card_test.dart | scan-correction: No results still says so | red |
| scan-correction → The offer fits in the answer strip without its own scroll bar | Short window keeps the strip limit | test/ui/scan_correction_card_test.dart | scan-correction: Short window keeps the strip limit | red |
| map-controls → The map credit names the map's creator | Map with an author | test/ui/map_workspace_controls_test.dart | map-controls: Map with an author | red |
| map-controls → The map credit names the map's creator | Map without an author | test/ui/map_workspace_controls_test.dart | map-controls: Map without an author | red |
| map-controls → The map credit names the map's creator | Long credit on a narrow map | test/ui/map_workspace_controls_test.dart | map-controls: Long credit on a narrow map | red |
| M9 exit criterion | The `polish-ember-ui` fixes look right | — | task 4.2 | user |

## 1. Top-bar tools reach the right edge

- [x] 1.1 Add the widget test `workspace-shell: Tools reach the right edge on a very wide window`. Pump the shell at 1920×1080, 2560×1440 and 3440×1440, with all timers enabled and again with every timer hidden. Assert that the search field is at most 480 wide and starts right after the area switch, that `bar.right - settings.right` is at most 16, and that it equals the 1660-wide value. Run it and confirm it fails at 2560 and 3440 because of the gap after Settings.
- [x] 1.2 In `lib/ui/shell.dart` `_headerItems`, replace the wide `Flexible` + `Spacer` with one `Expanded` that holds the 480 px-capped search aligned to its start (design D1). Leave the compact `Wrap` alone. Verify that the 1.1 test and every `workspace-shell:` test in `test/ui/shell_test.dart` pass, and flip the row to green.

## 2. Correction offer fits without a scroll bar

- [ ] 2.1 In `test/ui/scan_correction_card_test.dart`, add `scan-correction: Full offer on a 1080p window` (Map and Scanner, 5 candidates, 8 results: no `SingleChildScrollView` inside `correction-offer` or between it and the strip, all candidates, the field and all 8 `correction-result-*` inside the visible strip, the strip's scroll extent 0), `scan-correction: Results wrap as buttons` (8 results are `OutlinedButton`s in ID order, on more than one row at a narrow width, and tapping one selects it), `scan-correction: No results still says so` (`correction-no-match` shown, no result buttons, selection unchanged) and `scan-correction: Short window keeps the strip limit` (1280×600: no scroll view inside the offer, the strip stays within its 55 % limit, and the last result can be scrolled into view). Run them and confirm the first, second and fourth fail for the right reason. The third may already pass; keep it as the regression guard.
- [ ] 2.2 In `lib/ui/answer_strip.dart`, remove the offer's `ConstrainedBox` + `SingleChildScrollView`. In `lib/ui/correction_offer_block.dart`, render the results as a `Wrap` of `OutlinedButton`s keyed `correction-result-<id>` with `_rowLabel` (design D2). Update the class doc comment. Verify that the 2.1 tests and the whole file pass, including the existing same-name, cap-8 and navigation tests, with finders adjusted only from `InkWell` to the button type. Flip the rows to green.

## 3. Map credit names the map's creator

- [ ] 3.1 In `test/ui/map_workspace_controls_test.dart`, add `map-controls: Map with an author` (text `Map creator: Shebuka`, colour equals the dark palette `ink`), `map-controls: Map without an author` (pack map with no `author` and name `Customs`: text `Customs`, nothing starts with `Map creator:`) and `map-controls: Long credit on a narrow map` (one line, ellipsis overflow, its rect does not overlap the map control stack). Run them and confirm the first two fail.
- [ ] 3.2 In `lib/ui/map_workspace.dart`, render `Map creator: <author>` when `attribution['author']` is a non-empty string, else `map.name`, in `_overlayInk.ink` (design D3). Verify that the 3.1 tests and every `map-controls:` test pass, including `Normal use`, and flip the rows to green.

## 4. Integration and the owner's check

- [ ] 4.1 Run `dart format` on the changed files, then `mise run analyze` (no issues) and `mise run test` (all pass, including the release-notes check of this proposal). Confirm that every test-map row except the user row is green.
- [ ] 4.2 [user] The owner checks in the app, on a window wider than 1920×1080, that: the "Last scan not accepted — pick the item" block on Map and Scanner shows its results as buttons with no scroll bar; the map credit reads "Map creator: <name>" and is easier to read; and Stats, Import and Settings sit at the top bar's right edge. This is the `polish-ember-ui` part of M9's user-verified exit criterion. Agents do not run it, and it stays unverified until the owner reports a result.
