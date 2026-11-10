# Tasks

Every group follows the "Dart and Flutter code" section of AGENTS.md. Load `flutter-add-widget-test`, `dart-add-unit-test`, `dart-use-pattern-matching` and `dart-write-documentation` for every group. Prove each scenario at the cheapest widget layer: a widget test on the widget itself, and a full-shell test only where the scenario spans the shell (the guard, inspector tiles, the Map/Scanner switch). No sleeps: pump scan reports through the existing fakes in `test/ui/scan_evidence_panel_test.dart` and `test/ui/shell_test.dart`, and wait on the crop decode with `tester.runAsync` plus a pump, as the existing crop test does.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| settings-diagnostics → Main windows keep diagnostic detail out of normal use | Accepted scan on the Scanner | test/ui/shell_test.dart | main windows show no diagnostic detail for an accepted scan | green |
| settings-diagnostics → Main windows keep diagnostic detail out of normal use | Rejected scan with a correction offer | test/ui/shell_test.dart | main windows show no diagnostic detail beside a correction offer | green |
| settings-diagnostics → Main windows keep diagnostic detail out of normal use | Corrected scan subtitle | test/ui/scan_correction_card_test.dart | a picked correction is titled and aged as not accepted | green |
| settings-diagnostics → Problems the player must act on stay on the main windows | Rejected scan still explains itself | test/ui/scan_evidence_panel_test.dart | rejected report gives a plain reason with the best candidate not accepted | green |
| settings-diagnostics → Problems the player must act on stay on the main windows | Errors the player must act on stay visible | test/ui/shell_test.dart | catalog error and recording stop note stay on the Scanner | green |
| settings-diagnostics → Diagnostics shows the latest scans' evidence | Accepted scan | test/ui/scan_diagnostics_test.dart | accepted scan shows number, item id, pass, score, crop and text | green |
| settings-diagnostics → Diagnostics shows the latest scans' evidence | Rejection after an accepted item | test/ui/scan_diagnostics_test.dart | a later rejection shows its code and text and keeps the accepted crop | green |
| settings-diagnostics → Diagnostics shows the latest scans' evidence | Failed scan | test/ui/scan_diagnostics_test.dart | a failed scan shows its code and message and no crop | green |
| settings-diagnostics → Diagnostics shows the latest scans' evidence | No scan yet | test/ui/scan_diagnostics_test.dart | before any scan it says none is published and shows no timings | green |
| settings-diagnostics → Diagnostics shows the latest scans' evidence | A scan arrives while open | test/ui/settings_diagnostics_test.dart | a scan published while Diagnostics is open is shown at once | green |
| settings-diagnostics → Diagnostics shows stage timings | Timings of an accepted scan | test/ui/scan_diagnostics_test.dart | timings show stage and total ms labelled with the scan number | green |
| settings-diagnostics → Diagnostics shows stage timings | Early failure | test/ui/scan_diagnostics_test.dart | absent stages are shown as absent, not 0 | green |
| settings-diagnostics → Diagnostics shows stage timings | Timings follow the latest scan after a rejection | test/ui/scan_diagnostics_test.dart | after a rejection the timings are the new scan's | green |
| settings-diagnostics → Diagnostics lists the recent scans | Recent list bound | test/ui/scan_diagnostics_test.dart | recent list shows the 10 newest scans, newest first | green |
| settings-diagnostics → Diagnostics lists the recent scans | Hotkey and mouse scans | test/ui/scan_diagnostics_test.dart | recent list labels hotkey scans | green |
| settings-diagnostics → Diagnostics lists the recent scans | Rejected entry | test/ui/scan_diagnostics_test.dart | a rejected recent entry gives a plain reason and its end state | green |
| settings-diagnostics → Diagnostics lists the recent scans | No scans | test/ui/scan_diagnostics_test.dart | an empty recent list says there are no scans yet | green |
| settings-diagnostics → Diagnostics shows data source detail | Current catalog | test/ui/data_sources_panel_test.dart | Diagnostics shows source, UTC download time and record counts | green |
| settings-diagnostics → Diagnostics shows data source detail | No catalog | test/ui/data_sources_panel_test.dart | Diagnostics says there is no complete item data download | green |
| settings-diagnostics → Diagnostics shows data source detail | Tracker in cooldown | test/ui/data_sources_panel_test.dart | Diagnostics shows when progress refresh is available again | green |
| settings-diagnostics → Collapsed Diagnostics does no scan or source work | Collapsed with an accepted scan | test/ui/settings_diagnostics_test.dart | collapsed Diagnostics builds no scan evidence or crop | green |
| settings-diagnostics → Collapsed Diagnostics does no scan or source work | Expand after scans | test/ui/settings_diagnostics_test.dart | expanding shows the latest scan and every recent scan | green |
| scanner-evidence → Scanner shows the latest scan's evidence | Accepted scan | test/ui/scan_evidence_panel_test.dart | accepted report shows only the item name | green |
| scanner-evidence → Scanner shows the latest scan's evidence | Rejected scan | test/ui/scan_evidence_panel_test.dart | rejected report gives a plain reason with the best candidate not accepted | green |
| scanner-evidence → Scanner shows the latest scan's evidence | Failed scan | test/ui/scan_evidence_panel_test.dart | failed report gives a plain reason and no code | green |
| scanner-evidence → Scanner shows the latest scan's evidence | No scan yet | test/ui/scan_evidence_panel_test.dart | before any scan it says none is published | green |
| scanner-evidence → Scanner shows the latest scan's evidence | Navigation keeps evidence | test/ui/shell_test.dart | scan evidence survives Map and back | green |
| scanner-evidence → Scanner shows the latest scan's evidence | Newer accepted scan replaces the shown one | test/ui/scan_evidence_panel_test.dart | a newer accepted scan replaces the shown item | green |
| scanner-evidence → A later unaccepted scan is shown as a note | Rejection after an accepted item | test/ui/scan_evidence_panel_test.dart | rejection after an accepted item keeps it and shows a plain note | green |
| scanner-evidence → A later unaccepted scan is shown as a note | Crop and timings after a rejection | test/ui/scan_evidence_panel_test.dart | after a rejection the Scanner shows no crop and no timing | green |
| scanner-evidence → A later unaccepted scan is shown as a note | Failure after an accepted item | test/ui/scan_evidence_panel_test.dart | failure after an accepted item says the game window was not in front | green |
| scanner-evidence → A later unaccepted scan is shown as a note | Accepted again | test/ui/scan_evidence_panel_test.dart | a newer acceptance removes the note | green |
| scanner-evidence → Scan evidence panel is visible without scrolling | Desktop window | test/ui/shell_test.dart | scan evidence panel is fully on screen at 1660x870 | green |
| scanner-evidence → Scan evidence panel is visible without scrolling | Short desktop window | test/ui/shell_test.dart | scan evidence panel is on screen at 1100x720 with enlarged text | green |
| scanner-evidence → Scan evidence panel is visible without scrolling | Narrow window | test/ui/shell_test.dart | compact layout shows evidence without the old Scanner controls | green |
| player-facing-text → Developer wording stays out of the open view | Search field hint | test/ui/shell_test.dart | search hint asks for an item name without canonical | green |
| player-facing-text → Developer wording stays out of the open view | Searching by ID still works | test/ui/shell_test.dart | search still finds an item by its tarkov.dev id | green |
| player-facing-text → Developer wording stays out of the open view | Name does not resolve | test/ui/history_panel_test.dart | a row whose item has no name shows its id | green |
| player-facing-text → Developer wording stays out of the open view | Term check over the UI sources | test/ui/plain_language_source_test.dart | no scanned literal contains a banned term | green |
| player-facing-text → Times are shown in local time | History row time | test/ui/history_panel_test.dart | a row observed today shows its local time without ISO | green |
| player-facing-text → Times are shown in local time | Earlier day | test/ui/labels_test.dart | localTimeLabel gives date and time for an earlier day | green |
| player-facing-text → Times are shown in local time | Missing flea quote time | test/ui/data_sources_panel_test.dart | a missing flea quote time reads unknown | green |
| player-facing-text → Times are shown in local time | No UTC time in the inspector | test/ui/shell_test.dart | the Scanner inspector shows no UTC time | green |
| player-facing-text → Data sources panel reads in plain language | Current item data | test/ui/data_sources_panel_test.dart | current item data says up to date with its local time and has no Details | green |
| player-facing-text → Data sources panel reads in plain language | No catalog | test/ui/data_sources_panel_test.dart | no catalog says item data is not downloaded yet | green |
| player-facing-text → Data sources panel reads in plain language | Tracker in cooldown | test/ui/data_sources_panel_test.dart | cooldown is said in the panel with no end time | green |
| interface-theme → Ember surfaces and labels | A docked panel has no shadow | test/ui/ember_surfaces_test.dart | docked panels use panel colour, hairline and no elevation in both rooms | green |
| interface-theme → Ember surfaces and labels | Section labels are sentence case | test/ui/ember_surfaces_test.dart | section labels are sentence case | green |
| interface-theme → Ember surfaces and labels | The brand lockup keeps its capitals | test/ui/ember_surfaces_test.dart | brand lockup keeps its capitals | green |
| scan-correction → The offer lists the scan's best candidates | Close-named variants | test/ui/scan_correction_card_test.dart | the offer lists candidates in rank order without scores | green |
| scan-correction → The offer lists the scan's best candidates | More than five candidates | test/application/scan_correction_test.dart | offer lists at most five candidates | green |
| scan-correction → The offer lists the scan's best candidates | Weak candidates | test/application/scan_correction_test.dart | candidates below .40 are left out | green |
| scan-correction → The offer lists the scan's best candidates | Candidate gone from the catalog | test/application/scan_correction_test.dart | candidate missing from the live catalog is left out | green |
| scan-correction → The offer lists the scan's best candidates | No scan id in the offer | test/ui/scan_correction_card_test.dart | the offer says the last scan was not accepted without its number | green |
| scan-correction → Picking a correction makes it the current selection | Pick the runner-up | test/ui/scan_correction_card_test.dart | a picked correction is titled and aged as not accepted | green |
| scan-correction → Picking a correction makes it the current selection | Pick from search | test/ui/scan_correction_card_test.dart | a search pick is labelled corrected from a scan | green |
| scan-correction → Picking a correction makes it the current selection | FIR from the earlier item | test/application/scan_correction_test.dart | a pick resets FIR | green |
| scan-correction → Picking a correction makes it the current selection | History view open | test/application/scan_correction_test.dart | a pick closes an open history view | green |
| scan-correction → Picking a correction makes it the current selection | History write fails | test/application/scan_correction_test.dart | failed correction write keeps the correction with an error | green |
| scan-correction → Same-name candidates are told apart in the offer | Weapon case variants | test/ui/scan_correction_card_test.dart | same-name candidates show flea status and id suffix | green |
| scan-correction → Same-name candidates are told apart in the offer | Only one listed same-name item | test/ui/scan_correction_card_test.dart | a lone same-name candidate shows its name only | green |
| scan-correction → Same-name candidates are told apart in the offer | Unknown flea status | test/ui/scan_correction_card_test.dart | unknown flea status shows flea unknown | green |
| scan-correction → Same-name candidates are told apart in the offer | Variant found through the search | test/ui/scan_correction_card_test.dart | a search row in a same-name group is labelled | green |
| scan-correction → Same-name candidates are told apart in the offer | Picking a variant | test/ui/scan_correction_card_test.dart | picking the no-flea variant selects it | green |

