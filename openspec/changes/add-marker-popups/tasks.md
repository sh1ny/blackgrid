# Tasks

## Test map

All scenarios are new and start red. Named parameterized tests cover every alternative in their scenario; each row turns green only after its named test passes during apply. Tests use small synthetic fixtures and handwritten fakes, never a mocks package, real game, sleeps, or permanent source-text/wiring assertions.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| map-marker-popups → Marker selection opens one bubble | Select a marker | test/maps/marker_popup_test.dart | selection by badge browser and accessibility preserves view | red |
| map-marker-popups → Marker selection opens one bubble | Replace selection | test/maps/marker_popup_test.dart | selecting another marker replaces the bubble | red |
| map-marker-popups → Marker selection opens one bubble | Stale browser result | test/maps/marker_popup_test.dart | stale browser result after content replacement is rejected | red |
| map-marker-popups → Marker selection is cleared consistently | Close marker bubble | test/maps/marker_popup_test.dart | close clears selection bubble and linked highlights | red |
| map-marker-popups → Marker selection is cleared consistently | Pin selection | test/maps/marker_popup_test.dart | selecting a pin clears marker and retains pin details | red |
| map-marker-popups → Marker selection is cleared consistently | Empty map and Escape | test/maps/marker_popup_test.dart | empty canvas and Escape clear marker selection | red |
| map-marker-popups → Bubble tracks the badge within the viewport | Pan and zoom | test/maps/marker_popup_test.dart | pan and zoom track the projected anchor at fixed text size | red |
| map-marker-popups → Bubble tracks the badge within the viewport | Edge or small viewport | test/maps/marker_popup_test.dart | edge placements clamp prefer below and tether to anchor | red |
| map-marker-popups → Bubble tracks the badge within the viewport | Long content | test/maps/marker_popup_test.dart | long bubble content scrolls within viewport | red |
| map-marker-popups → Offscreen and ineligible selections differ | Anchor leaves and returns | test/maps/marker_popup_test.dart | offscreen anchor hides and restores the same bubble | red |
| map-marker-popups → Offscreen and ineligible selections differ | Outline remains visible but anchor leaves | test/maps/map_viewport_test.dart | visible outline with offscreen anchor retains selection without bubble | red |
| map-marker-popups → Offscreen and ineligible selections differ | Eligibility or content changes | test/maps/marker_popup_test.dart | floor category quest map and content invalidation clear selection | red |
| map-marker-popups → Offscreen and ineligible selections differ | Search only dims | test/maps/marker_popup_test.dart | search dimming keeps the selected bubble tracking | red |
| map-marker-popups → Bubble interaction respects map and focus | Operate and scroll inside bubble | test/maps/marker_popup_test.dart | bubble control and wheel do not operate the map | red |
| map-marker-popups → Bubble interaction respects map and focus | Navigate outside bubble | test/maps/marker_popup_test.dart | uncovered canvas drag and wheel navigate with tracking | red |
| map-marker-popups → Bubble interaction respects map and focus | Keyboard and help precedence | test/maps/marker_popup_test.dart | focused controls and help modal take keyboard precedence | red |
| map-marker-popups → Bubble interaction respects map and focus | Accessible dismissal | test/maps/marker_popup_test.dart | labelled keyboard close clears selection and restores usable map focus | red |
| map-marker-popups → Summaries reflect prepared marker facts | Quest and container | test/maps/marker_presentation_test.dart | quest objective and container show prepared names | green |
| map-marker-popups → Summaries reflect prepared marker facts | Linked extract and lock | test/maps/marker_presentation_test.dart | linked extract item count switch and lock key facts | green |
| map-marker-popups → Summaries reflect prepared marker facts | Missing or misleading fields | test/maps/marker_presentation_test.dart | missing malformed and misleading facts are not invented | green |
| map-marker-popups → Summaries reflect prepared marker facts | Boss chance scope | test/maps/marker_presentation_test.dart | boss wide chance is a percentage not a location chance | green |
| map-marker-popups → Item names use only the matching loaded catalog | Loaded name and update | test/maps/marker_popup_test.dart | matching catalog publication updates open bubble without requests | red |
| map-marker-popups → Item names use only the matching loaded catalog | Missing, mismatched or failed catalog | test/maps/marker_presentation_test.dart | absent mismatched missing and failed catalog names are unavailable | green |
| map-marker-popups → Item names use only the matching loaded catalog | Failed refresh with last-good data | test/maps/marker_popup_test.dart | failed refresh retains matching last good key without requests | red |
| map-marker-popups → Raw marker details are bounded and session-scoped | Lazy collapsed details | test/maps/marker_popup_test.dart | first collapsed details does not construct raw preview | red |
| map-marker-popups → Raw marker details are bounded and session-scoped | Session preference and current marker | test/maps/marker_popup_test.dart | expanded details follows current marker across tab and breakpoint | red |
| map-marker-popups → Raw marker details are bounded and session-scoped | Oversized source | test/maps/marker_preview_test.dart | bounded preview shortens large and deeply nested source | green |
| map-marker-popups → Raw marker details are bounded and session-scoped | Next launch | test/maps/marker_popup_test.dart | new app session starts details collapsed | red |

