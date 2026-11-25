# Tasks

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| raid-panel-reading → Detect exfil headers dimmed by night vision | Dimmed header on Shoreline | test/domain/raid_panel_text_parser_test.dart | detects an exfil header dimmed by night vision | green |
| raid-panel-reading → Detect exfil headers dimmed by night vision | Standard header | test/domain/raid_panel_text_parser_test.dart | green header in the right panel area is detected, dark frame is not (existing) | green |
| raid-panel-reading → Detect exfil headers dimmed by night vision | Night-vision scenery without a panel | test/domain/raid_panel_text_parser_test.dart | rejects night-vision scenery without an exfil header | green |
| raid-panel-reading → Detect exfil headers dimmed by night vision | Night-vision scenery without a panel (in-palette shapes) | test/domain/raid_panel_text_parser_test.dart | rejects an in-palette dim stripe outside the panel crop; rejects an in-palette dim stripe inside the panel crop | green |

## 1. Admit the dim panel and reject scenery

- [x] 1.1 Settle A1 before editing production code. Sample the existing detector grid in the two owner-approved saved NV panels (12.02 and 12.44), bright panel (12.10), and 11-21 no-panel NV screenshots. Compare current admission, a green-floor-only reduction and the dim yellow-green, low-blue candidate at unchanged coverage. Record outcomes and provenance; keep the reported 12.26 RGB as synthetic evidence only, and the floor-only hard negative as a separate synthetic control. If the saved samples do not separate, stop and take the evidence to the owner.
  - Owner-approved evidence: 12.26 was absent from the configured screenshot folder, so the reported RGB `(93,136,7)` is synthetic only. The 12.10 file has a standard bright header; the two other saved Shoreline panels independently reproduce the NV failure. All saved images below are 3440×1440 with a 10% admission threshold. The compact fixtures retain 12×10 evenly spaced RGB samples from each existing scan grid and no full images.

  | Saved image | Visible content | Legacy hits | Green floor 125 only | Narrow candidate |
  |---|---|---:|---:|---:|
  | 2026-11-25 12.02 | Shoreline NV panel | 0.61% | 25.01% | 24.82% |
  | 2026-11-25 12.44 | Shoreline NV panel | 0.00% | 24.67% | 24.67% |
  | 2026-11-25 12.10 | Bright panel | 24.83% | 25.23% | 25.23% |
  | 2026-11-21 2.12, 3.90, 5.75 | NV scenery without panel | 0.00% each | 0.00% each | 0.00% each |

- [x] 1.2 Add the two named detector tests before the fix. Use a compact synthetic RGB header strip from #140 and deterministic no-panel fixtures covering ordinary bright-enough NV tint and low-blue near-misses; retain minimal approved pixel data preserving measured scene coverage. Verify the dim positive is red on the old detector and at least one negative is red against an unconditional floor reduction. Keep the existing standard case green. No game, OCR DLL, timing or process manipulation in the tests.
  - Red runs: all three dim positives failed on the old detector; bright, scenery and crop controls passed. Changing only the green floor to 125 caused the synthetic ordinary-green-tint assertion to fail (`expected false, got true`).
- [x] 1.3 Add the calibrated dim path only to `RaidPanelProfile.detect` (D1). Leave the existing bright path, sample coverage and `panelBottom` rule unchanged. Verify the named detector tests and the original saved-image positives and negatives pass; mark the test map green.
  - Green proof: a scratch Dart script decoded all six original saved PNGs and called `RaidPanelProfile.detect` on their pixels. All three panels were detected and all three no-panel frames were rejected. The script was removed. The compact fixture and crop regression tests also passed in the offline suite.
- [x] 1.4 Carry C1 by confirming the no-panel rejection stays explicit in the `raid-panel-reading` delta; carry C2 with a short doc comment on `RaidPanelProfile.detect` explaining that dim NV colors are used only for admission, not crop sizing. Verify the delta and `dart format` on changed Dart files. Check release notes with `mise run release-notes -- --check openspec/changes/detect-panel-under-night-vision/proposal.md` (nonzero fails).
  - Strict OpenSpec validation and release-note check passed; formatter changed 0 files.
- [x] 1.5 Run `mise run analyze` and `mise run test` after the workstation gaming check, or use the same gates in PR CI on the exact head if the owner is gaming. Record which checks ran and their results.
  - Local offline gates: no analyzer issues; 3,634 app tests and 110 progress package tests passed.

## 2. Reject in-palette scenery shapes

- [x] 2.1 Add two in-palette vertical stripe negatives, one outside the crop and one inside but too narrow. Both must exceed the existing total colour coverage and fail against the colour-only implementation.
  - On the colour-only detector, both returned `true` when `false` was expected. The outside case also includes a single wide row inside the crop: the row has span but cannot reach the hit fraction without outside hits.
- [x] 2.2 Apply D1's crop-local quarter-width run to the dim path only; leave the bright path, sampling grid and crop behaviour unchanged. Carry C3 and clarify C2 at `RaidPanelProfile.detect`. Run the detector tests and six original saved images again, then run the offline gates after the gaming check.
  - Final detector: both dim panels and the bright control accepted; all three full no-panel images rejected. `mise run analyze` found no issues. `mise run test` passed all 3,636 app tests and 110 progress tests, including both stripe negatives and the crop regression.

## Workflow follow-up

- Owner-only live NV re-check: save one shot with the exfil panel open and one without, then check that Blackgrid reads only the former. Request through the coordinator or obtain approval to skip; record any skip as unverified. Offline saved-image verification above is required regardless.
- Once #136 merges and the coordinator authorizes the rebase, rebase onto `origin/main`, treat the delta as an addition to the now-existing `raid-panel-reading` capability, and verify the rebased head. Archive the change on the PR branch, confirm green checks and review, and leave merging to the owner.
