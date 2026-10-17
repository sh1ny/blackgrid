# Tasks

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| scan-decisions → An accepted scan becomes the current selection | Accepted scan replaces a manual selection | test/application/scan_decision_feed_test.dart | accepted scan replaces a manual selection | red |
| scan-decisions → An accepted scan becomes the current selection | Manual selection after a scan | test/application/selection_controller_test.dart | manual selection after a scan stays after refresh | red |
| scan-decisions → An accepted scan becomes the current selection | Accepted scan while a history row is open | test/application/selection_controller_test.dart | accepted scan closes an open history row into the live mode | red |
| scan-decisions → Scan decisions come from the shared engine | Confirmed current need | test/application/scan_decision_precedence_test.dart | scanned confirmed current need is Keep with the need | red |
| scan-decisions → Scan decisions come from the shared engine | Unknown progress | test/application/scan_decision_precedence_test.dart | scanned item with unknown progress is Check naming progress | red |
| scan-decisions → Scan decisions come from the shared engine | Every precedence rule | test/application/scan_decision_precedence_test.dart | every precedence rule matches the hand-selected decision | red |
| scan-decisions → Unaccepted scans never change the selection | Rejected scan with a candidate | test/application/scan_decision_feed_test.dart | rejected scan with a candidate changes nothing | red |
| scan-decisions → Unaccepted scans never change the selection | Failed scan after an accepted one | test/application/scan_decision_feed_test.dart | failed scan keeps the scanned item and its FIR | red |
| scan-decisions → Each accepted scan is consumed once | Refresh after an accepted scan | test/application/scan_decision_feed_test.dart | refresh after an accepted scan records nothing new | red |
| scan-decisions → Each accepted scan is consumed once | Unrelated notification | test/application/scan_decision_feed_test.dart | notification without a new accepted scan keeps the manual item | red |
| scan-decisions → Scans from an older mode or session drive no decision | Mode changes mid-scan | test/application/scan_decision_feed_test.dart | scan from an older mode is fenced | red |
| scan-decisions → Scans from an older mode or session drive no decision | Session changes mid-scan | test/application/scan_decision_feed_test.dart | scan from an older session is fenced | red |
| scan-decisions → Scans from an older mode or session drive no decision | Item missing from the current catalog | test/application/scan_decision_feed_test.dart | scan of an item missing from the current catalog is fenced | red |
| scan-decisions → Accepted scans are recorded in history as scans | Two scans of the same item | test/data/database_test.dart | scan activity is one row per item and mode with source scan | red |
| scan-decisions → Accepted scans are recorded in history as scans | History write fails | test/application/selection_controller_test.dart | failed scan history write keeps the decision with an error | red |
| scan-decisions → FIR resets on every new accepted scan | Same item scanned again | test/application/selection_controller_test.dart | FIR resets when the same item is scanned again | red |
| scan-decisions → FIR resets on every new accepted scan | Session change | test/application/scan_decision_feed_test.dart | session change retires the scan and resets FIR | red |
| scan-decisions → Scan advice shows its age and stops being current on a mode or session change | Prices go stale after a scan | test/application/selection_controller_test.dart | stale Flea quote downgrades the scan to Check, acceptance unchanged | red |
| scan-decisions → Scan advice shows its age and stops being current on a mode or session change | Mode changes after a scan | test/application/scan_decision_feed_test.dart | mode change retires the scan and records nothing | red |
| scanner-evidence → Unaccepted scan evidence never produces a recommendation | Accepted scan drives the decision card | test/ui/scanner_screen_test.dart | accepted scan drives the decision card | red |
| scanner-evidence → Unaccepted scan evidence never produces a recommendation | Rejected scan with a best candidate | test/application/scan_coordinator_flow_test.dart | rejected scan changes no selection or history | green |

## 1. ADR and architecture

- [x] 1.1 Write `docs/adr/0017-accepted-scans-feed-the-decision-engine.md` (MADR-short: Status accepted, Date, `Supersedes: 0013 (the decision "No decisions from scans before M4")`). It records design D1-D3 and D6, each with its rejected alternative and reversal cost. ADR-0013 stays unedited. Verify: the file exists, and `docs/adr/README.md` lists it if that file indexes ADRs.
- [x] 1.2 Update `openspec/architecture.md`:
  - add 0017 to the in-force index, with 0013 noted as partly superseded;
  - rewrite the "Not built yet" line (decisions from scans are built; the hotkey, correction and the Map snapshot are not);
  - add a `ScanDecisionFeed` component row;
  - update the selection and history state-ownership rows (scan source, `scan` activity source).

  Verify: `grep -n "0017\|ScanDecisionFeed" openspec/architecture.md` shows each.

