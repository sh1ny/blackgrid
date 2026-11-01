# Tasks

## Test map

**How to read the State column.**

- `red` means the test does not exist yet, or it asserts behaviour this change introduces.
- Rows marked *(coverage)* prove behaviour that already works but that no test proves on the boundary the scenario crosses. They start `red` because the test does not exist. Their test is expected to pass on its first run. If one fails, the failure is a real gap: fix it test-first in the same task.
- `green` rows already pass and only need a re-run.

**Where tests run.**

- **Storage scenarios** run on a file-backed database that is closed and reopened (D8, through `test/data/support/reopenable_database.dart`).
- **UI scenarios** are widget tests on the panel or dialog that shows the text.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| local-data-durability → Settings, pins and history survive a restart | Saved records reopen unchanged | test/data/database_test.dart | fresh defaults and restart retain settings pins identity activity and full catalog | green |
| local-data-durability → Settings, pins and history survive a restart | Removed pin stays removed | test/data/durability_restart_test.dart | a removed pin stays removed after reopening | green |
| local-data-durability → Settings, pins and history survive a restart | Failed save is not visible after restart | test/data/durability_restart_test.dart | a settings save aborted by the database reads back the earlier settings after reopening | green |
| local-data-durability → Unreadable settings start the session with defaults | Damaged settings record at startup | test/application/settings_load_test.dart | a settings row that is not JSON loads defaults, sets the notice and keeps the row bytes | green |
| local-data-durability → Unreadable settings start the session with defaults | Settings written by a newer version | test/application/settings_load_test.dart | a settings row naming an unknown mode or map loads defaults and sets the notice | green |
| local-data-durability → Unreadable settings start the session with defaults | Readable settings show no message | test/application/settings_load_test.dart | a readable settings row loads as saved with no notice | green |
| local-data-durability → Unreadable settings start the session with defaults | Next save replaces the unreadable record | test/application/settings_load_test.dart | the first save after a default start clears the notice and reads back after reopening | green |
| local-data-durability → Unreadable settings start the session with defaults | Replace import clears the message | test/application/settings_load_test.dart | a Replace import after a default start clears the settings notice on reload | green |
| local-data-durability → Unreadable pins are skipped, not fatal | One damaged pin among readable ones | test/application/settings_load_test.dart | one unreadable pin row is skipped, counted in the notice and kept on disk | green |
| local-data-durability → Unreadable pins are skipped, not fatal | All pins readable | test/application/settings_load_test.dart | readable pins load with no pin notice | green |
| local-data-durability → Unreadable history entries are skipped, not fatal | One entry with an unknown mode | test/application/history_controller_test.dart | an unreadable history row is skipped and counted in the error | green |
| local-data-durability → Unreadable history entries are skipped, not fatal | All entries readable | test/application/history_controller_test.dart | readable history rows load with no error | green |
| local-data-durability → History errors stay visible while entries are listed | Recording fails while entries are listed | test/ui/history_panel_test.dart | a record failure shows its message above the listed entries | green |
| local-data-durability → History errors stay visible while entries are listed | Empty history with no error | test/ui/history_panel_test.dart | empty history shows No items yet and no error | green |
| local-data-durability → A database from a newer version is refused with its own message | Newer schema version on disk | test/data/migration_test.dart, test/ui/app_test.dart | newer schema reaches the second query as NewerDatabaseException without byte mutation; a newer database shows the newer-version startup message | red |
| local-data-durability → A database from a newer version is refused with its own message | Other open failure | test/ui/app_test.dart | any other open failure shows the generic storage message | red *(coverage)* |
| local-data-durability → A damaged saved token reports the token as unavailable | Corrupt token bytes on disk | test/application/progress_controller_test.dart | corrupt token bytes on disk fail as Tracker token unavailable with no request | green |
| local-data-durability → A damaged saved token reports the token as unavailable | Saving a new token recovers | test/data/credential_store_test.dart | saving over corrupt token bytes reads back the new token after reopening | green |
| legacy-import → An import never changes this computer's own inputs | Replace keeps live scan and hotkey | test/data/legacy_import_test.dart | a Replace import keeps live scan and the scan hotkey and applies imported preferences | red |
| legacy-import → An import never changes this computer's own inputs | Replace keeps input folders | test/data/legacy_import_test.dart | a Replace import keeps both input folders and the follow switch | red *(coverage)* |
| legacy-import → An import never changes this computer's own inputs | Import with no stored settings | test/data/legacy_import_test.dart | an import with no stored settings uses default local inputs | red *(coverage)* |
| legacy-import → A failed import changes nothing, also after a restart | Failure on the last write | test/data/durability_restart_test.dart | an import aborted at its import record leaves every table unchanged after reopening and can run again | red *(coverage)* |
| legacy-import → A failed import changes nothing, also after a restart | Successful import survives a restart | test/data/durability_restart_test.dart | a committed import reads back pins history and its record after reopening | red *(coverage)* |
| legacy-import → The import dialog says why nothing was imported | Files already imported | test/ui/import_dialog_test.dart | a commit refused as already imported says so | red |
| legacy-import → The import dialog says why nothing was imported | Storage failure during commit | test/ui/import_dialog_test.dart | a commit storage failure says the import could not be saved | red |
| catalog-authority → A failed automatic catalog refresh is not retried | Startup fetch fails with a cached snapshot | test/application/app_services_refresh_test.dart | catalog: startup fetch fails with a cached snapshot | red |
| catalog-authority → A failed automatic catalog refresh is not retried | Startup fetch fails with no cache | test/application/app_services_refresh_test.dart | catalog: startup fetch fails with no cache | red |
| catalog-authority → A failed automatic catalog refresh is not retried | Manual refresh after a failure | test/application/app_services_refresh_test.dart | catalog: manual refresh after a failure | green |
| catalog-authority → A catalog failure message names its cause | No connection with a kept snapshot | test/application/catalog_controller_test.dart | transport failure with a kept snapshot names no connection and kept data | red |
| catalog-authority → A catalog failure message names its cause | Server error with a kept snapshot | test/application/catalog_controller_test.dart | HTTP 503 with a kept snapshot names the server error and kept data | red |
| catalog-authority → A catalog failure message names its cause | Invalid data with no snapshot | test/application/catalog_controller_test.dart | invalid data with no snapshot fails naming invalid data and no data | red |
| catalog-authority → A catalog failure message names its cause | Local save failure | test/application/catalog_controller_test.dart | commit failure names the local save and keeps the stored snapshot | red |
| catalog-authority → A catalog failure message names its cause | Timeout | test/data/catalog_client_test.dart | a stalled dataset fails as a transport CatalogException | red |
| catalog-authority → The Data sources panel shows the catalog error | Failure shown in the panel | test/ui/data_sources_panel_test.dart | a catalog error shows beside the out of date item status | red |
| catalog-authority → The Data sources panel shows the catalog error | Error cleared by a successful refresh | test/ui/data_sources_panel_test.dart | a successful refresh clears the catalog error from the panel | red |
| progress-authority → A malformed Tracker response keeps the session's last good progress | Malformed response after a good refresh | test/application/progress_controller_test.dart | malformed response keeps the earlier progress as stale | green |
| progress-authority → A malformed Tracker response keeps the session's last good progress | Malformed response with no progress yet | test/application/progress_controller_test.dart | first malformed response fails with no progress | green |
| progress-authority → A malformed Tracker response keeps the session's last good progress | Rejected token still discards progress | test/application/progress_controller_test.dart | $failure invalidates authority, transport and malformed retain stale | green |
| progress-authority → A malformed Tracker response keeps the session's last good progress | Account mismatch still discards progress | test/application/progress_controller_test.dart | $failure invalidates authority, transport and malformed retain stale | green |

