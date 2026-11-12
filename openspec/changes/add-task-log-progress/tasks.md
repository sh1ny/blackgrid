# Tasks

Skills for every Dart group (AGENTS.md "Dart and Flutter code"): `dart-use-pattern-matching`, `dart-write-documentation`, `dart-add-unit-test`, `dart-run-static-analysis`; group 6 also `flutter-add-widget-test`. Fakes are hand-written and injected; no sleeps. Agents never launch or test against the game.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| raid-lifecycle → Each task message is published once with its mode | Task finished in the menus | test/domain/raid_lifecycle_task_test.dart | task finished in the menus publishes one transition with folder mode | green |
| raid-lifecycle → Each task message is published once with its mode | Task message before any mode is logged | test/domain/raid_lifecycle_task_test.dart | task before any mode has no mode | green |
| raid-lifecycle → Each task message is published once with its mode | Mode from an earlier folder is not carried | test/domain/raid_lifecycle_task_test.dart | folder change clears the task mode | green |
| raid-lifecycle → Each task message is published once with its mode | Unrecognised mode | test/domain/raid_lifecycle_task_test.dart | unrecognised session mode gives no task mode | green |
| raid-lifecycle → Each task message is published once with its mode | Replay after an app restart | test/application/raid_lifecycle_controller_test.dart | re-reading a folder republishes task transitions with the same identity | green |
| game-log-input → Older session folders can be read once on request | Same identities as a live read | test/data/game_log/session_folder_read_test.dart | one-shot read matches live read identities and times | green |
| game-log-input → Older session folders can be read once on request | Folder-date order | test/data/game_log/session_folders_test.dart | lists session folders by date and ignores other entries | green |
| game-log-input → Older session folders can be read once on request | One-digit hour | test/data/game_log/session_folders_test.dart | one-digit hour sorts before two-digit hour | green |
| game-log-input → Older session folders can be read once on request | Folder without an application log | test/data/game_log/session_folder_read_test.dart | push log without application log gives tasks with no mode | green |
| game-log-input → Older session folders can be read once on request | Folder cannot be opened | test/data/game_log/session_folder_read_test.dart | unreadable folder is reported and yields no events | green |
| game-log-input → Older session folders can be read once on request | Malformed record in an older folder | test/data/game_log/session_folder_read_test.dart | malformed push record is counted and others are read | green |
| game-log-input → One-shot folder reads never touch the game process | Offline audit covers the one-shot reader | test/data/game_log/log_input_audit_test.dart | audit scans the session folder sources | green |
| task-log-progress → Each game mode has at most one active wipe | Wipe survives restart | test/data/progress_wipe_store_test.dart | wipe row survives reopening the database | red |
| task-log-progress → Each game mode has at most one active wipe | Modes are separate | test/application/task_log_progress_controller_test.dart | modes record into separate cycles | red |
| task-log-progress → Each game mode has at most one active wipe | Damaged wipe stays visible | test/application/task_log_progress_controller_test.dart | unavailable cycle marks wipe unavailable and creates none | red |
| task-log-progress → The first task event of a mode creates its wipe | First PvP task | test/application/task_log_progress_controller_test.dart | first task event creates wipe at its folder date | red |
| task-log-progress → The first task event of a mode creates its wipe | Creation fails | test/application/task_log_progress_controller_test.dart | failed cycle creation records nothing and reports | red |
| task-log-progress → Task messages become log-sourced task-state events | Task finished | test/domain/task_log_events_test.dart | task finished maps to log-sourced finished event with UTC time | red |
| task-log-progress → Task messages become log-sourced task-state events | Unknown task ID | test/domain/task_log_events_test.dart | task ID is kept without catalog lookup | red |
| task-log-progress → Task messages become log-sourced task-state events | Identity over budget | test/application/task_log_progress_controller_test.dart | over-budget identity is skipped and the rest recorded | red |
| task-log-progress → Reading the same record again changes nothing | Restart replays the live folder | test/application/task_log_progress_controller_test.dart | re-published live transitions leave revision unchanged | red |
| task-log-progress → Reading the same record again changes nothing | Replay overlaps catch-up | test/application/task_log_progress_controller_test.dart | replay over caught-up folder adds nothing | red |
| task-log-progress → A message without a known mode is skipped | Message before the mode line | test/application/task_log_progress_controller_test.dart | message without mode is skipped and counted | red |
| task-log-progress → A message without a known mode is skipped | Unrecognised session mode | test/application/task_log_progress_controller_test.dart | unrecognised mode is skipped, counted and creates no cycle | red |
| task-log-progress → A message without a known mode is skipped | Mode changes within a folder | test/application/task_log_progress_controller_test.dart | mode change within a folder routes messages per mode | red |
| task-log-progress → Live task messages are recorded as they are read | Live task start | test/application/task_log_progress_controller_test.dart | live task start becomes current state | red |
| task-log-progress → Live task messages are recorded as they are read | Store busy or failing | test/application/task_log_progress_controller_test.dart | live write failure shown until next success | red |
| task-log-progress → Live task messages are recorded as they are read | One conflicting record in a live batch | test/application/task_log_progress_controller_test.dart | conflicting live record falls back per event | red |
| task-log-progress → Startup catch-up reads the folders missed since the last run | A month away | test/application/task_log_progress_controller_test.dart | catch-up reads missed folders and leaves the live folder | red |
| task-log-progress → Startup catch-up reads the folders missed since the last run | Started during a raid | test/application/task_log_progress_controller_test.dart | catch-up waits for the raid to end and runs once | red |
| task-log-progress → Startup catch-up reads the folders missed since the last run | Interrupted catch-up | test/application/task_log_progress_controller_test.dart | storage failure keeps last folder and resumes there | red |
| task-log-progress → Startup catch-up reads the folders missed since the last run | A conflicting record does not block catch-up | test/application/task_log_progress_controller_test.dart | conflicting record is skipped and catch-up advances | red |
| task-log-progress → Startup catch-up reads the folders missed since the last run | A mode without a wipe in a caught-up folder | test/application/task_log_progress_controller_test.dart | catch-up creates a missing mode's wipe and advances its last folder | red |
| task-log-progress → Startup catch-up reads the folders missed since the last run | Folders ordered by date, not by name | test/application/task_log_progress_controller_test.dart | catch-up orders folders by date-time not name | red |
| task-log-progress → Replay reads the log folders from a date into the active wipe | Installed mid-wipe | test/application/task_log_progress_controller_test.dart | earlier replay date fills same cycle and moves start back | red |
| task-log-progress → Replay reads the log folders from a date into the active wipe | Other modes are left alone | test/application/task_log_progress_controller_test.dart | replay records only its mode | red |
| task-log-progress → Replay reads the log folders from a date into the active wipe | No folder from that date | test/application/task_log_progress_controller_test.dart | replay with no folders keeps start date | red |
| task-log-progress → Replay reads the log folders from a date into the active wipe | The live folder is never the last folder read | test/application/task_log_progress_controller_test.dart | replay reads live folder but never stores it as last folder | red |
| task-log-progress → Starting a new wipe creates a fresh cycle and replays into it | New wipe | test/application/task_log_progress_controller_test.dart | new wipe creates cycle, replays and keeps old cycle | red |
| task-log-progress → Starting a new wipe creates a fresh cycle and replays into it | Creation fails | test/application/task_log_progress_controller_test.dart | failed new wipe keeps previous wipe active | red |
| task-log-progress → Replay, catch-up and new wipe are refused during a raid | Replay requested in a raid | test/application/task_log_progress_controller_test.dart | replay in raid is refused with reason | red |
| task-log-progress → Replay, catch-up and new wipe are refused during a raid | Replay while catch-up runs | test/application/task_log_progress_controller_test.dart | second run is refused while one runs | red |
| task-log-progress → Replay, catch-up and new wipe are refused during a raid | Raid starts during a replay | test/application/task_log_progress_controller_test.dart | raid stops replay after current folder and names it | red |
| task-log-progress → Each run reports its result | Successful replay | test/application/task_log_progress_controller_test.dart | replay result counts folders, events and skips | red |
| task-log-progress → Each run reports its result | Unreadable folder | test/application/task_log_progress_controller_test.dart | unreadable folder is counted and run continues | red |
| settings-page → Settings sections and their order | Sidebar order | test/ui/settings_page_test.dart | sidebar lists nine sections in order | red |
| settings-page → Settings sections and their order | Jump to a section | test/ui/settings_page_test.dart | (existing) jump to a section | green |
| settings-page → Settings sections and their order | Jump to Diagnostics | test/ui/settings_page_test.dart | (existing) jump to Diagnostics expands it | green |
| settings-page → Local progress section | Wipe shown | test/ui/settings_local_progress_test.dart | wipe row shows start date, last folder and default replay date | red |
| settings-page → Local progress section | No wipe yet | test/ui/settings_local_progress_test.dart | mode without wipe says No wipe yet | red |
| settings-page → Local progress section | Last result shown | test/ui/settings_local_progress_test.dart | last run result is shown with mode and time | red |
| settings-page → Local progress actions are disabled with a reason | In a raid | test/ui/settings_local_progress_test.dart | actions disabled in raid with reason | red |
| settings-page → Local progress actions are disabled with a reason | Confirm a new wipe | test/ui/settings_local_progress_test.dart | new wipe asks confirmation naming mode and date | red |
| settings-page → Local progress actions are disabled with a reason | Confirmation cancelled | test/ui/settings_local_progress_test.dart | cancelled confirmation changes nothing | red |

