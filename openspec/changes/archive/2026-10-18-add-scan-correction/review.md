# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed:** proposal.md, design.md, specs/scan-correction/spec.md, specs/item-title-matching/spec.md, specs/scan-decisions/spec.md; main specs openspec/specs/scan-decisions, item-title-matching; openspec/architecture.md (component rows, state table, ADR index, "Not built yet"); docs/adr/0001, 0002, 0003, 0012, 0017; source lib/application/selection_controller.dart, scan_decision_feed.dart, scan_coordinator.dart (ScanEnd, AcceptedScanSource, ScanReport, latest, _publish), accepted_scan.dart, app_services.dart, history_controller.dart, scan_epoch.dart, catalog_controller.dart (setMode), lib/domain/title_matching.dart (TitleMatch, normaliseTitle, matchTitle, OutcomeRejected), lib/domain/catalog.dart (searchIndex, search), lib/ui/item_decision_card.dart, scan_evidence_panel.dart (shownEvidence, _note), map_screen.dart, scanner_screen.dart, shell.dart, evidence_panels.dart; tests test/application/selection_controller_test.dart, test/application/support/fake_accepted_scan_source.dart; reference companion Services/ScannerOrchestrator.cs (AcceptCorrection), MainWindow.xaml.cs (ScannerWorkspace_CorrectionSubmitted). Skills loaded: dart-use-pattern-matching, dart-add-unit-test, flutter-add-widget-test, dart-write-documentation.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

Verified and holding: the matcher claim in Context/D4 is correct. `TitleMatchIndex` is sorted by ID (`title_matching.dart:483`), equal normalised names always score equal (`:607-609`), and the strict `>` runner-up loop (`:625-639`) yields exactly the second entry of a distinct-name top-k ranked by score then ID, including the restricted-quantity pool. The feed ordering for a single notify (lastAccepted first, then latest) is sound provided the existing early `return` at `scan_decision_feed.dart:47` is restructured, which the design states. The pick's history-write fence by `_generation` matches the existing `selectScan` pattern. No game interaction is introduced.

### Critical (blocking)

None.

### Moderate

1. **D7's sync rule makes the Scanner and Map fields diverge, breaking the spec scenario "Navigation keeps the offer".** Both screens stay mounted in an `IndexedStack` (`lib/ui/shell.dart:161-171`, ADR-0002), so there are two live `ItemDecisionCard` instances (`scanner_screen.dart:67`, `map_screen.dart:395`), each with its own `TextEditingController` under D7. D7 syncs a controller from the offer's query only "when the offer's report id changes". The user edits the text on Scanner to `ANA M1 black` (`setCorrectionQuery` updates selection), switches to Map, and Map's field still shows `ANA M1 OD GREEN` while its results come from the edited query. The scenario requires "the same text in its field". D7's own rejected alternative is argued on "lost on navigation", which `IndexedStack` does not do; the real hazard is two mounted fields, and the chosen rule has it too.

2. **D5 has the app-layer feed call a UI function.** D5 picks the OCR text through `shownEvidence` (`lib/ui/scan_evidence_panel.dart:400-407`), but `ScanDecisionFeed` lives in `lib/application/`. No file in `lib/application` or `lib/domain` imports `lib/ui` today, and the architecture limits the UI layer to widget-local view state (architecture.md row "Shell / UI"). Following D5 literally makes the feed import a widget library, which reverses the dependency direction and pulls Flutter widgets into the feed's service tests. Also, `shownEvidence` falls back to `_firstEntry(report.fallback/targeted)` when `outcome.evidence` is null. If that path is taken, the offer's OCR text comes from a different evidence entry than the `outcome.match` that supplies its candidates. The design should name the source directly: `ScanRejected.outcome.evidence.text` paired with `outcome.match.candidates`. That pure helper should live in the application layer (e.g. `scan_correction.dart`), and the panel may reuse it.

3. **`closeHistory` clears the offer in the design but not in the spec, and the design's choice loses offers on an ordinary action.** D1, the State & Ownership table and the lifecycle diagram list `closeHistory` as an offer clearer. The spec's clearing list ("Only the newest offer is current") does not include it. Flow & State Gaps says an offer made while the history view is open "shows in the card above the history inspection". The natural next step is to close the history view to get back to live, and under D1 that destroys the offer. Because `_offered` was already raised, the offer cannot come back. `reloadAfterImport` (`app_services.dart:256-259`) also calls `closeHistory` and would drop an offer. Pick one and make spec and design agree: either `closeHistory` leaves the offer (recommended, since closing a view is not a new selection and the pick re-checks item presence anyway), or the spec adds `closeHistory` as a clearer with a scenario.

4. **D2's "exactly one non-null" contradicts current selection semantics that a test pins.** `openHistory` deliberately keeps `_manualId` (`selection_controller.dart:179-189`), so `closeHistory` returns to the live manual item. `test/application/selection_controller_test.dart:36-58` ("close returns live selection") asserts this. If the implementer enforces "exactly one non-null" in `openHistory`, that behaviour and test break. If they don't clear `_manualId` in `selectCorrection`, a retired correction (`retireScan`) would bring back the earlier manual item as current advice after a session change, against the spec ("the corrected item SHALL no longer be shown as current advice" holds, but an older manual item would silently appear). The design should state the precedence (history row > scan > correction > manual), say that `selectCorrection` clears `_manualId` and `_scanItemId`/`_scan` as `selectScan` does, and say that `openHistory` keeps the manual fallback as today.

### Suggestions

