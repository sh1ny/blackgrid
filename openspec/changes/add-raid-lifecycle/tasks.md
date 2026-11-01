# Tasks

Skills for every Dart group (AGENTS.md "Dart and Flutter code"): `dart-use-pattern-matching`, `dart-add-unit-test`, `dart-write-documentation`, `dart-run-static-analysis`; `flutter-add-widget-test` for group 6. Fixtures are small synthetic files under `test/fixtures/game_logs/`, built from the real 1.3.0.0.48484 line formats quoted in the specs, with made-up IDs (never the user's account, profile or session IDs). No arbitrary sleeps: drive the reader with `rescan()` and injected poll intervals, as `test/data/session_log_reader_test.dart` does. The game is never launched or touched.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| game-log-input → Session log files are read from the newest session folder | Three files of the newest folder | test/data/game_log/session_log_reader_events_test.dart | reads the three files of the newest folder only | green |
| game-log-input → Session log files are read from the newest session folder | A newer folder replaces the current one | test/data/game_log/session_log_reader_events_test.dart | a newer folder replaces the current one | green |
| game-log-input → Session log files are read from the newest session folder | Missing push-notifications log | test/data/game_log/session_log_reader_events_test.dart | missing push log keeps application and backend events | green |
| game-log-input → Session log files are read from the newest session folder | No log folder | test/data/game_log/session_log_reader_events_test.dart | no session folder produces no events | green |
| game-log-input → Backend and push-notification problems never change the Map's log state | Push log missing during a raid | test/application/map_session_controller_test.dart | missing push log leaves Logs status and screenshot labels unchanged | green |
| game-log-input → Backend and push-notification problems never change the Map's log state | Rejected push record | test/data/game_log/session_log_reader_events_test.dart | rejected push record reports on raid logs only | green |
| game-log-input → Backend and push-notification problems never change the Map's log state | Backend log rewritten | test/data/game_log/session_log_reader_events_test.dart | backend rewrite keeps map, mode and incarnation | green |
| game-log-input → A record is decoded only when it is complete | Line split across two reads | test/data/game_log/log_file_tail_test.dart | line split across two reads decodes once | green |
| game-log-input → A record is decoded only when it is complete | Multi-byte character split across reads | test/data/game_log/log_file_tail_test.dart | multi-byte character split across reads stays intact | green |
| game-log-input → A record is decoded only when it is complete | Unfinished last line | test/data/game_log/log_file_tail_test.dart | unfinished last line waits for its newline | green |
| game-log-input → A record spans its header and continuation lines | Notification with a JSON body | test/data/game_log/log_file_tail_test.dart | push record completes at its closing brace | green |
| game-log-input → A record spans its header and continuation lines | Body not yet complete | test/data/game_log/log_file_tail_test.dart | half-written push body produces nothing yet | green |
| game-log-input → A record spans its header and continuation lines | Body cut off by the next header | test/data/game_log/log_file_tail_test.dart | next header ends an unclosed push body | green |
| game-log-input → A record spans its header and continuation lines | Body that is not valid JSON | test/data/game_log/game_log_parsers_test.dart | invalid JSON body is rejected and later records parse | green |
| game-log-input → Malformed and over-long records are rejected visibly | Malformed UTF-8 line | test/data/game_log/log_file_tail_test.dart | malformed UTF-8 line is rejected and reading continues | green |
| game-log-input → Malformed and over-long records are rejected visibly | Over-long line | test/data/game_log/log_file_tail_test.dart | over-long line and over-limit push record are rejected | green |
| game-log-input → Replaced or rewritten files are read again from the start | Truncated file | test/data/game_log/log_file_tail_test.dart | truncated file is read again from the start | green |
| game-log-input → Replaced or rewritten files are read again from the start | Rewritten bytes | test/data/game_log/log_file_tail_test.dart | same-length rewrite is read again from the start | green |
| game-log-input → Events carry their log time and a stable record identity | Same identity after restart | test/data/game_log/session_log_reader_events_test.dart | a second reader gives the same identities and times | green |
| game-log-input → Events carry their log time and a stable record identity | Records with the same text | test/data/game_log/session_log_reader_events_test.dart | identical lines get different identities | green |
| game-log-input → Application log lines become lifecycle events | Menu events | test/data/game_log/game_log_parsers_test.dart | session mode and profile selected | green |
| game-log-input → Application log lines become lifecycle events | Rejoin line | test/data/game_log/game_log_parsers_test.dart | transit reconnect line becomes raid rejoined | green |
| game-log-input → Application log lines become lifecycle events | A full raid in the application log | test/data/game_log/game_log_parsers_test.dart | full raid lines in order | green |
| game-log-input → Application log lines become lifecycle events | Matching cancelled | test/data/game_log/game_log_parsers_test.dart | matching cancelled line | green |
| game-log-input → Application log lines become lifecycle events | Unknown scene | test/data/game_log/game_log_parsers_test.dart | unknown scene has no map | green |
| game-log-input → Application log lines become lifecycle events | Event map presets | test/data/game_log/game_log_parsers_test.dart | event presets map to Factory and The Lab | green |
| game-log-input → Application log lines become lifecycle events | Unrelated line | test/data/game_log/game_log_parsers_test.dart | unrelated line produces nothing | green |
| game-log-input → Backend log notification lines become raid-exit events | Raid exit | test/data/game_log/game_log_parsers_test.dart | userMatchOver line becomes raid exit | green |
| game-log-input → Backend log notification lines become raid-exit events | Other notification | test/data/game_log/game_log_parsers_test.dart | other payload types produce nothing | green |
| game-log-input → Push-notification messages become flea-sale and task events | Flea sale | test/data/game_log/game_log_parsers_test.dart | type 4 sale with roubles | green |
| game-log-input → Push-notification messages become flea-sale and task events | Task failed | test/data/game_log/game_log_parsers_test.dart | type 10, 11 and 12 task messages | green |
| game-log-input → Push-notification messages become flea-sale and task events | Flea sale paid in another currency | test/data/game_log/game_log_parsers_test.dart | sale in another currency has no rouble amount | green |
| game-log-input → Push-notification messages become flea-sale and task events | Message without a task ID | test/data/game_log/game_log_parsers_test.dart | task message without an ID is rejected | green |
| game-log-input → Log input never touches the game process | Offline audit | test/data/game_log/log_input_audit_test.dart | log input source has no process or write calls | green |
| raid-lifecycle → Raid phases follow the log events | A whole raid | test/domain/raid_lifecycle_test.dart | a whole raid walks every phase | green |
| raid-lifecycle → Raid phases follow the log events | No events yet | test/domain/raid_lifecycle_test.dart | initial state is unknown | green |
| raid-lifecycle → Raid phases follow the log events | Raid without a starting countdown | test/domain/raid_lifecycle_test.dart | match found goes straight to in raid | green |
| raid-lifecycle → Raid phases follow the log events | Out-of-place event | test/domain/raid_lifecycle_test.dart | raid started without a queue | green |
| raid-lifecycle → A raid records its map, mode, times and entry | Recorded raid | test/domain/raid_lifecycle_test.dart | raid records map, mode, times, entry and cause | green |
| raid-lifecycle → A raid records its map, mode, times and entry | Map unknown | test/domain/raid_lifecycle_test.dart | unsupported scene leaves the map unknown | green |
| raid-lifecycle → Events read together are reduced in log-time order | Replay matches the live read | test/application/raid_lifecycle_controller_test.dart | replay and live read end the raid identically | green |
| raid-lifecycle → Events read together are reduced in log-time order | Same time in two files | test/data/game_log/session_log_reader_events_test.dart | equal times sort application before backend | green |
| raid-lifecycle → Events read together are reduced in log-time order | A file could not be read for a poll | test/domain/raid_lifecycle_test.dart | late raid exit after a menu ending changes nothing | green |
| raid-lifecycle → The first ending of a raid wins and later endings change nothing | Raid exit first | test/domain/raid_lifecycle_test.dart | raid exit first ends the raid once | green |
| raid-lifecycle → The first ending of a raid wins and later endings change nothing | Profile select first | test/domain/raid_lifecycle_test.dart | profile select first ends the raid once | green |
| raid-lifecycle → The first ending of a raid wins and later endings change nothing | Stale raid exit after a new queue | test/domain/raid_lifecycle_test.dart | stale exit after a new queue is ignored | green |
| raid-lifecycle → The first ending of a raid wins and later endings change nothing | Raid exit with no raid | test/domain/raid_lifecycle_test.dart | raid exit in menus is ignored | green |
| raid-lifecycle → A queue that ends without a raid is aborted | Matching cancelled after a match was found | test/domain/raid_lifecycle_test.dart | matching cancelled aborts the queue | green |
| raid-lifecycle → A queue that ends without a raid is aborted | Back to menus while loading | test/domain/raid_lifecycle_test.dart | profile select while loading aborts the queue | green |
| raid-lifecycle → A queue that ends without a raid is aborted | Aborted with no queue | test/domain/raid_lifecycle_test.dart | abort in menus is ignored | green |
| raid-lifecycle → Rejoining a raid is a transit or a reconnect | Transit to another map | test/domain/raid_lifecycle_test.dart | rejoin after an ended raid is a transit | green |
| raid-lifecycle → Rejoining a raid is a transit or a reconnect | Queue between the raid and the rejoin | test/domain/raid_lifecycle_test.dart | rejoin after a queue is a reconnect | green |
| raid-lifecycle → Rejoining a raid is a transit or a reconnect | Unknown rejoin location | test/domain/raid_lifecycle_test.dart | unknown rejoin location has no map | green |
| raid-lifecycle → A client restart during a raid continues that raid | Restart and reconnect while Blackgrid runs | test/domain/raid_lifecycle_test.dart | restart and reconnect continue one raid | green |
| raid-lifecycle → A client restart during a raid continues that raid | Restart without reconnecting | test/domain/raid_lifecycle_test.dart | restart then queue ends the raid by client restart | green |
| raid-lifecycle → A client restart during a raid continues that raid | Blackgrid starts after the restart | test/domain/raid_lifecycle_test.dart | new folder alone starts a reconnect raid | green |
| raid-lifecycle → Each lifecycle transition is published once | One transition per event | test/domain/raid_lifecycle_test.dart | a whole raid publishes one start and one end | green |
| raid-lifecycle → Each lifecycle transition is published once | Re-read after restart | test/application/raid_lifecycle_controller_test.dart | re-reading a folder republishes the same transitions | green |
| raid-lifecycle → Map shows the raid phase | In raid | test/ui/map_rail_test.dart | raid line shows in raid on Customs | green |
| raid-lifecycle → Map shows the raid phase | Matching cancelled | test/ui/map_rail_test.dart | raid line shows matching cancelled | green |
| raid-lifecycle → Map shows the raid phase | No log input | test/ui/map_rail_test.dart | raid line shows unknown without log input | green |

## 1. ADR and architecture

- [x] 1.1 Write `docs/adr/0030-game-log-input.md` (MADR-short, `Status: accepted`, date, source `add-raid-lifecycle` design D1, D2, D3, D5, D7) covering one reader per session folder, record framing, per-scan log-time ordering, the application-only Map state and the stable record identity, with the rejected alternatives and consequences from design.md. Verify: the file exists and `docs/adr/README.md` (if it indexes ADRs) lists it.
- [x] 1.2 Update `openspec/architecture.md`: the in-force ADR index row for ADR-0030; component rows for the session log reader (three tails) and `RaidLifecycleController`; the "Game inputs" boundary (three files, framing, event identity, application-only Map state); the "Log tail" row in Resource bounds (push record 1 MiB / 8 192 lines); the Session evidence state row notes raid state lives in `RaidLifecycleController`. Verify: `git diff openspec/architecture.md` shows each item and no line still says only `application*.log` is read.

## 2. Per-file tail and record framing

- [x] 2.1 Write the failing tests in `test/data/game_log/log_file_tail_test.dart` for the decode, framing, rejection and restart rows of the test map (line split, multi-byte split, unfinished line, push record at closing `}`, half body, body cut by next header, malformed UTF-8, over-long line and over-limit push record, truncation, same-length rewrite), using tiny temp files and chunk sizes of a few bytes. Verify: they fail because `LogFileTail` does not exist.
- [x] 2.2 Extract the byte tail from `lib/data/session_log_reader.dart` into `lib/data/game_log/log_file_tail.dart` (offset, 4 KiB window revalidation through the same handle, 64 KiB line cap, decode on newline, CR drop) and add record framing per file kind: header regex, header-only records for application and backend, push records closed by a lone `}` or the next header, 1 MiB / 8 192-line push limit. Doc comments on public APIs. Verify: 2.1 tests pass, `test/data/session_log_reader_test.dart` still passes, and the rows flip green.

## 3. Event types and line parsers

- [x] 3.1 Write the failing tests in `test/data/game_log/game_log_parsers_test.dart` for every application, backend and push parser row of the test map, using lines copied in format from the specs with synthetic IDs, plus `Сёма` in a push body. Verify: they fail because the parsers do not exist.
- [x] 3.2 Add the sealed `GameLogEvent` hierarchy, `LogRecordId(folder, LogFile, offset)` and log-time parsing (local `DateTime`) in `lib/domain/raid_lifecycle.dart`, and the parsers in `lib/data/game_log/game_log_parsers.dart`: application message table, backend `payloadType=userMatchOver`, push `ChatMessageReceived` bodies decoded with map patterns (types 4, 10, 11, 12; task ID from the first word of `templateId`; roubles only for template `5449016a4bdc2d6f028b456f`). Move the scene table to a shared place, add `factory_event_preset` → `factory` and `laboratory_event_preset` → `thelab`, and add the rejoin location table (`bigmap`, `TarkovStreets`, `Shoreline`, `RezervBase`, `Lighthouse`, `laboratory`, `laboratory_event`, `Interchange`, `Woods`, `Sandbox`, `Sandbox_high`, `factory4_day`, `factory4_night`, `factory_event`, `Icebreaker`, case-insensitive). Verify: 3.1 tests pass and their rows flip green.

## 4. Session log reader over three files

- [x] 4.1 Write the failing tests in `test/data/game_log/session_log_reader_events_test.dart` for folder selection, missing push log, no folder, rejected push record and backend rewrite (Map state unchanged, `raidLogsMessage` set), identity across two reader instances, identical lines, and equal-time ordering (application before backend). Write `test/data/game_log/log_input_audit_test.dart`, which scans `lib/data/game_log/` and `lib/data/session_log_reader.dart` for the banned calls listed in design.md's Mechanism Ledger. Verify: the reader tests fail on the missing `events` stream; the audit test passes on today's code and fails when a banned call is added to a scratch copy of a scanned file (then removed).
- [x] 4.2 Rework `SessionLogReader` per design D1, D3, D7: one folder selection per scan, three tails, `stat` all three then read, collect the scan's events and emit one sorted batch on `Stream<List<GameLogEvent>> events` (sort key: log time, file rank, offset); emit `SessionFolderChanged` on a folder switch and `LogInputReset` on rebind and on an application-log rewrite (which restarts all three tails and replays the folder in one scan, design Flow & State Gaps); keep `SessionLogState` status, incarnation, map, mode and message application-only; add `raidLogsMessage` (missing push log reads "notifications log not written yet"; backend or push rejections and rewrites). Verify: 4.1 tests pass, `test/data/session_log_reader_test.dart` passes unchanged, rows flip green.

## 5. Raid state machine

- [x] 5.1 Write the failing tests in `test/domain/raid_lifecycle_test.dart` for every reducer row of the test map, with event lists built in code (no files). Cover that `interrupted` is a flag on the raid, not a phase (review round 2 note), and that the client-restart rule overrides "the first ending wins" only for a new folder's profile selected. Verify: they fail because `reduce` does not exist.
- [x] 5.2 Implement `RaidPhase`, `RaidLifecycleState`, `RaidTransition` (raid started, raid ended with cause, matching aborted, each with its `LogRecordId` and time) and the pure `reduce(state, event)` in `lib/domain/raid_lifecycle.dart` per both specs and design D3, D6, D8, using switch expressions over the sealed events. Verify: 5.1 tests pass and their rows flip green.

## 6. Controller, wiring and the Map lines

- [x] 6.1 Write the failing tests: `test/application/raid_lifecycle_controller_test.dart` (a temp session folder whose backend raid exit is 9 minutes before the next profile select: the bind-time replay and a line-by-line live append end the raid with the same time, cause and identity; a second controller over the same folder republishes the same transitions), the `map_session_controller_test.dart` case for a missing push log during a followed screenshot, and the three Raid-line widget tests plus a "Raid logs:" line test in `test/ui/map_rail_test.dart` (follow `flutter-add-widget-test`). Verify: they fail for the missing controller and lines.
- [x] 6.2 Add `RaidLifecycleController` (`lib/application/raid_lifecycle_controller.dart`, subscribes in its constructor), build the reader, then the controller, then `MapSessionController` with the reader injected in `lib/application/app_services.dart`, and dispose the controller after `mapSession.close()`. Expose `raidLogsMessage` through `MapSessionState`, and add the "Raid:" line (plain words from a `raidPhaseLabel` helper, map label when known, "(matching cancelled)" after an aborted queue, "unknown" without log input) and the "Raid logs:" line to `_MapInputStatus` in `lib/ui/map_screen.dart`. Verify: 6.1 tests pass, rows flip green, and the existing `map_rail_test.dart` and `map_session_controller_test.dart` tests still pass.

## 7. Integration checks

- [x] 7.1 Run `dart format` on changed files, `mise run analyze` and `mise run test`. Verify: analyze reports no issues, every test passes, and every test-map row is green.
- [x] 7.2 Run `openspec validate add-raid-lifecycle --strict` and `mise run release-notes -- --check openspec/changes/add-raid-lifecycle/proposal.md`, and update the proposal's `## Release Notes` if what ships changed. Verify: both exit 0.

## Workflow follow-up

- User-verified (never run by an agent): during real raids, the "Raid:" line follows queue, match found, raid starting, in raid, raid ended and back to the menus, including one matching cancel and, if it happens, a transit. Record the result in the PR or at the M7 close; until then it is unverified.
- If the user ever sees a client restart and reconnect mid-raid, ask for that session folder's application log lines around it, to confirm the assumed fixture behind design D8.
- The design's State & Ownership row for `RaidLifecycleState` names only a log-root change as a reset trigger; the application-log rewrite reset is in Flow & State Gaps and task 4.2.
