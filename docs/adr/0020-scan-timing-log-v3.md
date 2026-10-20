# 0020 - Scan timing log v3: pass start, decision stamp reported back by the feed, sticky recording flag, log appended after publication

- Status: accepted
- Date: 2026-10-20 (M4 change `qualify-scanner-latency`)
- Supersedes: 0019, its "Timing log v2" bullet only. The line keeps every v2 key, including `trigger`.
- Source: change `qualify-scanner-latency` (design D1, D2); [implementation strategy §6](../IMPLEMENTATION_STRATEGY.md#6-scanner-strategy)

## Context and problem

The M4 latency gate asks three questions of a live session: does a targeted scan reach an actionable decision within 300 ms p95 of the trigger, is the fallback visibly underway by about 300 ms, and does a scan finish within 1.5 s p95. The timing log v2 ([ADR-0019](0019-scan-hotkey-on-the-capture-input-thread.md)) cannot answer the first two:

- it records no stamp for when a pass begins, so the moment Scanner shows `fallback underway` is unknown;
- it records `published`, but not when an accepted scan's decision was applied to the selection;
- it does not say whether frame recording touched the scan, and [ADR-0015](0015-opt-in-scan-frame-recording.md) judges latency with recording off.

[ADR-0013](0013-scan-pipeline-coordination.md) makes the coordinator the sole writer of the line and requires a `v` bump for any key change. [ADR-0017](0017-accepted-scans-feed-the-decision-engine.md) keeps the coordinator from referencing selection, so it cannot observe the decision directly.

## Decision

- **Each pass records its start (D1).** `PassTimeline.started` is stamped when the pass begins: the targeted pass in `_begin`, next to its phase change; the fallback pass where its phase becomes `fallback underway`, before the fallback wait ([ADR-0014](0014-scan-settle-and-fallback-waits.md)). The stamp lives outside `_setPhase`, which returns early when the phase is unchanged.
- **The feed reports the decision back through `AcceptedScanSource.markDecided` (D1).** The interface gains `void markDecided(int reportId)`. `ScanDecisionFeed._applyAccepted` calls it after `selection.selectScan` has set `selection.scan` for that report, where it advances `SessionScanState`. A fenced or undecided scan never calls it. `ScanCoordinator` stamps a per-scan `decided` only when `reportId` is the scan being finished; a late or foreign call is ignored.
- **The log is appended after publication (D1).** `_finish` builds the report, publishes it (the synchronous notify, during which the feed may call `markDecided`), then appends the line with the stamp. The coordinator stays the sole writer.
- **Recording is a sticky per-scan flag (D2).** It is set when recording is on at `_begin`, or when any pass copies a frame for recording, and is never cleared.
- **The line is v3 and only adds keys (D2).** `"v":3`; `ms.<pass>.started` for each pass that began; `ms.decided` when stamped; top-level `"recording": bool`. No key is renamed or removed, so a reader that ignores unknown keys still reads it.

## Rejected alternatives

- **Stamping "after notify returns" for every accepted scan:** it would record a decision for fenced scans (mode or session change, item missing) and overstate the decision path.
- **Letting the feed or `SelectionController` write its own log line:** two writers for one scan's record, against ADR-0013, and the report would need a join.
- **Keeping v2 and inferring the figures** (the targeted pass's last stamp as fallback start, `published` as decided): the proxies miss the matching time on rejection paths and the decision step. The user chose real stamps on 2026-10-20.
- **Inferring recording from session folders by time:** fragile, and the reason recording-on scans have polluted earlier timing reads.

## Consequences

- **A reader exists.** `tool/qualification/scan_latency.dart` reads v2 and v3 lines; only v3 lines with `recording` false drive verdicts, and v2 lines give proxies marked as such.
- **The log append moves after the feed's synchronous work,** a few hundred microseconds; the log is asynchronous anyway.
- **A listener that throws during the notify** leaves the line without `decided`, and the report counts that accept as "accepted, no decision".
- **Reversal cost:** low for the interface method and the reorder in `_finish`; medium for the line format, because later readers key on v3.
