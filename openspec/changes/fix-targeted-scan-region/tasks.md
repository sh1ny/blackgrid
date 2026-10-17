# Tasks

Dart work follows the "Dart and Flutter code" section of [AGENTS.md](../../../AGENTS.md). Load these skills before writing code: `dart-use-pattern-matching`, `dart-write-documentation`, `dart-add-unit-test` and `dart-run-static-analysis`. Verify with `mise run analyze` and `mise run test`, and format with `dart format`.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| inspection-capture → Targeted region is planned in physical client pixels | Sixteen resolution and scaling cells | test/data/capture/capture_geometry_test.dart | targeted region for all 16 resolution and DPI cells | red |
| inspection-capture → Targeted region is planned in physical client pixels | Region does not follow the cursor | test/data/capture/capture_geometry_test.dart | targeted region is the same for any in-client point | red |
| inspection-capture → Targeted region is planned in physical client pixels | Client taller than 16:9 | test/data/capture/capture_geometry_test.dart | targeted region on a 1920x1200 client starts at the top | red |
| inspection-capture → Targeted region is planned in physical client pixels | Non-integral scale | test/data/capture/capture_geometry_test.dart | targeted region on a 1366x768 client floors each term | red |
| inspection-capture → Targeted region is planned in physical client pixels | Click on a negative-origin monitor | test/data/capture/capture_geometry_test.dart | negative-origin monitor maps to client and back | red |
| inspection-capture → Targeted region is planned in physical client pixels | Trigger point outside the client | test/data/capture/capture_geometry_test.dart | trigger outside client is roiOutsideClient | green |
| inspection-capture → Clipping is explicit, never padded | Region inside a fully visible client | test/data/capture/capture_geometry_test.dart | band inside a visible client is not clipped | red |
| inspection-capture → Clipping is explicit, never padded | Region crosses the right edge | test/data/capture/capture_geometry_test.dart | right-edge region is clipped not padded | red |
| inspection-capture → Clipping is explicit, never padded | Region crosses the top-left corner | test/data/capture/capture_geometry_test.dart | top-left region is clipped not padded | red |
| inspection-capture → Clipping is explicit, never padded | Region entirely off-screen | test/data/capture/capture_geometry_test.dart | off-desktop region is roiOutsideClient | red |
| inspection-capture → Frames have an immutable pixel layout | Frame layout | test/data/capture/capture_policy_test.dart | targeted frame reports layout and desktop origin | red |
| inspection-capture → Frames have an immutable pixel layout | Pixel access after release | test/data/capture/capture_frame_test.dart | pixels after release throw frameReleased | green |
| inspection-capture → Frames carry their provenance | Frame provenance | test/data/capture/capture_policy_test.dart | frame carries request id identity and ordered timestamps | green |
| inspection-capture → Frames carry their provenance | Clipped provenance | test/data/capture/capture_policy_test.dart | clipped frame reports both rectangles | red |
| inspection-capture → Frames carry their provenance | Client size of a targeted frame | test/data/capture/capture_policy_test.dart | targeted frame reports the validated client size | green |
| inspection-capture → Frames carry their provenance | Client size of a clipped fallback frame | test/data/capture/capture_policy_test.dart | clipped fallback frame reports full client width | green |
| inspection-recognition → Targeted recognition finds every inspection in its region | Marker present | test/data/vision/inspection_job_test.dart | targeted extraction runs the specified stages with the specified arguments | red |
| inspection-recognition → Targeted recognition finds every inspection in its region | Cascaded inspection windows | test/data/vision/inspection_job_test.dart | targeted frame with two separated peaks gives two entries in score order | red |
| inspection-recognition → Targeted recognition finds every inspection in its region | Score just below the gate | test/data/vision/inspection_job_test.dart | best score 0.8199 yields no evidence and no OCR call | red |
| inspection-recognition → Targeted recognition finds every inspection in its region | Score at the gate | test/data/vision/inspection_job_test.dart | best score exactly 0.82 runs title extraction | red |
| inspection-recognition → Targeted recognition finds every inspection in its region | Too many peaks | test/data/vision/inspection_job_test.dart | targeted peak overflow rejects markerPeaksOverflow | red |
| item-title-matching → Targeted and fallback evidence are ranked into one outcome | Targeted accepted | test/domain/title_matching_test.dart | accepted targeted evidence wins without consulting fallback | green |
| item-title-matching → Targeted and fallback evidence are ranked into one outcome | Targeted entries ranked among themselves | test/domain/title_matching_test.dart | best targeted entry wins over a higher-marker unaccepted one without fallback | red |
| item-title-matching → Targeted and fallback evidence are ranked into one outcome | Two accepted targeted entries | test/domain/title_matching_test.dart | of two accepted targeted entries the higher similarity wins | red |
| item-title-matching → Targeted and fallback evidence are ranked into one outcome | Fallback chooses the accepted inspection | test/domain/title_matching_test.dart | ranking prefers accepted over higher marker score | green |
| item-title-matching → Targeted and fallback evidence are ranked into one outcome | Nothing accepted | test/domain/title_matching_test.dart | nothing accepted is a rejection with top evidence and no accepted id | green |
| item-title-matching → Targeted and fallback evidence are ranked into one outcome | No marker anywhere | test/domain/title_matching_test.dart | no evidence anywhere rejects noMarker with both best scores | green |
| item-title-matching → Targeted and fallback evidence are ranked into one outcome | Index from another mode | test/domain/title_matching_test.dart | index from another mode rejects catalogModeMismatch | green |
| scan-frame-recording → Every published scan writes one case line and its frames | Scan accepted by the fallback pass | test/application/scan_coordinator_recording_test.dart | fallback acceptance records full and targeted PNGs and one line | red |
| scan-frame-recording → Every published scan writes one case line and its frames | Superseded scan | test/application/scan_coordinator_recording_test.dart | a superseded scan records nothing | green |
| scan-frame-recording → Every published scan writes one case line and its frames | Accepted scan whose extra capture fails | test/application/scan_coordinator_recording_test.dart | failed extra capture records the strip with image null and fullFailure | green |
| scan-frame-recording → Every published scan writes one case line and its frames | Ended on the targeted pass without a fallback | test/application/scan_coordinator_recording_test.dart | catalogUnavailable records the strip with image null | green |
| scan-frame-recording → Every published scan writes one case line and its frames | No frame at all | test/application/scan_coordinator_recording_test.dart | captureBusy records a line with no frames | green |