## 1. Scan diagnostics widget

- [x] 1.1 Create `test/ui/scan_diagnostics_test.dart` by moving the Details tests from `test/ui/scan_evidence_panel_test.dart` (id/pass/score/crop/text, codes, timings, recent list) onto a new `ScanDiagnostics` widget, renamed per the test map. Add "before any scan…", "an empty recent list…", "a rejected recent entry … end state" and "timings … labelled with the scan number". Verify they fail to compile or fail because `ScanDiagnostics` does not exist.
- [x] 1.2 Add `ScanDiagnostics` to `lib/ui/scan_evidence_panel.dart` (design D1): today's `_details` content, the recent list with plain row, hotkey label, end state and total, and the crop decode with its per-id fence and dispose on unmount, moved from `_ScanEvidencePanelState`. It listens to the coordinator and catalog only while mounted. Document it with `///`. Verify that every `scan_diagnostics_test.dart` row in the test map passes, and flip those rows green.

## 2. Scanner keeps only the plain result

- [x] 2.1 Update `test/ui/scan_evidence_panel_test.dart`: the accepted, rejected, failed, note and noMarker tests assert that the panel shows no item ID, pass, score, crop, OCR text, code, timing, recent list or Details control. Add "before any scan it says none is published" and "after a rejection the Scanner shows no crop and no timing". Remove the tests that moved in 1.1. Update `test/ui/scanner_screen_test.dart`: replace the two Details tests (collapsed start, survives the breakpoint) and "a new app starts with Details collapsed" with one test that the Scanner has no Details control. Verify the new assertions fail.
- [x] 2.2 Strip `ScanEvidencePanel` to the phase, the summary and the note. Drop `detailsExpanded`/`onDetailsExpandedChanged`, the crop decode and the recent list, and remove `_scanDetailsExpanded` from `lib/ui/scanner_screen.dart`. Verify the 2.1 tests pass and flip their scanner-evidence rows green.
- [x] 2.3 Update `test/ui/shell_test.dart`: remove "scan evidence Details stays expanded across Map and back". Rewrite the 1100x720 test as "scan evidence panel is on screen at 1100x720 with enlarged text", with a phase, a note and an accepted scan at a text scale where the content is taller than the frame, asserting that the frame is on screen and the inner list scrolls. Re-run "scan evidence survives Map and back", "…fully on screen at 1660x870", "compact layout shows evidence…" and the overflow sizes. Verify they pass and flip their rows green.

