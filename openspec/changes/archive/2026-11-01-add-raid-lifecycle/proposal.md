# Proposal

## Why

This change serves M7 (raid lifecycle, timers and local stats) and is its first change. It delivers the milestone's first exit criterion: "`application.log` and `notifications.log` feed one raid state machine covering queue, match found, raid starting and started, matching aborted, raid exit, back in menus, profile select and reconnects. Partial lines, multi-byte text split across reads and the two logs arriving in either order are each proved by offline fixture tests." It also gives the user-verified criterion ("during real raids, the raid state … follow[s] the game") its raid-state part. `add-raid-timers` and `add-local-stats` build on its events, and M9's task progress takes its task events.

Today Blackgrid reads only two facts from the game's logs, the map and the mode (`lib/data/session_log_reader.dart`). It cannot tell whether the player is in a queue, in a raid or back in the menus, so nothing can time a raid or count one.

A read of the user's own log folder (855 sessions, newest on game version 1.3.0.0.48484) on 2026-11-01 corrected two roadmap assumptions:

- **There is no `notifications.log`.** Notifications go to `<session> push-notifications_000.log`, and each notification there is a header line followed by a multi-line JSON body. Records span lines.
- **The push-notifications log drops notifications.** In the 1.3.0 sessions it logged none of the raid-exit (`userMatchOver`) notifications, and it misses every notification that arrives while the player is loading into or playing a raid, flea sales included. `backend_000.log` logs one line per notification for all of them (`payloadType=userMatchOver`, `payloadType=RagfairOfferSold`), without a body. Raid exit therefore comes from `backend_000.log`, and flea sales and task messages, which need the body, come from the push-notifications log with that gap.

The exit criterion's "`notifications.log`" is met by these two files. The roadmap wording is left as it is; the M7 close records the correction.

## What Changes

- **One log tail for three files.** The newest session folder's `application_000.log`, `backend_000.log` and `push-notifications_000.log` are each tailed read-only from byte offsets. The existing safeguards apply to all three:
  - a line is decoded only once it is complete, so a partial line or a multi-byte character split across reads is never decoded early;
  - an over-long line or malformed UTF-8 is rejected and reported;
  - a replaced or rewritten file restarts that file's read.

  A record is a timestamped header line plus the lines that follow it up to the next header, so a JSON body belongs to its notification.
- **Typed log events.** Records become typed events, each carrying its log time and a record identity (session folder, file and byte offset) that stays the same across app restarts:
  - from `application_000.log`: session mode, profile selected, queue entered, scene (map) loaded, match found, raid starting, raid started, matching aborted, and transit or reconnect into a raid;
  - from `backend_000.log`: raid exit (`userMatchOver`);
  - from `push-notifications_000.log`: flea sale (item, count and roubles received), and task started, failed and finished (message types 10, 11 and 12; the task ID).
- **One raid state machine.** A pure Dart reducer turns the events into the raid phase: unknown, in menus, in queue, match found, raid starting, in raid, or raid ended. It records the raid's map and mode, its start time and whether the player entered it by reconnect or transit. Raid exit and the next profile select come from different files and may be read in either order. Both end the current raid, the second changes nothing, and an event logged before the current raid started never ends it.
- **Map and mode keep working.** The detected map, mode and "Logs:" status still come from the application log alone, with the same behaviour as today. A problem with the backend or push-notifications log never changes them. The one addition: the event-raid scenes `factory_event_preset` and `laboratory_event_preset` are now detected as Factory and The Lab. The user's logs show them in 4 of 6 raids on 2026-10-31.
- **Two status lines.** The Map saved-file inputs section shows the raid phase in plain words, for example "Raid: in raid on Customs" or "Raid: in menus". A "Raid logs:" line reports problems with the backend and push-notifications logs. Timers come with `add-raid-timers`.
- **Fixture tests, offline.** Small synthetic fixtures built from the real line formats prove partial lines, multi-byte text split across reads, records spanning lines, either-order arrival of raid exit and profile select, matching aborted, transit and reconnect, and a full queue-to-menus raid.

Out of scope:

- No timer, stat, storage or task progress. They are later changes (`add-raid-timers`, `add-local-stats`, M9).
- Flea sales and task messages that the push-notifications log drops are not recovered. `add-local-stats` decides how to report that gap.
- No game process is read, found or touched. Only the log files are read.
- No TarkovMonitor code is copied. The line formats come from the user's own logs.

## Capabilities

### New Capabilities

- `game-log-input`: how the game's log files are found, tailed and turned into typed, timestamped events with a stable record identity, including partial lines, split multi-byte text, records spanning lines and replaced files.
- `raid-lifecycle`: the raid phases, the transitions between them, reconnects and transits, the either-order handling of raid exit and profile select, and the raid status line on Map.

### Modified Capabilities

None. Map and mode detection keeps its current behaviour; no current spec states it.

## Impact

- **Code:**
  - `lib/data/session_log_reader.dart`: its byte tail becomes a shared per-file tail; map and mode come from the new events.
  - New: `lib/data/game_log/` (file tail, record framing, line parsers) and `lib/domain/raid_lifecycle.dart` (events and the reducer).
  - `lib/application/map_session_controller.dart` and `lib/domain/map_session.dart`: expose the raid phase.
  - `lib/ui/map_screen.dart`: the raid status line.
- **Tests:** new fixtures under `test/fixtures/game_logs/` and tests under `test/data/game_log/` and `test/domain/`. The existing `session_log_reader_test.dart` keeps passing.
- **Architecture:** a new row for the game-log input and the raid state machine, and the "Game inputs" boundary lists the two extra files. A design decision on the tail and the event identity is recorded as an ADR.
- **Dependencies:** none new.

## Release Notes

Blackgrid now follows the raid from the game's log files: it knows when you are queuing, loading, in a raid or back in the menus, and shows the raid phase on the Map. Later updates build raid timers and local stats on it.

### Added
- The Map's saved-file inputs show the raid phase (in menus, in queue, match found, raid starting, in raid or raid ended), read from the game's application, backend and push-notification logs.
- A "Raid logs:" line on the Map reports problems with the backend and push-notification logs, such as a notifications log the game has not written yet, without changing the "Logs:" line.

### Fixed
- Factory and The Lab are detected from the game logs during event raids (the `factory_event_preset` and `laboratory_event_preset` scenes).
