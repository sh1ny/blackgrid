# Tasks

Implementer packets carry AGENTS.md "Dart and Flutter code" and the skills `dart-add-unit-test`, `dart-write-documentation` and `dart-use-pattern-matching`, plus `flutter-add-widget-test` for groups 4-5. Every check is offline (`mise run analyze`, `mise run test`). No task launches Blackgrid or needs the game.

The selection method is `showScan(AcceptedScan)`, as in design D2. The proposal's Impact list calls it `showLatestScan`.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Only an accepted scan that drives a decision advances the latest scan | Accepted scan advances the latest scan | test/application/scan_decision_feed_test.dart | accepted scan advances the latest scan without a pump | red |
| Only an accepted scan that drives a decision advances the latest scan | Other selections leave it unchanged | test/application/scan_decision_feed_test.dart | manual, history and correction leave the latest scan | red |
| Only an accepted scan that drives a decision advances the latest scan | Refresh and age update leave it unchanged | test/application/scan_decision_feed_test.dart | refresh and age tick leave the latest scan | red |
| Only an accepted scan that drives a decision advances the latest scan | Fenced scan does not advance it | test/application/scan_decision_feed_test.dart | fenced scans do not advance the latest scan | red |
| Only an accepted scan that drives a decision advances the latest scan | Unaccepted scan does not advance it | test/application/scan_decision_feed_test.dart | rejected scan does not advance the latest scan | red |
| The latest scan advances once per scan and never goes back | Newer scan replaces older | test/application/session_scan_state_test.dart | a newer report replaces the latest scan | green |
| The latest scan advances once per scan and never goes back | Repeated notification | test/application/scan_decision_feed_test.dart | repeated notification keeps the first acceptance time | red |
| The latest scan advances once per scan and never goes back | Same item scanned again | test/application/scan_decision_feed_test.dart | same item scanned again takes the second acceptance time | red |
| The latest scan is session-only and clears on a mode or session change | Empty at startup | test/application/app_services_scan_test.dart | latest scan starts empty with scan history present | red |
| The latest scan is session-only and clears on a mode or session change | Mode change clears it | test/application/scan_decision_feed_test.dart | epochChanged clears the latest scan | red |
| The latest scan is session-only and clears on a mode or session change | Session change clears it | test/application/app_services_scan_test.dart | session change through AppServices retires the scan | red |
| The decision card can return to the latest scan | Return after a manual selection | test/application/selection_controller_test.dart | showScan restores the scan without recording | red |
| The decision card can return to the latest scan | Return closes history | test/ui/latest_scan_card_test.dart | Back to latest scan closes history on Map and Scanner | red |
| The decision card can return to the latest scan | Return resets FIR | test/application/selection_controller_test.dart | showScan resets FIR | red |
| The decision card can return to the latest scan | No action while the latest scan is shown | test/ui/latest_scan_card_test.dart | no Back action while the latest scan is shown | red |
| The decision card can return to the latest scan | No action without a latest scan | test/ui/latest_scan_card_test.dart | no Back action without or after clearing a latest scan | red |
| The decision card can return to the latest scan | Stale return is refused | test/application/selection_controller_test.dart | showScan refuses a stale epoch, mode or missing item | red |
| Map shows scans in its one decision card | No separate panel | test/ui/map_screen_test.dart | Map rail has no latest-scan panel | red |
| Map shows scans in its one decision card | Scan accepted with Map open | test/ui/latest_scan_card_test.dart | a scan accepted with Map open shows on Map's card | red |
| Map shows scans in its one decision card | Scan fenced with Map open | test/ui/latest_scan_card_test.dart | a fenced scan with Map open changes nothing | red |

## 1. Snapshot state

- [x] 1.1 Write `test/application/session_scan_state_test.dart`: empty at construction; `advance` takes a higher report id ("a newer report replaces the latest scan"), ignores an equal or lower one, notifies only on change; `clear` empties it and keeps the mark, so `advance(#7)`, `clear()`, `advance(#5)` leaves it empty and `advance(#8)` takes it (review suggestion 3). Verify that it fails because the API does not exist.
- [x] 1.2 Rewrite `lib/application/session_scan_state.dart` as a documented `ChangeNotifier` with `AcceptedScan? latest`, `hasAcceptedScan`, `advance` and `clear` (design D1, D3). Remove `status`. Verify that 1.1 passes; flip its row green.

