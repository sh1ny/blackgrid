# Tasks

## Test map

Named parameterized tests cover every alternative in their scenario; each row turns green only after its named test passes during apply. Existing green rows record the earlier implementation; new or changed rows are red pending this amendment. Tests use small synthetic fixtures and handwritten fakes, never a mocks package, real game, sleeps, or permanent source-text/wiring assertions.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| map-marker-popups → Marker selection opens one bubble | Select a marker | test/maps/marker_popup_test.dart | selection by badge browser and accessibility preserves view | green |
| map-marker-popups → Marker selection opens one bubble | Overlapping badges | test/maps/map_controller_test.dart | topmost equal-distance badge wins while nearest and inclusive radius remain | green |
| map-marker-popups → Marker selection opens one bubble | Replace selection | test/maps/marker_popup_test.dart | selecting another marker replaces the bubble | green |
| map-marker-popups → Marker selection opens one bubble | Stale browser result | test/maps/marker_popup_test.dart | stale browser result after content replacement is rejected | green |
| map-marker-popups → Marker selection is cleared consistently | Close marker bubble | test/maps/marker_popup_test.dart | close clears selection bubble and linked highlights | green |
| map-marker-popups → Marker selection is cleared consistently | Pin selection | test/maps/marker_popup_test.dart | selecting a pin clears marker and retains pin details | green |
| map-marker-popups → Marker selection is cleared consistently | Empty map and Escape | test/maps/marker_popup_test.dart | empty canvas and Escape clear marker selection | green |
| map-marker-popups → Bubble tracks the badge within the viewport | Pan and zoom | test/maps/marker_popup_test.dart | pan and zoom track the projected anchor at fixed text size | green |
| map-marker-popups → Bubble tracks the badge within the viewport | Edge or small viewport | test/maps/marker_popup_test.dart | edge placements clamp prefer below and tether to anchor | green |
| map-marker-popups → Bubble tracks the badge within the viewport | Long content | test/maps/marker_popup_quest_test.dart | long summary content scrolls within viewport | green |
| map-marker-popups → Offscreen and ineligible selections differ | Anchor leaves and returns | test/maps/marker_popup_test.dart | offscreen anchor hides and restores the same bubble | green |
| map-marker-popups → Offscreen and ineligible selections differ | Outline remains visible but anchor leaves | test/maps/map_viewport_test.dart | visible outline with offscreen anchor retains selection without bubble | green |
| map-marker-popups → Offscreen and ineligible selections differ | Eligibility or content changes | test/maps/marker_popup_test.dart | floor category quest map and content invalidation clear selection | green |
| map-marker-popups → Offscreen and ineligible selections differ | Search only dims | test/maps/marker_popup_test.dart | search dimming keeps the selected bubble tracking | green |
| map-marker-popups → Bubble interaction respects map and focus | Operate and scroll inside bubble | test/maps/marker_popup_test.dart | bubble summary and wheel do not operate the map | green |
| map-marker-popups → Bubble interaction respects map and focus | Navigate outside bubble | test/maps/marker_popup_test.dart | uncovered canvas drag and wheel navigate with tracking | green |
| map-marker-popups → Bubble interaction respects map and focus | Keyboard and help precedence | test/maps/marker_popup_test.dart | focused popup and help modal take keyboard precedence | green |
| map-marker-popups → Bubble interaction respects map and focus | Popup focus isolates map navigation keys | test/maps/marker_popup_test.dart | focused popup controls isolate all map navigation keys without stealing child input | green |
| map-marker-popups → Bubble interaction respects map and focus | Accessible dismissal | test/maps/marker_popup_test.dart | labelled keyboard close clears selection and restores usable map focus | green |
| map-marker-popups → Summaries reflect prepared marker facts | Quest and container | test/maps/marker_presentation_test.dart | quest objective and container show prepared names | green |
| map-marker-popups → Summaries reflect prepared marker facts | Linked extract and lock | test/maps/marker_presentation_test.dart | linked extract item count switch and lock key facts | green |
| map-marker-popups → Summaries reflect prepared marker facts | Missing or misleading fields | test/maps/marker_presentation_test.dart | missing malformed and misleading facts are not invented | green |
| map-marker-popups → Summaries reflect prepared marker facts | Boss chance scope | test/maps/marker_presentation_test.dart | boss wide chance is a percentage not a location chance | green |
| map-marker-popups → Item names use only the matching loaded catalog | Loaded name and update | test/maps/marker_popup_test.dart | matching catalog publication updates open bubble without requests | green |
| map-marker-popups → Item names use only the matching loaded catalog | Missing, mismatched or failed catalog | test/maps/marker_presentation_test.dart | absent mismatched missing and failed catalog names are unavailable | green |
| map-marker-popups → Item names use only the matching loaded catalog | Failed refresh with last-good data | test/maps/marker_popup_test.dart | failed refresh retains matching last good key without requests | green |
| map-marker-popups → Marker bubbles contain summaries only | Summary without raw details | test/maps/marker_popup_test.dart | marker bubble shows summary without raw details | green |