## 1. ADR and architecture

- [x] 1.1 Write `docs/adr/0044-log-task-progress-active-wipes.md` (MADR short, `Status: accepted`, the date, extends ADR-0041). It covers active wipes per mode in `ProgressWipes` with one writer, the shared controller queue that later progress readers and writers must use, the `log1|<cycleId>|<folder>|pushNotifications|<offset>` event ID with its literal file token, per-folder mode (unrecognised = none), catch-up, replay and new-wipe rules, the live-folder rule, folder date-time order, and per-record rejection fallback. Verify that the file exists and that the rejected alternatives from design D1–D8 are listed.
- [x] 1.2 Update `openspec/architecture.md`: an ADR-0044 index row, state-ownership rows (active wipe, task progress events written by the controller), a resource-bounds row (log-progress runs), the component and boundary text (schema 9, one-shot folder reader), and the Local progress line. Verify with `mise run analyze` (no Dart change) and a read-through that every row cites ADR-0044.

## 2. Task transitions and per-folder mode (raid-lifecycle)

- [x] 2.1 Write failing tests in `test/domain/raid_lifecycle_task_test.dart` for the four reducer rows of the test map, and add the restart re-publish test in `test/application/raid_lifecycle_controller_test.dart`. Verify that they fail because no task transition exists.
- [x] 2.2 Add `folderMode` to `RaidLifecycleState`: set by `SessionModeChanged` (null for `GameMode.unknown`), cleared by `SessionFolderChanged` and `LogInputReset`. Add `TaskTransition(id, time, taskId, ProgressTaskStatus status, GameMode? mode)` emitted for `TaskStarted/Failed/Finished`, with doc comments. Verify that the group 2 tests pass, flip their rows green, and confirm with `mise run test` that the flea, side and lifecycle tests stay green.

