# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code harness)
- **Reviewed:** proposal.md, design.md (TIER: FULL), specs/scan-latency-report/spec.md, specs/scan-pipeline/spec.md, specs/item-title-matching/spec.md, specs/scan-correction/spec.md; main specs openspec/specs/scan-pipeline, item-title-matching, scan-correction; openspec/roadmap.md (M4), docs/IMPLEMENTATION_STRATEGY.md §6 and §12; ADR-0013, 0017, 0018, 0019 (0014-0016 by reference in the design); source: lib/application/scan_coordinator.dart (PassTimeline, ScanReport.toLogLine, _passLine, _begin, _setPhase, _flow, _fallsBackAfterRejection, _finish, _conclude, _copyForRecording, _log, _publish), lib/application/scan_decision_feed.dart, lib/application/selection_controller.dart (correctionCandidates, selectScan), lib/domain/title_matching.dart (TitleMatchIndex.build, matchTitle, candidates assert), lib/domain/catalog.dart (noFlea), lib/ui/item_decision_card.dart (correction offer), lib/data/scan_timing_log.dart, tool/qualification/statistics.dart, test/qualification/support/inspection_corpus.dart (tally, compareWithBaseline), docs/qualification/m2/CORPUS.md, mise.toml. `openspec validate --strict` passes. Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis, flutter-add-widget-test.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

The core mechanics hold up against the code. `_publish` ends in `_notify()`, which is `ChangeNotifier.notifyListeners`. That call runs `ScanDecisionFeed._onSource` synchronously, and `selectScan` sets `_scan` before its first `await`. So the D1 order (publish, then `markDecided`, then `_log`) is sound. It keeps ADR-0013's single-writer rule and ADR-0017's rule that the coordinator never imports selection. The id check makes a stray call harmless. The nearest-rank examples in the report spec match `nearestRankQuantile` (N=20: rank 19 = 190 ms, rank 10 = 100 ms). The matcher rule is placed after the gates, so `belowSimilarity` and the existing near-tie results are unchanged. The shared-name rule itself is a user decision and is not re-litigated here.

### Critical (blocking)

None.

### Moderate

**M1. The intended coverage loss collides with a coverage gate written as "at least the reference's", and the design does not say how that gate is judged.**
- The roadmap M4 exit criterion requires corpus coverage "at least the reference's". Strategy §6 requires "Automatic coverage must be baseline-or-better ... removing difficult cases cannot satisfy ...", and §12 risk 1 requires "coverage ≥ baseline ... without hiding corrections".
- The corpus runner turns that into a hard check: `BaselineComparison.passed` requires `current.correct >= baseline.correct` (`test/qualification/support/inspection_corpus.dart:572-575`), and the test fails when it is false (CORPUS.md "Pass rule").
- The reference fork accepts the base-slug variant of a shared name. So any labelled case that expects that variant is "reference correct" and now ends `ambiguous`. That is a regression, and `passed` becomes false. Ammo packs are among the 46 shared groups, and the M2 corpus already contains an M855A1 ammo pack case (roadmap change 3).
- The design's only answer is "A regression that is a same-name group is recorded as intended, not as a gap" (Risks). That is an informal reinterpretation of a gate that the strategy, the roadmap and the test all state literally.
- Consequence: the agent-side corpus rerun will either report a failing criterion with no defined disposition, or quietly mark a failed gate as met. The latter is what `EVIDENCE.md` is meant to prevent.
- The user's decision covers the matcher rule. It does not say that the coverage gate is amended for it.

**M2. `CatalogItem.noFlea` is `bool?`, and D5 and the scan-correction delta only define `flea` or `no flea`.**
- `noFlea` is null when the catalog's `types` are missing (`lib/data/catalog_normalizer.dart:123`).
- The decision engine treats null as unknown and never as permission (`lib/domain/decision_engine.dart:370-371`). Strategy §6 also says "An unknown Flea restriction is never treated as explicit permission".
- A row label of `flea` for a null item would be a false factual claim on the one row the user reads to pick a variant. A shorter label could also make two variants look identical.
- The spec has no scenario for this case.