Apply discipline: each group lands its own red tests, implementation and applicable API documentation together; run targeted tests with the official Dart MCP `run_tests` route at the relevant red and green steps. Before changing any exported signature, use LSP references and migrate every caller, with no compatibility shims. Use existing Dart/Flutter skills and AGENTS.md's Dart and Flutter code guidance; no new dependencies or native/game services. Keep the proposal's Release Notes current in the group if its delivered behavior changes.

Groups 1–4 and their 14 checked task IDs are historical commit attribution, not current acceptance for retired raw preview or marker Details behavior. Group 5 removes that work; current acceptance is the revised specification and test map plus groups 5–7. Prior integration results predate this amendment.

## 1. Controller selection and uncropped eligibility

- [x] 1.1 Add focused red controller invariant tests in `test/maps/map_controller_test.dart` using synthetic markers: selected eligible marker and existing projected badge anchor remain available independent of visible inventory, margin and outline; pan/resize preserves selection, search only dims, and floor/category/quest changes or map/content replacement synchronously clear selection and linked highlights without restoration on filter reversal. Include outline-visible/anchor-offscreen and coherent listener notification cases. Verify via targeted MCP tests that the new invariant assertions fail for the missing behavior.
- [x] 1.2 Implement the authoritative controller selection accessor and invalidation using the existing eligibility predicate, transform and marker scene point; preserve browser generation fencing and linked highlights. Run LSP references before any exported signature change, migrate all callers without shims, and document changed public APIs. Verify the 1.1 targeted tests pass and existing controller selection/highlight tests remain passing; the associated widget scenario rows remain red until group 3 exercises the real UI boundary.

## 2. Pure summary and bounded preview

- [x] 2.1 Add the red `marker_presentation_test.dart` test-map cases with synthetic prepared markers and catalog snapshots: translated quest/objective/item and container names; extract transfer item count, scalar and reverse source links on the same map, lock type/key/power; category label fallback; absent/malformed optional fields, unlinked and other-map switches, valid/invalid/nonfinite boss chances, and absent, missing-ID, wrong-mode or failed catalog names with no raw IDs in summaries. Verify targeted MCP tests fail for the missing presentation behavior.
- [x] 2.2 Implement the pure presentation value/derivation using prepared facts, same-map source links and matching-mode existing snapshots only; no fetch, invented availability, raw summary IDs or location-specific chance. Document public APIs and migrate any exported signature callers after LSP references. Verify the four summary rows and the missing-catalog row in the test map pass, then flip those rows green.
- [x] 2.3 Add the red `marker_preview_test.dart` oversized-source test, parameterized for huge multibyte strings, large collections, depth and node limits, including unshortened small input and UTF-8 boundaries. Verify targeted MCP tests fail for the missing bounded preview.
- [x] 2.4 Implement incremental current-marker diagnostic preview with at most 16 KiB UTF-8 output, depth 16, 1,024 visited nodes and 128 entries per collection; stop at the first limit and expose a shortening signal without serializing the complete source. Document public APIs. Verify the preview test passes for every limit and the oversized-source row turns green.