Apply discipline: each group lands its own red tests, implementation and applicable API documentation together; run targeted tests with the official Dart MCP `run_tests` route at the relevant red and green steps. Before changing any exported signature, use LSP references and migrate every caller, with no compatibility shims. Use existing Dart/Flutter skills and AGENTS.md's Dart and Flutter code guidance; no new dependencies or native/game services. Keep the proposal's Release Notes current in the group if its delivered behavior changes.

## 1. Controller selection and uncropped eligibility

- [x] 1.1 Add focused red controller invariant tests in `test/maps/map_controller_test.dart` using synthetic markers: selected eligible marker and existing projected badge anchor remain available independent of visible inventory, margin and outline; pan/resize preserves selection, search only dims, and floor/category/quest changes or map/content replacement synchronously clear selection and linked highlights without restoration on filter reversal. Include outline-visible/anchor-offscreen and coherent listener notification cases. Verify via targeted MCP tests that the new invariant assertions fail for the missing behavior.
- [x] 1.2 Implement the authoritative controller selection accessor and invalidation using the existing eligibility predicate, transform and marker scene point; preserve browser generation fencing and linked highlights. Run LSP references before any exported signature change, migrate all callers without shims, and document changed public APIs. Verify the 1.1 targeted tests pass and existing controller selection/highlight tests remain passing; the associated widget scenario rows remain red until group 3 exercises the real UI boundary.

## 2. Pure summary and bounded preview

- [x] 2.1 Add the red `marker_presentation_test.dart` test-map cases with synthetic prepared markers and catalog snapshots: translated quest/objective/item and container names; extract transfer item count, scalar and reverse source links on the same map, lock type/key/power; category label fallback; absent/malformed optional fields, unlinked and other-map switches, valid/invalid/nonfinite boss chances, and absent, missing-ID, wrong-mode or failed catalog names with no raw IDs in summaries. Verify targeted MCP tests fail for the missing presentation behavior.
- [x] 2.2 Implement the pure presentation value/derivation using prepared facts, same-map source links and matching-mode existing snapshots only; no fetch, invented availability, raw summary IDs or location-specific chance. Document public APIs and migrate any exported signature callers after LSP references. Verify the four summary rows and the missing-catalog row in the test map pass, then flip those rows green.
- [x] 2.3 Add the red `marker_preview_test.dart` oversized-source test, parameterized for huge multibyte strings, large collections, depth and node limits, including unshortened small input and UTF-8 boundaries. Verify targeted MCP tests fail for the missing bounded preview.
- [x] 2.4 Implement incremental current-marker diagnostic preview with at most 16 KiB UTF-8 output, depth 16, 1,024 visited nodes and 128 entries per collection; stop at the first limit and expose a shortening signal without serializing the complete source. Document public APIs. Verify the preview test passes for every limit and the oversized-source row turns green.

