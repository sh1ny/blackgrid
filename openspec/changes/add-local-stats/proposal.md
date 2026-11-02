# Proposal

## Why

This change serves M7 (raid lifecycle, timers and local stats) and is its third and last change. It delivers the milestone's third exit criterion: "Total flea sales and raids per map are stored only in the local database, survive restart and are emptied by the clear button, proved by offline tests." It also gives the user-verified criterion ("during real raids, the raid state, timers and stats follow the game") its stats part.

`add-raid-lifecycle` (archived 2026-11-01) already reads flea sales from the push-notifications log and publishes each raid start once, with a stable record identity. Nothing keeps them yet: when Blackgrid closes, the player's count of raids and sales is gone. TarkovMonitor keeps such stats; Blackgrid rebuilds them independently, without copying its code and without its bug:

- **The log reader replays the newest session folder at every start** (ADR-0030). A naive counter would add the same raids and sales again on each restart of Blackgrid or each rewritten log. Blackgrid stores each raid and sale under its log record identity (folder, file and byte offset), so a replay adds nothing.
- **A clear must stay cleared.** Clearing and then restarting Blackgrid replays the same folder; the replayed records must not come back. The clear records its time, and records logged at or before it are never counted again.

## What Changes

- **Flea sales reach consumers through the lifecycle.** The raid reducer publishes a flea-sale transition once per sale, with the sale's record identity, time, item, count, rouble payout and the session mode logged before it. Today the reducer drops sales.
- **Raids and sales are stored in the local database.** A new Drift schema version (4) adds a raid stats table, a flea sale table and a one-row stats record holding the time of the last clear. Each row is keyed by its log record identity; inserting a known record changes nothing.
- **What counts as a raid.** Every raid-started transition counts once for its map and mode, including transits and raids entered without a queue. A reconnect counts unless the newest stored raid of the same mode is on the same map and started at most 2 hours earlier, so a raid continued after the game and Blackgrid both restarted is not counted twice.
- **A Stats dialog.** A "Stats" button in the header opens a dialog for the app's current mode: number of flea sales, items sold, roubles earned (with a note for sales not paid in roubles), and raids per map with a total. It says since when stats are counted.
- **A clear button.** "Clear stats" in the dialog, after a confirmation, deletes every stored raid and sale of every mode in one transaction and records the clear time. Records logged at or before that time are never stored again, so a replay after the clear does not restore them.
- **Failures are visible.** A stats read or write that fails shows a message in the dialog; the rest of the app keeps working.
- **Offline tests.** The ledger's idempotence under replay, the clear watermark, the reconnect rule, the 3→4 migration and restart survival are proved with an in-memory or temporary database and small synthetic events.

Out of scope:

- No upload, sync, export or account. Nothing leaves the machine (STRATEGY.md).
- No reading of older session folders: stats start from what Blackgrid reads, the newest folder at each start and everything after. A raid history from old log folders is M15.
- No raid history list, per-week charts, kill or survival stats; M15 extends these totals.
- No task progress from the task notifications; that is M9's `add-task-log-progress`.

## Capabilities

### New Capabilities

- `local-stats`: which raids and flea sales count, how they are stored once each under their log record identity, the clear and its watermark, the Stats dialog and its failure messages.

### Modified Capabilities

- `raid-lifecycle`: the reducer also publishes each flea sale once as a transition carrying the session mode, so stats can store it under its record identity.

## Impact

- **Code:**
  - `lib/domain/raid_lifecycle.dart`: a `FleaSoldTransition`; `reduce` publishes it for `FleaSale`.
  - `lib/application/raid_timers_controller.dart`: its exhaustive transition switch ignores the new case.
  - New: `lib/domain/local_stats.dart` (stat rows, totals and the reconnect rule) and `lib/application/local_stats_controller.dart` (stores transitions in order, loads totals, clears).
  - `lib/data/database.dart`: schema version 4 with the three tables, the 3→4 step, and the ledger, totals and clear queries; a new `drift_schemas/drift_schema_v4.json`.
  - `lib/ui/shell.dart` (the Stats button) and a new `lib/ui/stats_dialog.dart`.
  - `lib/application/app_services.dart`: builds and disposes the controller.
- **Tests:** domain tests for the reconnect rule and totals; database tests for idempotent inserts, the watermark, clear and restart survival; a migration test from 3 (and 1) to 4; controller tests with fake sources; a reducer test for the flea-sale transition; widget tests for the dialog and the clear confirmation.
- **Architecture:** the SQLite schema contract moves to version 4; a component row for `LocalStatsController` and state-ownership rows for the stats tables and the clear time.
- **Dependencies:** none new.

## Release Notes

Blackgrid now keeps local stats: your flea market sales and how many raids you ran on each map, read from the game's logs and stored only on your PC. A Stats button shows them for the current mode, and Clear stats empties them.

### Added
- A Stats dialog, opened from the header, shows the current mode's flea sales (sales, items sold, roubles earned) and raids per map, counted from the game's logs and kept across restarts. Nothing leaves your PC.
- Clear stats empties every mode's stats after a confirmation; a restart of Blackgrid does not bring the cleared raids and sales back.
