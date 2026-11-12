# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:** openspec/changes/add-task-log-progress/proposal.md, design.md, specs/task-log-progress/spec.md, specs/raid-lifecycle/spec.md, specs/game-log-input/spec.md, specs/settings-page/spec.md; ADR-0041, ADR-0030 (decision and consequences), ADR list for 0003/0037/0042/0043; lib/domain/raid_lifecycle.dart (reducer, LogRecordId), lib/data/session_log_reader.dart (selection, scan, flush, raid-log reads, folder regex), lib/data/game_log/game_log_parsers.dart, lib/data/game_log/game_locations.dart (gameModeFromLog), lib/domain/local_progress_store.dart, lib/domain/local_progress.dart (enums, identity validation), lib/data/database.dart (schema 8 upgrade chain), lib/data/database_progress.dart (admission guard); AGENTS.md. Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis, flutter-add-widget-test.
- **Re-check (same round):** a second fresh-context subagent re-checked Required Changes M1-M4 and the three suggestions against the revised proposal.md, design.md and the four spec deltas, and against the cited source (`lib/data/game_log/game_locations.dart:55-62`, `lib/data/session_log_reader.dart:612-617`, `lib/domain/raid_lifecycle.dart`). This is not a new full review. No skills were named for the re-check, so none were loaded for it.

## Findings

### Critical (blocking)

None.

### Moderate

**M1. A deterministic per-record append failure wedges catch-up and replay permanently.** **Status: resolved.**
`appendProgressEvents` rejects the whole batch on `ProgressIdentityConflict` or `ProgressInvalidInput` (`lib/domain/local_progress_store.dart`, append doc: "reuse with different canonical content returns ProgressIdentityConflict and rejects the entire batch"). The design treats every append failure in a run the same way: "Run stops; `lastFolder` stays at the last stored folder. The next catch-up continues from there. Retry safe: yes" (Failure & Visibility, "Append during a run"). For a deterministic failure that is false: the next catch-up re-reads the same folder, builds the same chunk, gets the same rejection and stops again. Every later folder then stays unrecorded, on every launch. With chunks of up to 256 events, one bad record also blocks every other record in its chunk.
At least one real trigger: D2 derives `occurredAtMs` from the record's local wall-clock time (ADR-0030: "Log times are local wall-clock DateTimes"), converted with the machine's current timezone. A folder re-read after the Windows timezone changes yields the same event ID with a different `occurredAtMs`, which is a conflict. M2 below is a second trigger.
The same applies to live batches. A restart re-publishes the whole live folder, and one conflicting record rejects the new messages batched with it.

**M2. An unrecognised session mode produces `GameMode.unknown`, not "no mode". The design does not handle it.** **Status: resolved.**
`gameModeFromLog` maps any unknown value to `GameMode.unknown` (`lib/data/game_log/game_locations.dart:57-62`), and the parser emits `SessionModeChanged(..., GameMode.unknown)` for it (`game_log_parsers.dart:94-95`). D3 sets `folderMode` from every `SessionModeChanged`, so a task after such a line carries `mode: GameMode.unknown`, not `null`. S6 and the "A message without a known mode is skipped" requirement only cover a message "logged before any session mode". ADR-0041 says "Unknown modes ... fail", so for that message the controller would try to create or append a cycle for `unknown`. A live message would then keep "Some task progress could not be saved" on screen. In a run it would stop the run and, through M1, stop every later catch-up. A future game mode string, or a renamed one, would trigger this.

**M3. "`name > lastFolder`" is not folder-date order for the folder names the reader accepts.** **Status: resolved.**
D7 states catch-up reads folders with "`name > lastFolder` (in folder-date order)". The shared folder regex accepts one-digit hours (`(\d{1,2})`, `session_log_reader.dart:614-617`), and the live reader orders folders by the parsed `DateTime`, padding the hour (`:248-266`). As strings, `log_2026.11.02_9-00-00_…` sorts after `log_2026.11.02_10-00-00_…`. If `lastFolder` is compared as text, catch-up can skip a newer folder for good, and the "only ever advances" rule can refuse a real advance. In both cases progress is silently missing. Nothing reports it, because the skipped folder is never listed as unread.

