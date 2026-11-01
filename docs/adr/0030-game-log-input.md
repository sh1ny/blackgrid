# 0030 - Game log input: one reader per session folder, framed records and stable record identity

- Status: accepted
- Date: 2026-11-01 (change `add-raid-lifecycle`)
- Source: change `add-raid-lifecycle` (design D1, D2, D3, D5, D7)

## Context and problem

Until this change Blackgrid read one file from the game's logs: the newest session folder's `application*.log`, for the map and the mode (`lib/data/session_log_reader.dart`). M7 needs the raid lifecycle (queue, match found, raid starting, in raid, raid exit, back in menus) and, later, flea sales and task messages. A read of the user's log folder on 2026-11-01 (game version 1.3.0.0.48484) showed that this takes three files of the same session folder:

- `application_000.log`: one header line per lifecycle event; some headers are followed by continuation lines (stack traces, settings JSON) that carry no event.
- `backend_000.log`: one `payloadType=` line per received notification, including the raid exit (`userMatchOver`), without a body.
- `push-notifications_000.log`: a `Got notification | <Kind>` header, then a multi-line JSON body that ends with `}` alone on its line. It is created about a minute after its folder, never in some folders, and drops every notification that arrives while the player loads into or plays a raid.

Raid exit (backend) and the next profile select (application) come from different files, so a reader that hands events over file by file reduces them in a different order on a startup replay than on a live read. The Map's evidence rules (`MapSessionController`) treat any log status other than `watching` as missing context, so a problem with the two new files must not reach that status. Later changes (`add-local-stats`, M9 task progress) store events and need an identity that survives an app restart.

## Decision

- **One reader owns all three files of one session folder (D1).** `SessionLogReader` keeps its public API, selects the newest `log_*` folder once per scan and drives three `LogFileTail`s (application, backend, push-notifications) over it. Each tail is the earlier byte tail extracted unchanged: byte offset, 4 KiB window revalidation through the same handle, 64 KiB line cap, decode only after the newline, trailing CR dropped, restart from the first byte on truncation, replacement or a rewrite of already-read bytes. The reader adds `Stream<List<GameLogEvent>> events` beside `states`.
- **Records are framed per file; push bodies end at a lone `}` (D2).** A header is a line matching `^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\|`. Application and backend records are header lines only, emitted at their newline; continuation lines are dropped. A push record opens at a `Got notification |` header and completes at a line equal to `}` or at the next header, whichever is read first; its body is decoded with `jsonDecode` and Dart map patterns. A push record is capped at 1 MiB and 8 192 lines; over the cap it is rejected and framing resumes at the next header.
- **Each scan is sorted by log time (D3).** One scan stats all three files first, reads each to its stat size, and emits that scan's events as one batch sorted by (log time, file rank application < backend < push-notifications, byte offset). The bind-time replay is one such scan, so a replay and a live read reduce the same events in the same order. Log times are local wall-clock `DateTime`s with milliseconds. The raid reducer also guards each ending by log time (an ending logged before the current queue or rejoin is ignored; the first applied ending wins).
- **Event identity is folder name, file and record start offset (D5).** `LogRecordId(folder, LogFile, offset)`: the session folder's directory name (not its path), the file kind and the byte offset of the record's header line. A rewritten file's records restart at offset 0 and collide with the old ones by design: the file was replaced.
- **The Map's log state stays application-only (D7).** `SessionLogState.status`, `incarnation`, `detectedMapId`, `detectedMode` and `message` come from the application log alone, as before. Backend and push problems (missing, unreadable, rewritten, a rejected record) go into a separate `raidLogsMessage`, shown on its own "Raid logs:" line. A backend or push rewrite restarts only that file's tail. A rewrite of the application log restarts all three tails, emits `LogInputReset` and replays the folder in one scan, as at startup. A missing push log reads "notifications log not written yet".
- **Read-only, no process access.** The log-input sources (`lib/data/game_log/`, `lib/data/session_log_reader.dart`) only open files for reading. An offline audit test bans `Process.run`, `Process.start`, `Process.killPid`, `dart:ffi`, `openWrite`, `writeAsBytes`, `writeAsString`, `FileMode.write`, `FileMode.append`, `.rename(` and `.delete(` there.

## Rejected alternatives

- **Three independent readers, one per file, each choosing its own newest folder (D1).** A folder switch could leave them reading different sessions for a poll, and the reducer could not tell whether a raid exit belongs to the raid it would end.
- **Completing every record only at the next header (D2).** The last event before a quiet period (a profile select, a flea sale) would wait until the game writes another line, which can take minutes.
- **Handing events over file by file in read order (D3).** A replay would apply every application event before any backend event, so every replayed raid would end "from the menus" at a different time and with a different identity than the live read.
- **A timed merge window across polls (D3).** It adds a timer and latency to every event; sorting within a scan needs neither.
- **A hash of the record text as identity (D5).** Two identical lines (two `Matching with group id` lines) are different events.
- **Folding all three files into the one log status (D7).** `MapSessionController` would label followed screenshots assumed and drop evidence for a push-log problem, changing Map behaviour that the `map-rail` spec describes.

## Consequences

- **`events` is a contract.** `RaidLifecycleController` consumes it now; `add-raid-timers`, `add-local-stats` and M9 task progress build on it.
- **Identity is durable once stored.** `add-local-stats` stores `LogRecordId` to drop duplicates, so changing its parts later needs a migration.
- **Known limit of per-scan sorting.** When one file cannot be read for a poll, its events arrive one poll later and may lose to an ending read on time; events written between the first and the last `stat` of a scan are read on the next scan.
- **The push log's gaps are not recovered.** Flea sales and task messages that arrive during raid loading or play are missing from it; the backend log has no bodies.
- **Two status lines on the Map.** "Logs:" keeps its meaning (application log); "Raid logs:" reports the backend and push-notifications logs.
- **A game update that renames a line** stops the matching event; each parser matches one fixed message with a fixture per line from 1.3.0.0.48484.
- **Reversal cost:** low for the reader, framing and sorting (internal); high for the record identity once `add-local-stats` stores it.
