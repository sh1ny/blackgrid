# Tasks

## Test map

`SC` = `test/application/scan_correction_test.dart` (new, service tests over `ScanDecisionFeed` + `SelectionController` with `FakeAcceptedScanSource` and `FakeScanEpochReader`). `CW` = `test/ui/scan_correction_card_test.dart` (new, narrow widget tests).

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| item-title-matching → Best and runner-up are chosen deterministically | Duplicate names | test/domain/title_matching_test.dart | duplicate normalised names keep the smaller id and skip runner-up | green |
| item-title-matching → Best and runner-up are chosen deterministically | Distinct names tie | test/domain/title_matching_test.dart | distinct names at equal score give margin 0 | green |
| item-title-matching → Best and runner-up are chosen deterministically | Ranked candidates | test/domain/title_matching_test.dart | candidates are the top five distinct names, best then runner-up first | red |
| item-title-matching → Best and runner-up are chosen deterministically | Duplicate names in the candidates | test/domain/title_matching_test.dart | duplicate normalised names appear once in the candidates | red |
| item-title-matching → Best and runner-up are chosen deterministically | Fewer candidates than five | test/domain/title_matching_test.dart | a two-item index gives two candidates | red |
| item-title-matching → Best and runner-up are chosen deterministically | Rejected before scoring | test/domain/title_matching_test.dart | results rejected before scoring carry no candidates | red |
| item-title-matching → Best and runner-up are chosen deterministically | Quantity restriction | test/domain/title_matching_test.dart | quantity restriction limits the candidates | red |
| scan-decisions → An accepted scan becomes the current selection | Accepted scan replaces a manual selection | test/application/scan_decision_feed_test.dart | accepted scan replaces a manual selection | green |
| scan-decisions → An accepted scan becomes the current selection | Manual selection after a scan | test/application/selection_controller_test.dart | manual selection after a scan stays after refresh | green |
| scan-decisions → An accepted scan becomes the current selection | Accepted scan while a history row is open | test/application/selection_controller_test.dart | accepted scan closes an open history row into the live mode | green |
| scan-decisions → An accepted scan becomes the current selection | Accepted scan after a correction | SC | accepted scan after a correction replaces it | red |
| scan-decisions → FIR resets on every new accepted scan | Same item scanned again | test/application/selection_controller_test.dart | FIR resets when the same item is scanned again | green |
| scan-decisions → FIR resets on every new accepted scan | Session change | test/application/scan_decision_feed_test.dart | session change retires the scan and resets FIR | green |
| scan-decisions → FIR resets on every new accepted scan | Correction to the item already shown | SC | correcting to the scanned item resets FIR | red |
| scan-correction → An unaccepted scan with a title offers a correction | Ambiguous scan with item A shown | SC | ambiguous scan offers a correction and keeps the selection | red |
| scan-correction → An unaccepted scan with a title offers a correction | Below-similarity scan with nothing shown | SC | below-similarity scan offers a correction with no recommendation | red |
| scan-correction → An unaccepted scan with a title offers a correction | Rejections that offer nothing | SC | other rejection reasons offer nothing | red |
| scan-correction → An unaccepted scan with a title offers a correction | Failed scan | SC | failed scan offers nothing | red |
| scan-correction → An unaccepted scan with a title offers a correction | Empty OCR text | SC | empty OCR text offers nothing | red |
| scan-correction → An unaccepted scan with a title offers a correction | Mode changed before publication | SC | scan from an older mode offers nothing | red |
| scan-correction → The offer lists the scan's best candidates | Close-named variants | SC | offer lists close variants in rank order with scores | red |
| scan-correction → The offer lists the scan's best candidates | More than five candidates | SC | offer lists at most five candidates | red |
| scan-correction → The offer lists the scan's best candidates | Weak candidates | SC | candidates below .40 are left out | red |
| scan-correction → The offer lists the scan's best candidates | Candidate gone from the catalog | SC | candidate missing from the live catalog is left out | red |
| scan-correction → The offer searches the catalog from the scan's text | Words in another order | test/domain/catalog_search_test.dart | every word must appear, in any order | red |
| scan-correction → The offer searches the catalog from the scan's text | Edited text | SC | editing the offer text searches without changing the selection | red |
| scan-correction → The offer searches the catalog from the scan's text | No results | SC | offer search with no match leaves the selection | red |
| scan-correction → Picking a correction makes it the current selection | Pick the runner-up | SC | picking the runner-up selects it as a correction | red |
| scan-correction → Picking a correction makes it the current selection | Pick from search | SC | picking a search result selects it as a correction | red |
| scan-correction → Picking a correction makes it the current selection | FIR from the earlier item | SC | a pick resets FIR | red |
| scan-correction → Picking a correction makes it the current selection | History view open | SC | a pick closes an open history view | red |
| scan-correction → Picking a correction makes it the current selection | History write fails | SC | failed correction write keeps the correction with an error | red |
| scan-correction → A correction is recorded as manual activity | Correction recorded | SC | a correction records manual activity at the pick time | red |
| scan-correction → A correction is recorded as manual activity | Correction of an item already in history | test/data/database_test.dart | a manual record after a scan row revises the same row | red |
| scan-correction → A correction stops being current on a mode or session change | Session change after a correction | SC | session change retires a correction | red |
| scan-correction → A correction stops being current on a mode or session change | Prices go stale after a correction | SC | stale Flea quote downgrades a correction to Check | red |
| scan-correction → A correction is never a new accepted scan | Correction after an accepted scan | SC | a correction is never an accepted scan | red |
| scan-correction → A correction is never a new accepted scan | Refresh after a correction | SC | refresh after a correction records nothing new | red |
| scan-correction → Only the newest offer is current | Newer offer | SC | a newer offer replaces the older one | red |
| scan-correction → Only the newest offer is current | Accepted scan clears the offer | SC | an accepted scan clears the offer | red |
| scan-correction → Only the newest offer is current | Failure keeps the offer | SC | a later failure keeps the offer | red |
| scan-correction → Only the newest offer is current | Manual selection clears the offer | SC | manual selection clears the offer | red |
| scan-correction → Only the newest offer is current | Closing a history view keeps the offer | SC | closing a history view keeps the offer | red |
| scan-correction → Only the newest offer is current | Dismiss | SC | dismiss clears only the offer | red |
| scan-correction → Only the newest offer is current | Session change | SC | session change clears the offer | red |
| scan-correction → Only the newest offer is current | Re-notification | SC | a dismissed offer is not offered again | red |
| scan-correction → A stale pick changes nothing | Offer replaced before the pick | SC | a pick from a replaced offer changes nothing | red |
| scan-correction → A stale pick changes nothing | Item removed by a catalog refresh | SC | a pick of an item no longer in the catalog changes nothing | red |
| scan-correction → A stale pick changes nothing | Mode changed before the pick | SC | a pick after a mode change changes nothing | red |
| scan-correction → The offer appears with the decision card on Scanner and Map | Offer on Map | CW | Map card shows the offer next to the item and a pick selects it | red |
| scan-correction → The offer appears with the decision card on Scanner and Map | Navigation keeps the offer | CW | the offer text is shared by the mounted Scanner and Map cards | red |