## 3. Bubble, input and MapScreen session state

- [x] 3.1 Add red `marker_popup_test.dart` test-map cases for all selection paths and replacement; stale browser results using controlled completers after map/content or eligibility/visibility changes; close, Escape, empty canvas and pin selection with linked highlights and pin details/editing preserved; offscreen return, floor/category/quest and map/content invalidation, and search dimming. Include marker selection clearing pin selection. Verify targeted MCP tests fail for the missing UI behavior.
- [x] 3.2 Add red widget cases for above/below/corner placement, tether, narrow/zero viewport and scaled text, pan/zoom without changing text size, long-content scroll, and popup wheel/click/secondary-click isolation versus uncovered map drag/wheel/context pin input. Exercise labelled keyboard Close and map focus restoration, Enter/N/Delete focus precedence, popup Escape and help-modal Escape precedence. Verify targeted MCP tests fail for the missing layout/input behavior.
- [x] 3.3 Add red widget cases for collapsed lazy construction, session-wide expansion across different markers, tab switches and compact/wide reconstruction, current-only raw data, and a fresh session reset. Use an injected counting preview builder or equivalent observable seam. Add matching catalog publication/update, wrong mode and failed refresh with and without matching last-good data using handwritten fakes that count requests; assert no popup-triggered requests. Verify targeted MCP tests fail for the missing behavior.
- [x] 3.4 Implement the clipped viewport-stack bubble with existing projection, measured constrained layout, above/below placement, clamp and tether, scrolling and isolated pointer/keyboard handling. Make controller selection authoritative, remove duplicate workspace marker selection/generation and obsolete `_MarkerDetails`; retain the existing saved-pin logic, browser content-generation fence and current visible/eligible recheck. Run LSP references before exported constructor/method changes and migrate every caller, no shims. Verify the selection, geometry and interaction tests from 3.1–3.2 pass and flip their corresponding rows green.
- [x] 3.5 Own the initially collapsed Details preference in `MapScreen` above its layout split, pass it to every workspace caller, lazily construct only the current bounded preview and display shortening; listen to catalog publication with both active and snapshot mode checks and no selection-triggered request. Add an isolated `@Preview` from `package:flutter/widget_previews.dart` using a synthetic presentation value and explicit constraints, without transitive native/game service dependencies. Update existing `README.md` Map controls section for bubble selection, dismissal, scroll and session Details, and keep proposal Release Notes current if shipped behavior changes; document any changed public APIs. Verify the 3.3 tests pass, the corresponding rows turn green, and the preview and README changes are present and describe the delivered behavior.
- [x] 3.6 Update `test/maps/map_viewport_test.dart`: replace the obsolete offscreen title assertion with the named offscreen-anchor test while retaining hazard paint, outline hit and linked-highlight proofs; replace the raw-open assertion with collapsed/expanded Details assertions while retaining cursor-anchor and 21-versus-23 logical-pixel hit proofs. Verify the targeted viewport suite passes and its test-map row turns green.

## 4. Final integration checks

- [x] 4.1 Run `mise run analyze` and `mise run test`; verify both exit zero and all test-map rows are green. These are offline checks, not a real-map readability judgment.
- [x] 4.2 Run `openspec validate add-marker-popups --strict` and `mise run release-notes -- --check openspec/changes/add-marker-popups/proposal.md`; verify both exit zero and Release Notes match delivered behavior. Release is disabled: do not bump a version.

## 5. Summary-only popup and keyboard isolation