## 3. Data sources detail moves

- [x] 3.1 In `test/ui/data_sources_panel_test.dart`, make the current-item-data and cooldown tests assert that `SourcePanel` has no Details control, URL, record count or cooldown end time. Add the three `DataSourceDiagnostics` tests from the test map. The no-catalog test uses a missing catalog. A history-catalog case, if added, uses a row from another game mode, because a same-mode row reads the live catalog (`lib/application/selection_controller.dart:57-60`). Verify the new tests fail.
- [x] 3.2 Add `DataSourceDiagnostics` to `lib/ui/evidence_panels.dart` from `SourcePanel`'s Details builder, reading the selection's inspection catalog and quote (design D3). Drop the Details section and its parameters from `SourcePanel`, and `sourceDetailsExpanded` from `lib/ui/shell.dart`. Delete `DetailsSection` from `lib/ui/panels.dart` and `test/ui/details_section_test.dart`. Verify `data_sources_panel_test.dart` passes and flip its rows green.

## 4. Diagnostics in Settings and the correction offer

- [x] 4.1 Create `test/ui/settings_diagnostics_test.dart` over `SettingsDialog`: collapsed Diagnostics builds no scan evidence or crop; expanding shows Map inputs, Scans and Data sources headings in that order, the latest scan and every recent scan; a scan published while it is open is shown at once. In `test/ui/scan_correction_card_test.dart`, change the offer and subtitle expectations to the test map's names: "Last scan not accepted — pick the item", no `#7`, no `1.00`/`0.97` on candidate or same-name rows, the lone same-name row showing its name only, "Corrected from a scan • …", and a search pick labelled the same way. Verify they fail.
- [x] 4.2 In `lib/ui/settings_dialog.dart`, give the Diagnostics panel three titled parts: Map inputs (`MapDiagnostics`), Scans (`ScanDiagnostics`) and Data sources (`DataSourceDiagnostics`) (design D2). In `lib/ui/item_decision_card.dart`, drop the scan number from the offer heading and the corrected subtitle, and drop the score from candidate rows; keep "Read: …" and the pre-filled field. Verify 4.1's tests pass and flip their rows green.
- [x] 4.3 Add the shell guard tests to `test/ui/shell_test.dart`: "main windows show no diagnostic detail for an accepted scan" (Scanner with the inspector open and Inspection details, Requirements and Sources expanded, then Map), "…beside a correction offer" (scan 7 rejected `ambiguous`, on both areas), "catalog error and recording stop note stay on the Scanner" (Sources expanded) and "the Scanner inspector shows no UTC time". Update `test/ui/ember_surfaces_test.dart` "section labels are sentence case" to the new scenario: "Scan evidence" on Scanner, "Live scan" and, after expanding Diagnostics, "Recent scans" in Settings, and no "Recent scans" on the Scanner. Verify they pass and flip their rows green.
- [x] 4.4 Re-run every `green` row of the test map. Fill in the exact names of the "existing … (re-run)" rows in `test/application/scan_correction_test.dart` and `test/application/selection_controller_test.dart`, and remove the test map's note about those rows. Verify `mise run test` passes.

## 5. Specs, docs and checks

- [x] 5.1 Reword the Purpose lines of `openspec/specs/scanner-evidence/spec.md` (the Scanner shows the scan phase and result in plain words; evidence and timings are in Settings under Diagnostics) and `openspec/specs/player-facing-text/spec.md` (developer detail is kept in the Diagnostics section of Settings, not in Details sections). Verify `openspec validate --specs --strict` passes.
- [x] 5.2 Update DESIGN.md X12's Diagnostics row to list the scan evidence, timings and recent scans, and the data source detail, beside the map input lines. Verify by reading the row.
- [x] 5.3 Run `dart format lib test`, `mise run analyze` and `mise run test`, and `mise run release-notes -- --check openspec/changes/move-scanner-diagnostics/proposal.md`. Verify all exit 0.

## Workflow follow-up

- The M8.5 user-verified criterion (verdict and dialogs read right on a second monitor, alt-tabbed) is judged at the milestone close after `restyle-dialogs`, as the proposal says; this change adds no `[user]` task.
- Archive and finish through `specwright-finish` (pr mode) after the pre-ship review.