1. **The injected epoch reader in `SelectionController` (D6) cannot fire in the app.** Every mode or session change runs `catalog.setMode` and `++_modeTransition`, then calls `scanFeed.epochChanged()` → `retireScan` in the same synchronous `_syncMapSession` call (`app_services.dart:230-245`). D1 has `retireScan` clear the offer, so no UI event can reach `selectCorrection` with a stale-epoch or stale-mode offer still current. The offer-identity check already covers it. Either drop the reader (one fewer constructor dependency and fake), or keep it and correct the Mechanism Ledger's rationale to "defence in depth". If you keep it, give the new constructor parameter a default, as ADR-0017 did for the coordinator's `epoch`, so existing `SelectionController` constructions in tests compile unchanged.
2. **Qualify the main requirement "Unaccepted scans never change the selection"** (`openspec/specs/scan-decisions/spec.md:38-47`) in the scan-decisions delta. Its text "SHALL NOT change the selection ... or the history, even when it has a best candidate" and its scenario "no history entry for C is added" will read as contradicted by the archived scan-correction spec. In that spec, picking C from the rejected scan's offer selects C and records it. A one-clause MODIFIED ("the scan itself; a user's pick from its correction offer is a separate selection") avoids that.
3. **Say where the offer goes in the compact Map card.** The card is a fixed `300 * scale` (`map_screen.dart:393-396`) and scrolls its content. If the offer renders after the full item detail, it sits below the fold in a normal-size window, so the Map scenario holds but the offer is not visible in raid without scrolling. One sentence in D5/Risks (e.g. "the offer renders above the item detail") is enough. Further layout stays with M4.5.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. design.md D7: replace "synced from it when the offer's report id changes" with a rule that keeps every mounted card's field equal to `correctionOffer.query`. For example, on each selection notify, set the controller's text when it differs from the offer's query, preserving the selection when the field has focus. Update D7's rejected-alternative rationale to cite the two mounted cards (`shell.dart:161-171`) rather than loss on navigation. Add a widget-test line to the proposal's Tests bullet: editing the field in one card updates the other.
2. design.md D5 (and Failure & Visibility if it references it): replace the `shownEvidence` reference with an application-layer helper in `scan_correction.dart` that reads OCR text from `ScanRejected.outcome.evidence.text` and candidates from the same `outcome.match`, and offers nothing when either is absent. Note that the evidence panel keeps or reuses its own `shownEvidence`.
3. Resolve `closeHistory` in both artifacts. Either remove `closeHistory` from the offer clearers in D1, the State & Ownership table ("Current correction offer" row) and the lifecycle diagram, and add a scan-correction scenario showing that closing the history view keeps the offer (recommended). Or add `closeHistory` to the spec's clearing list in "Only the newest offer is current", with a scenario.
4. design.md D2: replace "with exactly one non-null" with the precedence history row > scan > correction > manual. State that `selectCorrection` clears `_manualId`, `_scanItemId` and `_scan`, that `openHistory` keeps the manual fallback as today (`selection_controller_test.dart:36-58`), and that `openHistory` clears the correction source.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

Author, after round 1:

- Required change 1 (M1, two mounted cards): fixed. D7 now keeps each mounted card's controller equal to `correctionOffer.query` on every selection notify, preserving cursor and selection while focused, and its rejected alternative cites `shell.dart:161-171`. The proposal's Tests bullet adds the cross-card widget test.
- Required change 2 (M2, UI import): fixed. D5 reads the OCR text and the candidates from one `ScanRejected.outcome` (`evidence.text`, `match`) through an application-layer helper in `scan_correction.dart`, offers nothing when either is absent, and notes that the panel keeps its own `shownEvidence`.
- Required change 3 (M3, `closeHistory`): fixed with the recommended option. `closeHistory` keeps the offer in D1, the State & Ownership row and the lifecycle diagram, and the spec adds the scenario "Closing a history view keeps the offer".
- Required change 4 (M4, source precedence): fixed. D2 states the precedence history row > scan > correction > manual. `selectCorrection` clears `_manualId`, `_scanItemId` and `_scan`. `openHistory` keeps the manual fallback and clears the correction source.
- Suggestions (epoch reader, qualifying "Unaccepted scans never change the selection", where the offer sits on Map's card): not applied in this round, to keep the verdict's scope to the required changes. The epoch reader stays, with a default in the constructor (an implementation detail). The other two are left to apply and to M4.5's `polish-map-rail`.

Reviewer re-check (2026-10-18): required changes 1-4 applied; accepted by reviewer.

- 1: D7 keeps every mounted card's controller equal to `correctionOffer.query` on each selection notify, preserving cursor and selection when focused; its rejected alternative cites the two mounted cards (`shell.dart:161-171`, confirmed `IndexedStack` with MapScreen and ScannerScreen). The proposal's Tests bullet adds the cross-card widget test.
- 2: D5 names an application-layer helper in `scan_correction.dart` that reads `ScanRejected.outcome.evidence.text` and the same `outcome.match`, offers nothing when either is absent, and notes the panel keeps `shownEvidence`. Failure & Visibility does not reference `shownEvidence`.
- 3: `closeHistory` is removed from the offer clearers in D1, the "Current correction offer" State & Ownership row and the lifecycle diagram (now "closeHistory (kept)"); the spec's clearing list omits it and the scenario "Closing a history view keeps the offer" is added.
- 4: D2 states the precedence history row > scan > correction > manual, that `selectCorrection` clears `_manualId`, `_scanItemId` and `_scan`, that `openHistory` keeps the manual fallback (matches `selection_controller.dart:179-189` and `selection_controller_test.dart:36-58`), and that `openHistory` clears the correction source.