## 1. Restart test support and restart coverage

Load `dart-add-unit-test` first. Every task in this change also follows the "Dart and Flutter code" section of AGENTS.md: no sleeps, hand-written fakes, small fixtures.

- [x] 1.1 Add `test/data/support/reopenable_database.dart` (D8). It opens `BlackgridDatabase(NativeDatabase(file))` on a `Directory.systemTemp.createTemp` file, with `reopen()` (close, then open the same file) and `delete()` for `tearDown`. It also has `abortNextInsert(table)`, which installs a `CREATE TEMP TRIGGER … BEFORE INSERT … RAISE(ABORT, 'test')`, and `writeRawRow(sql, args)` through `customStatement`. Verify with one self-test: a TEMP trigger does not survive `reopen()`.
- [x] 1.2 Write the *(coverage)* tests "a removed pin stays removed after reopening" and "a settings save aborted by the database reads back the earlier settings after reopening" in `test/data/durability_restart_test.dart`. Verify both pass with `mise run test -- test/data/durability_restart_test.dart`; if one fails, fix the gap test-first. Flip both rows green. Re-run "fresh defaults and restart retain settings pins identity activity and full catalog" (green row).

## 2. Unreadable settings, pins and history (D1, D7)

Load `dart-add-unit-test`, `dart-use-pattern-matching`, `dart-write-documentation` and `flutter-add-widget-test` first.

