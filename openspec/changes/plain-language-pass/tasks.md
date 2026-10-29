# Tasks

## Test map

Test files:
- `test/ui/labels_test.dart` (new): pure label and time functions.
- `test/ui/plain_language_source_test.dart` (new): source checks A and B, file IO only.
- `test/ui/details_section_test.dart` (new, widget).
- `test/ui/data_sources_panel_test.dart` (new, widget).
- `test/ui/history_panel_test.dart` (new, widget).
- `test/ui/decision_card_text_test.dart` (new, widget).
- Existing: `test/ui/scan_evidence_panel_test.dart`, `test/ui/scanner_screen_test.dart`, `test/ui/shell_test.dart`, `test/ui/map_rail_test.dart`.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| player-facing-text → Shown states use plain-language labels | Stale catalog in the footer | test/ui/shell_test.dart | footer says item data is out of date when the catalog is stale | red |
| player-facing-text → Shown states use plain-language labels | Imported scan in history | test/ui/history_panel_test.dart | an imported scan row says Imported scan | red |
| player-facing-text → Shown states use plain-language labels | Every value has a label | test/ui/labels_test.dart | every value of every shown kind has a plain label | green |
| player-facing-text → Shown states use plain-language labels | Unknown found-in-raid state | test/ui/decision_card_text_test.dart | unknown found in raid is said in words | red |
| player-facing-text → Developer wording stays out of the open view | Search field hint | test/ui/shell_test.dart | search hint asks for an item name without canonical | red |
| player-facing-text → Developer wording stays out of the open view | Searching by ID still works | test/ui/shell_test.dart | search still finds an item by its tarkov.dev id | green |
| player-facing-text → Developer wording stays out of the open view | Name does not resolve | test/ui/history_panel_test.dart | a row whose item has no name shows its id | green |
| player-facing-text → Developer wording stays out of the open view | Term check over the UI sources | test/ui/plain_language_source_test.dart | no scanned literal contains a banned term | red |
| player-facing-text → Times are shown in local time | History row time | test/ui/history_panel_test.dart | a row observed today shows its local time without ISO | red |
| player-facing-text → Times are shown in local time | Earlier day | test/ui/labels_test.dart | localTimeLabel gives date and time for an earlier day | green |
| player-facing-text → Times are shown in local time | Missing flea quote time | test/ui/data_sources_panel_test.dart | a missing flea quote time reads unknown | red |
| player-facing-text → Details sections start collapsed | Collapsed at launch | test/ui/scanner_screen_test.dart | scan evidence Details starts collapsed with no score or timing | red |
| player-facing-text → Details sections start collapsed | Expanding shows the detail | test/ui/details_section_test.dart | tapping the Details title builds the content | green |
| player-facing-text → Details sections start collapsed | Survives a tab switch | test/ui/shell_test.dart | scan evidence Details stays expanded across Map and back | red |
| player-facing-text → Details sections start collapsed | Survives a layout change | test/ui/scanner_screen_test.dart | scan evidence Details stays expanded across the compact breakpoint | red |
| player-facing-text → Details sections start collapsed | New launch | test/ui/scanner_screen_test.dart | a new app starts with Details collapsed | red |
| player-facing-text → Data sources panel reads in plain language | Current item data | test/ui/data_sources_panel_test.dart | current item data says up to date with its local time and hides the URL | red |
| player-facing-text → Data sources panel reads in plain language | No catalog | test/ui/data_sources_panel_test.dart | no catalog says item data is not downloaded yet | red |
| player-facing-text → Data sources panel reads in plain language | Tracker in cooldown | test/ui/data_sources_panel_test.dart | cooldown is said in the open and its end time only in Details | red |
| player-facing-text → Raw enum names are never interpolated into UI text | Clean sources | test/ui/plain_language_source_test.dart | lib/ui has no raw enum name in text | red |
| player-facing-text → Raw enum names are never interpolated into UI text | A regression | test/ui/plain_language_source_test.dart | check A flags a status name chain | green |
| player-facing-text → Raw enum names are never interpolated into UI text | A destructured regression | test/ui/plain_language_source_test.dart | check A flags a destructured reason name | green |
| player-facing-text → Raw enum names are never interpolated into UI text | Keys are not text | test/ui/plain_language_source_test.dart | check A ignores names inside keys and item names | green |
| scanner-evidence → Scan phase is visible, including fallback | Fallback becomes visible | test/ui/scan_evidence_panel_test.dart | fallback phase says it is trying a wider scan | red |
| scanner-evidence → Scan phase is visible, including fallback | Superseded scan | test/ui/scan_evidence_panel_test.dart | superseded scan shows only the newer phase | red |
| scanner-evidence → Scanner shows the latest scan's evidence | Accepted scan | test/ui/scan_evidence_panel_test.dart | accepted report shows the item name, and Details shows id, pass, score, crop and text | red |
| scanner-evidence → Scanner shows the latest scan's evidence | Rejected scan | test/ui/scan_evidence_panel_test.dart | rejected report gives a plain reason with the best candidate not accepted | red |
| scanner-evidence → Scanner shows the latest scan's evidence | Failed scan | test/ui/scan_evidence_panel_test.dart | failed report gives a plain reason and its code only in Details | red |
| scanner-evidence → Scanner shows the latest scan's evidence | Navigation keeps evidence | test/ui/shell_test.dart | scan evidence survives Map and back | green |
| scanner-evidence → Scanner shows the latest scan's evidence | Newer accepted scan replaces the shown one | test/ui/scan_evidence_panel_test.dart | a newer accepted scan replaces the shown item | green |
| scanner-evidence → Scanner shows stage timings and recent scans | Timings of an accepted scan | test/ui/scan_evidence_panel_test.dart | timings in Details show stage and total ms | red |
| scanner-evidence → Scanner shows stage timings and recent scans | Timings hidden while collapsed | test/ui/scan_evidence_panel_test.dart | no timing is shown while Details is collapsed | red |
| scanner-evidence → Scanner shows stage timings and recent scans | Early failure | test/ui/scan_evidence_panel_test.dart | absent stages are shown as absent, not 0 | red |
| scanner-evidence → Scanner shows stage timings and recent scans | Recent list bound | test/ui/scan_evidence_panel_test.dart | recent list shows the 10 newest scans, newest first | green |
| scanner-evidence → Scanner shows stage timings and recent scans | Recent rejected entry | test/ui/scan_evidence_panel_test.dart | a rejected recent entry gives a plain reason | red |
| scanner-evidence → Scanner shows stage timings and recent scans | Hotkey scan in the list | test/ui/scan_evidence_panel_test.dart | recent list labels hotkey scans | green |
| scanner-evidence → A later unaccepted scan is shown as a note | Rejection after an accepted item | test/ui/scan_evidence_panel_test.dart | rejection after an accepted item keeps it and shows a plain note | red |
| scanner-evidence → A later unaccepted scan is shown as a note | Crop and timings after a rejection | test/ui/scan_evidence_panel_test.dart | after a rejection Details keeps the accepted crop and shows the new scan's timings | red |
| scanner-evidence → A later unaccepted scan is shown as a note | Failure after an accepted item | test/ui/scan_evidence_panel_test.dart | failure after an accepted item says the game window was not in front | red |
| scanner-evidence → A later unaccepted scan is shown as a note | Accepted again | test/ui/scan_evidence_panel_test.dart | a newer acceptance removes the note | green |
| map-rail → Map saved-file inputs starts collapsed | Collapsed on first show | test/ui/map_rail_test.dart | inputs section starts collapsed | green |
| map-rail → Map saved-file inputs starts collapsed | Expanding shows the inputs | test/ui/map_rail_test.dart | expanding shows status, Follow logs and a working Read Latest | green |
| map-rail → Map saved-file inputs starts collapsed | Status lines use labels | test/ui/map_rail_test.dart | expanded status lines use labels, not state names | red |
| map-rail → Map saved-file inputs starts collapsed | Collapsing keeps settings | test/ui/map_rail_test.dart | expand then collapse keeps Follow logs and the maps | green |
| map-rail → Map saved-file inputs starts collapsed | Pending screenshot while collapsed | test/ui/map_rail_test.dart | pending screenshot keeps the section collapsed | green |

