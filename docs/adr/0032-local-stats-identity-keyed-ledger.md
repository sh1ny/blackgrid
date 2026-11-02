# 0032 - Local stats are an identity-keyed ledger with a clear watermark

- Status: accepted
- Date: 2026-11-02 (change `add-local-stats`)
- Source: change `add-local-stats` (design D2, D3, D5)

## Context and problem

M7 keeps the player's flea market sales and raids per map in the local database. They come from `RaidLifecycleController`'s transitions, and each raid start and flea sale carries the `LogRecordId(folder, file, offset)` of its log record (ADR-0030).

`SessionLogReader` replays the newest session folder at every bind and after an application-log rewrite. A count that only adds would grow on every restart of Blackgrid. A clear must also stay cleared: after a clear and a restart, the same folder replays the records the clear removed. Once stored, the ledger is the player's history, and M15's raid history extends it, so its format is hard to change later.

## Decision

- **One row per counted raid and per sale, keyed by its record identity (D2).** `RaidStatRecords` and `FleaSaleRecords` have the primary key `(folder, file, offset)` and are written with insert-or-ignore, so a replayed record changes nothing. Totals are `GROUP BY` queries per mode. The mode is stored as the `GameMode` name, `unknown` when none was logged; an unknown mode is never part of a known mode's totals.
- **Times are integer milliseconds since the epoch.** Raid starts, sale times and the clear time keep the log's millisecond precision, not Drift's default whole seconds, so the watermark comparison is exact.
- **The clear is a durable watermark written with the delete (D3).** A one-row `StatsMeta(id = 0, clearedAtMs)` table. A clear deletes both ledgers and upserts the watermark (the injected clock's now) in one transaction. Every insert reads the watermark in its own transaction and skips a record whose log time is at or before it.
- **The reconnect rule reads only earlier rows (D5).** A reconnect raid start is skipped when the newest stored raid of the same mode that started strictly before it is on the same map and at most 2 hours earlier. Rows that start later never affect the decision, so a replay decides the same way with no extra stored state.
- Schema version 4 adds the three tables; earlier versions upgrade in order (ADR-0003).

## Rejected alternatives

- **Per-mode counters (`raids[map]++`, `roubles += n`) with a separate set of seen identities.** A counter cannot tell a replay from a new event without the set anyway, and a counter and its set written apart could drift. The ledger is also what M15's raid history extends.
- **Tombstones for cleared record identities instead of a watermark.** The tombstone set grows forever, and a rewritten log restarting at offset 0 could collide with the tombstone of a different record.
- **Storing a skipped reconnect as a "not counted" row.** Every total would have to filter the flag; comparing only against earlier starts gives the same replay stability.

## Consequences

- **Replay-safe.** A restart or a rewritten application log re-publishes the same identities, and nothing is added. Records logged at or before the last clear are never stored again, so a clear survives a restart.
- **Stored format.** `LogRecordId` becomes stored data, as ADR-0030 anticipated. A rewritten log that reuses an offset for a different record is ignored at that identity; such rewrites come only from a reinstall or a launcher cache clear, which also deletes the old records.
- **Late records after a clear are dropped.** A record logged before the clear but read after it is skipped: a clear means "everything up to now".
- **Unbounded by design.** The ledgers grow with the player's activity (about 10 000 rows a year for a heavy player); the indexed per-mode queries stay fast, and Clear empties them.
- **Known limits.** Log times and the clock are local wall time, so in the autumn daylight-saving repeat hour a record can compare wrongly against a clear made in that hour. Stats start from what Blackgrid reads: the newest folder at each start and everything after.
- **Reversal cost:** high for the stored format (identity key, millisecond times, the watermark row); low for the 2-hour reconnect window, which never rewrites stored rows.