- [x] 2.1 Write the failing tests for the red `local-data-durability` rows on settings, pins and history in `test/application/settings_load_test.dart` and `test/application/history_controller_test.dart`. Use `ReopenableDatabase` with raw rows: a non-JSON payload, a payload with `"mode":"arena"`, a payload with an unknown map, a pin payload that is not JSON, a pin with an unsupported frame, and an activity row with `mode` `arena`. The "Replace import clears the message" test commits a Replace import through `LegacyImport` and then calls `SettingsController.load`, as `reloadAfterImport` does. Verify they fail for the missing behaviour, not for setup errors.
- [x] 2.2 Implement D1 in `lib/data/database.dart`:
  - `readSettings` returns `StoredSettings(settings, unreadable)`. `readPins` returns `(pins, skipped)`. `readActivity` returns `(rows, skipped)`.
  - Only the per-row decode sits inside `try … on Object` (review S1: decoders throw `FormatException`, `StateError`, `TypeError` and `ArgumentError`). The query stays outside it, so open and query errors still throw.
  - `readPins` also runs `CustomPin.validate()` per row and counts a failure as skipped (review S2).
  - Loading writes nothing.
  - Update every caller: `SettingsController`, `HistoryController`, `LegacyImport.previewFiles` (`legacy_import.dart:35-36`) and the tests that call these methods.
  - For the import preview, a skipped destination pin is accepted: the preview may report "add" while a Replace-off commit keeps the unreadable row (review S3). Document that on `previewFiles`.
  - Verify the database tests pass.
- [x] 2.3 Implement D7:
  - `SettingsController.loadNotice` is built from the settings sentence, recomputed by every `load` and cleared by a successful `save`, and the pins sentence, recomputed after every `readPins`. Singular and plural follow the spec texts.
  - `HistoryController.load` sets `error` from `skipped`.
  - Show `loadNotice` after `settings.error` in `lib/ui/manual_controls.dart` and `lib/ui/map_screen.dart`.
  - Show `history.error` above the list in the history panel (`lib/ui/evidence_panels.dart:379`).
  - Add `///` docs on the new public members.
  - Verify the 2.1 tests and the two `history_panel_test.dart` rows pass, and flip their rows green.

## 3. Newer database refusal (D2)

- [ ] 3.1 Write the failing test in `test/data/migration_test.dart`. It opens a `user_version 99` file through `BlackgridDatabase.open(file)` (`createInBackground`), runs a first query and ignores its failure, then asserts the type of the second query's error. Keep the unchanged-bytes and future-table assertions. Write the `test/ui/app_test.dart` tests: the bootstrap's `open` throws what that test proves arrives and shows the newer-version message; any other error shows the generic message; Retry is present in both. Verify they fail.
- [ ] 3.2 Implement D2:
  - Add `NewerDatabaseException` in `lib/data/database.dart` with `///` docs.
  - `onUpgrade` throws it when `from > to`, before any migrator call or transaction. `from < 1` keeps the `StateError`.
  - Remove the unreachable `beforeOpen` version check.
  - `BlackgridBootstrap` (`lib/ui/app.dart:78-87`) maps the error type proven in 3.1, unwrapping exactly as that test shows, to the spec's message.
  - Verify the 3.1 tests pass and flip both rows green.

## 4. Catalog failure causes and the Data sources panel (D3)

- [ ] 4.1 Write the failing tests:
  - the cause rows in `test/application/catalog_controller_test.dart`;
  - the timeout row in `test/data/catalog_client_test.dart`, using `StallingHttpClient`;
  - the panel rows in `test/ui/data_sources_panel_test.dart`.
  - Update the two exact-text tests, `catalog_controller_test.dart:212` and `app_services_refresh_test.dart:482`, to the spec's new texts.
  - Verify they fail.
