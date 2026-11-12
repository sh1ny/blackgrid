# 0044 - Log task progress records into one active wipe per mode

- Status: accepted
- Date: 2026-11-12 (change `add-task-log-progress`)
- Source: reviewed `add-task-log-progress` proposal S1–S7 and design D1–D8
- Extends: ADR-0041; no accepted ADR is superseded.

## Context and problem

The local progress ledger retains mode-scoped cycles but does not select an active cycle or ingest logs. Task messages must survive missed sessions and replay without duplication, wrong-mode attribution or loss of manual corrections. The game log is read-only, and its push log does not report every mid-raid task failure (ADR-0030).

## Decision

- **Active wipes and one writer.** Drift schema 9 additively creates `ProgressWipes(mode TEXT PRIMARY KEY, cycleId, startDate TEXT YYYY-MM-DD, lastFolder TEXT NULL, updatedAtMs)`, with `(mode, cycleId)` referencing `ProgressCycles`. Existing rows are untouched. `TaskLogProgressController` is the sole writer through `ProgressWipeStore`. Each mode has at most one active wipe. The first task message for a mode without one creates a cycle and wipe starting on that folder's date. `startDate` only moves earlier except when a new wipe replaces the row; `lastFolder` only advances in folder order. An unavailable cycle remains visible and is not silently replaced.
- **Shared operation queue.** The app-scoped controller subscribes to lifecycle task transitions before the first reader bind and serializes its log-progress store writes through one FIFO queue. `LocalProgressStore` admits only one operation per instance, including reads. Later progress readers **and** writers must use this queue or a shared queue above it; a second independent caller would collide with it. Live writes and run chunks share the queue.
- **Durable log identity and time.** A task event's ID is `log1|<cycleId>|<folder>|pushNotifications|<offset>`, with decimal byte offset and literal `pushNotifications`, not an enum name. The versioned, cycle-specific identity makes re-reading idempotent while allowing the same record in separate wipes. Use `progressDeviceId()`, source `log`, the task ID as given, a task-state target and the corresponding started, failed or finished value. Convert the record's local log time to UTC epoch milliseconds with `DateTime.millisecondsSinceEpoch`; an ambiguous fall-back hour resolves consistently on each read. An over-budget identity is skipped and counted.
- **Same-folder mode.** The reducer tracks a separate folder mode, set by `SessionModeChanged` and cleared on folder change or input reset. An unrecognised `GameMode.unknown` sets it to null. A task message without a known mode in its own folder is skipped and counted, never assigned from an earlier folder or the selected app mode. Existing carried session mode and flea-sale behavior remain unchanged.
- **Catch-up and replay.** The shared folder listing orders by parsed folder date-time, then name, not raw name order. Catch-up considers the union across existing wipes of folders on or after each start date, later than its `lastFolder` and older than the live folder; messages are routed only to wipes whose ranges include the folder. If a read reveals a mode without a wipe, its first message creates one at that folder date and subsequent messages use it. With no wipes, fresh-install catch-up has no range and reads no folders; the first live task creates a wipe. Replay reads from the chosen date into the active cycle, preserving manual history; an earlier start moves back when folders are read. A new wipe creates and selects a fresh cycle before replay, leaving the old cycle intact. Replay and new wipe include the live folder up to its current size, but no run ever stores the live folder as `lastFolder`.
- **Bounded reading and failures.** A one-shot `Isolate.run` read per folder uses the existing log framing and parser on application and push logs, sorted as in the live reader. Appends are chunked at 256 events. A batch rejected for identity conflict or invalid input is retried one event at a time; rejected records are counted and skipped, and the rest are stored. Storage, busy or unavailable failures instead stop a run without advancing beyond the last stored folder; live failures are shown. Unreadable folders are counted. No automatic retry or history deletion is introduced.
- **Raid and run guards.** At most one run is admitted, only with a known live folder and phase unknown, in menus or raid ended. Catch-up is requested once per launch and re-armed if initially refused until the guard clears. Runs check phase before each folder; if queue, match found, raid starting or in raid begins, they finish storing the current folder and stop. A stopped replay reports its last stored folder for player-directed replay; catch-up resumes on a later launch. Live recording continues.

## Rejected alternatives

- **D1:** Store active wipes in Preferences; it gives Settings ownership of progress state without a cycle foreign key.
- **D2:** Hash the identity with SHA-256; readable versioned IDs fit the identity budget and are inspectable.
- **D3:** Use carried `sessionMode`; live and one-shot reads could assign the same record to different wipes.
- **D4:** Accept a typed date; invalid input would need separate rejection rather than the themed Flutter date picker.
- **D5:** Put recording in the lifecycle controller or a store-side writer; this mixes lifecycle with persistence and still needs serialization.
- **D6:** Parse folders on the UI isolate or keep a long-lived worker; large logs can block the UI, and one-shot reads have no worker state to retain.
- **D7:** Exclude the live folder from replay as well as catch-up; a new wipe would miss task messages already read in the live session. Raw name ordering also misorders one-digit hours.
- **D8:** Pause and automatically resume replay after a raid; it retains hidden state across raids, unlike an explicit stopped result.

## Consequences

Wipe rows and log event identities are durable contracts extending ADR-0041, not an automatic official wipe detector. History remains immutable; occurrence-time ordering keeps older catch-up evidence from overriding newer progress. Future progress operations must share the admission queue. Log deletion and the push-log gap can leave missing evidence; replay and later manual corrections are the recovery paths. Tracker remains the existing advice and timer authority.
