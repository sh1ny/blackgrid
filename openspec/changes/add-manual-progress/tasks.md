# Tasks

Every task group follows the "Dart and Flutter code" section of AGENTS.md. Before writing Dart, load `dart-use-pattern-matching`, `dart-write-documentation`, `dart-add-unit-test` and `dart-run-static-analysis`; also load `flutter-add-widget-test` for group 5. Fakes are hand-written and injected through constructors; no arbitrary sleeps (use completers, fake clocks and injected ID generators).

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| task-catalog → Traders and their loyalty levels are retained | Traders with levels | packages/blackgrid_progress/test/parse_traders_test.dart | keeps trader levels in ascending order | green |
| task-catalog → Traders and their loyalty levels are retained | Traders with levels (no extra request) | test/data/catalog_normalizer_progress_test.dart | passes raw traders to the progress catalog without another request | green |
| task-catalog → Traders and their loyalty levels are retained | Malformed levels | packages/blackgrid_progress/test/parse_traders_test.dart | missing or non-positive levels become unknown | green |
| task-catalog → Traders and their loyalty levels are retained | Duplicate level numbers | packages/blackgrid_progress/test/parse_traders_test.dart | duplicate level numbers become unknown | green |
| task-catalog → Stored catalogs without traders still load | Older stored catalog | packages/blackgrid_progress/test/progress_catalog_json_test.dart | catalog stored without traders loads with traders unknown | green |
| task-catalog → Stored catalogs without traders still load | Round trip | packages/blackgrid_progress/test/progress_catalog_json_test.dart | traders round trip at format version 1 | green |
| local-progress → One event can be read by its ID | Read an undo's target | test/data/local_progress_store_test.dart | readProgressEvent returns the event and keeps the revision | green |
| local-progress → One event can be read by its ID | ID from another cycle | test/data/local_progress_store_test.dart | readProgressEvent does not find another cycle's event | green |
| local-progress → One event can be read by its ID | Damaged event | test/data/local_progress_store_test.dart | readProgressEvent reports a damaged event as unavailable | green |
| manual-progress → Manual entries are manual events in the mode's active wipe | Set level | test/application/local_progress_access_test.dart | appendManual records one manual level event | green |
| manual-progress → Manual entries are manual events in the mode's active wipe | Newer log event beats the edit | test/application/local_progress_access_test.dart | a newer log event beats an older manual edit | green |
| manual-progress → Manual entries are manual events in the mode's active wipe | Edit beats older log evidence | test/application/local_progress_access_test.dart | a newer manual edit beats older log evidence | green |
| manual-progress → Manual entries are manual events in the mode's active wipe | Other mode unchanged | test/application/local_progress_access_test.dart | appendManual writes only the submitting mode | green |
| manual-progress → The first entry creates a wipe when none is active | No wipe yet | test/application/local_progress_access_test.dart | first entry creates a wipe starting today without a folder | green |
| manual-progress → The first entry creates a wipe when none is active | Session began before midnight | test/application/local_progress_access_test.dart | wipe starts on the earlier live folder date and keeps later live events | green |
| manual-progress → The first entry creates a wipe when none is active | Creation fails | test/application/local_progress_access_test.dart | failed cycle creation records nothing and reports | green |
| manual-progress → Player values are bounded | Edition chosen | test/application/manual_progress_controller_test.dart | edition choices come from the edition table | green |
| manual-progress → Player values are bounded | Level out of range | test/application/manual_progress_controller_test.dart | level outside 1-79 is rejected before the queue | green |
| manual-progress → Trader loyalty uses the trader's real levels | Fence bounded | test/application/manual_progress_controller_test.dart | loyalty choices follow the trader's catalog levels | green |
| manual-progress → Trader loyalty uses the trader's real levels | Single-level trader | test/application/manual_progress_controller_test.dart | single-level traders are not listed | green |
| manual-progress → Trader loyalty uses the trader's real levels | No task catalog | test/application/manual_progress_controller_test.dart | without a task catalog only player values are editable | green |
| manual-progress → Hideout station levels run from not built to the highest level | Station built | test/application/manual_progress_controller_test.dart | station level is bounded by catalog levels | green |
| manual-progress → Hideout station levels run from not built to the highest level | Not built versus unknown | test/application/manual_progress_controller_test.dart | not built records 0, distinct from unknown | green |
| manual-progress → Task states can be overridden by search | Override a missed task | test/application/manual_progress_controller_test.dart | search finds a task and sets it finished by hand | green |
| manual-progress → Task states can be overridden by search | No match | test/application/manual_progress_controller_test.dart | search with no match lists nothing | green |
| manual-progress → Any value can be cleared to unknown | Clear level | test/application/manual_progress_controller_test.dart | clear records unset and reads unknown | green |
| manual-progress → Any value can be cleared to unknown | Clear unknown value | test/application/manual_progress_controller_test.dart | clear is disabled for an unknown value | green |
| manual-progress → The last manual change of a value can be undone and redone | Undo a level change | test/application/local_progress_access_test.dart | undo restores the previous value and keeps history | green |
| manual-progress → The last manual change of a value can be undone and redone | Redo after undo | test/application/local_progress_access_test.dart | redo appends a new manual edit with the undone value | green |
| manual-progress → The last manual change of a value can be undone and redone | Undo after redo | test/application/manual_progress_controller_test.dart | undo after redo restores the earlier value and offers redo | green |
| manual-progress → The last manual change of a value can be undone and redone | Winner came from the logs | test/application/manual_progress_controller_test.dart | no undo or redo for a log winner | green |
| manual-progress → The last manual change of a value can be undone and redone | Stale undo | test/application/local_progress_access_test.dart | stale undo or redo reports a conflict and records nothing | green |
| manual-progress → Entry failures are visible and change nothing | Entry during replay | test/application/local_progress_access_test.dart | manual entry queued during replay is recorded between chunks | green |
| manual-progress → Entry failures are visible and change nothing | Storage failure | test/application/manual_progress_controller_test.dart | storage failure is shown beside the value and nothing changes | green |
| manual-progress → Entry failures are visible and change nothing | Damaged wipe | test/application/manual_progress_controller_test.dart | unavailable wipe disables entry with its reason | green |
| manual-progress → Entry failures are visible and change nothing | Local progress not loaded | test/application/manual_progress_controller_test.dart | failed initial load disables entry for every mode | green |
| manual-progress → Entry failures are visible and change nothing | During a raid | test/application/local_progress_access_test.dart | manual entry is recorded during a raid | green |
| manual-progress → Shown values follow the store | Log event arrives | test/application/manual_progress_controller_test.dart | a progress revision change re-reads while shown | green |
| manual-progress → Shown values follow the store | New wipe | test/application/manual_progress_controller_test.dart | a new wipe shows every value unknown | green |
| manual-progress → Consumers keep their current progress source | Advice unchanged | test/application/app_services_test.dart | manual level does not change advice progress | red |
| manual-progress → Consumers keep their current progress source | No token | test/application/app_services_test.dart | manual values without a token leave advice without progress | red |
| settings-page → Local progress holds a Your progress part | Shows the effective mode | test/ui/settings/settings_your_progress_test.dart | titled for the effective mode | red |
| settings-page → Local progress holds a Your progress part | Effective mode changes while open | test/application/manual_progress_controller_test.dart | write submitted for PvE lands in PvE after a mode switch | green |
| settings-page → Local progress holds a Your progress part | Unknown mode | test/ui/settings/settings_your_progress_test.dart | unknown mode asks to choose a game mode | red |
| settings-page → Local progress holds a Your progress part | Mode without a wipe | test/ui/settings/settings_your_progress_test.dart | mode without a wipe explains the first entry | red |
| settings-page → Your progress values show their source | Source shown | test/ui/settings/settings_your_progress_test.dart | values show From game logs or Set by hand | red |
| settings-page → Your progress values show their source | Failure shown | test/ui/settings/settings_your_progress_test.dart | a failure shows beside its row with the previous value | red |
| settings-page → (existing) Settings sections and their order | Sidebar order | test/ui/settings/settings_page_test.dart | existing sidebar order test | green |

