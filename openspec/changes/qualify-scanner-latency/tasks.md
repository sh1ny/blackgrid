# Tasks

**Implementer packets.** Each packet carries:
- the AGENTS.md "Dart and Flutter code" section;
- the skills `dart-add-unit-test`, `dart-write-documentation` and `dart-use-pattern-matching`, plus `flutter-add-widget-test` for group 4.

**Checks.**
- Every check is offline: `mise run analyze` and `mise run test`. No task launches Blackgrid, the reference companion or the game.
- The live session, the reference timing baseline and the reference corpus outcomes belong to the user (group 6). They are recorded as unverified until the user reports them.

**Review suggestions carried in:**
- S1: the fallback capture-request p95 is an informational figure (task 3.3).
- S3: shared-name scans pay the full fallback; noted in the protocol (task 6.1).
- S4: `normaliseTitle` is the UI comparison key (task 4.2).

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Best and runner-up are chosen deterministically | Duplicate names | test/domain/title_matching_test.dart | duplicate normalised names keep the smaller id and skip runner-up | red |
| Best and runner-up are chosen deterministically | Distinct names tie | test/domain/title_matching_test.dart | distinct names at equal score give margin 0 | green |
| Best and runner-up are chosen deterministically | Ranked candidates | test/domain/title_matching_test.dart | candidates are the top five distinct names, best then runner-up | green |
| Best and runner-up are chosen deterministically | Duplicate names in the candidates | test/domain/title_matching_test.dart | duplicate normalised names appear once in the candidates | red |
| Best and runner-up are chosen deterministically | Same display name in the candidates | test/domain/title_matching_test.dart | same display name items follow the best, runner-up unchanged | red |
| Best and runner-up are chosen deterministically | Fewer candidates than five | test/domain/title_matching_test.dart | a two-item index gives two candidates | green |
| Best and runner-up are chosen deterministically | Rejected before scoring | test/domain/title_matching_test.dart | results rejected before scoring carry no candidates | green |
| Best and runner-up are chosen deterministically | Quantity restriction | test/domain/title_matching_test.dart | quantity restriction limits the candidates | green |
| A best candidate sharing its display name is ambiguous | Weapon case variants | test/domain/title_matching_test.dart | Weapon case variants are ambiguous | red |
| A best candidate sharing its display name is ambiguous | Equal normalised names | test/domain/title_matching_test.dart | equal normalised names sharing a display name are ambiguous | red |
| A best candidate sharing its display name is ambiguous | Unique display name | test/domain/title_matching_test.dart | a unique display name is accepted as before | red |
| A best candidate sharing its display name is ambiguous | Shared name below the gate | test/domain/title_matching_test.dart | a shared name below the gate stays belowSimilarity | red |
| Same-name items are listed among the candidates | Two variants | test/domain/title_matching_test.dart | same-name variants lead the candidates | red |
| Same-name items are listed among the candidates | More same-name items than fit | test/domain/title_matching_test.dart | a 50-item same-name group lists the best and four by id | red |
| Same-name candidates are told apart in the offer | Weapon case variants | test/ui/scan_correction_card_test.dart | same-name candidates show flea status and id suffix | red |
| Same-name candidates are told apart in the offer | Only one listed same-name item | test/ui/scan_correction_card_test.dart | a lone same-name candidate shows name and score only | red |
| Same-name candidates are told apart in the offer | Unknown flea status | test/ui/scan_correction_card_test.dart | unknown flea status shows flea unknown | red |
| Same-name candidates are told apart in the offer | Variant found through the search | test/ui/scan_correction_card_test.dart | a search row in a same-name group is labelled | red |
| Same-name candidates are told apart in the offer | Picking a variant | test/ui/scan_correction_card_test.dart | picking the no-flea variant selects it | red |
| The report reads timing log files over a UTC window | Two files, one window | test/qualification/scan_latency_report_test.dart | two files are read over one window | red |
| The report reads timing log files over a UTC window | Malformed and unknown lines | test/qualification/scan_latency_report_test.dart | malformed and unsupported lines are skipped by reason | red |
| The report reads timing log files over a UTC window | Missing file | test/qualification/scan_latency_cli_test.dart | a missing input exits non-zero and writes nothing | red |
| Only v3 lines with recording off drive verdicts | Recording-on lines excluded | test/qualification/scan_latency_report_test.dart | recording-on lines are excluded and counted | red |
| Only v3 lines with recording off drive verdicts | Only v2 lines | test/qualification/scan_latency_report_test.dart | v2 lines give proxies and indeterminate verdicts | red |
| Figures are computed per trigger source | Nearest rank | test/qualification/scan_latency_report_test.dart | nearest-rank p50, p95 and max over twenty samples | red |
| Figures are computed per trigger source | Superseded scans | test/qualification/scan_latency_report_test.dart | superseded scans are counted, not sampled | red |
| Figures are computed per trigger source | No hotkey scans | test/qualification/scan_latency_report_test.dart | an empty hotkey stratum is indeterminate | red |
| The report states the targeted share of accepts | Most accepts targeted | test/qualification/scan_latency_report_test.dart | targeted share above half passes | red |
| The report states the targeted share of accepts | Half targeted | test/qualification/scan_latency_report_test.dart | targeted share of exactly half fails | red |
| The report states each latency figure against its target | All figures pass | test/qualification/scan_latency_report_test.dart | all latency figures pass under target | red |
| The report states each latency figure against its target | Targeted decision too slow | test/qualification/scan_latency_report_test.dart | slow targeted decision fails | red |
| The report states each latency figure against its target | Failed scan counts toward total | test/qualification/scan_latency_report_test.dart | a failed fallback scan is a total sample | red |
| The report states each latency figure against its target | Accepted scan without a decision | test/qualification/scan_latency_report_test.dart | an accept without decided is counted, not sampled | red |
| Too few samples give no verdict | Small sample | test/qualification/scan_latency_report_test.dart | fewer than twenty samples is indeterminate | red |
| Too few samples give no verdict | Exactly twenty | test/qualification/scan_latency_report_test.dart | exactly twenty samples gives a verdict | red |
| The report is written as JSON and as a readable summary | Report written | test/qualification/scan_latency_cli_test.dart | report json and console table carry the verdicts | red |
| The report is written as JSON and as a readable summary | Output exists | test/qualification/scan_latency_cli_test.dart | an existing output is kept without --force | red |
| Every scan records stage timings | Accepted targeted scan timings | test/application/scan_coordinator_flow_test.dart | accepted targeted scan records start, stages, publication and decision in order | red |
| Every scan records stage timings | Fallback wins | test/application/scan_coordinator_flow_test.dart | fallback start precedes its capture request | red |
| Every scan records stage timings | Fallback start before its wait | test/application/scan_coordinator_wait_test.dart | fallback start is stamped before the fallback wait | red |
| Every scan records stage timings | Scan ended early | test/application/scan_coordinator_flow_test.dart | early capture failure leaves later stages absent | red |
| Every scan records stage timings | Accepted scan that drives no decision | test/application/scan_decision_feed_test.dart | a fenced accepted scan is not marked decided | red |
| Each finished scan is logged as one JSON line | Accepted scan line | test/application/scan_report_test.dart | accepted fallback report encodes v3 with started and decided | red |
| Each finished scan is logged as one JSON line | Hotkey scan line | test/application/scan_report_test.dart | hotkey report encodes trigger hotkey | red |
| Each finished scan is logged as one JSON line | Recording on | test/application/scan_coordinator_recording_test.dart | recording on at scan start marks the line | red |
| Each finished scan is logged as one JSON line | Recording turned on mid-scan | test/application/scan_coordinator_recording_test.dart | recording turned on mid-scan marks the line | red |
| Each finished scan is logged as one JSON line | Rejected scan line | test/application/scan_report_test.dart | rejected report has fallback started and no decided | red |
| Each finished scan is logged as one JSON line | Superseded scan line | test/application/scan_report_test.dart | superseded report encodes only the stages reached | red |