## 1. ADR and architecture

- [x] 1.1 Write `docs/adr/0018-scan-correction-is-transient-selection-state.md` (MADR-short: Status accepted, Date, Supersedes: none). It records design D1-D4 and D8, each with its rejected alternative and reversal cost, and the binding rule that only accepted reports from `AcceptedScanSource` may advance the Map snapshot (change 5). No accepted ADR is edited. Verify: the file exists, and `docs/adr/README.md` lists it if that file indexes ADRs.
- [x] 1.2 Update `openspec/architecture.md`:
  - add 0018 to the In-force ADRs index;
  - extend the `ScanDecisionFeed` row with the offer path and `_offered`;
  - extend the selection state row with the correction source and the offer;
  - extend the title matcher row with `candidates`;
  - rewrite the "Not built yet" line, dropping scan correction.

  Verify: `grep -n "0018\|correction" openspec/architecture.md` shows each.

## 2. Matcher candidates

Load `dart-add-unit-test`, `dart-write-documentation` and `dart-use-pattern-matching` first.

- [ ] 2.1 Add the five red `title_matching_test.dart` tests from the test map (ranked candidates, duplicate names, two-item index, rejected before scoring, quantity restriction). Verify that they fail because `TitleMatch` has no `candidates`; a compile error counts.
- [ ] 2.2 Add `TitleCandidate(id, score)` and `TitleMatch.candidates` (unmodifiable, default `const []`, documented). Add `maxTitleCandidates = 5`. In `matchTitle`, fill the candidates by an insertion pass over `scores` within the same pool as best: distinct normalised names, ranked by score descending, then ID. Assert in debug that `candidates[0]` is the best and `candidates[1]` the runner-up when present. Leave `toLogLine` and `frames.jsonl` unchanged. Verify: the 2.1 rows are green, and the two green rows still pass. `mise run test` passes `scan_report_test.dart` and the timing-log tests unchanged.

## 3. Offer-aware catalog search

- [ ] 3.1 Add the red test `every word must appear, in any order` to the new `test/domain/catalog_search_test.dart`, with a small synthetic snapshot: `ANA M1 OD GREEN` finds "ANA Tactical M1 plate carrier (OD Green)", and an extra word excludes it. Also cover blank text giving no results and the 8-result cap in ID order. Verify that it fails because `searchWords` does not exist.
- [ ] 3.2 Add `CatalogSnapshot.searchWords(String text, {int limit})`. It splits `normaliseTitle(text)` into words and keeps items whose existing `searchIndex` text contains every word, in ID order, up to `limit`. `search` is unchanged. Verify: the 3.1 row is green.

## 4. Correction records, feed offers and selection state