## 1. Traders in the progress catalog

- [x] 1.1 Write failing package tests for trader levels (`parse_traders_test.dart`: levels kept ascending, malformed or missing levels unknown, duplicates unknown) and for the stored form (`progress_catalog_json_test.dart`: older catalog without `traders` loads with traders unknown; round trip at `formatVersion: 1`). Verify with `mise run test` that they fail for the missing API.
- [x] 1.2 Add `CatalogTraderLevels` and the optional `traders` list to `ProgressCatalog` (JSON at format version 1, absent = null) and parse traders in `parseProgressCatalog` from the raw `traders` data and its dictionary (D2). Document the public API. Verify the 1.1 tests pass and flip their rows green.
- [x] 1.3 Write a failing test in `test/data/catalog_normalizer_progress_test.dart` that the normalizer passes raw traders through and makes the same requests as before; then pass `rawTraders` and the `traders` dictionary to `parseProgressCatalog` in `lib/data/catalog_normalizer.dart`. Verify it passes, the package audit test still passes, and flip the row green.
- [x] 1.4 Update the `blackgrid_progress` row of `openspec/architecture.md` to name trader loyalty levels. Verify `mise run analyze` is clean.

## 2. Single-event read in the progress store

- [x] 2.1 Write failing tests in `test/data/local_progress_store_test.dart` for `readProgressEvent(scope, eventId)`: returns the event with unchanged revision, not found for another cycle's ID, unavailable for a damaged event with bytes kept. Verify they fail.
- [x] 2.2 Add `readProgressEvent` to `LocalProgressStore` (with a not-found result) and implement it in the Drift adapter on the existing by-ID lookup, admitted like other operations. Update fakes implementing the interface. Verify the 2.1 tests pass and flip their rows green.
- [x] 2.3 Update the `LocalProgressStore` row of `openspec/architecture.md` to list the single-event read. Verify `mise run analyze` is clean.