## 3. Session folders and one-shot reads (game-log-input)

- [x] 3.1 Write failing tests: `test/data/game_log/session_folders_test.dart` (listing and order, including one-digit hours) and `test/data/game_log/session_folder_read_test.dart` (identities match a live `SessionLogReader` read of the same small synthetic folder; no application log; unreadable folder; malformed push record). Extend `log_input_audit_test.dart` to scan the new sources. Build the fixtures from existing game-log fixture lines; keep them small. Verify the failures.
- [x] 3.2 Add `lib/data/game_log/session_folders.dart` (shared folder regex, file patterns, `SessionFolder(name, path, time)`, `listSessionFolders(root)` ordered by date-time then name) and switch `SessionLogReader._select` to it with no behaviour change. Verify that `session_log_reader_test.dart` and `session_log_reader_events_test.dart` stay green and the listing rows turn green.
- [x] 3.3 Add `readSessionFolderTasks(folderPath)`, which is pure and isolate-safe. It reads the application and push-notifications logs with `LogFileTail` to their sizes, parses, sorts by (time, file rank, offset), folds `SessionFolderChanged` plus the events through `reduce`, and returns `FolderTaskRead(folder, tasks, skippedNoMode, rejected, unreadable)`. Run it once under `Isolate.run` in a test. Verify that the group 3 rows, including the audit row, turn green.