Every group follows AGENTS.md "Dart and Flutter code" and loads the skills `dart-use-pattern-matching`, `dart-write-documentation`, `dart-add-unit-test` and `dart-run-static-analysis`, plus `flutter-add-widget-test` for groups with widget tests. No sleeps: use the existing bounded crop poll (`scan_evidence_panel_test.dart:39`) only where a decode crosses the engine. Each group ends green on `mise run analyze` and `mise run test`, formatted with `dart format`.

## 1. Labels, local time and the source-check engine

- [x] 1.1 Write `test/ui/labels_test.dart`: "every value of every shown kind has a plain label" iterates `.values` of `CatalogStatus`, `ProgressStatus`, `MapInputStatus`, `RaidPanelState`, `ScanRejectReason`, `ScanFailureCode`, `ScanPass`, `FirState` and `ActivitySource`, asserting each label is non-empty, has no `[a-z][A-Z]`, and differs from `.name` unless the name is one lowercase word. Add `localTimeLabel` cases with a fixed `now`: same local day gives `HH:mm`, an earlier day gives `d MMM HH:mm` ("localTimeLabel gives date and time for an earlier day"), and null gives `unknown`. Verify it fails to compile or fails (no `lib/ui/labels.dart`).
- [x] 1.2 Add `lib/ui/labels.dart` with one exhaustive `switch` expression per kind and `localTimeLabel(DateTime?, {required DateTime now})` (design D1, D5), with `///` docs. Verify 1.1 passes and flip "Every value has a label" and "Earlier day" green.
- [x] 1.3 Write the check-engine tests in `test/ui/plain_language_source_test.dart` over in-memory samples: "check A flags a status name chain" (`'Catalog: ${catalog.status.name}'`), "check A flags a destructured reason name" (`'Reason: ${reason.name}'`), "check A ignores names inside keys and item names" (`ValueKey('results-${mode.name}')`, `Text(item.name)`, a `//` comment), and a Check B sample set: a hit on "canonical", "identities" and "Normalized", none inside `Key('…')`, and `M1` whole-word only. Verify they fail.
- [x] 1.4 Implement the two checks as pure functions in `test/ui/support/plain_language_check.dart` (D6 patterns, file:line in each hit). Verify 1.3 passes and flip "A regression", "A destructured regression" and "Keys are not text" green. The whole-tree assertions are added in group 7.