## 1. ADRs

- [x] 1.1 Write `docs/adr/0020-scan-timing-log-v3.md` (design D1, D2):
  - pass `started`;
  - `decided` reported back through `AcceptedScanSource.markDecided` with the report-id check;
  - the sticky `recording` flag;
  - the log appended after publication;
  - `Supersedes: 0019`, its "Timing log v2" bullet only.

  Write `docs/adr/0021-shared-display-names-are-ambiguous.md` (D4, D5):
  - the matcher rule;
  - the same-name candidate listing;
  - the offer labels, including `flea unknown`;
  - stricter than the reference fork on purpose, decided by the user on 2026-10-20;
  - the open coverage-criterion decision from design Open Questions;
  - `Supersedes: 0018`, its distinct-name top 5 bullet, for same-name groups only.

  Both use `Status: accepted` and today's date. Add both rows to the in-force index in `openspec/architecture.md`, and add "partly superseded" notes to the 0018 and 0019 rows. Verify by reading the index: both new rows are present, and no accepted ADR file is edited.

## 2. Timing log v3 in the coordinator

- [ ] 2.1 Write the failing tests:
  - in `test/application/scan_report_test.dart`, the v3 line rows, updating the existing `"v":2` assertions to 3;
  - in `scan_coordinator_flow_test.dart` and `scan_coordinator_wait_test.dart`, the stage rows. The fallback-start test uses the fake clock and asserts an exact `started` (S2c) and a `captureRequested` of at least 200 ms;
  - in `scan_coordinator_recording_test.dart`, the recording rows;
  - in `scan_decision_feed_test.dart`, the fenced row, with a fake source that records `markDecided` calls.

  Confirm they fail for the missing keys or method.
