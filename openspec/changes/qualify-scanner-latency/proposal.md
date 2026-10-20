# Proposal

## Why

M4 (complete raid-time Scanner slice) cannot close until its latency and coverage gate has evidence, and today there is none.

- **Latency.** The timing log (`scan-timings.jsonl`, schema v2) has no reader, and it cannot answer two of the gate's questions:
  - it does not record when Scanner shows `fallback underway`, which is the "fallback visibly underway by about 300 ms" figure;
  - it does not record when an accepted scan's decision was applied, which is the "trigger to decision" figure;
  - it does not say whether frame recording was on, so a "recording off" session cannot be checked from the log.
- **Coverage.** No reference timing baseline or reference corpus outcomes exist, and the labelled corpus is not on this machine.
- **False positive.** The corpus has one standing false positive. Scans 0012/0013 are the no-flea Weapon case, but the scanner accepts the flea-listable Weapon case. Both items are named "Weapon case" in game, so no OCR improvement can separate them. The matcher picks the flea-listable one because the catalog gives the other the slug `weapon-case-1`. The current catalog has 46 such shared display names: ammo packs, cases, dogtags, gear crates, Twitch drop cases.

This is M4 change 7. It serves these M4 exit criteria:
- the targeted pass accepts most scans;
- the reference timing baseline is recorded;
- targeted scans reach a decision within 300 ms p95 from the trigger, the fallback is visibly underway by about 300 ms, and scans finish within 1.5 s p95 in total;
- corpus coverage is at least the reference's, and false positives are no worse.

It needs changes 1-6, all merged.

## What Changes

- **Timing log v3.** The line gains three things, and `"v"` becomes 3:
  - a `started` stage per pass, stamped when that pass's phase is published (the fallback pass's `started` is when `fallback underway` appears);
  - `ms.decided`, stamped after an accepted scan's publication has been applied to the selection and decision;
  - a top-level `recording` flag, saying whether frame recording was on when the scan was triggered.

  Nothing else in the line changes.
- **Scan latency report.** A new offline command, `tool/qualification/scan_latency.dart`, with a mise task. It reads `scan-timings.jsonl` and `scan-timings.1.jsonl` (v2 and v3) over a UTC window. It reports:
  - counts by trigger, pass and end;
  - the targeted share of accepts;
  - nearest-rank p50 and p95 for targeted trigger-to-decision, trigger-to-`fallback underway` and total trigger-to-publication.

  It reports each figure against its target as pass, fail or indeterminate. Lines with recording on are excluded and counted. v2 lines use stated proxies and are marked as such.
- **Shared display names are ambiguous.** When the best candidate's display name is shared by another catalog item, the match ends `ambiguous` instead of accepted. The same-name items are listed as candidates. The scan then offers a correction instead of a recommendation that may name the wrong variant.
- **Correction rows tell same-name variants apart.** A row whose name another listed candidate shares shows the item's flea status and a short ID.
- **M4 qualification protocol and evidence.** New files under `docs/qualification/m4/`:
  - the live-session steps for the user: recording off, mouse and hotkey, the named setup;
  - how the user records the reference timing baseline and the reference's corpus outcomes (`baseline.json`) using the existing recipe;
  - an evidence file that records each M4 exit criterion with who verified it. Anything the user has not run is recorded as unverified.
- **Coverage investigation.** Once the user restores the corpus, the agent reruns it with the new matcher rule. Any coverage gap is investigated and recorded, with 0012/0013 expected to become ambiguous rejects that offer a correction.

## Capabilities

### New Capabilities
- `scan-latency-report`: the offline report over the scan timing log. It covers which lines count, the strata, the p95 method, targets and verdicts, how v2 proxies are handled, and how recording-on lines are excluded.

### Modified Capabilities
- `scan-pipeline`: the timing log line moves to schema v3, with per-pass `started`, `ms.decided` and `recording`.
- `item-title-matching`: a best candidate whose display name is shared by another indexed item is `ambiguous`, and its same-name items are among its candidates.
- `scan-correction`: offer rows for candidates that share a display name show flea status and a short ID.

## Impact

- **Code:**
  - `lib/application/scan_coordinator.dart`: pass `started` stamps, `decided` after publication, `recording` on the report, and the v3 line;
  - `lib/domain/title_matching.dart`: the shared-display-name rule and sibling candidates;
  - the scan correction offer widget;
  - new `tool/qualification/scan_latency.dart`, reusing `tool/qualification/statistics.dart` (`nearestRankQuantile`);
  - `mise.toml`.
- **Tests:**
  - coordinator timing tests;
  - title-matching tests (Weapon case, ammo packs);
  - correction offer widget test;
  - report unit tests over small synthetic JSONL;
  - the corpus support tests stay offline.
- **ADR:** a new ADR covers timing log v3 and the shared-display-name rule. ADR-0013 and ADR-0019 require an ADR for a log key change. The matcher rule is stricter than the reference fork on purpose.
- **Behaviour users see:**
  - scanning one of the 46 shared-name items, such as a flea-listable Weapon case, now offers a correction instead of accepting at once;
  - the timing log's `v` changes to 3;
  - there is no change to the hotkey, capture, regions or waits.
- **Live checks belong to the user:** the live session, the reference timing baseline and the reference corpus outcomes. Until the user reports them, their criteria stay unverified.
