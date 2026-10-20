# M4 qualification evidence

One row per M4 exit criterion ([roadmap](../../../openspec/roadmap.md)), with who verifies it, the result and its source. The live steps are in [PROTOCOL.md](PROTOCOL.md) and belong to the user. A criterion the user has not reported reads `unverified`, never passed.

Agent checks were run offline on `feat/qualify-scanner-latency`, 2026-10-20: `mise run analyze` found no issues and `mise run test` passed 1562 tests.

The user ran the live session (PROTOCOL steps 1-3) on 2026-10-20 with build `0.1.0+323` (`ffc0d02`). The agent computed the figures from the timing log afterwards, with the game closed; see "Live session" and "Latency report".

## Exit criteria

| # | Exit criterion | Verifier | Result | Source |
|---|---|---|---|---|
| 1 | The targeted pass accepts scans: in a live session at the user's resolution, with recording off, most accepts come from the targeted pass | user (agent reads the log) | **passed** (user session, 2026-10-20) | [`latency-report.json`](latency-report.json): mouse 47 of 63 accepts targeted (74.6%, verdict `pass`); hotkey 17 of 17 (100%, `indeterminate`: below 20 samples, accepted by the user). Supporting, not the criterion: the offline replay of 70 recorded frames accepted 39/39 full-client accepts in the targeted band too ([`fix-targeted-scan-region` evidence](../../../openspec/changes/archive/2026-10-17-fix-targeted-scan-region/evidence.md), PR #37) |
| 2 | An accepted scan, automatic or manual, produces one decision from the shared engine against the mode-correct catalog and session progress; unaccepted evidence never yields a recommendation and offers correction; fixture tests cover every precedence rule for scan input | agent | **passed** | `add-scan-decisions` (PR #39): `test/application/scan_decision_precedence_test.dart` ("every precedence rule matches the hand-selected decision"); `add-scan-correction` (PR #42): `test/ui/scan_correction_card_test.dart`, `test/application/selection_controller_test.dart`. This change: shared display names end `ambiguous` and offer a correction (`test/domain/title_matching_test.dart`, ADR-0021) |
| 3 | Latest-wins bursts, late completions, mode or session changes, correction, history selection and refresh cannot publish a stale decision, record a scan twice or advance the Map snapshot as a new accepted scan | agent | **passed** | Service tests: `test/application/scan_decision_feed_test.dart`, `selection_controller_test.dart`, `session_scan_state_test.dart`, `scan_coordinator_flow_test.dart` (PRs #39, #42, #46). This change keeps them green and adds "a fenced accepted scan is not marked decided" |
| 4 | Selecting a known mode starts one catalog refresh without blocking startup; a failed refresh keeps the last-good snapshot and does not retry in a loop | agent | **passed** | `add-catalog-startup-refresh` (PR #44): `test/application/app_services_refresh_test.dart`. The user's status-bar check after launch stays **unverified** |
| 5 | The global hotkey runs the same pipeline as the mouse trigger; a conflict shows the trigger unavailable and allows rebinding; the hotkey is unregistered on rebinding and shutdown | agent (state, fakes); user (live hotkey scan) | agent part **passed**; live hotkey scan **passed** (user, 2026-10-20) | `add-scan-hotkey-trigger` (PR #45): `test/application/scan_coordinator_hotkey_test.dart`, `windows/capture/unittest.cpp`. Live: 21 F9 scans in the session; the user reported F9 behaved the same as the mouse trigger. The native `selftest.cpp` hotkey rows were not run and stay **unverified** |
| 6 | Map shows the latest accepted scan in its one decision card, with no separate latest-scan panel, and scanning works with Map open | agent (state); user (live) | agent part **passed**; live part **passed** (user, 2026-10-20) | `add-map-scan-snapshot` (PR #46): `test/application/session_scan_state_test.dart`, `test/application/app_services_scan_test.dart`, `test/ui/map_screen_test.dart`. Live (PROTOCOL step 2.5): the user reported that with Map open its decision card followed the latest accepted scan |
| 7 | The reference timing baseline is recorded on the named Windows setup | user | **unverified** | Pending PROTOCOL steps 1 and 4 |
| 8 | From the timing log of a live session with recording off: targeted ≤300 ms p95 from trigger to decision, fallback visibly underway by about 300 ms, ≤1.5 s p95 total | user runs it; agent computes | **passed** (user session, agent figures, 2026-10-20) | Mouse: all three figures `pass` (targeted decided p95 139.6 ms, fallback underway p95 169.1 ms, total p95 572.4 ms). Hotkey: every figure inside its target but `indeterminate` below 20 samples; the user accepted these figures for the verdict rather than run a longer hotkey round. See "Latency report". Tooling built by this change: timing log v3 (ADR-0020; `test/application/scan_report_test.dart`, `scan_coordinator_flow_test.dart`, `scan_coordinator_wait_test.dart`, `scan_coordinator_recording_test.dart`) and the report `mise run qualification:scan-latency` (`test/qualification/scan_latency_report_test.dart`, `scan_latency_cli_test.dart`) |
| 9 | On the labelled corpus, coverage is at least the reference's and false positives are no worse, against the reference's outcomes on the same cases | agent, once the user has recorded the reference outcomes | **unverified (reference outcomes not recorded)** | Corpus restored and run (see "Corpus run"): 31/35 items, 0 false positives, 15/15 rejects, no baseline to compare. Judged under the rule below |

## Corpus judging rule (design D6)

- The corpus criterion is recorded from the unmodified `compareWithBaseline` result of `test/qualification/inspection_corpus_test.dart` (`test/qualification/support/inspection_corpus.dart`): `passed` requires `current.correct >= baseline.correct` and no more false positives, over the cases in both.
- Each regression whose expected item is in the best candidate's same-name group (ADR-0021) is listed separately, with its case ID, its group, and whether the expected item appears among the offer's candidates.
- The criterion is **not** marked met on that basis. It stays `fail`, or `unverified` while inputs are missing, until the user explicitly decides whether the M4 coverage criterion (roadmap; strategy §6 and §12) is amended for same-name groups. If it is, a superseding ADR records the amendment.

## Corpus

The original corpus folder `F:\Dev\Dart\blackgrid-corpus\inspection` was deleted. Its source recording, `%LOCALAPPDATA%\Blackgrid\scan-frames\20261014-122522`, survives: 50 lines in `frames.jsonl`, none with a null image or clipped.

**Rebuilt (agent, 2026-10-20).** The labels in [`corpus-labels-20261014-122522.json`](corpus-labels-20261014-122522.json) were proposed by the agent from the recording and the `fix-title-crop` evidence. The user confirmed them on 2026-10-20 after a brief review on the phone. `mise run qualification:build-corpus -- <recording> docs/qualification/m4/corpus-labels-20261014-122522.json F:\Dev\Dart\blackgrid-corpus\inspection` wrote `corpus.json` with 50 cases (35 items, 15 rejects) and the 50 full frames. `catalog.json` is the cached `json.tarkov.dev:seasonal` snapshot (revision `84555bf4…d986`, observed 2026-10-19, 5,480 items), exported as `docs/qualification/m2/REPLAY.md` describes, from a scratch copy of `blackgrid.sqlite` opened read-only. The recording was made in that mode. No `baseline.json` exists: the reference's outcomes are not recorded.

## Corpus run (task 6.4, agent, 2026-10-20)

Run offline after `tasklist` showed no `EscapeFromTarkov.exe`, `BsgLauncher.exe` or `blackgrid.exe`. Command: `mise exec -- flutter test --tags qualification test/qualification/inspection_corpus_test.dart` with `BLACKGRID_RELEASE_BUNDLE=build\windows\x64\runner\Release` and `BLACKGRID_CORPUS_DIR=F:\Dev\Dart\blackgrid-corpus\inspection`. It passed in 22 s; the report is `out\report.json` in the corpus folder.

**Unmodified result:** 35 item cases, 31 correct (coverage 0.886), **0 false positives**, and all 15 reject cases rejected. With no `baseline.json`, `compareWithBaseline` did not run, so the criterion stays `unverified` until the reference's outcomes are recorded (PROTOCOL step 5). For comparison only, the M2 run on the same 50 cases gave 31/35 with 2 false positives (roadmap, M2 close).

**Same-name regressions (D6), listed separately:** none against a baseline, since none exists. Cases 0012 and 0013 end `ambiguous` in the Weapon case group (`59fb023c86f7746d0d4b423c` flea-listable, `weapon-case`; `6a997c6e21aaf68dc6045d88` no flea, `weapon-case-1`). The expected no-flea Weapon case is the runner-up at .909 and the second candidate of the offer. In M2 these two cases were the 2 false positives (the flea-listable case was accepted). They are misses now, not false positives, as ADR-0021 intends.

**Other misses, investigated:**

| Case | Expected | Outcome | Cause |
|---|---|---|---|
| 0007 | ANA Tactical M1 plate carrier (OD Green) (`5c0e722886f7740458316a57`) | `ambiguous` | OCR read the title exactly; the best is the expected item at 1.0, but the M2 variant scores .974, inside the .05 margin gate. Not a same-name group. A known M2 miss (roadmap change 3); the expected item is offered as the first candidate |
| 0051 | 5.56x45mm M855A1 ammo pack (100 pcs) (`65702652cfc010a0f5006a53`) | `ambiguous` | OCR read `5.56x45mm M85SA1 ammo pack (188 pcs)`; the expected item and the M856A1 pack tie at .893 (margin 0). Not a same-name group (its display name is unique in the catalog). A known M2 miss; the expected item is offered as the first candidate |

No false positive remains to investigate.

## Live session (user, 2026-10-20)

Setup (PROTOCOL step 1), from the user's report:

```json
{
  "record_type": "environment",
  "setup_alias": "warzone-3440",
  "hardware": { "cpu": "Intel Core i7-13700K", "gpu": "NVIDIA GeForce RTX 4080", "ram_bytes": 68464529408 },
  "windows": { "version": "Windows 11 Pro 10.0.26200", "architecture": "x64" },
  "runtime": { "sdk": "Flutter 3.47.6" },
  "app_build": { "id": "ffc0d02", "version": "0.1.0+323" },
  "display": { "width": 3440, "height": 1440, "os_scale_percent": 100, "origin": { "x": 0, "y": 0 }, "topology": "two monitors; primary 3440x1440 on the right, secondary to its left" },
  "viewport": { "width": 3440, "height": 1440, "client_width": 3440, "client_height": 1440, "ui_scale": 1.0 },
  "observer": null,
  "locale": "en",
  "display_mode": "borderless",
  "warm_state": "warm"
}
```

The user scanned items in the stash with recording off, from about 15:22 to 15:27 UTC, with both the mouse and F9, and some scans with Map open. The agent did not touch the app or the game during the session.

What the user reported:
- F9 behaved the same as the mouse trigger.
- With Map open, its decision card followed the latest accepted scan.
- Weapon case: the user owns only the no-flea variant, and the flea-listable one cannot be bought on the flea, so whether the `flea` / `no flea` labels tell the variants apart was **not tested**. The scans ended `ambiguous` and offered both cases (the flea-listable `…4b423c` ranked first at 1.0, the no-flea `…045d88` at .909), as ADR-0021 intends; before ADR-0021 this was a false positive.

What the agent read in the log (no pixels or item images are kept):
- 36 mouse and 4 hotkey scans were `rejected`. 29 of them ended with no inspect-window marker (marker scores .55-.78), most likely releases that opened no inspect window; that was not checked with the user.
- The other rejects were shared names that ended `ambiguous`, as ADR-0021 intends: the Weapon case (2 mouse, 2 hotkey), dogtags, the Medicine case and one other shared-name pair. One ammo-pack near-tie (OCR read `128 pcs` as `128 pes`) ended `ambiguous` too.
- Some targeted passes read the stash's `FILTER BY ITEM` button instead of the title and fell back to the full-client pass, which recovered the title. This is a follow-up candidate for the targeted region, not a verdict issue: those scans count in the fallback and total figures.

## Latency report

`mise run qualification:scan-latency -- --since 2026-10-20T15:22:00Z --until 2026-10-20T15:27:44Z --out <temp> <scan-timings.jsonl>`, run by the agent offline; the output is [`latency-report.json`](latency-report.json). The window held 142 v3 lines, none with recording on, and 0 dropped triggers. 1,318 older lines in the same log (before v3) were skipped as an unsupported version.

| Trigger | Figure | N | p50 | p95 | max | Target | Verdict |
|---|---|---|---|---|---|---|---|
| mouse | targeted share of accepts | 63 | | 74.6% | | > 50% | pass |
| mouse | targeted trigger to decision (ms) | 47 | 116.4 | 139.6 | 150.4 | ≤ 300 | pass |
| mouse | trigger to fallback underway (ms) | 52 | 134.7 | 169.1 | 175.2 | ≤ 300 | pass |
| mouse | total, trigger to decision (ms) | 52 | 480.6 | 572.4 | 614.9 | ≤ 1500 | pass |
| hotkey | targeted share of accepts | 17 | | 100% | | > 50% | indeterminate (N < 20) |
| hotkey | targeted trigger to decision (ms) | 17 | 62.8 | 78.0 | 78.0 | ≤ 300 | indeterminate (N < 20) |
| hotkey | trigger to fallback underway (ms) | 4 | 61.7 | 72.0 | 72.0 | ≤ 300 | indeterminate (N < 20) |
| hotkey | total, trigger to decision (ms) | 4 | 214.7 | 332.3 | 332.3 | ≤ 1500 | indeterminate (N < 20) |

Mouse: 121 scans (63 accepted, 36 rejected, 22 superseded). Hotkey: 21 scans (17 accepted, 4 rejected). For information, "real fallback work began" (the fallback capture request) has a mouse p95 of 201.7 ms.

The hotkey stratum fell short of the protocol's 20 samples (17 accepts, 4 fallbacks), so the report gives no hotkey verdict. On 2026-10-20 the user decided not to run a longer hotkey round and to use these figures for the criterion. Every hotkey figure is well inside its target.

## User decisions open at M4 close

- Whether the corpus coverage criterion is amended for same-name groups (ADR-0021, design Open Questions).
- The reference timing baseline (row 7, PROTOCOL step 4) and the reference corpus outcomes (row 9, PROTOCOL step 5) are not recorded. Both rows stay unverified until the user records them or explicitly waives them, as M2 waived its reference comparison.

Decided: on 2026-10-20 the user accepted the hotkey figures (below 20 samples) for row 8, instead of running a longer hotkey round.
