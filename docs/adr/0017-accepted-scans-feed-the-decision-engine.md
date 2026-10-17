# 0017 - Accepted scans feed the shared decision engine through an app-layer feed

- Status: accepted
- Date: 2026-10-18 (M4 change `add-scan-decisions`)
- Supersedes: 0013 ([ADR-0013](0013-scan-pipeline-coordination.md)), the decision "No decisions from scans before M4" only. The coordinator ownership, latest-wins supersession, fallback list and timing log v1 stay in force, as does the rule that `ScanCoordinator` never references selection or history.
- Source: change `add-scan-decisions` (design D1, D2, D3, D6); [implementation strategy §6](../IMPLEMENTATION_STRATEGY.md#6-scanner-strategy)

## Context and problem

ADR-0013 shows accepted scans as evidence and keeps them out of keep/sell advice until M4. M4 now connects them. Four things have to be fixed together, because the correction flow (change 3), the Map snapshot (change 5) and M6 code against them:

- who carries an accepted scan from the coordinator to the one decision projection (ADR-0001), without breaking the coordinator's ownership split;
- how one accepted scan is consumed exactly once, when the coordinator notifies for many other reasons;
- how a scan that began in one mode or session is kept from advising in another, which is a wrong-Sell risk;
- what a scan-sourced history row looks like on disk.

## Decision

- **A separate app-layer feed carries accepted scans into selection (D1).** A new `ScanDecisionFeed` (`lib/application/scan_decision_feed.dart`) is built and disposed by `AppServices`. It listens to an `AcceptedScanSource`, a `Listenable` with `ScanReport? lastAccepted`, which `ScanCoordinator` already satisfies. For a new accepted report it applies the fences below and then calls `SelectionController.selectScan`. A mode or session change calls `SelectionController.retireScan`. The coordinator still imports neither selection nor history, so ADR-0013's two source audits stand.
- **Exactly once, by report id (D2).** The feed keeps `_consumed`, the highest accepted report id it has seen. It starts at `lastAccepted?.id ?? 0` when the feed is built and is never lowered. A notification acts only when `lastAccepted.id > _consumed`. The mark rises before the fences, so a fenced scan is never retried. Phase changes, status changes, rejected and failed publishes and recording status leave the mark alone.
- **Fence with an epoch stamped when the scan begins (D3).** A value type `ScanEpoch(int modeTransition, int session)` (`lib/application/scan_epoch.dart`). `ScanCoordinator` takes an optional `ScanEpoch Function()? epoch` reader, defaulting to a constant. `AppServices` passes `() => ScanEpoch(_modeTransition, mapSession.state.sessionEpoch)`. `_begin` stores the reading on the scan, and the report copies it to a new nullable `ScanReport.epoch` field. At consumption the feed requires all of:
  1. `report.epoch` equals the current epoch;
  2. `report.catalogMode` equals `catalog.mode`;
  3. the item is in the current catalog snapshot.

  A failed check drops the scan from the decision path. Its evidence stays published. A `debugPrint` names the failed fence. The epoch is in memory only, so the timing log stays at schema v1.
- **History source `scan`, with no Drift migration (D6).** `ActivitySource` gains `scan`, stored as its name in the existing `ActivityRecords.source` text column. `schemaVersion` stays 2. `recordActivity` and `HistoryController.record` take a `source` parameter, defaulting to `manual`. A failed scan write sets the card error "Accepted scan was not recorded: local persistence failed." and keeps the decision shown. An older build reading a `scan` row throws in `byName`, so its history load shows an error and nothing is lost or rewritten.

## Rejected alternatives

- **Giving `ScanCoordinator` a `SelectionController` and calling it from `_publish` (D1).** It merges the evidence pipeline with decision state, puts a Drift write behind the latency-critical publish, and breaks the audit that keeps the coordinator the only file allowed to reference the capture and vision services. Reversal cost: low.
- **Having `SelectionController` listen to the scanner itself (D1).** Selection would then need the mode-transition and session state that `AppServices` owns, and its tests would need a coordinator. Reversal cost: low.
- **A per-notification diff of `latest` (D2).** `latest` changes on rejected and failed scans too, and a fenced scan would be seen again on the next notification. Reversal cost: low.
- **An event stream from the coordinator (D2).** It adds a second publication channel, with its own ordering, beside `notifyListeners`, for the same fact. Reversal cost: low.
- **Fencing on `report.catalogMode` alone (D3).** It misses a session change (a new raid or a game restart in the same mode), and strategy §6 says a session change must reset scan authority. Reversal cost: low.
- **Taking the epoch at publication (D3).** That is the moment that must be checked against, so it proves nothing. Reversal cost: low.
- **Writing scans as `manual` (D6).** History would lie about where an entry came from, and ADR-0003 keeps sources distinct. Reversal cost: medium, because the stored value is user data.
- **A separate scan-history table (D6).** It needs a migration and splits one-row-per-(item, mode) activity in two. Reversal cost: medium.

## Consequences

- **Accepted scans now drive keep/sell advice** through the one engine and the one caller (ADR-0001). Selection has three sources: manual, history and scan.
- **A fenced scan looks like "scan did nothing."** The evidence is still shown. Fences fire only across a mode or session change, which is rare during a scan. There is no retry, because a retry would advise from a context the trigger did not see.
- **A mode or session change retires the current scan** and resets FIR for every source.
- **Downgrades lose scan history visibility.** An older build cannot load history that holds `scan` rows, and the failure is a visible load error, not data loss. Builds are local-only until M6.
- **Reversal cost:** low for the feed, the id mark and the epoch (one class, one field, wired in one place, in memory only). Medium for the stored `scan` source, because relabelling user data needs a rewrite.