## 3. Bubble, input and MapScreen session state

- [ ] 3.1 Add red `marker_popup_test.dart` test-map cases for all selection paths and replacement; stale browser results using controlled completers after map/content or eligibility/visibility changes; close, Escape, empty canvas and pin selection with linked highlights and pin details/editing preserved; offscreen return, floor/category/quest and map/content invalidation, and search dimming. Include marker selection clearing pin selection. Verify targeted MCP tests fail for the missing UI behavior.
- [ ] 3.2 Add red widget cases for above/below/corner placement, tether, narrow/zero viewport and scaled text, pan/zoom without changing text size, long-content scroll, and popup wheel/click/secondary-click isolation versus uncovered map drag/wheel/context pin input. Exercise labelled keyboard Close and map focus restoration, Enter/N/Delete focus precedence, popup Escape and help-modal Escape precedence. Verify targeted MCP tests fail for the missing layout/input behavior.
- [ ] 3.3 Add red widget cases for collapsed lazy construction, session-wide expansion across different markers, tab switches and compact/wide reconstruction, current-only raw data, and a fresh session reset. Use an injected counting preview builder or equivalent observable seam. Add matching catalog publication/update, wrong mode and failed refresh with and without matching last-good data using handwritten fakes that count requests; assert no popup-triggered requests. Verify targeted MCP tests fail for the missing behavior.
- [ ] 3.4 Implement the clipped viewport-stack bubble with existing projection, measured constrained layout, above/below placement, clamp and tether, scrolling and isolated pointer/keyboard handling. Make controller selection authoritative, remove duplicate workspace marker selection/generation and obsolete `_MarkerDetails`; retain the existing saved-pin logic, browser content-generation fence and current visible/eligible recheck. Run LSP references before exported constructor/method changes and migrate every caller, no shims. Verify the selection, geometry and interaction tests from 3.1–3.2 pass and flip their corresponding rows green.
- [ ] 3.5 Own the initially collapsed Details preference in `MapScreen` above its layout split, pass it to every workspace caller, lazily construct only the current bounded preview and display shortening; listen to catalog publication with both active and snapshot mode checks and no selection-triggered request. Add an isolated `@Preview` from `package:flutter/widget_previews.dart` using a synthetic presentation value and explicit constraints, without transitive native/game service dependencies. Update existing `README.md` Map controls section for bubble selection, dismissal, scroll and session Details, and keep proposal Release Notes current if shipped behavior changes; document any changed public APIs. Verify the 3.3 tests pass, the corresponding rows turn green, and the preview and README changes are present and describe the delivered behavior.
- [ ] 3.6 Update `test/maps/map_viewport_test.dart`: replace the obsolete offscreen title assertion with the named offscreen-anchor test while retaining hazard paint, outline hit and linked-highlight proofs; replace the raw-open assertion with collapsed/expanded Details assertions while retaining cursor-anchor and 21-versus-23 logical-pixel hit proofs. Verify the targeted viewport suite passes and its test-map row turns green.

## 4. Final integration checks

- [ ] 4.1 Run `mise run analyze` and `mise run test`; verify both exit zero and all test-map rows are green. These are offline checks, not a real-map readability judgment.
- [ ] 4.2 Run `openspec validate add-marker-popups --strict` and `mise run release-notes -- --check openspec/changes/add-marker-popups/proposal.md`; verify both exit zero and Release Notes match delivered behavior. Release is disabled: do not bump a version.

## Workflow follow-up

- After implementation, follow the configured review, verification, archive and PR workflow separately; none is a tracked implementation task here.
- Any later runtime visual smoke requires prior confirmation that no game is running; if that cannot be confirmed, do not launch. Agents never launch or test against the game. M8 real-map readability is a user-only milestone-close check after remaining M8 work is delivered; it has not been passed by this change.
