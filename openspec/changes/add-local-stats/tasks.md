# Tasks

Skills for every Dart group (AGENTS.md "Dart and Flutter code"): `dart-use-pattern-matching`, `dart-add-unit-test`, `dart-write-documentation` and `dart-run-static-analysis`. Group 6 also uses `flutter-add-widget-test`.

Rules for every group:
- Clocks are injected (`DateTime Function()`); no arbitrary sleeps. Async ordering is driven with completers or fake stores that hold a write until released.
- Databases in tests are in-memory (`NativeDatabase.memory()`) or a temporary file when a test closes and reopens it (restart). Events are small synthetic `LogRecordId`s and made-up item IDs.
- Fakes are hand-written and injected through constructors; the repo has no mocking package.
- The game is never launched or touched.
- Read failures, write failures and clear failures are three separate states (design State & Ownership: `readError`, `writeError`, `clearError`). Design D6 still says `error`; implement the three fields (review S3).

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| raid-lifecycle → Each flea sale is published once with its mode | Sale during a session | test/domain/raid_lifecycle_flea_test.dart | sale publishes one flea-sale transition with the session mode | green |
| raid-lifecycle → Each flea sale is published once with its mode | Sale before any mode is logged | test/domain/raid_lifecycle_flea_test.dart | sale before any mode has no mode | green |
| raid-lifecycle → Each flea sale is published once with its mode | Sale paid in another currency | test/domain/raid_lifecycle_flea_test.dart | sale without roubles publishes no payout | green |
| raid-lifecycle → Each flea sale is published once with its mode | Replay after an app restart | test/application/raid_lifecycle_controller_test.dart | replayed folder republishes the sale with the same identity | green |
| raid-lifecycle → Each flea sale is published once with its mode | Sale during a raid | test/domain/raid_lifecycle_flea_test.dart | sale in raid leaves phase and raid unchanged | green |
| local-stats → Each raid start counts once for its map and mode | Two raids on one map | test/data/local_stats_store_test.dart | two raid starts on one map count 2 | green |
| local-stats → Each raid start counts once for its map and mode | Transit counts as a new raid | test/data/local_stats_store_test.dart | transit raid counts on its own map | green |
| local-stats → Each raid start counts once for its map and mode | Replay after a restart | test/data/local_stats_store_test.dart | same raid identity stored twice counts once | green |
| local-stats → Each raid start counts once for its map and mode | Unknown map | test/data/local_stats_store_test.dart | raid with no map counts under unknown map | green |
| local-stats → A reconnect continuing a counted raid does not count again | Both apps restarted mid-raid | test/domain/local_stats_test.dart | reconnect on same map within 2 h is not counted | green |
| local-stats → A reconnect continuing a counted raid does not count again | Reconnect on another map | test/domain/local_stats_test.dart | reconnect on another map counts | green |
| local-stats → A reconnect continuing a counted raid does not count again | Reconnect long after the last raid | test/domain/local_stats_test.dart | reconnect 2 h 1 min after counts | green |
| local-stats → A reconnect continuing a counted raid does not count again | Reconnect with nothing stored | test/domain/local_stats_test.dart | reconnect with no earlier raid counts | green |
| local-stats → A reconnect continuing a counted raid does not count again | Replay of a skipped reconnect after a later raid | test/data/local_stats_store_test.dart | replayed skipped reconnect stays skipped after a later raid | green |
| local-stats → Each flea sale counts once | Two sales | test/data/local_stats_store_test.dart | two sales total sales items and roubles | green |
| local-stats → Each flea sale counts once | Replayed sale | test/data/local_stats_store_test.dart | same sale identity stored twice counts once | green |
| local-stats → Each flea sale counts once | Sale not paid in roubles | test/data/local_stats_store_test.dart | sale without roubles counts items but no roubles | green |
| local-stats → Raids and sales with no mode are kept apart | Sale before the mode is logged | test/data/local_stats_store_test.dart | sale with no mode is in no known mode's totals | green |
| local-stats → Raids and sales with no mode are kept apart | Known mode | test/data/local_stats_store_test.dart | PvE sale changes only PvE totals | green |
| local-stats → Stats stay on this PC and survive a restart | Restart | test/data/local_stats_store_test.dart | stats read back after close and reopen | green |
| local-stats → Stats stay on this PC and survive a restart | Upgrade from an older database | test/data/migration_test.dart | 3 to 4 and 1 to 4 keep data and start with empty stats | green |
| local-stats → Clear empties stats and keeps them empty | Clear | test/data/local_stats_store_test.dart | clear empties every mode | green |
| local-stats → Clear empties stats and keeps them empty | Replay after a clear and a restart | test/data/local_stats_store_test.dart | records at or before the clear time are not stored after reopen | green |
| local-stats → Clear empties stats and keeps them empty | New activity after a clear | test/data/local_stats_store_test.dart | raid after the clear time is stored | green |
| local-stats → Clear empties stats and keeps them empty | Clear fails | test/application/local_stats_controller_test.dart | failed clear keeps totals and shows the clear message | green |
| local-stats → The Stats dialog shows the current mode's stats | Stats for the current mode | test/ui/stats_dialog_test.dart | shows the current mode's maps by count, total and sales | green |
| local-stats → The Stats dialog shows the current mode's stats | Empty stats | test/ui/stats_dialog_test.dart | empty mode shows no raids or flea sales message | green |
| local-stats → The Stats dialog shows the current mode's stats | Mode not known yet | test/application/local_stats_controller_test.dart | unknown app mode loads no totals | green |
| local-stats → The Stats dialog shows the current mode's stats | Mode changes while open | test/application/local_stats_controller_test.dart | mode change reloads the new mode's totals | green |
| local-stats → The Stats dialog shows the current mode's stats | New sale while open | test/application/local_stats_controller_test.dart | stored sale reloads totals and notifies | green |
| local-stats → Clearing asks for confirmation | Confirmed | test/ui/stats_dialog_test.dart | confirming clear empties the stats | green |
| local-stats → Clearing asks for confirmation | Cancelled | test/ui/stats_dialog_test.dart | cancelling clear deletes nothing | green |
| local-stats → Stats failures are visible and contained | Read fails | test/application/local_stats_controller_test.dart | failed read sets the read message | green |
| local-stats → Stats failures are visible and contained | Write fails | test/application/local_stats_controller_test.dart | failed insert sets the write message and the next insert still runs | green |
| local-stats → Stats failures are visible and contained | Write message survives a reload | test/application/local_stats_controller_test.dart | successful reload keeps the write message | green |
| local-stats → Stats failures are visible and contained | Write message clears on the next write | test/application/local_stats_controller_test.dart | next successful insert clears the write message | green |
| local-stats → Stats failures are visible and contained | Clear message survives a reload | test/application/local_stats_controller_test.dart | successful reload keeps the clear message | green |