- [ ] 2.2 Implement D1 and D2:
  - `PassTimeline.started`, stamped in `_begin` and at the fallback phase change, outside `_setPhase`;
  - `AcceptedScanSource.markDecided(int reportId)`, implemented by `ScanCoordinator` with the id check;
  - `ScanDecisionFeed._applyAccepted` calls it where it advances `SessionScanState`;
  - `_finish` reorders to publish first, then log;
  - a per-scan sticky `recording` flag;
  - `toLogLine` writes `"v":3`, `ms.<pass>.started`, `ms.decided` and `recording`.

  Update doc comments, including the `toLogLine` key list. Update the fake `AcceptedScanSource` implementations in the tests. Verify that the 2.1 tests pass, and flip their rows green.
- [ ] 2.3 Add a test proving that a listener throwing inside the publish notify still leaves exactly one log line, with no `decided` (design Failure table). Verify it passes.
- [ ] 2.4 Update the `ScanCoordinator` and `ScanDecisionFeed` rows of `openspec/architecture.md` (v3, `markDecided`, log after publish). Verify by reading the diff: no remaining "schema v2" claim for the live line.

## 3. Scan latency report

- [ ] 3.1 Write `test/qualification/scan_latency_report_test.dart` over small synthetic JSONL strings built in the test, one per report-spec row. These are plain unit tests with no `qualification` tag, like `m0_statistics_test.dart`. Confirm they fail because the library does not exist.
- [ ] 3.2 Implement `tool/qualification/scan_latency_report.dart` (D3):
  - pure parse, classify and summarise;
  - per-trigger strata;
  - `nearestRankQuantile` from `statistics.dart`;
  - the targets and the 20-sample floor, each stated once as a constant;
  - the v2 proxy section;
  - skip and exclusion counts.

  Verify that 3.1 passes, and flip its rows green.
- [ ] 3.3 Add the informational fallback `captureRequested` p95 per trigger (review S1). It has no verdict and is labelled "real fallback work began". Test it in the same file. Verify it passes.
- [ ] 3.4 Write `test/qualification/scan_latency_cli_test.dart`. It runs the CLI's `main` function in-process on temporary files and covers the missing-file, report-written and output-exists rows. Then implement `tool/qualification/scan_latency.dart`:
  - `--since`, `--until`, `--out`, `--force` and file arguments;
  - the JSON output;
  - the console table;
  - a non-zero exit on usage or IO errors.

  Add the mise task `qualification:scan-latency`. Verify that the CLI tests pass, and flip their rows green.

## 4. Shared display names in matching and correction

- [ ] 4.1 Write the failing matcher tests in `test/domain/title_matching_test.dart`:
  - the new rows;
  - the Weapon case fixture: names, `normalizedName` `weapon-case`/`weapon-case-1`, title "Weaponcase";
  - the 50-item group.

  Rewrite "duplicate normalised names keep the smaller id and skip runner-up" so it expects `ambiguous` with best `a1`, and `b2` not the runner-up. Rewrite "duplicate normalised names appear once in the candidates" with differing raw names, per the modified scenario. Confirm they fail.
- [ ] 4.2 Implement D4 in `lib/domain/title_matching.dart`:
  - display-name groups built once in `TitleMatchIndex.build`;
  - after-gate conversion to `ambiguous`;
  - the same-name candidate listing, capped at 5;
  - the candidates assert relaxed only for that case.

  Update the doc comments. Verify that 4.1 passes, and that `title_matching_benchmark_test.dart` (`mise run test:qualification` if available, else note as not run) still meets ≤ 20 ms p95. Flip the rows green.
- [ ] 4.3 Write the failing widget tests in `test/ui/scan_correction_card_test.dart`:
  - Weapon case variants labelled;
  - lone same-name candidate unlabelled;
  - `flea unknown`;
  - a labelled search row in a 12-item group;
  - picking the no-flea row selects it.

  Then implement D5 in `lib/ui/item_decision_card.dart`: compare display names with `normaliseTitle` (S4) across candidates and search results, and label shared rows `'<name> · <flea status> · <last 6 of id>'`. Verify that the tests pass, and flip the rows green.