**M3. Same-name labelling covers only candidate rows, but groups of more than 5 can only be reached through search rows, which have no labels.**
- The design states that groups have "two to fifty items" and that candidates are capped at 5 (best plus 4 siblings, per the "More same-name items than fit" scenario).
- In a large group, the right variant is often not among the candidates. The user's only route is the offer's text search. It renders `Text(item.name)` only (`lib/ui/item_decision_card.dart:482-491`) and lists up to 8 items in ID order.
- So the user sees up to 8 identical names with no flea status or ID. Variants past the eighth cannot be reached unless the user types the ID.
- The design's main mitigation for the click cost ("the correction offer lists the variants, labelled by D5, one click away") therefore fails for exactly the groups where the rule fires most.

### Suggestions

**S1. Also report the fallback capture request as a "real fallback start" figure.**
- Strategy §6 says "A timeout label is not running fallback". The chosen figure, `ms.fallback.started`, is the moment the `fallback underway` label is published, before the fallback wait (ADR-0014).
- `ms.fallback.captureRequested` is already logged and marks when real fallback work begins.
- Showing its p95 next to `started` (informational, no new verdict) would show the gate's wording is met, at no schema cost.

**S2. Tighten the scan-pipeline delta wording.**
- (a) "A pass's start SHALL be the moment its phase ... is published." A pending scan that begins after a superseded one can find the phase already `targeted`. `_setPhase` then publishes nothing (`scan_coordinator.dart:2396`; the phase is reset only by `_publish` and `_abandonScans`). The design rightly stamps outside `_setPhase`, so the spec should say "the moment the pass begins, when its phase is set".
- (b) "appended ... after its publication and decision have been applied" should say "for a published scan", because superseded scans are never published.
- (c) "at about 120 ms" in "Fallback start before its wait" is exact under the fake clock the tests use. State the exact value so the THEN can be asserted.

**S3. Shared-name ambiguity always pays the full fallback.**
- An `ambiguous` targeted result falls back (`_fallsBackAfterRejection`, `:2528-2538`). So every scan of a shared-name item waits until 200 ms or later, runs a full-client job, and only then shows the offer, even though OCR cannot separate same-name variants.
- This is consistent with today's ambiguous handling, and the user accepted the click cost. But it delays the offer, and it adds these scans to the "total" stratum in the live session the protocol asks for ("including Weapon cases").
- Worth noting in `PROTOCOL.md` or `EVIDENCE.md` when the total figure is read. A short-circuit could be a later gap-closing change if the figures warrant it.

**S4. Define the UI comparison key.** D5 "counts display names" in the widget, while the spec defines display name as `normaliseTitle(item.name)`. Have the card use the same `normaliseTitle` (domain), not raw `item.name`, so the matcher and the UI agree on what counts as "the same name".

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **(M1)** In design.md, under Risks (coverage) and D6, replace "recorded as intended, not as a gap" with an explicit judging rule.
   - `EVIDENCE.md` records the corpus criterion from the unmodified `compareWithBaseline` result. Each regression whose expected item is in the best candidate's same-name group is listed separately, with its case ID, group and whether the expected item appears in the offer's candidates.
   - The criterion is not marked met on that basis. It stays `fail` or `unverified` until the user explicitly decides whether the M4 coverage criterion (roadmap; strategy §6/§12) is amended for same-name groups.
   - Add that decision to Open Questions as a user decision. Note that ADR-0021 records the amendment if the user makes it.
2. **(M2)** In design.md D5 and in specs/scan-correction/spec.md "Same-name candidates are told apart in the offer", define the label for `noFlea == null` (for example `flea unknown`). Add a scenario: two same-name candidates, one with unknown flea status, showing `flea unknown` and never `flea` for it.
3. **(M3)** In design.md D5 and in specs/scan-correction/spec.md, apply the same flea-status and short-ID labelling to the offer's search result rows whose display name another listed row (candidate or search result) shares. Add a scenario: a best candidate in a same-name group larger than 5, where the user finds a sixth variant through the search and its row is labelled.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

- M1: fixed, re-checked by reviewer (design.md D6 "Corpus judging rule", Risks coverage bullet, Open Questions user decision and ADR-0021 note).
- M2: fixed, re-checked by reviewer (design.md D5 `flea unknown`; scan-correction spec requirement and "Unknown flea status" scenario).
- M3: fixed, re-checked by reviewer (design.md D5 labels search rows too; scan-correction spec requirement and "Variant found through the search" scenario).
