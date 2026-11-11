# 0041 - Local progress is a versioned event ledger with derived winners

- Status: accepted
- Date: 2026-11-11 (change `add-progress-store`)
- Source: reviewed `add-progress-store` proposal S1–S3 and design D1–D7
- Extends: ADR-0003; no accepted ADR is superseded.

## Context and problem

M9 needs durable local task, objective, hideout, player and trader facts before its catalog, rules, ingestion and checklist can share progress. Tracker's expiring session snapshot is not that history. Replays, late log evidence and manual corrections must converge without discarding manual history or changing existing advice authority.

## Decision

- **Single database, explicit local identity.** `BlackgridDatabase` implements the pure Dart `LocalProgressStore` contract alongside `LocalStatsStore`. One persisted random device UUID v4 and explicitly created mode-scoped cycle UUIDs survive restart. A cycle is not an official wipe, date, log-folder identity or active-cycle preference. Unknown modes, absent cycles and mode mismatches fail. Creation preserves previous cycles; no discovery, automatic rollover or reset occurs.
- **Named portable version 1.** Events contain `formatVersion`, `eventId`, `deviceId`, UTC integer `occurredAtMs`, `mode`, `cycleId`, `source`, `target` (`kind`, `id`, `field`), typed `value` and optional `undoOf`. Tags are names, never enum ordinals. IDs are portable; ordinary replay preserves identity and time. Local identities are random; writers may supply stable event IDs and retain them for explicit retries. Canonical fixed-order JSON defines semantic duplicate equality; unknown fields, tags and invalid combinations fail closed.
- **Independent typed registers.** `(mode, cycleId, entityKind, entityId, field)` identifies a register. Catalog entities use tarkov.dev IDs; player uses `self`. Task state is started/failed/finished; objective count and completion are independent; station/player levels and trader loyalty are nonnegative exact integers; faction is bear/usec; edition is opaque nonempty text. Counts are absolute, not increments. Explicit unset wins like any value and means unknown without resurrecting history. Catalog membership, availability and edition rules do not belong to storage.
- **Deterministic occurrence-time order.** The greatest tuple `(occurredAtMs, sourceRank, deviceId, eventId)` wins per register. Manual ranks before log at equal time; IDs use ordinal string order. A newer manual correction beats older log evidence and newer log evidence beats an older manual edit. Arrival order is not authority; losing facts remain history.
- **Atomic immutable ledger and rebuildable heads.** Schema 8 adds `ProgressMeta`, `ProgressCycles`, `ProgressEvents` and `ProgressHeads` without resetting old records. Cycles have globally unique IDs and a `(mode, cycleId)` candidate key. Events have a global unique event ID, composite scope foreign key, private monotonic sequence, canonical payload and indexed envelope columns that must agree with decoding. Heads reference winners in the same scope/register, checked transactionally. Indexes support scoped sequence paging and predecessor ordering. New events, heads and one cycle-revision advance commit together. Exact duplicates change neither bytes nor revision; contradictory reuse rejects the whole batch across all scopes.
- **Guarded compensation, not deletion.** Undo checks that its target remains current and appends a linked manual event restoring its greatest strict predecessor or unset. The time is `max(now, target + 1 ms)` with checked overflow. A stable compensation/request event ID returns its original committed result before checking the old target again; contradictory request reuse fails. Undoing a compensation follows the same rule; history is never edited.
- **Fail closed with bounded operations.** At most 256 events per batch/page, 4096 UTF-8 bytes per encoded event and one admitted operation per instance; concurrent calls report busy without an operation queue or automatic retry. Identity tokens, including undo links, are at most 256 canonical JSON UTF-8 bytes and edition tokens at most 1024, including quotes/escaping. Five identity tokens plus edition and a 512-byte fixed envelope reserve total 2816 bytes, preserving compensation headroom. Times span ±8640000000000000 milliseconds; numeric values are at most 9007199254740991. No truncation or automatic history pruning occurs.
- **Scoped integrity and snapshot reads.** Opening validates paged history and rebuilds only that scope's heads atomically, checking indexed envelopes against payloads. Damaged/future history makes the cycle unavailable, never empty-success or a partial projection. Cache only one validated `(mode, cycleId, revision)` token after commit. Current-page revision checks, validation/rebuild and decoded rows share one transaction snapshot, including the final page; changed continuations fail stale-cursor. History uses scoped `(highWaterSequence, lastSequence)` cursors so later appends are excluded. Cycle listing is keyset-paged. No transaction remains open between calls; rebuild uses bounded pages and database-backed heads rather than an all-history map. Failed rebuild rolls back heads and preserves event bytes.
- **Tracker coexists unchanged.** No controller, screen, log ingestion, credential migration, advice/timer cutover, synchronization or export/import is introduced. Later M9 changes choose writers, readers and active cycles. Returned invalid-input, identity-conflict, storage, unavailable, busy, stale-cursor and undo-conflict failures are the complete visibility contract at this layer.

## Rejected alternatives

- Permanent source priority or arrival order: prevents correction or makes replay change winners.
- Whole-entity snapshots: invent values for independent fields not observed by a writer.
- Deleting/retracting historical events: loses audit history and can alter later edits.
- Full-history replay for every current read: steady-state cost grows with history.
- Silent insert-or-ignore, damaged-row skipping or automatic reset: hides conflicting or unavailable progress.
- External wipe IDs, sync, compaction, retries or background infrastructure: unproven or outside this change.

## Consequences

The durable format and conflict order have high reversal cost. Clock skew remains visible in original occurrence times; ingestion owns timezone conversion. History intentionally grows on disk, and open/rebuild is linear but bounded in process memory. SQLite serializes cross-instance writes; lock failures surface explicitly, not as automatic retries. Future screens must show unavailable failures rather than treating them as empty progress. Existing database durability, newer-schema refusal and Tracker authority remain in force.