## 2. Details section and Scanner-owned expansion state

- [x] 2.1 Write `test/ui/details_section_test.dart`: collapsed shows only the "Details" title and never calls the builder, and "tapping the Details title builds the content" calls `onExpandedChanged(true)`, after which the host rebuild shows the content. Verify it fails.
- [x] 2.2 Add the stateless `DetailsSection` to `lib/ui/theme.dart` (title row button, chevron, `WidgetBuilder` called only while expanded, `///` docs), following `CollapsibleGridPanel`. Verify 2.1 passes and flip "Expanding shows the detail" green.
- [x] 2.3 Make `ScannerScreen` a `StatefulWidget` that owns `scanDetailsExpanded` and `sourceDetailsExpanded` above its `LayoutBuilder`. Pass each flag and setter as required parameters to `ScanEvidencePanel` and `SourcePanel` (D2). Update the existing panel test hosts to supply them. Verify `mise run test` is still green with no behaviour change yet.

## 3. Scan evidence panel in plain language

- [ ] 3.1 Rewrite the red rows of `test/ui/scan_evidence_panel_test.dart` to the new spec: the phase words, the open-view item name or plain reason with the best candidate "(not accepted)", codes, pass, scores, margin, OCR text, crop and item ID found only after expanding Details, timings only in Details, a rejected recent entry with no `noMarker`, and the plain note text. Keep the existing keys on the same facts, and assert the raw code under `scan-reason-code` (D3). Add "a newer accepted scan replaces the shown item" (green rider) and "no timing is shown while Details is collapsed". Write "scan evidence Details starts collapsed with no score or timing", "scan evidence Details stays expanded across the compact breakpoint" and "a new app starts with Details collapsed" in `test/ui/scanner_screen_test.dart`, and "scan evidence Details stays expanded across Map and back" in `test/ui/shell_test.dart`. Verify the red rows fail for the wording or Details reason, not a harness error.
- [ ] 3.2 Rework `lib/ui/scan_evidence_panel.dart` per D3: plain phase text, the summary in the open view, everything diagnostic inside `DetailsSection`, labels from `labels.dart`, the "Evidence only • never a decision" subtitle reworded without banned terms, and the crop decode left unchanged. Verify all scanner-evidence rows and the four Details rows from 3.1 pass, and flip them green. Re-run the green riders ("Navigation keeps evidence", "Recent list bound", "Hotkey scan in the list", "Accepted again") and confirm they still pass.

## 4. Data sources panel and history