The `Scan accepted by the fallback pass` row is red because the targeted PNG must now be band-sized (1140x600 on a 1920x1080 client). If the coordinator test's fake capture sets the strip size itself rather than planning it, make the assertion use the planned band size so that the row proves the new size.

## 1. ADR-0016 and architecture index

- [x] 1.1 Write `docs/adr/0016-centred-targeted-region.md` (MADR-short: Status accepted, Date 2026-10-17, `Supersedes: 0010` with "region formula in the ROI bullet only"), from design D1–D3 and D6. Include the measured geometry, the rejected alternatives with reversal costs, the consequence for the M4 hotkey (the region needs no cursor beyond the in-client guard), and the corrected size bound from review S2 (the pixel cap binds first, at about 11,650 px wide at 16:9). Do not edit ADR-0010, 0012 or 0014. Verify: the file exists, and `grep -n "Supersedes: 0010" docs/adr/0016-*.md` matches.
- [x] 1.2 Update `openspec/architecture.md`: add the 0016 row to the in-force index, and mark the 0010 row as partly superseded by 0016 (region formula). Fix any prose that describes the targeted region as a cursor strip. Verify: `grep -n "0016" openspec/architecture.md` shows the index row, and `grep -n -i "cursor strip\|near the cursor" openspec/architecture.md` returns nothing stale.

## 2. Centred targeted band (inspection-capture)

