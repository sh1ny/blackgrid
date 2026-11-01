# Proposal

## Why

This change serves M6 (Windows CI and releases), whose last open agent criterion is: "Offline, refresh and auth failures keep the last good data and say what failed, and settings, pins and history survive restart and interrupted imports, each proved by offline tests." It covers risk 7 in the implementation strategy (§12, "Persistence/import corrupts pins/history"). It also covers the failure half of the refresh risks that M1 left untested.

A survey of `main` at `fb638da` found that most of this already holds and is tested. The catalog cache, transactional writes, schema migrations and the DPAPI store are fine. Five gaps break the criterion:

- **Unreadable data stops startup.** A settings row or one pin row that can't be read stops Blackgrid from starting. A row can be unreadable because it is corrupt or because a newer build wrote it. The app shows the generic "Local storage … could not be opened" screen, and its Retry button fails every time.
- **Catalog errors don't say what failed.** Every catalog failure shows "Catalog refresh failed; last-good data retained", whatever the cause. The message is wrong when there is no last good data, and the Data sources panel doesn't show it.
- **A garbled Tracker response drops progress.** A Tracker response that can't be parsed throws away progress already loaded this session. An unreachable Tracker keeps it as out of date.
- **One bad history row hides all history.** Once rows exist, the panel hides history errors.
- **Import resets local settings.** An import with "Replace" ticked resets the user's live-scan switch and scan hotkey, although the dialog says they are never imported. Nothing tests on a file-backed database that a failed import leaves stored data unchanged after a restart.

## What Changes

- **Unreadable stored records start with safe values.**
  - An unreadable settings row starts the session with default settings.
  - Unreadable pin rows and history rows are skipped.
  - The stored rows are not rewritten by loading. One message says what could not be read.
- **Newer database message.** A database written by a newer Blackgrid version gets its own startup message, which says to install that version. Today it shows the generic storage message. Blackgrid still never downgrades, resets or deletes it.
- **Catalog failure messages name the cause:** no connection, download refused, invalid data or local save failed. They say whether earlier item data is still in use. The Data sources panel shows the message too. **BREAKING** for the exact-text scenario in `catalog-authority`.
- **Malformed Tracker responses keep progress.** A response that can't be parsed now keeps the session's last good progress as out of date, as an unreachable Tracker does. A rejected token, a permission, mode or account mismatch, and a cooldown keep today's behaviour.
- **History errors stay visible** when history rows are shown.
- **Import keeps local settings.** A preference import never changes live scan or the scan hotkey. "Already imported" gets its own message instead of "Nothing was changed".
- **Offline tests on a reopened file database prove that:**
  - settings, pins (added and removed) and history survive restart;
  - a failed import leaves every stored record unchanged after reopening;
  - a cached catalog starts offline;
  - corrupt credential bytes on disk report the token as unavailable, and saving a new token recovers.

Out of scope, by the user's decision (2026-11-01):

- Tracker progress stays session-only. ADR-0003 and the strategy call it "current-session authority", so nothing about it is saved to disk.
- There is no clear-cache feature.
- No test kills the process mid-write. The tests rely on SQLite's own journal for power-loss atomicity.

## Capabilities

### New Capabilities

- `local-data-durability`: how stored settings, pins and history load, survive restart and degrade when a record or the database can't be read.
- `legacy-import`: what an explicit legacy import may change, and that a failed import changes nothing.

### Modified Capabilities

- `catalog-authority`: the failed-refresh requirement's error text names the cause and whether earlier data is kept.
- `progress-authority`: a malformed Tracker response keeps the session's last good progress as out of date.

## Impact

- **Code:**
  - `lib/application/settings_controller.dart`
  - `lib/data/database.dart` (`readSettings`, `readPins`, `readActivity`, `commitImport`, the newer-version error type)
  - `lib/application/catalog_controller.dart` and `lib/data/catalog_client.dart` (typed failure kinds)
  - `lib/data/tracker_client.dart` (`invalidatesAuthority`)
  - `lib/application/history_controller.dart`
  - `lib/data/legacy_import.dart`
  - `lib/ui/app.dart` (the startup message)
  - `lib/ui/evidence_panels.dart` (the Data sources panel and the history error)
  - `lib/ui/import_dialog.dart`
- **Tests:** new and changed offline tests under `test/data/`, `test/application/` and `test/ui/`. No qualification-tier test is needed.
- **No schema change:** no Drift migration, no new dependency, no network or game interaction.
- **No ADR is superseded.** The fixes follow ADR-0003 (one SQLite store, transactional writes, newer versions refused).
