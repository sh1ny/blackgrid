# 0045 - Task attribution uses complete application evidence behind a push snapshot

- Status: accepted
- Date: 2026-11-12 (change `add-task-log-progress`, approved pre-ship correction)
- Supersedes: ADR-0030 only for task-attribution snapshot ordering and its between-stat completeness limitation.
- Extends: ADR-0044; all record identities, immutable ledger rules and game-interaction boundaries remain unchanged.

## Context and problem

Per-scan sorting does not establish folder-wide delivery order. A push read may recover after a later mode change was delivered, and application-first snapshots can omit a mode line written before a task included by the later push snapshot. Recording a task in the wrong mode or wipe cannot be repaired by deleting history. A replay below an existing monotonic watermark also cannot be automatically resumed from that watermark after interruption.

## Decision

- Both live and one-shot readers snapshot push-notifications before application, using one shared helper with an injected stat seam for offline tests. Application is snapshotted last, after other selected files.
- Before releasing tasks from that push snapshot, application consumption must reach its later snapshot without a partial line. A failed, short or partial-line application read never falls back to older mode evidence. Live input leaves push consumption pending for a later complete scan; one-shot input returns unreadable without partial task output. A genuinely missing application file retains the no-mode behavior.
- The reducer retains immutable timestamped same-folder mode evidence until folder change or input reset. A task uses the greatest application `(log time, record offset)` at or before its own log time; unknown mode evidence invalidates attribution. Task lookup does not copy history. Existing carried session mode and flea-sale behavior remain unchanged.
- A live task is admitted only when its folder date is on or after the active wipe's start, checked inside the shared FIFO operation. An explicitly requested earlier replay remains the path that moves the start backward.
- A run captures the live folder at admission. Only a folder strictly older than that frontier may advance the fully-read watermark; newer listed folders may still be growing or not yet bound.
- Catch-up can recover from its watermark after failure or closure. An interrupted or failed earlier replay must be requested again from its original selected date. Its result exposes that retry date, and Local progress always warns that closing Blackgrid stops replay. No hidden auto-resume state is added.

## Rejected alternatives

- Latest processed mode alone: delayed push records can disagree with replay.
- Timestamped history without a complete application snapshot: unseen preceding mode records still cause wrong-mode writes.
- Application-first or unordered snapshots: the push snapshot can include a task whose preceding mode was excluded.
- Publishing tasks after an application read failure or partial read: silently uses stale evidence.
- Marking every folder different from the captured live folder complete: a newer not-yet-bound folder can lose later writes to catch-up.
- Promising automatic resumption of earlier replay: a monotonic watermark may already be newer than the interrupted work.

## Consequences

Mode evidence grows with mode-change records in one folder, not with task count, and is discarded at folder change/reset. An incomplete application line can delay task delivery until it completes; this is preferable to contaminating immutable progress. Deterministic log event IDs make explicitly repeated replay safe. Accepted ADR-0030 and ADR-0044 files remain historical records; this decision records the correction without rewriting them.