- [x] 2.1 Rewrite the targeted-planning and clipping tests in `test/data/capture/capture_geometry_test.dart` for the new spec scenarios: the 16 cells, cursor independence, 1920×1200, 1366×768, negative origin, inside-visible, right edge (desktop ends at 1200), top-left corner (client at (-1000, -200)) and off-desktop (client at (-1700, 0)). Run `mise exec -- flutter test test/data/capture/capture_geometry_test.dart` and confirm that every red row fails on the old strip sizes, not on test setup.
- [x] 2.2 Implement the band in `planTargeted` (`lib/data/capture/capture_geometry.dart`), with named constants for 440, 700, 540 (vertical scale only) and 60 in exact-rational form, the region `(cx - f(440), 0, f(440) + f(700), cy + f(60))`, and the in-client guard kept. Update its doc comment. Verify: the geometry tests pass, and their rows flip to green.
- [x] 2.3 Update `test/data/capture/capture_policy_test.dart` for the band (frame layout 1140×600, stride ≥ 4560, origin (520, 0); clipped provenance through a desktop edge), then run it. Verify: it passes, the layout and clipped-provenance rows flip to green, and the green provenance and client-size tests re-run and still pass. Re-run `capture_frame_test.dart` (pixels after release, green).
- [x] 2.4 Update the main spec example `openspec/specs/inspection-capture/spec.md`, "Blank captures are reported", from "a 650×50 region" to "a 1140×600 region" (review S4: the archive sync does not touch it). Verify: `grep -n "650×50" openspec/specs/inspection-capture/spec.md` returns nothing.

## 3. Multi-peak targeted recognition (inspection-recognition)

- [x] 3.1 Update `test/data/vision/inspection_job_test.dart` over the existing fake `VisionNative` seam:
  - the targeted stage test expects the peak primitive, not the single best match;
  - add a two-peak targeted test (two entries in score order, each with its own title);
  - a 0.8199 targeted test (no evidence, best score reported through the no-peak best-match query, no OCR);
  - a 0.82 targeted test;
  - a targeted overflow test (`markerPeaksOverflow`).

  Run it and confirm that the red rows fail because the targeted branch still calls `matchTemplate` only.
- [x] 3.2 Route the targeted kind through the full-client peak path in `lib/data/vision/inspection_recognition.dart`: one code path, with `kind` kept on the result. Update the `evidence` doc comment at `lib/data/vision/inspection_evidence.dart:162` to "0 to 8, in score order" for both kinds. Verify: the job tests pass, and the rows flip to green. The existing full-client tests still pass.

## 4. Ranking within targeted entries (item-title-matching)

- [x] 4.1 Add tests to `test/domain/title_matching_test.dart`. In the first, an unaccepted targeted entry with marker .95 and an accepted one with marker .85: the accepted one wins, and the fallback is not matched (assert it with a fallback entry that would otherwise outrank). In the second, two accepted targeted entries with similarities about .90 and .97: the higher one wins. Run them and confirm that the first fails or the second picks the first-visited entry under today's loop.
- [x] 4.2 Change `rankOutcome` (`lib/domain/title_matching.dart`): match every targeted entry, take the best by `_outranks`, and return it when it is accepted. Otherwise rank everything together as today. Update its doc comment. Verify: the new tests pass, and the green ranking tests re-run and still pass, including `a full tie keeps the targeted entry first`. Also run `test/application/recognition_matcher_test.dart`.

## 5. Coordinator, recording and corpus tooling follow-through

- [x] 5.1 Update `test/application/scan_coordinator_recording_test.dart` so that the fallback-acceptance test asserts a band-sized targeted PNG (1140×600 on 1920×1080), and fix any other test fixture that hard-codes the 650×50 strip (`grep -rn "650\|866" test`). Verify: `mise run test` passes, and the recording row flips to green. The green recording rows re-run and still pass.
- [x] 5.2 Update `test/qualification/support/inspection_corpus.dart` docs and `test/qualification/inspection_corpus_support_test.dart` expectations for the band crop, and update the targeted crop rule in `docs/qualification/m2/CORPUS.md` (the formula and its link to ADR-0016). Verify: `mise exec -- flutter test test/qualification/inspection_corpus_support_test.dart` passes, and `grep -n "600 s\|r = floor" docs/qualification/m2/CORPUS.md` no longer shows the strip rule.

