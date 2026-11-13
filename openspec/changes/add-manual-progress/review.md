# Review

## Metadata

- **Round:** 1 (second re-check of the Required Changes only)
- **Prior round:** none (round 1's first re-check found RC1 and RC3 applied and RC2 partly applied: the Release Notes wording and the state after a Redo were open)
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:**
  - Round 1: openspec/changes/add-manual-progress/proposal.md, design.md, specs/manual-progress/spec.md, specs/settings-page/spec.md, specs/task-catalog/spec.md; docs/adr/0041, 0042, 0044 (0043 via the edition table); source: lib/application/task_log_progress_controller.dart, lib/application/raid_lifecycle_controller.dart, lib/application/map_session_controller.dart, lib/application/app_services.dart, lib/application/catalog_controller.dart, lib/domain/local_progress.dart, lib/domain/local_progress_store.dart, lib/domain/task_log_events.dart, lib/data/database_progress.dart, lib/data/catalog_normalizer.dart, lib/data/session_log_reader.dart, lib/ui/settings/local_progress_settings.dart, packages/blackgrid_progress/lib/src/{edition_table,player_progress,parse_progress_catalog,progress_catalog}.dart.
  - This re-check: the current proposal.md (S3, S4, Modified Capabilities, Impact, Release Notes), design.md (D1, D3, D5, the new D7, decision summary, Flow & State Gaps, Mechanism Ledger), specs/manual-progress/spec.md, specs/settings-page/spec.md, the new specs/local-progress/spec.md, and `_progressEventById` in lib/data/database_progress.dart:335.
  - Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, flutter-add-widget-test.

## Findings

### Critical (blocking)

None.

### Moderate

**M1. A wipe created "today" by manual entry silently drops the current session's live task events when the game session started before midnight.**
S3 / the spec's "The first entry creates a wipe when none is active" set the new wipe's start to today's local date. The log path does not do this: it starts a wipe at the *folder's* date (ADR-0044: "creates a cycle and wipe starting on that folder's date"; `_recordChunk(mode, [transition], folderDate, run)` at `task_log_progress_controller.dart:356`). The live path then drops any transition whose folder date is before the wipe start: `if (wipe != null && folderDate.isBefore(_date(wipe.startDate))) return;` (`:352-355`). This drop is not counted and does not set an error. Catch-up has the same filter (`_inRange`, `:528-531`). Scenario: the game was launched at 23:00 on 11-12, so the live folder is dated 11-12. At 00:30 on 11-13 the player sets their level, and the PvE wipe starts on 11-13. Every task the player starts, fails or finishes for the rest of that session is then discarded without notice, now and on later catch-ups. Only a replay from 11-12 recovers them, and nothing tells the player one is needed. The proposal also says "as the log path does", which is not what the design does. The Failure & Visibility table and Flow & State Gaps do not cover this case.

**M2. Undo of an undo re-applies the undone value. The mechanism ledger says the opposite, and the spec leaves the second click undefined.**
The ledger rejects an undo history because "one-level undo per click already walks back, since a compensation can be undone and undo restores the predecessor". The store does not behave that way. `undoProgress` (`database_progress.dart:854-922`, ADR-0041 "Undoing a compensation follows the same rule") restores the target's greatest strict predecessor. The predecessor of a compensation is the event it undid. Example: level set 30 (m1), then 34 (m2). Undo writes c1 = 30. A second click on Undo (still offered, because c1 is a manual winner, per the spec's "When a value's current winner is a manual event") writes c2 = 34. The value toggles between the last two values; it never walks back to before 30. Two more effects follow:
- When the predecessor was a log event, the compensation is a manual event carrying the log's value, so the row shows "Set by hand" for a value that came from the logs.
- The release note says "Every change can be undone", but in fact only the last change can be, as a toggle.

The ledger row is therefore justified by a false claim, and users will see "Undo" act as "Redo".

**M3. The projection re-read trigger is much broader than D3 states, and the controller lives for the whole app.**
D3 re-reads when `TaskLogProgressController` notifies ("log event, run progress, new wipe"). That controller notifies on many more occasions:
- every lifecycle batch: `_onLifecycle` calls `_notify()` unconditionally (`:327-330`), and `RaidLifecycleController._onBatch` notifies once per emitted log batch (`raid_lifecycle_controller.dart:35-45`);
- every refusal;
- per folder and per chunk during runs (`:561, :581, :432, :673`).

The State & Ownership table gives the projection the lifetime "Memory, while the app runs", so these re-reads happen even with Settings closed. Each re-read is a full `readCurrent` (about 3 pages today) enqueued on the same FIFO as live writes and replay chunks. During launch catch-up and any replay, coalescing (D3) still allows a full projection read between almost every chunk and folder. That slows the run the design says manual work merely "interleaves" with, and it does store reads nobody looks at. The Resource Bounds row assumes the rate is bounded by user-visible work, which it is not.

### Suggestions