Load `dart-use-pattern-matching`, `dart-write-documentation` and `dart-add-unit-test` first. No sleeps: use `FakeAcceptedScanSource`, `FakeScanEpochReader`, an injected clock, and a completer or failing database for history writes.

- [ ] 4.1 Add the new file `lib/application/scan_correction.dart`, with doc comments:
  - the immutable `ScanCorrectionOffer` (report id, epoch, mode, catalog revision, OCR text, candidates, query);
  - `ScanCorrection` (report id, item, mode, catalog revision, `correctedAt`, epoch);
  - the constants `correctionCandidateFloor = .40` and `correctionSearchLimit = 8`;
  - the helper `correctionOfferFor(ScanReport)` (design D5): `ScanRejected` with reason `ambiguous` or `belowSimilarity`, and an outcome carrying both evidence with non-empty text and a match, else null.

  Add `ScanReport? get latest` to `AcceptedScanSource`, and a settable `latest` and `publish(report)` to `FakeAcceptedScanSource`. Verify: `mise run analyze` is clean, and every existing test still compiles and passes.
- [ ] 4.2 Write every red `SC` row of the test map in `test/application/scan_correction_test.dart`, plus `accepted scan after a correction replaces it` and `correcting to the scanned item resets FIR`. Verify that they fail because the feed makes no offers and `selectCorrection` does not exist.
- [ ] 4.3 Implement the following, per design D1, D2, D5, D6 and D7:
  - **`SelectionController`:**
    - `correctionOffer`, `correction`, `offerCorrection`, `setCorrectionQuery`, `selectCorrection(reportId, itemId)`, `dismissCorrection` and `correctionResults`;
    - offer clearing in `selectManual`, `selectScan`, `openHistory` and `retireScan`, with `closeHistory` keeping the offer;
    - the source precedence history row, then scan, then correction, then manual;
    - a pick that clears `_manualId`, `_scanItemId` and `_scan`, bumps the generation, resets FIR, and records `manual` at `correctedAt` behind the generation check, with the error "Correction was not recorded: local persistence failed.";
    - `retireScan` retiring a correction like a scan;
    - an injected epoch reader with a default that never fences.
  - **`ScanDecisionFeed`:**
    - restructure `_onSource` so the accepted path no longer returns early before the offer path;
    - add `_offered`, seeded from `source.latest` and raised before the checks;
    - offer through `correctionOfferFor` behind the epoch and mode fences, logging fenced offers like fenced scans.
  - **`AppServices`:** pass the epoch reader to selection.

  Verify: every `SC` row and both scan-decisions rows are green. `scan_decision_feed_test.dart` and `selection_controller_test.dart` stay green, including the history manual-fallback test at `selection_controller_test.dart:36-58`.
- [ ] 4.4 Add `a manual record after a scan row revises the same row` to `test/data/database_test.dart` (scan row at revision 1, then a manual record, giving one row at revision 2 with source `manual`). Add `every precedence rule matches the hand-selected decision for a correction` to `test/application/scan_decision_precedence_test.dart`: for each of the six rules, a picked correction gives the same decision as a manual selection with the same catalog, progress and FIR. Verify: both pass, and the database row is green.

## 5. Decision card offer on Scanner and Map

Load `flutter-add-widget-test` and `dart-write-documentation` first.

- [ ] 5.1 Write the two red `CW` rows in `test/ui/scan_correction_card_test.dart`, with a small synthetic catalog and the shell's mounted `IndexedStack` or both cards pumped together. Also write narrow tests for:
  - "Corrected scan" as the title, with "Corrected from scan #N", the age and "not an accepted scan" as the subtitle;
  - Dismiss;
  - search results capped at 8.

  Verify that they fail because the card shows no offer.
- [ ] 5.2 In `ItemDecisionCard`, render the offer as a bounded block next to the shown item, never in its place:
  - candidate buttons resolved from the live snapshot, with similarity;
  - a `TextField` whose controller is kept equal to `correctionOffer.query` on each notify, keeping cursor and selection while focused, with `onChanged` calling `setCorrectionQuery`;
  - up to 8 results;
  - Dismiss.

  The offer also shows when no item is selected, in place of the empty-state hint. Add the corrected title and subtitle. Verify: the `CW` rows are green, and the existing `scanner_screen_test.dart`, `map_screen_test.dart` and `scan_evidence_panel_test.dart` pass unchanged.

## 6. Integration checks

- [ ] 6.1 Run `dart format` on the changed Dart files, then `mise run analyze` and `mise run test`. Verify that both exit 0, and that every Test map row reads green.
- [ ] 6.2 `openspec validate add-scan-correction --strict` passes.

## Workflow follow-up

- Live check for the user, with the game running and never by an agent: make an `ambiguous` scan (for example ANA M1 OD Green), pick the right candidate in raid with Map open, and confirm the card shows it as corrected and the evidence panel still shows the scan as not accepted. Until the user reports it, it is unverified.
- After apply: `specwright-commit` verification, pre-ship review, then `specwright-pr` **ship**, and archive after merge.