## 4. Wipe table and log event mapping (schema 9)

- [ ] 4.1 Write failing tests: `test/data/progress_wipe_store_test.dart` (insert or replace a mode, survive reopening, monotonic `lastFolder` in folder order, start moves only earlier, foreign key to `ProgressCycles`) and `test/domain/task_log_events_test.dart` (mapping a `TaskTransition` to a `ProgressEvent`: log source, task target, state value, local-to-UTC time, unknown task ID kept, one fully pinned event ID string, over-budget identity reported). Extend `test/data/migration_test.dart` for 8→9 with existing rows kept. Verify the failures.
- [ ] 4.2 Add the `ProgressWipeStore` domain interface and the `ProgressWipes` table in `database_progress.dart`, bump `schemaVersion` to 9 with a `from < 9` additive step, and generate `drift_schemas/drift_schema_v9.json` and `database.g.dart` with build_runner. Add the pure event-mapping function next to the store contract in `lib/domain/`. Verify that the group 4 rows and `migration_test.dart` pass.

## 5. TaskLogProgressController

- [ ] 5.1 Write failing tests in `test/application/task_log_progress_controller_test.dart` with hand-written fakes: an in-memory `LocalProgressStore` that can inject storage failures, unavailable cycles, identity conflicts and busy; a `ProgressWipeStore` fake; a lifecycle source exposing phase, current folder and transitions; and an injected folder lister and reader (no isolate in these tests). Cover every task-log-progress row of the test map, plus two extra tests from the review: a wipe created mid-catch-up advances its own `lastFolder`; and the "stopped by a raid" result names the last folder stored. Verify the failures.
- [ ] 5.2 Implement `lib/application/task_log_progress_controller.dart` per design D5, D7 and D8:
  - one FIFO write queue;
  - wipe load and `openProgressCycle` at start, with unavailable shown;
  - live `TaskTransition` recording with automatic wipe creation (S4);
  - catch-up after the first lifecycle state with a live folder and an allowed phase, re-armed after a refusal;
  - replay and new wipe, with the live folder included and never stored as `lastFolder`;
  - per-record fallback on identity conflict and invalid input;
  - a phase check between folders;
  - the run result, the last result and error messages exposed for Settings.

  Use `Isolate.run` for folder reads through an injected runner. Verify that every controller row turns green.
- [ ] 5.3 Wire the controller in `AppServices` before the first bind (beside `LocalStatsController`), with the log root from the bound reader, and dispose it with the services. Verify with an `AppServices` construction test (existing harness) that the controller subscribes before bind, and with `mise run test`.

## 6. Settings "Local progress" section

- [ ] 6.1 Write failing widget tests in `test/ui/settings_local_progress_test.dart` over a fake controller (rows per mode, No wipe yet, unavailable, last result, disabled reasons in raid, busy and no log folder, new-wipe confirmation and cancel). Update the sidebar-order test in `test/ui/settings_page_test.dart` to nine sections. Verify the failures.
- [ ] 6.2 Add the Local progress section after Tracker progress in `lib/ui/settings/settings_page.dart` (new `local_progress_settings.dart`), with Ember theme styles only (ADR-0037). Date buttons open `showDatePicker` (range from the oldest folder date or 2017-01-01 to today; initial date the wipe start or today). Add the Start a new wipe confirmation dialog. Verify that the group 6 rows turn green, that the existing jump tests stay green (flip their rows after re-running), and that the `lib/ui` colour-literal source check passes.

## 7. Integration checks

- [ ] 7.1 Run `dart format .`, `mise run analyze` and `mise run test`. All must pass. Confirm every test-map row is green.
- [ ] 7.2 Run `openspec validate add-task-log-progress --strict` and `mise run release-notes -- --check openspec/changes/add-task-log-progress/proposal.md`. Both exit 0. Update the proposal's Release Notes if apply changed what ships.

## Workflow follow-up

- M9 user-verified criterion 5 ("A replay of the player's real log folders matches their in-game quest state") is judged at the M9 close, once `add-quest-checklist` shows task states. This change adds no `[user]` task (see proposal Why).
- Pre-ship review, PR, archive and finish follow `specwright-commit`, `specwright-review`, `specwright-pr` and `specwright-finish`.