**M4. Catch-up does not say what happens to task messages of a mode that has no wipe.** **Status: resolved.**
The catch-up requirement reads only "every log folder of each mode's wipe". S4 and the "The first task event of a mode creates its wipe" requirement say the first task message for a mode without a wipe creates one, but they are written around live and replay reads. Take a player with a PvP wipe who first plays PvE while Blackgrid is closed. Their PvE task messages sit in folders that catch-up reads for PvP. The spec allows either outcome: drop them uncounted, or auto-create a PvE wipe. A fresh install with no wipes reads nothing at all. Implementers will diverge, and the player cannot see the "drop" outcome, because those messages are not counted under any skip reason. The same gap covers how each mode's `lastFolder` advances when one folder read serves several modes.

### Suggestions

**S-a. Pin the file token of the event ID as a literal.** **Status: taken.** D2 builds the ID from "the `LogFile` name (`pushNotifications`)". If that comes from `LogFile.pushNotifications.name`, renaming the enum silently changes every durable ID. Replays would then double events instead of matching them. Use a constant in the ID builder and add a test that pins one full ID string.

**S-b. The single-admission guard covers reads too.** **Status: taken.** `BlackgridDatabase` admits one progress operation of any kind (`_progressBusy`, `database_progress.dart:24-51`). The Risks section only names a second writer (`add-manual-progress`). A reader on the same instance, such as `add-quest-checklist` or the availability rules, will also make live writes fail with `ProgressBusy`, and live writes are not retried (Mechanism ledger). ADR-0044 should say that every progress operation on that instance goes through the queue (or the one above it), reads included.

**S-c. D8's "the next launch's catch-up continues" does not hold for a replay into an existing wipe.** **Status: taken (in design.md).** A replay from an early date that a raid stops while it is still below `lastFolder` leaves those older folders unread, and catch-up never returns to them, because it only reads folders newer than `lastFolder`. The "stopped by a raid" result should name the folder or date it stopped at, so the player knows where to replay from.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

Re-check: all four required changes are applied correctly. Details are under Rebuttals. The change can proceed to tasks.

## Required Changes

1. [resolved] (M1) In design.md Failure & Visibility and D5/D8, split append failures into two kinds:
   - Transient (`ProgressStorageFailure`, `ProgressBusy`, `ProgressUnavailable`): the run stops and `lastFolder` is kept, as today.
   - Deterministic per record (`ProgressIdentityConflict`, `ProgressInvalidInput`): retry that chunk one event at a time, count each rejected record in the run result under a new skip reason (for example "conflicting record"), keep going, and advance `lastFolder` as normal.

   Apply the same per-event fallback to live batches. In specs/task-log-progress/spec.md, add the reason to "Each run reports its result", and add a scenario: a re-read record whose stored event has a different time is counted as skipped, the rest of the folder is recorded, and the next catch-up does not stop at that folder.
2. [resolved] (M2) In D3 and S6, treat `GameMode.unknown` from `SessionModeChanged` as no known mode: the `TaskTransition` mode is `null`, or the controller counts it as skipped for no mode. Add a scenario to the "A message without a known mode is skipped" requirement: a task message after a `Session mode:` line whose value Blackgrid does not recognise is not recorded, is counted as skipped for no mode, and creates no cycle. Add the matching scenario to specs/raid-lifecycle/spec.md.
3. [resolved] (M3) In D7 and the State & Ownership row, define folder order as (parsed folder date-time, then name), from the shared `session_folders.dart` helper, for the catch-up filter and for the monotonic `lastFolder` advance. Raw name comparison is not that order. Add a scenario to the game-log-input listing requirement, or to catch-up, with a one-digit-hour folder (for example `log_2026.11.02_9-00-00_…` before `log_2026.11.02_10-00-00_…`).
4. [resolved] (M4) State in the catch-up requirement what happens to the task messages of a mode with no active wipe in the folders catch-up reads. Either catch-up creates that mode's wipe per S4 (start date = that folder's date) and records them, or it does not and the result counts them under a named skip reason. Add a scenario for whichever is chosen. If the choice changes the user-chosen S2/S4 behaviour beyond a clarification, put it to the user first.

