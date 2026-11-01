# Evidence: M6 failure and restart criterion

M6 exit criterion (agent part): "Offline, refresh and auth failures keep the last good data and say what failed, and settings, pins and history survive restart and interrupted imports, each proved by offline tests."

Every test below is offline. None launches the app, touches the network or needs the game. All of them run in `mise run test`.

## Refresh failures keep the last good data and say what failed

Catalog (group 4):

- `test/application/app_services_refresh_test.dart`
  - "catalog: startup fetch fails with a cached snapshot": the cached snapshot is kept as `stale` and the error names no connection and kept data.
  - "catalog: startup fetch fails with no cache": `failed`, no snapshot, and the error says no item data is available yet.
  - "catalog: manual refresh after a failure": exactly one more fetch.
- `test/application/catalog_controller_test.dart`
  - "transport failure with a kept snapshot names no connection and kept data"
  - "HTTP 503 with a kept snapshot names the server error and kept data"
  - "invalid data with no snapshot fails naming invalid data and no data"
  - "commit failure names the local save and keeps the stored snapshot"
- `test/data/catalog_client_test.dart`
  - "a stalled dataset fails as a transport CatalogException"
- `test/ui/data_sources_panel_test.dart`
  - "a catalog error shows beside the out of date item status"
  - "a successful refresh clears the catalog error from the panel"

Tracker progress (group 5):

- `test/application/progress_controller_test.dart`
  - "malformed response keeps the earlier progress as stale"
  - "first malformed response fails with no progress"
  - "$failure invalidates authority, transport and malformed retain stale": transport and malformed failures keep the last good progress as stale.

## Auth failures

Group 5:

- `test/application/progress_controller_test.dart`
  - "$failure invalidates authority, transport and malformed retain stale": a rejected token (`authentication`), a missing permission, a mode mismatch and an account mismatch (`identity`) discard progress and say what failed.
  - "corrupt token bytes on disk fail as Tracker token unavailable with no request"
- `test/data/credential_store_test.dart`
  - "saving over corrupt token bytes reads back the new token after reopening"

## Settings, pins and history across restart

Groups 1 and 2, on a file-backed database that is closed and reopened (`test/data/support/reopenable_database.dart`):

- `test/data/database_test.dart`
  - "fresh defaults and restart retain settings pins identity activity and full catalog"
- `test/data/durability_restart_test.dart`
  - "a removed pin stays removed after reopening"
  - "a settings save aborted by the database reads back the earlier settings after reopening"
- `test/application/settings_load_test.dart`
  - "a settings row that is not JSON loads defaults, sets the notice and keeps the row bytes"
  - "a settings row naming an unknown mode or map loads defaults and sets the notice"
  - "a readable settings row loads as saved with no notice"
  - "the first save after a default start clears the notice and reads back after reopening"
  - "a Replace import after a default start clears the settings notice on reload"
  - "one unreadable pin row is skipped, counted in the notice and kept on disk"
  - "readable pins load with no pin notice"
- `test/application/history_controller_test.dart`
  - "an unreadable history row is skipped and counted in the error"
  - "readable history rows load with no error"
- `test/ui/history_panel_test.dart`
  - "a record failure shows its message above the listed entries"
  - "empty history shows No items yet and no error"
- `test/data/migration_test.dart` and `test/ui/app_test.dart` (group 3)
  - "newer schema reaches the second query as NewerDatabaseException without byte mutation"
  - "a newer database shows the newer-version startup message"
  - "any other open failure shows the generic storage message"

## Interrupted imports

Group 6:

- `test/data/durability_restart_test.dart`
  - "an import aborted at its import record leaves every table unchanged after reopening and can run again"
  - "a committed import reads back pins history and its record after reopening"
- `test/data/legacy_import_test.dart`
  - "a Replace import keeps live scan and the scan hotkey and applies imported preferences"
  - "a Replace import keeps both input folders and the follow switch"
  - "an import with no stored settings uses default local inputs"
- `test/ui/import_dialog_test.dart`
  - "a commit refused as already imported says so"
  - "a commit storage failure says the import could not be saved"

## Not tested

- **Killing the process mid-write is not tested** (design D8). Interrupted writes are simulated with connection-scoped `TEMP` triggers that raise `ABORT`, and each test reopens the file so that the rollback, not the trigger, is what kept the data. Power-loss atomicity relies on SQLite's own journal (ADR-0003), which is not re-tested.
- No live-game or reference-companion check is part of this criterion.