## 2. History source `scan`

- [x] 2.1 Add the failing test `scan activity is one row per item and mode with source scan` to `test/data/database_test.dart`. It records the same item twice in PvP with `ActivitySource.scan`, then expects one row with source `scan`, revision 2 and the second time, and expects it to survive `readActivity`. Verify that it fails because `recordActivity` has no source parameter (a compile error counts).
- [x] 2.2 Add `scan` to `ActivitySource` (`lib/domain/settings.dart`). Give `BlackgridDatabase.recordActivity` and `HistoryController.record` a `source` parameter defaulting to `manual`. `record` takes the failure message from its source ("Accepted scan was not recorded: local persistence failed." for `scan`). Add a `_disposed` guard to `HistoryController`, so a `load` or `record` finishing after `dispose` does not notify (review suggestion 6), with a test in `test/application/history_controller_test.dart`. Keep `schemaVersion` at 2 with no Drift migration. Verify: the 2.1 row is green, `mise run test` passes the existing database and migration tests, and the history panel labels `scan` rows (covered by 5.1).

## 3. Selection gains a scan source

Load `dart-use-pattern-matching`, `dart-write-documentation` and `dart-add-unit-test` first.

- [x] 3.1 Add the failing tests to `test/application/selection_controller_test.dart`, using `M1Harness` and calling `selectScan` directly:
  - `manual selection after a scan stays after refresh`
  - `accepted scan closes an open history row into the live mode`, which also asserts `loadingHistory` is false
  - `failed scan history write keeps the decision with an error`
  - `FIR resets when the same item is scanned again`
  - `stale Flea quote downgrades the scan to Check, acceptance unchanged`, which sets FIR yes, then advances an injected clock past the 1 h quote age; no sleeps

  Verify that they fail because `selectScan` does not exist.
- [ ] 3.2 Add `lib/application/scan_epoch.dart` with the value type `ScanEpoch(modeTransition, session)` (equality and hashCode, doc comments). Add the immutable `AcceptedScan` (report id, item id, mode, catalog revision, accepted at, epoch, `decisionAtAcceptance`) in `selection_controller.dart` or its own file.

  `SelectionController.selectScan` takes the report fields (`reportId, itemId, mode, catalogRevision, epoch`). It stamps `acceptedAt` from its own `clock` when it is called, never from `report.utc` (design D4, review round 2), and uses that time for `history.record` and the card's age. It builds the `AcceptedScan` only after its first projection, so the record is immutable from construction (review suggestion 2). It then does what design D4 lists: generation bump, clear the other sources, `loadingHistory = false`, FIR unknown, project, notify, then `history.record(..., source: scan)` behind the generation check.

  `selectManual`, `openHistory` and `closeHistory` clear the scan source, and `selectManual` also clears `loadingHistory`. Add `retireScan()`. When it retires a scan source it bumps the generation, so a pending scan-write error cannot replace the retired message (review suggestion 3). It does not bump it for a manual or history source, so a history load in flight is not stranded on "Opening stored-mode catalog…" (review round 2, suggestion 1); test `retiring a non-scan source keeps a history load alive`. It resets FIR for every source, and when the source is a scan it clears it and sets `scanRetired`, which the next select or open clears. Expose `scan` (the current `AcceptedScan?`) and `scanRetired`.

  Verify: every 3.1 row is green, and the existing selection tests still pass.

## 4. Feed, epoch stamp and wiring

- [ ] 4.1 Add the failing test `the epoch is stamped when the scan begins` to `test/application/scan_coordinator_flow_test.dart`. Its reader returns E0 at the trigger and E1 before publication, and the published `ScanReport.epoch` must equal E0 and survive `withoutCrops`. Verify that it fails because the field does not exist.
- [ ] 4.2 Give `ScanCoordinator` an optional `ScanEpoch Function()? epoch` reader (default constant). Read it in `_begin`, store it on `_Scan`, and copy it to `ScanReport.epoch`. It stays out of `toLogLine`, so log schema v1 is unchanged. Verify: the 4.1 test is green, and the existing coordinator, timing-log and audit tests pass unchanged (the coordinator still imports no selection or history).
- [ ] 4.3 Add the failing tests to `test/application/scan_decision_feed_test.dart`. The source is a hand-written `FakeAcceptedScanSource` (a `ChangeNotifier` with a settable `lastAccepted`), and the epoch reader is injected; both live in `test/application/support/`. Use the `M1Harness` selection, history and catalog. The tests:
  - `accepted scan replaces a manual selection`
  - `rejected scan with a candidate changes nothing`
  - `failed scan keeps the scanned item and its FIR`
  - `refresh after an accepted scan records nothing new`
  - `notification without a new accepted scan keeps the manual item`
  - `scan from an older mode is fenced`
  - `scan from an older session is fenced`
  - `scan of an item missing from the current catalog is fenced`
  - `session change retires the scan and resets FIR`
  - `mode change retires the scan and records nothing`

  Verify that they fail because the feed does not exist.