## 6. Offline replay over recorded scans (design D5)

- [x] 6.1 Add pure support in `test/qualification/support/targeted_region_replay.dart`, with unit tests in `test/qualification/targeted_region_replay_support_test.dart` (untagged, so they run in `mise run test`):
  - parse `frames.jsonl` by the CORPUS.md rules: skip lines with `image: null` or `clipped: true`, skip `fullClient` lines (they have no cursor, review S3) and count every skip by reason, tolerate an unparseable final line, and reject a malformed other line with a `FormatException` naming it;
  - classify each frame: targeted accepts, full-client accepts, agreement, conflicting accept (the hard failure), and miss cause (winner marker outside the band, or inside it but rejected);
  - build the summary: share of full-client accepts also accepted by the targeted pass, conflict count, and job-time percentiles per kind.

  Use small synthetic inputs. Verify: the support tests pass.
- [x] 6.2 Add `test/qualification/targeted_region_replay_test.dart` (`@Tags(['qualification'])`). It skips with a printed reason unless `BLACKGRID_RELEASE_BUNDLE`, `BLACKGRID_RECORDING_DIRS` (`;`-separated) and `BLACKGRID_REPLAY_CATALOG` are set. It runs a real `VisionService` over the bundle as the corpus test does, and writes `out/replay.json` atomically under a run directory given by `BLACKGRID_REPLAY_OUT`, refusing to write inside an input folder. It fails on any conflicting accept. Verify: with the variables unset it skips cleanly under `mise run test:qualification`.
- [ ] 6.3 Document the replay in `docs/qualification/m2/CORPUS.md` (or a sibling `REPLAY.md` linked from it): its inputs, how to export the PvP catalog from a read-only copy of `%LOCALAPPDATA%\Blackgrid\blackgrid.sqlite` (the `catalogRecords` JSON payload, written as `catalog.json` outside the repo), and the pass rule. Verify: the doc names all three variables and the hard rule.
- [ ] 6.4 Run the replay. First confirm that Escape from Tarkov is not running (`tasklist /FI "IMAGENAME eq EscapeFromTarkov.exe"` shows no match; if that cannot be confirmed, stop and ask the user). Build the Release bundle (`mise run build:release`), export the catalog, then run it over `scan-frames\20261014-122522` and `scan-frames\20261017-130909`. Record in `openspec/changes/fix-targeted-scan-region/evidence.md`:
  - the bundle version;
  - frames used and skipped, by reason;
  - full-client accepts and the targeted share;
  - every conflict, which must be 0;
  - every miss with its cause;
  - targeted and full-client job-time p50/p95.

  If the conflict count is not 0, or misses cluster just outside the band, stop and bring the evidence to the user before changing constants (a spec amendment). Verify: evidence.md holds the summary, and the hard rule passed.

## 7. Integration checks

- [ ] 7.1 Run `dart format` on the changed files, then `mise run analyze` and `mise run test`. Verify: both exit 0. Record the counts in evidence.md.
- [ ] 7.2 Run `openspec validate fix-targeted-scan-region --strict`. Verify: it reports the change as valid.
- [ ] 7.3 Record the user-verified checks in evidence.md as **unverified** until the user reports them, and ask the user to run them with the game, with frame recording off:
  - live scans at their resolution, with the share of accepts by pass taken from `scan-timings.jsonl`;
  - targeted publish latency (≤300 ms p95), which the agent computes from the log the user supplies.

  The agent never runs these. Verify: evidence.md lists both, each with status `unverified` or the user's reported result attributed to the user.

## Workflow follow-up

- Open question from design: if the user restores the labelled M2 corpus (`F:\Dev\Dart\blackgrid-corpus\inspection`), run the corpus runner over it (game not running) as an additional before/after check against 31/35 items, 2 false positives, 15/15 rejects.
- After the PR merges: archive the change (`/opsx:archive`, then `specwright-finish`), then `specwright-roadmap next` for M4 change 2 (`add-scan-decisions`).
