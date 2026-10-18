# 0018 - Scan correction is transient selection state

- Status: accepted
- Date: 2026-10-18 (M4 change `add-scan-correction`)
- Supersedes: none
- Source: change `add-scan-correction` (design D1, D2, D3, D4, D8); [implementation strategy §6](../IMPLEMENTATION_STRATEGY.md#6-scanner-strategy)

## Context and problem

When a scan is not accepted (`ambiguous` or `belowSimilarity`), the user can pick the right item by hand. Change 5's Map snapshot reads accepted-scan state ([ADR-0017](0017-accepted-scans-feed-the-decision-engine.md)), so a pick must not look like a new accepted scan. Five things have to be fixed together:

- who owns the correction offer, and how it reaches selection without the coordinator referencing selection or history ([ADR-0013](0013-scan-pipeline-coordination.md));
- what selection source a picked correction becomes;
- what history stores for it;
- where the candidate names come from;
- how the feed reads the latest scan report, accepted or not.

## Decision

- **The offer is selection state, fed by the existing feed (D1).** `SelectionController` owns the current `ScanCorrectionOffer` and is its only writer (`offerCorrection`, `setCorrectionQuery`, `selectCorrection`, `dismissCorrection`, and clearing in `selectManual`, `selectScan`, `openHistory` and `retireScan`). `closeHistory` keeps the offer. `ScanDecisionFeed` builds offers from `AcceptedScanSource.latest` through `correctionOfferFor`, behind the epoch and mode fences, with its own offer high-water mark `_offered`, and calls `offerCorrection`. The coordinator still imports neither selection nor history.
- **A correction is its own selection source, never an `AcceptedScan` (D2).** A pick sets an immutable `ScanCorrection` record (report id, item, mode, catalog revision, `correctedAt`, epoch). `selection.scan` stays null. `selectedId` resolves by precedence: history row, scan, correction, manual. `retireScan` retires a correction like a scan. **Binding rule: only accepted reports from `AcceptedScanSource` may advance the Map snapshot (M4 change 5).** A correction never does.
- **History records a correction as `manual` (D3).** `history.record(itemId, liveMode, correctedAt)` uses the default source. No OCR text, candidates or correction record is stored. A failed write sets "Correction was not recorded: local persistence failed." and keeps the decision shown.
- **The matcher keeps a distinct-name top 5 (D4).** `TitleMatch` gains `candidates`: up to 5 `TitleCandidate(id, score)` (`maxTitleCandidates`), distinct normalised names, ranked by score then ID, from the same pool as best. It is filled in the same `matchTitle` call off the UI isolate. `candidates[0]` is the best and `candidates[1]` the runner-up. The default is `const []`, so existing call sites compile unchanged. No stored format changes.
- **`AcceptedScanSource` exposes `latest` (D8).** The interface gains `ScanReport? get latest`, which `ScanCoordinator` already implements. The interface name stays.

## Rejected alternatives

- **A separate `ScanCorrectionController` (D1).** Every selection path would have to clear it through a second controller, giving two writers whose ordering must agree. A scan accepted between "selection changed" and "offer cleared" could leave an offer beside the wrong item. Reversal cost: medium.
- **Calling `selectScan` with a flag, or building an `AcceptedScan` (D2).** Change 5's Map snapshot and the "Accepted scan" card read accepted-scan state, so a correction would pass as a new accepted scan. Routing through `selectManual` was also rejected: the card could not label it, and it would survive a session change. Reversal cost: medium.
- **A new `ActivitySource.correction` (D3).** History could tell corrections apart, but older builds fail to load the row, and nothing reads the distinction yet. Reversal cost: low, because adding it later is additive by name with no migration.
- **Re-scoring the OCR text against the catalog on the UI isolate (D4).** It duplicates the quantity and duplicate-name rules and costs a full Levenshtein pass on the isolate that ADR-0012 freed. Offering only best and runner-up was also rejected, because a third close variant could not be picked. Reversal cost: low.
- **A second interface and listener on the coordinator (D8).** Both would fire on the same notify, and the feed would have to merge them in order. Reversal cost: low.

## Consequences

- **Selection has four sources:** manual, history, scan and correction. A correction is retired by a mode or session change and by any newer selection.
- **Corrections are memory-only.** After a restart only the `manual` history row survives, and history cannot tell it from a hand pick.
- **Change 5 relies on the binding rule.** A Map snapshot reducer that read `selection.correction` would break it.
- **Reversal cost:** medium for the selection ownership and the distinct source, because change 5 and M4.5's plain-language pass read them. Low for `manual` history, `candidates` and the `latest` getter.