Ownership: UI and `test/maps/*` popup/viewport/presentation tests, plus `README.md`; do not edit `lib/application/map_controller.dart` or `test/maps/map_controller_test.dart`, which belong to group 6.

- [x] 5.1 Add red widget regressions for the summary-only scenario and all map navigation shortcut isolation while a popup control has focus, including ArrowLeft; verify child-handled input still works, Escape/modal precedence and uncovered map navigation remain correct. Replace the old preview-dependent long-scroll case with `long summary content scrolls within viewport` using genuinely long player-facing summary content. Keep existing scenario test names unless their behavior changes.
- [x] 5.2 Remove marker raw Details UI, preview implementation and preview-only tests, expansion preference/callbacks and all related callers and obsolete assertions, with no compatibility shims or cache. Implement popup-focus isolation for all map navigation shortcuts while letting child controls handle their own input and preserving Escape/modal precedence. Preserve `PreparedMarker.details` and `.source` for pure summaries, unrelated app Details, saved-pin behavior and existing catalog behavior. Use LSP references before changing exported APIs. Update `test/maps/map_viewport_test.dart` without losing its geometry and hit proofs; update `README.md` Map controls and applicable API documentation to the summary-only behavior. No pack/data regeneration or network changes.
- [x] 5.3 Verify the group 5 red cases pass with official Dart MCP targeted tests and retained popup/viewport/presentation coverage; update their test-map rows only on passing evidence. Preserve the widget preview as a summary-only isolated preview.

## 6. Generic controller badge hit ordering

Ownership: `lib/application/map_controller.dart` and `test/maps/map_controller_test.dart` only; group 5 owns UI and other map tests.

- [x] 6.1 Add red synthetic controller regression `topmost equal-distance badge wins while nearest and inclusive radius remain`: equal-position/equal-distance eligible badges with differing categories and paint order select the topmost, a strictly nearer badge wins regardless of order, exact-radius hits remain included, and outside-radius hits remain excluded. Preserve existing outline hit behavior.
- [x] 6.2 Fix generic `hitTestMarker` badge tie handling to honor topmost paint order without a boss special case; keep nearest-distance and inclusive-radius semantics. No data changes, fetches or pack regeneration.
- [x] 6.3 Verify the controller regression and relevant existing controller tests via official Dart MCP targeted tests; update its test-map row only on passing evidence.

## 7. Integration gates

- [x] 7.1 After groups 5 and 6 land, run `mise run analyze` and `mise run test` and ensure all current test-map rows are green. These offline checks do not establish milestone-wide readability.
- [x] 7.2 Run `openspec validate add-marker-popups --strict` and `mise run release-notes -- --check openspec/changes/add-marker-popups/proposal.md`; ensure the release notes match summary-only behavior. Do not bump a version.
- [x] 7.3 Obtain a fresh FULL design review of the amended decisions before implementing groups 5 and 6; the prior review approval is invalidated by the user-approved D4 reversal.

## Verification evidence

- Amended FULL design review round 2: `VERDICT: APPROVE`, `CHANGES_APPLIED: n/a`, recorded before groups 5 and 6.
- Final offline gate after the focused log-reader repair and readability corrections: `mise run analyze` passed with no issues; `mise run test` passed all 2,532 tests. The 84 affected popup, presentation and map UI tests also passed through official Dart MCP.
- No native application or live-game verification was performed. The owner's earlier feel check is not the milestone-wide readability check.

## Workflow follow-up

- After implementation, follow the configured review, verification, archive and PR workflow separately; none is a tracked implementation task here.
- The user reported the feel test worked fine on Release 0.7.0+403 at head `7bd9a60`; this is not the M8 milestone-wide readability assessment. Any later runtime visual smoke requires prior confirmation that no game is running; if that cannot be confirmed, do not launch. Agents never launch or test against the game. M8 real-map readability is a user-only milestone-close check after remaining M8 work is delivered; it has not been passed by this change.