- [ ] 4.4 Add `lib/application/scan_decision_feed.dart` per design D1-D3. The high-water id starts at `lastAccepted?.id ?? 0` and rises before the fences. The three fences each name themselves in a `debugPrint`. `epochChanged()` calls `selection.retireScan()`. The listener has no `try`/`catch`, because `ChangeNotifier` already reports listener errors (review suggestion 1). `dispose` removes the listener.

  Wire it in `AppServices`:
  - pass the epoch reader `() => ScanEpoch(_modeTransition, mapSession.state.sessionEpoch)` to the coordinator;
  - build the feed after selection;
  - keep `_appliedSessionEpoch`, and call `feed.epochChanged()` once at the end of `_syncMapSession` when the mode block bumped `_modeTransition` or the session epoch changed (review suggestion 4);
  - dispose the feed before the scanner.

  Verify: every 4.3 row is green.
- [ ] 4.5 Add `test/application/app_services_scan_test.dart` test `accepted scan through AppServices selects and records once`. It runs the real coordinator with `ScanFakePorts`, publishes one accepted scan, and expects the selection to be the item and history to hold one `scan` row. A second notification (a phase change) must add nothing. Verify that it passes.

## 5. Precedence fixtures and the decision card

- [ ] 5.1 Add `test/application/scan_decision_precedence_test.dart` with a small fixture catalog: one item per precedence rule, plus progress fixtures, reusing the shapes in `test/domain/decision_engine_test.dart`. The tests:
  - `scanned confirmed current need is Keep with the need`
  - `scanned item with unknown progress is Check naming progress`
  - `every precedence rule matches the hand-selected decision`: for each fixture it calls `selectScan`, sets FIR yes for Flea, Trader and Price Unavailable, records the recommendation and reasons, then does the same through `selectManual` and compares

  Verify that the tests fail before group 3 is merged, or are written and run red first, then pass.
- [ ] 5.2 Replace `test/ui/scanner_screen_test.dart:88` (`decision card unchanged after accepted scan`) with `accepted scan drives the decision card`. It publishes a targeted scan for item B after a manual selection of item A, and expects:
  - the card title "Accepted scan" with item B;
  - a "Scanned … ago" subtitle;
  - history holding the manual row plus one `scan` row, with the history panel labelling it as a scan.

  Verify that it fails before 5.3.
- [ ] 5.3 Update `ItemDecisionCard` (`lib/ui/item_decision_card.dart`):
  - a scan source shows the title "Accepted scan" and the subtitle "Scanned <age> ago • shared item decision", with the age from `selection.clock` minus `scan.acceptedAt`;
  - the manual subtitle stays "not an accepted scan";
  - `scanRetired` shows "Last scan was in an earlier mode or session; scan again" in the empty state.

  Update `HistoryPanel` (`lib/ui/evidence_panels.dart`) to label `scan` rows. Load `flutter-add-widget-test` first. Verify: the 5.2 row is green, and `test/ui/map_screen_test.dart` and `test/ui/m1_flow_test.dart` still pass.

## 6. Integration checks

- [ ] 6.1 Re-run `rejected scan changes no selection or history` in `test/application/scan_coordinator_flow_test.dart`, along with its accepted-scan sibling, which still holds for the bare coordinator. Verify that both pass and flip the scanner-evidence row green.
- [ ] 6.2 Run `dart format` on the changed files, then `mise run analyze` and `mise run test`. Verify that the analyzer reports no issues and every test passes.
- [ ] 6.3 Run `openspec validate add-scan-decisions --strict`. Verify that it passes.

## Workflow follow-up

- User-verified, not run by agents: in a live session, an accepted scan updates the decision card on Scanner and Map, and history shows the scan. It is recorded as unverified until the user reports it (AGENTS.md).
- Archive with `/opsx:archive` after the PR is ready (specwright-finish, pr mode).