- [ ] 4.2 Implement D3:
  - `CatalogFailure { transport, http, invalid }` on `CatalogException`, set at each throw site in `lib/data/catalog_client.dart`.
  - In `CatalogController._refresh`, a `commitCatalog` throw becomes `save`, and a non-`CatalogException` fetch throw becomes `invalid`.
  - Add a pure `catalogFailureMessage(kind, kept:)`, using a `switch` expression.
  - The Data sources panel shows `catalog.error` under the item data line in the gold style.
  - Add `///` docs.
  - Verify the 4.1 tests pass, the `plain_language_source_test.dart` banned-term check passes, and "catalog: manual refresh after a failure" still passes. Flip the rows green.

## 5. Tracker malformed responses and damaged tokens (D4)

- [x] 5.1 Write the failing tests "malformed response keeps the earlier progress as stale" and "first malformed response fails with no progress". Move `malformed` out of the invalidating list in the parametrized test, renamed "$failure invalidates authority, transport and malformed retain stale", which keeps `authentication`, `permission`, `mode` and `identity`. Verify the malformed cases fail.
- [x] 5.2 Implement D4: `invalidatesAuthority` is true only for `authentication`, `permission`, `mode` and `identity` (`lib/data/tracker_client.dart:24-26`). Verify the 5.1 tests pass and flip the four progress rows green.
- [x] 5.3 Add a `HeaderProtector` fake next to `SyntheticProtector` (D8). It prefixes a fixed header on protect and rejects bytes without it on unprotect. Write the *(coverage)* tests:
  - "corrupt token bytes on disk fail as Tracker token unavailable with no request": random bytes written into the file of a `DpapiCredentialStore` using `HeaderProtector`, read through `ProgressController` with a request-counting tracker.
  - "saving over corrupt token bytes reads back the new token after reopening".
  - Verify they pass, or fix test-first, and flip both rows green.

## 6. Import keeps local inputs and explains refusals (D5, D6)

- [ ] 6.1 Write the failing tests for the `legacy-import` rows in `test/data/legacy_import_test.dart` and `test/ui/import_dialog_test.dart`. The import-record abort uses `ReopenableDatabase.abortNextInsert('import_records')`. The two durability rows live in `test/data/durability_restart_test.dart`. Verify the red ones fail for the right reason.
- [ ] 6.2 Implement D5:
  - `ImportPreview.settings` becomes `ImportedPreferences`, holding mode, map, save-marker-filters, marker filters and the Tracker switch.
  - The preview stops reading destination settings for local inputs.
  - Inside the `commitImport` transaction, read stored settings through the tolerant `readSettings` and, with Replace on or no row stored, write `stored.copyWith(<preferences>)`.
  - Note review S4 in a code comment on `commitImport`: a settings save that lands between the commit and the reload can still overwrite the imported preferences. That is existing behaviour.
  - Verify the `legacy-import` storage rows pass.
- [ ] 6.3 Implement D6:
  - `ImportAlreadyCommitted` replaces the `StateError` in `commitImport`, with `///` docs.
  - `import_dialog.dart` maps it to "These files were already imported. Nothing was changed." and maps any other error to "The import could not be saved. Nothing was changed."
  - Keep the existing preview-time "These files were already imported." text.
  - Verify the dialog rows pass, and flip every `legacy-import` row green.

## 7. Integration checks

- [ ] 7.1 Run `mise run analyze` and `mise run test`. Both pass, with every Test map row green. Format the changed Dart with `dart format`.
- [ ] 7.2 Run `openspec validate qualify-failure-and-restart --strict`. It passes.
- [ ] 7.3 Record the M6 exit criterion evidence in this change's `evidence.md`. List the tests that prove each part: refresh failures keep last good data and say what failed (groups 4 and 5), auth failures (group 5), and settings, pins and history across restart and interrupted import (groups 1, 2 and 6). Note that killing the process mid-write is not tested (design D8). Verify that the file names an existing test for each part.

## Workflow follow-up

- Pre-ship review, PR (`feat(qualify-failure-and-restart): …`), archive and finish per Specwright.
- After merge, `/specwright-roadmap next` reports the M6 milestone end; `close` walks the exit criteria.