## 3. LocalProgressAccess on the shared queue

- [x] 3.1 Move `_randomProgressId` into a public domain-level UUID v4 helper used by the data layer, and add an injectable ID generator to `TaskLogProgressController`. Verify existing `local_progress_store_test.dart` and `task_log_progress_controller_test.dart` still pass.
- [x] 3.2 Write failing tests in `test/application/local_progress_access_test.dart` (fake store, fake lifecycle, fake clock, fixed IDs) for every row mapped to that file: manual append, log/manual ordering both ways, mode isolation, wipe start on today or the earlier live folder date with later live events kept, failed creation, undo, redo as a new edit, stale undo and stale redo conflicts, entry queued during replay, entry during a raid, and `progressRevision` moving only on inserted events, undo, wipe creation/replacement and availability change. Verify they fail.
- [x] 3.3 Define `LocalProgressAccess` (`appendManual`, `undo`, `redo`, `readCurrent`, `progressRevision`, load state) with sealed results and implement it on `TaskLogProgressController`, each call one `enqueueProgress` operation (D1, D4, D7); raise `progressRevision` only on data changes (D3). Verify the 3.2 tests pass, all existing `task_log_progress_controller_test.dart` tests pass, and flip the rows green.
- [x] 3.4 Update the `TaskLogProgressController` row of `openspec/architecture.md` to name manual writes through `LocalProgressAccess`. Verify `mise run analyze` is clean.

## 4. ManualProgressController

- [x] 4.1 Write failing tests in `test/application/manual_progress_controller_test.dart` (fake `LocalProgressAccess`, fake catalog and effective-mode sources) for every row mapped to that file: bounds and choices for level, edition, loyalty and stations; single-level traders hidden; missing task catalog or catalog of another mode; task search with the 50-row cap; clear; Undo/Redo labels from the winner; per-value pending and failure state; unavailable wipe and failed load disabling entry; reads only while attached and on revision changes, coalesced to one in flight plus one dirty re-read; a new wipe showing unknowns; a write submitted for PvE landing in PvE after a mode switch. Verify they fail.
- [x] 4.2 Implement `ManualProgressController` (D3, D5, D6) with documented public API. Verify the 4.1 tests pass and flip their rows green.

## 5. Your progress in Settings

- [ ] 5.1 Write failing widget tests in `test/ui/settings/settings_your_progress_test.dart` for the rows mapped to that file (title for the effective mode, unknown mode, mode without a wipe, source labels, failure beside its row), using small synthetic catalogs. Verify they fail.
- [ ] 5.2 Build the Your progress part (player values, trader loyalty, stations, task search, set/clear/Undo-or-Redo controls, edition display names for the five `editionTable` IDs with a test that every table edition has a name) after the wipe rows in `LocalProgressSettings`, attaching the controller while mounted. Verify the 5.1 tests pass, `settings_local_progress_test.dart` and `settings_page_test.dart` (sidebar order row) still pass, and flip the rows green.
- [ ] 5.3 Build `ManualProgressController` in `AppServices` over `localProgress`, `catalog` and `mapSession.effectiveMode`, dispose it before the database closes, and pass it to Settings. Write the `app_services_test.dart` tests that a manual level leaves advice's progress unchanged with and without a Tracker token; verify they pass and flip their rows green.
- [ ] 5.4 Update `openspec/architecture.md` with a `ManualProgressController` row. Verify `mise run analyze` and `mise run test` pass, and format with `dart format`.

## 6. Integration and user check

- [ ] 6.1 Run `mise run analyze`, `mise run test` and `openspec validate add-manual-progress --strict`; all pass and every test-map row is green except the user row.
- [ ] 6.2 Run `mise run release-notes -- --check openspec/changes/add-manual-progress/proposal.md`; it exits 0 and the section still describes what shipped.
- [ ] 6.3 [user] With a built app (Escape from Tarkov not driven by any agent), the owner opens Settings → Local progress → Your progress, sets level, faction, edition, a trader's loyalty, a station level and a missed quest's state, undoes and redoes one, and confirms the values and their sources look right in play (M9 exit criterion "manual progress entry works in play"; the checklist half is judged at the M9 close after `add-quest-checklist`).
