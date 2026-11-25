# Tasks

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| raid-panel-reading → Detect exfil headers dimmed by night vision | Dimmed header on Shoreline | test/domain/raid_panel_text_parser_test.dart | detects an exfil header dimmed by night vision | red |
| raid-panel-reading → Detect exfil headers dimmed by night vision | Standard header | test/domain/raid_panel_text_parser_test.dart | green header in the right panel area is detected, dark frame is not (existing) | green |
| raid-panel-reading → Detect exfil headers dimmed by night vision | Night-vision scenery without a panel | test/domain/raid_panel_text_parser_test.dart | rejects night-vision scenery without an exfil header | red |

## 1. Admit the dim panel and reject scenery

- [ ] 1.1 Settle A1 before editing production code. Sample the existing detector grid in the owner-provided saved day panel, NV panels (12.10 and 12.26), and no-panel NV screenshots; compare current admission and a dim yellow-green, low-blue candidate at unchanged coverage. Record outcomes and fixture provenance, including a hard negative that a green-floor-only reduction would accept. Do not substitute a synthetic scene for the saved-image comparison or claim real-world coverage from synthetic pixels. If the supplied samples do not separate, stop and take the evidence to the owner.
- [ ] 1.2 Add the two named detector tests before the fix. Use a compact synthetic RGB header strip from #140 and deterministic no-panel fixtures covering ordinary bright-enough NV tint and low-blue near-misses; retain minimal approved pixel data preserving measured scene coverage. Verify the dim positive is red on the old detector and at least one negative is red against an unconditional floor reduction. Keep the existing standard case green. No game, OCR DLL, timing or process manipulation in the tests.
- [ ] 1.3 Add the calibrated dim path only to `RaidPanelProfile.detect` (D1). Leave the existing bright path, sample coverage and `panelBottom` rule unchanged. Verify the named detector tests and the original saved-image positives and negatives pass; mark the test map green.
- [ ] 1.4 Carry C1 by confirming the no-panel rejection stays explicit in the `raid-panel-reading` delta; carry C2 with a short doc comment on `RaidPanelProfile.detect` explaining that dim NV colors are used only for admission, not crop sizing. Verify the delta and `dart format` on changed Dart files. Check release notes with `mise run release-notes -- --check openspec/changes/detect-panel-under-night-vision/proposal.md` (nonzero fails).
- [ ] 1.5 Run `mise run analyze` and `mise run test` after the workstation gaming check, or use the same gates in PR CI on the exact head if the owner is gaming. Record which checks ran and their results.

## Workflow follow-up

- Owner-only live NV re-check: save one shot with the exfil panel open and one without, then check that Blackgrid reads only the former. Request through the coordinator or obtain approval to skip; record any skip as unverified. Offline saved-image verification above is required regardless.
- Once #136 merges and the coordinator authorizes the rebase, rebase onto `origin/main`, treat the delta as an addition to the now-existing `raid-panel-reading` capability, and verify the rebased head. Archive the change on the PR branch, confirm green checks and review, and leave merging to the owner.