- [ ] 4.4 Run the offline corpus support tests (`test/qualification/inspection_corpus_support_test.dart`) and `test/qualification/targeted_region_replay_support_test.dart`. Verify that both pass unchanged.

## 5. Integration check

- [ ] 5.1 Run `dart format`, `mise run analyze` and `mise run test`. Verify that all pass with no new analyzer issues and every test-map row is green.

## 6. M4 qualification protocol and evidence

- [ ] 6.1 Write `docs/qualification/m4/PROTOCOL.md` (D6). It holds:
  - the named setup block;
  - recording off;
  - at least 40 mouse and 20 hotkey scans of mixed items, including a Weapon case, with a note that shared-name scans pay the full fallback before the offer (S3);
  - `mise run qualification:scan-latency -- --since <utc> --out <file> <logs>`;
  - the reference timing baseline via `tool/qualification/reference/instrumentation-recipe.md`;
  - restoring the corpus and writing the reference's outcomes to `baseline.json` (`docs/qualification/m2/CORPUS.md`).

  It says agents never run the live steps. Verify by reading it against the M4 exit criteria in `openspec/roadmap.md`: each user-verified criterion has a step.
- [ ] 6.2 Write `docs/qualification/m4/EVIDENCE.md`: one row per M4 exit criterion, with its verifier, its result and its source.
  - Fill the agent-verified rows from this change and changes 1-6. Cite the archived change evidence and the tests.
  - Mark every user-verified row `unverified`.
  - Mark the corpus row `unverified (corpus not restored; reference outcomes not recorded)`, with D6's judging rule written out.

  Verify that no user-verified row reads passed.
- [ ] 6.3 Rebuild the labelled corpus from the surviving recording. The original `F:\Dev\Dart\blackgrid-corpus\inspection` was deleted; its source recording is `%LOCALAPPDATA%\Blackgrid\scan-frames\20261014-122522`.
  - Write `tool/qualification/build_corpus.dart` with the mise task `qualification:build-corpus`. It takes a recording folder, a labels file and an output folder, and writes `corpus.json` plus copies of the full frames, as `docs/qualification/m2/CORPUS.md` describes. It refuses a non-empty output folder and refuses labels whose `status` is not `confirmed`, and every recorded line must have exactly one label.
  - Add plain unit tests over a 2-case synthetic recording (tiny PNG stand-ins).
  - The labels are `docs/qualification/m4/corpus-labels-20261014-122522.json`. They were proposed by the agent on 2026-10-20 from the recording and the fix-title-crop evidence, and stay `proposed` until the user confirms them; only the user's confirmation sets `confirmed`.
  - Build the corpus to `F:\Dev\Dart\blackgrid-corpus\inspection`, outside Git.

  Verify that the tests pass and that the built `corpus.json` has 50 cases (35 items, 15 rejects). If the labels are still `proposed`, record "blocked: labels await user confirmation" in `EVIDENCE.md` instead.
- [ ] 6.4 If the corpus folder is available (`BLACKGRID_CORPUS_DIR` set and present), run `mise run test:qualification` for `inspection_corpus_test.dart` with the release bundle. Record in `EVIDENCE.md`:
  - the unmodified result;
  - same-name regressions listed separately, per D6;
  - an investigation note for each other miss or false positive (cases 0012/0013 expected to become `ambiguous` with the no-flea Weapon case among the candidates).

  If the corpus is not available, record "not run: corpus not on this machine" and leave the row `unverified`. Verify by reading the row: it states one of the two outcomes.

## Workflow follow-up

- The user runs the live session, records the reference timing baseline and restores the corpus with the reference's outcomes. The agent then runs the report and the corpus comparison and updates `EVIDENCE.md`. That can be done at M4 **close** without reopening this change.
- At M4 close, the user decides whether the coverage criterion is amended for same-name groups (design Open Questions).
- Follow-up idea (user chose 2026-10-20 to keep this plan): the inspect window shows a "CANNOT BE LISTED ON FLEA MARKET" banner on no-flea items (frames 20261014-122522-0012 and -0037). Detecting it could resolve same-name pairs whose flea status differs without a correction click. Candidate for M4.5 or a follow-up change; groups with equal flea status still need the ambiguous rule.
- The corpus labels in `docs/qualification/m4/corpus-labels-20261014-122522.json` stay `proposed` until the user confirms them; task 6.3 is blocked until then.