**S-a. Guard against catalog and effective-mode skew.** `AppServices._syncMapSession` calls `catalog.setMode(mode)`, which sets `snapshot = null` and loads asynchronously (`catalog_controller.dart:63-97`). For a moment, `CatalogController.mode`/`snapshot` and `MapSessionController.effectiveMode` can disagree. D3 and D5 should state that rows and validation (loyalty and station levels, task list) use the catalog only when `catalog.mode == effectiveMode`. Otherwise they show "Task data is not loaded yet".

**S-b. Handle a progress load failure.** If `_load` fails (`readProgressWipes` throws, or the device ID is missing), `_wipes` is empty. Your progress would then say "the first entry starts a wipe today", but every entry fails with "restart Blackgrid" (`_createWipe`, `:374-378`). Add a row to the Failure & Visibility table, and expose a "not loaded" state on `LocalProgressAccess` so that entry is disabled with that reason, as it already is for an unavailable wipe.

**S-c. Name the ID generator for app-side events.** D1 has `appendManual` and `undo` generate random event and request IDs in the application layer. The only generator, `_randomProgressId`, is private to `lib/data/database_progress.dart:141`. Name the seam, for example an injected `String Function() newId` with a secure default, so that tests can supply deterministic IDs.

**S-d. Task "Not started" and "Clear" both record unset.** Each task row then has two controls that write the same event, and a task set to not started shows as unknown with no source. Consider showing an unset task as "Not started" and dropping the separate clear for task rows. Otherwise the spec should say the two are the same action.

**S-e. Add a scenario for "it beats older log evidence".** The manual-progress requirement claims this but has no scenario. Add one, for example: a task finished by hand at 18:00, then a replay reads a 10:00 "started" for it, and the task stays finished, set by hand. This is the main recovery path S3 relies on ("replay from an earlier date still works later").

### Re-check of Required Changes

- **RC1 (M1): applied.** As found in the first re-check, the wipe starts on the earlier of today and the live folder's date across S3, D1, the manual-progress spec (with the midnight scenario), the settings-page text and Flow & State Gaps. Nothing has regressed.
- **RC2 (M2): applied.**
  - **2a.** The Release Notes now read "The last change of each value can be undone, and an undo can be redone", and the Added line reads "with undo and redo of the last change". Both match the spec.
  - **2b.** D7 makes Redo append a new ordinary manual edit carrying the undone value, and compensations are never undone. The label therefore follows from the winner alone: no `undoOf` means Undo, `undoOf` means Redo. The `undoOf` chain never exceeds depth 1, which removes the earlier ambiguity.
    - Traced against the store, using 30 (m1), 34 (m2), undo c1 = 30, redo r = 34 (no `undoOf`). Undo of r restores r's greatest strict predecessor, c1 = 30, as a compensation, so the control reads Redo. This matches the new "Undo after redo" scenario and ADR-0041's predecessor rule (`database_progress.dart:854-922`).
    - The ledger, S4, D1 (`redo(mode, cycleId, undoEventId)`) and the decision summary agree.
- **RC3 (M3): applied.** As found in the first re-check: D3 re-reads on `progressRevision` only while the part is mounted, and State & Ownership, Resource Bounds and the Mechanism Ledger match. Nothing has regressed. The D1 sentence slip is fixed: `readCurrent` is again a listed interface operation.

### New problems from D7 or the local-progress delta

No new problem with a concrete consequence was found, so nothing blocks.
- `readProgressEvent` is read-only and scope-checked. The store already has a private by-ID lookup to build on (`_progressEventById`, `database_progress.dart:335`).
- The read and the "still the winner" check run inside one queued operation. ADR-0044's single shared queue is the only writer path, so no other write can interleave between the check and the append.
- No stored format changes.

One suggestion:

- **S-f. Specify a stale Redo in the spec.** The manual-progress requirement says "A stale undo SHALL report the conflict and change nothing", and D7 checks that the compensation is still the winner, but the spec has no matching line or scenario for Redo. Add "a stale undo or redo" with a scenario: a log event replaces the undone value, then Redo reports that the value changed and records nothing. Without it, the conflict path has no spec-mapped test.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (M1) Make a wipe created by manual entry never start after the live session folder's date. **Status: applied.**
2. (M2) Correct the ledger claim; specify the undo/redo behaviour with scenarios, the compensation's source label, the state after a Redo and how the controller tells an undo from a redo; make the Release Notes match. **Status: applied** (2a Release Notes; 2b through D7 and the local-progress delta).
3. (M3) Narrow the re-read trigger to a progress-data signal and to while the part is shown. **Status: applied.**

CHANGES_APPLIED: yes

## Rebuttals

- M1: fixed (S3, D1, manual-progress spec "first entry creates a wipe" plus the midnight scenario, settings-page "Mode without a wipe", Flow & State Gaps). Confirmed by reviewer.
- M2: fixed (ledger, S4, D7, manual-progress spec undo/redo requirement with the "Redo after undo" and "Undo after redo" scenarios, the local-progress delta for the by-ID read, Release Notes). Confirmed by reviewer.
- M3: fixed (D3 `progressRevision`, mounted-only lifetime, State & Ownership, Resource Bounds, Mechanism Ledger). Confirmed by reviewer.