CHANGES_APPLIED: yes

## Rebuttals

The author applied fixes rather than rebutting. Each fix was checked in the files.

- **M1 (fixed, verified).** design.md D5 now splits append failures. Transient failures (`ProgressStorageFailure`, `ProgressBusy`, `ProgressUnavailable`) stop a run with `lastFolder` kept. Per-record failures (`ProgressIdentityConflict`, `ProgressInvalidInput`) make the controller retry the chunk one event at a time, count each rejected record as "conflicting record", and continue and advance `lastFolder`. The text names the time-zone trigger. Failure & Visibility has separate rows for "Append during a run, transient failure" and "Append rejects a record", and the second covers live batches through the not-saved message. The Mechanism Ledger has a "Per-event fallback on a rejected batch" row. In specs/task-log-progress/spec.md, "Each run reports its result" lists "conflicting record" and says that a record rejected as conflicting or invalid is counted and skipped without stopping the run. The scenarios "A conflicting record does not block catch-up" (catch-up) and "One conflicting record in a live batch" (live recording) are present. D8 needs no separate change: its stop conditions are the raid phase, and failures are covered by D5.
- **M2 (fixed, verified).** D3 says a `SessionModeChanged` carrying `GameMode.unknown` sets `folderMode` to null. It cites `game_locations.dart:57-62`, and the source confirms that unrecognised values map to `GameMode.unknown`. proposal.md S6 and its summary row cover a mode that is not recognised. specs/task-log-progress/spec.md has the updated requirement text and the scenario "Unrecognised session mode" (not recorded, skipped for no mode, no cycle). specs/raid-lifecycle/spec.md has the updated requirement ("no mode when that folder logged none or the last one is not recognised"), the scenario "Unrecognised mode", and the scenario "Mode from an earlier folder is not carried".
- **M3 (fixed, verified).** D7 defines folder order as (parsed folder date-time, then name) from the shared `session_folders.dart` helper. It says why raw name order is wrong and cites the `\d{1,2}` hour in the regex, and the source confirms that regex at `session_log_reader.dart:614-617`. The State & Ownership row says `lastFolder` only advances in that order. The catch-up requirement reads "by folder date and time". The scenarios "Folders ordered by date, not by name" (task-log-progress) and "One-digit hour" (game-log-input) are present.
- **M4 (fixed, verified; a clarification of S4).** D7 says catch-up reads the union of folders over the existing wipes, and routes each folder's messages to a mode's wipe only within that wipe's range. It also says a mode with no wipe gets one from its first message, with that folder's date as start (S4), so later messages in the run go to it, and that a fresh install with no wipes reads nothing. The scenario "A mode without a wipe in a caught-up folder" is present. This follows from S4's own wording ("The first task event for a mode with no wipe creates one") and from the "first task event of a mode creates its wipe" requirement, which applies to any message to be recorded. It is a clarification, not a change to user-chosen behaviour, so it did not need to go to the user. Not blocking: the caught-up wipe's `lastFolder` advance is implied by the per-folder advance rule rather than spelled out. Apply should cover it with a test.
- **Suggestions.** S-a: D2 now uses the literal token `pushNotifications`, never `LogFile.name`, and pins one full ID in a test. S-b: the Risks section and the ADR-0044 note say that the busy guard rejects reads as well as writes, and that later progress readers and writers must share this queue or one above it. S-c: D8 says the "stopped by a raid" result names the last folder stored, so the player can replay from it. The spec scenario "Raid starts during a replay" still says only "stopped by a raid". Adding the folder there is optional.