- [ ] 4.1 Write `test/ui/data_sources_panel_test.dart` ("current item data says up to date with its local time and hides the URL", "no catalog says item data is not downloaded yet", "cooldown is said in the open and its end time only in Details", "a missing flea quote time reads unknown") and `test/ui/history_panel_test.dart` ("an imported scan row says Imported scan", "a row observed today shows its local time without ISO", plus the green rider "a row whose item has no name shows its id"). Build expected times with `localTimeLabel` from the same instant (design Flow & State Gaps). Verify the red ones fail.
- [ ] 4.2 Rework `SourcePanel` in `lib/ui/evidence_panels.dart` into "Data sources" (D4) and `HistoryPanel` (subtitle, empty text, `activitySourceLabel`, `localTimeLabel`). Keep `itemsSourceUpdateLabel` behind Details and update `test/ui/evidence_source_time_label_test.dart` only if its text moves. Verify 4.1 passes and flip its rows green.

## 5. Decision card, shell, manual controls and live scan panel

- [ ] 5.1 Write `test/ui/decision_card_text_test.dart` ("unknown found in raid is said in words": no `FIR: unknown`, and none of the D7 decision-card developer strings) and, in `test/ui/shell_test.dart`, "footer says item data is out of date when the catalog is stale", "search hint asks for an item name without canonical" and the green rider "search still finds an item by its tarkov.dev id". Verify the red ones fail.
- [ ] 5.2 Rewrite `lib/ui/item_decision_card.dart`, `lib/ui/shell.dart` (footer and hint), `lib/ui/manual_controls.dart` (status lines through labels, prompts, no `normalizedName` subtitle), `lib/ui/live_scan_panel.dart` (any banned term) and the empty card in `lib/ui/theme.dart` per D7. Update the existing assertions in `m1_flow_test.dart`, `latest_scan_card_test.dart`, `scan_correction_card_test.dart`, `live_scan_panel_test.dart` and `scanner_screen_test.dart` that pinned old wording. Verify 5.1 passes, flip its rows green, and `mise run test` is green.

## 6. Settings, import, pin editor and controller messages

- [ ] 6.1 Rewrite `lib/ui/settings_dialog.dart`, `lib/ui/import_dialog.dart` ("File fingerprint", plain prompts) and `lib/ui/pin_editor.dart` (labels, and the frame literals replaced by `MapCoordinateFrame.*.wireName` per D6). Rewrite the display strings in `lib/application/selection_controller.dart`, `settings_controller.dart`, `progress_controller.dart`, `map_controller.dart` and `history_controller.dart`, and the `reason:` strings in `lib/data/legacy_import.dart` (ISO times through `localTimeLabel`, or plain wording with no time), per D7. Leave `catalog_controller.dart:68,124` unchanged. Update `settings_dialog_test.dart`, `import_dialog_test.dart` and any application or data test that pinned old message text. Add a pin-save regression test in an existing pin editor test proving a new pin on `thelab` and on another map saves with the `labs-native-normalized` and `legacy-normalized` frames. Verify `mise run test` is green.

## 7. Map rail and workspace, then the whole-tree checks

- [ ] 7.1 Write "expanded status lines use labels, not state names" in `test/ui/map_rail_test.dart`. Verify it fails.
- [ ] 7.2 Rewrite `lib/ui/map_screen.dart` (Logs, Screenshots and Raid panel lines through `mapInputStatusLabel` and `raidPanelStateLabel`, local times, the subtitle, "N saved pins") and `lib/ui/map_workspace.dart` (any banned term). Verify 7.1 passes and flip it green, and re-run the green map-rail riders.
- [ ] 7.3 Add the whole-tree tests to `test/ui/plain_language_source_test.dart`: "lib/ui has no raw enum name in text" (Check A over `lib/ui/**/*.dart`) and "no scanned literal contains a banned term" (Check B over `lib/ui/**`, the six controller files and `lib/data/legacy_import.dart`). Fix any remaining hit by rewording, never with an allow-list entry for a player-facing literal. Verify both pass, and flip "Clean sources" and "Term check over the UI sources" green.
- [ ] 7.4 Integration check: `mise run analyze` and `mise run test` green, every Test map row green, and `openspec validate plain-language-pass --strict` passes.

## Workflow follow-up

- User-verified, not agent work: the in-raid read of the new wording (M4.5 exit criterion, "user for the read"). It stays unverified until the user reports it. Agents never launch the app while Escape from Tarkov is running.
- After this change merges, the milestone is at its end: run `/specwright-roadmap close`.