## 1. ADR and architecture

- [x] 1.1 Write `docs/adr/0032-local-stats-identity-keyed-ledger.md` (MADR-short, `Status: accepted`, today's date): design D2 and D3 (ledger keyed by `LogRecordId`, millisecond times, insert-or-ignore, durable clear watermark written with the delete), the rejected counters and tombstones, reversal cost high for the stored format. Verify: the file exists with Status, Date, Context, Decision, Consequences.
- [x] 1.2 Update `openspec/architecture.md`: ADR-0032 row in the in-force index; the SQLite schema contract to `schemaVersion` 4 with the 3→4 step; a component row for `LocalStatsController` (`lib/application/local_stats_controller.dart`, `lib/domain/local_stats.dart`, `lib/ui/stats_dialog.dart`); state-ownership rows for the ledgers and the clear watermark (design State & Ownership). Verify: `grep -n "0032\|schemaVersion\` 4\|LocalStatsController" openspec/architecture.md` shows each.

## 2. Flea sales as lifecycle transitions

- [x] 2.1 Write failing tests in `test/domain/raid_lifecycle_flea_test.dart` for the four reducer rows, and the replay row in `test/application/raid_lifecycle_controller_test.dart` (a reader fake replaying the same batch twice). Verify they fail because `FleaSoldTransition` does not exist.
- [x] 2.2 Add `FleaSoldTransition(id, time, itemId, count, roubles, mode)` to the sealed `RaidTransition` in `lib/domain/raid_lifecycle.dart` and publish it from `reduce` for `FleaSale` with `state.sessionMode`, state unchanged (design D1). Add the case to `RaidTimersController._onTransition` as a no-op. Verify: group 2 rows green, `test/domain/raid_lifecycle_test.dart` and `test/application/raid_timers_controller_test.dart` still pass.

## 3. Reconnect rule and totals (domain)

- [x] 3.1 Write failing tests in `test/domain/local_stats_test.dart` for the four `countsReconnect` rows, plus edges: exactly 2 h is the same raid (not counted), a non-reconnect entry always counts, and a previous raid of another mode never suppresses a count. Verify they fail because `lib/domain/local_stats.dart` does not exist.
- [x] 3.2 Create `lib/domain/local_stats.dart`: stored-row value types (`RaidStatRow`, `FleaSaleRow`), `LocalStatsTotals` (maps with counts ordered by count then label key, raid total, sales, items, roubles, sales not in roubles), `countsReconnect(previous, candidate)` with the 2 h window as one named constant (design D5). Verify: group 3 rows green.

## 4. Database schema 4 and the ledger

- [x] 4.1 Write failing migration tests in `test/data/migration_test.dart`: 3→4 and 1→4, each keeping preferences, pins, activity and the active catalog and creating the three stats tables empty. Keep the existing tests passing. Verify they fail because schema 4 is missing.
- [x] 4.2 Add `RaidStatRecords`, `FleaSaleRecords` and `StatsMeta` (design data model: integer-millisecond times, key `(folder, file, offset)`, indexes on mode) to `lib/data/database.dart`, set `schemaVersion` to 4 and chain `onUpgrade` 1→2→3→4, any other range still throwing. Regenerate with `dart run build_runner build`, dump `drift_schemas/drift_schema_v4.json` and generate `test/data/generated/schema_v4.dart` with `drift_dev`. Verify: the group 4.1 tests pass and `mise run analyze` is clean.
- [x] 4.3 Write failing tests in `test/data/local_stats_store_test.dart` for the store rows of the test map (raid and sale insert-or-ignore, unknown map and mode, totals per mode, restart via a temporary file closed and reopened, clear, the watermark across reopen, a raid after the clear, and the replay of a skipped reconnect after a later raid). Verify they fail because the store methods do not exist.
- [x] 4.4 Add a `LocalStatsStore` interface (in `lib/domain/local_stats.dart` or beside it) implemented by `BlackgridDatabase`: `recordRaid`, `recordSale` (each one transaction: read the watermark, skip at or before it; for a reconnect read the newest same-mode raid starting strictly before it and apply `countsReconnect`; insert-or-ignore), `readTotals(mode)`, `readSince()`, `clear(now)` (delete both ledgers and upsert the watermark in one transaction). Verify: group 4.3 rows green.

## 5. LocalStatsController

- [x] 5.1 Write failing tests in `test/application/local_stats_controller_test.dart` with a fake lifecycle source (a sync broadcast stream), a fake mode source and a fake `LocalStatsStore` whose calls can fail or be held by completers. Cover the controller rows of the test map, plus: writes run in publication order and a clear queued after a write runs after it; a read failure's message stays after a successful write; `dismissClearError()` clears the clear message (review S4); disposal stops notifications and drops queued work. Verify they fail because the controller does not exist.
- [x] 5.2 Implement `lib/application/local_stats_controller.dart` (design D4): subscribes to `transitions` in its constructor, one serial write queue for inserts and clear, one coalesced pending reload, `totals`/`since`/`modeKnown`, and `readError`, `writeError`, `clearError` with the spec's clearing rules. Verify: group 5 rows green.

## 6. Stats dialog, header button and wiring

- [x] 6.1 Write failing widget tests in `test/ui/stats_dialog_test.dart` with a controller over a fake store: the current mode's maps by count with `mapLabel` names, the raid total, sales/items/roubles and the "not paid in roubles" note, the empty message, the unknown-mode message, the since line, each failure message, the clear confirmation text "Clear the stats of every mode? This cannot be undone." with confirm and cancel. Add a shell test (in `test/ui/app_test.dart` or a new file) that the header's Stats button opens the dialog. Verify they fail because the dialog does not exist.
- [x] 6.2 Implement `lib/ui/stats_dialog.dart` and the "Stats" `OutlinedButton` beside Settings in `lib/ui/shell.dart` (design D6). Build `LocalStatsController` in `AppServices` right after `RaidTimersController`, before `MapSessionController` binds the reader, with `catalog` as the mode source; dispose it before the database closes. Verify: group 6 rows green, `test/application/app_services_test.dart` still passes, and an app-services test asserts the controller is built and disposed.

## 7. Integration checks

- [ ] 7.1 Run `mise run analyze` and `mise run test`, both clean; run `dart format` on every changed Dart file. Verify: both commands exit 0 and every test-map row is green.
- [ ] 7.2 Run `openspec validate add-local-stats --strict` and `mise run release-notes -- --check openspec/changes/add-local-stats/proposal.md`. Verify: both exit 0; update the proposal's Release Notes if the shipped behaviour changed.

## Workflow follow-up

- User-verified (M7 criterion 4, stats part): during real raids, the Stats dialog counts the raids per map and flea sales as they happen, and a restart of Blackgrid does not add them twice. Agents never run this check; it stays unverified until the user reports it.