## 2. Feed producer and AppServices wiring

- [ ] 2.1 Add the feed tests from the test map to `test/application/scan_decision_feed_test.dart`, with a `SessionScanState` passed to the feed in `setUp`. The first one asserts `latest` straight after `source.accept`, with no pump (the design's synchronous-prefix risk). Fenced: wrong epoch, wrong mode, item missing from the catalog. Rejected: a non-accepted `latest` report. Run them to confirm they fail.
- [ ] 2.2 Give `ScanDecisionFeed` a required `SessionScanState scans` parameter. After `selectScan`, advance with `selection.scan` when its `reportId` equals the applied report's id. `epochChanged()` calls `retireScan()`, then `scans.clear()` (D1). Update the other constructions in `test/application/scan_correction_test.dart` (`:128`, `:538`). Verify that 2.1 passes; flip the rows green.
- [ ] 2.3 In `AppServices`, build `scans` as a `SessionScanState` (no longer `const`), pass it to the feed and dispose it in `dispose`. In `test/application/app_services_scan_test.dart`, add "latest scan starts empty with scan history present". Extend "session change through AppServices retires the scan" to assert `scans.hasAcceptedScan` is true before the change and false after it. Verify with `mise run test`; flip the rows green.

## 3. Return to the latest scan

- [ ] 3.1 Add the three `showScan` tests from the test map to `test/application/selection_controller_test.dart`. Restore: after a manual selection, `selectedId`, `item` and `decision` are those of the scan's item, `scan` is the same instance, its `acceptedAt` is unchanged and history has no new row. FIR: reset to unknown. Stale: a different epoch, mode or missing item changes nothing and logs once. Confirm that they fail.
- [ ] 3.2 Implement `SelectionController.showScan(AcceptedScan)` per D2. It sets `_scanItemId` and `_scan`, re-projects so that `item` and `decision` follow the id (review suggestion 1), bumps `_generation`, clears manual, correction, offer, history and `scanRetired`, resets FIR and records nothing. Document it. Verify that 3.1 passes; flip the rows green.

## 4. Card action and Map rail

- [ ] 4.1 Write `test/ui/latest_scan_card_test.dart`, using `pumpM1` (add an optional `scanPorts` parameter if it lacks one) to drive real accepted scans through `publishTargetedScan`. Map rows: Back closes history and shows the scan on Map and on Scanner; no Back while the latest scan is shown; no Back with no scan and after a session change; a scan accepted with Map open shows as "Accepted scan" on Map's card and in `scans.latest`; a scan fenced with Map open (mode switched mid-scan) changes neither. Confirm that they fail.
- [ ] 4.2 In `ItemDecisionCard`, listen to `selection` and `scans`, and show "Back to latest scan" in `trailing` (beside the history close button) per D4. The tooltip names the item. The tap calls `selection.showScan(services.scans.latest!)`. Verify that 4.1 passes; flip the rows green.
- [ ] 4.3 Remove the "Latest accepted scan" panel from `lib/ui/map_screen.dart`; the Active map panel keeps the first row alone. Replace the stub-text assertions in `test/ui/map_screen_test.dart:260`, `test/ui/scanner_screen_test.dart:41` and `test/widget_test.dart:17` (do not just delete them): no "Latest accepted scan" text, with the Active map panel and the decision card present ("Map rail has no latest-scan panel"). Verify with `mise run test`; flip the row green.

## 5. Docs and verification

- [ ] 5.1 Update `openspec/architecture.md`: the "Not built yet" note (line 71), the components table (the `ScanDecisionFeed` row, plus `SessionScanState` as the snapshot owner), a state-ownership row for the latest accepted scan, the §9 row (line 140) and line 168. Note that `selection.scan` can now be a returned record, not only a newly accepted scan. Verify by reading the diff: no remaining "stub" or "not built" claim about the Map snapshot.
- [ ] 5.2 Run `dart format`, `mise run analyze` and `mise run test`. Verify that all pass with no new analyzer issues, and that every test-map row is green.

## Workflow follow-up

- The user verifies the live part of the exit criterion "Map shows the latest accepted scan in its one decision card ... scanning works with Map open", when they are not in a raid. Until then it is recorded as unverified.
