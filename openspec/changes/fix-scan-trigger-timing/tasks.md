# Tasks

Implementation notes:

- **Design D1, "Rejected" bullet 2 is stale.** It says "The fork measures from enqueue", but that holds only for the fork's fallback deadline. The fork's settle starts when its worker dequeues the request (`ScannerOrchestrator.cs:182-183`). ADR-0014 (task 1.1) states this correctly.
- **Test conventions (AGENTS.md):**
  - Use hand-written fakes and no sleeps.
  - Wait tests inject a recording fake `ScanWaiter` whose futures complete on `Completer`s, plus a fake QPC clock.
  - Every other rig defaults to an immediate waiter.
- **Safety:** agents verify only offline. The live retest with the game belongs to the user. Never launch the app while Escape from Tarkov runs.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| scan-pipeline → One scan in flight, latest trigger wins | Burst during capture | test/application/scan_coordinator_flow_test.dart | burst during capture keeps only the newest trigger | green |
| scan-pipeline → One scan in flight, latest trigger wins | Pending trigger meets an overrun capture | test/application/scan_coordinator_flow_test.dart | pending trigger after captureTimeout fails captureBusy and is logged | green |
| scan-pipeline → One scan in flight, latest trigger wins | Trigger during the vision stage | test/application/scan_coordinator_flow_test.dart | trigger during the vision stage invalidates at once (extended: the new scan's settle wait starts before the old job ends) | green |
| scan-pipeline → One scan in flight, latest trigger wins | Trigger during matching | test/application/scan_coordinator_flow_test.dart | trigger during matching discards the old match | green |
| scan-pipeline → One scan in flight, latest trigger wins | Triggers dropped by the native queue | test/application/scan_coordinator_flow_test.dart | droppedBefore is recorded on the scan | green |
| scan-pipeline → Targeted capture waits for the inspect window to settle | Fresh trigger | test/application/scan_coordinator_wait_test.dart | fresh trigger waits the remaining 49 ms before the targeted capture | green |
| scan-pipeline → Targeted capture waits for the inspect window to settle | Trigger already old | test/application/scan_coordinator_wait_test.dart | a trigger already 120 ms old captures without waiting | green |
| scan-pipeline → Targeted capture waits for the inspect window to settle | Switched off while waiting | test/application/scan_coordinator_wait_test.dart | switch-off during the settle wait requests no capture and publishes nothing | green |
| scan-pipeline → Fallback capture waits until 200 ms after the trigger | Quick targeted rejection | test/application/scan_coordinator_wait_test.dart | quick noMarker publishes fallback phase, then waits to trigger + 200 ms | green |
| scan-pipeline → Fallback capture waits until 200 ms after the trigger | Slow targeted rejection | test/application/scan_coordinator_wait_test.dart | targeted rejection after 260 ms falls back without waiting | green |
| scan-pipeline → A trigger during a wait supersedes the scan at once | Second click during the settle wait | test/application/scan_coordinator_wait_test.dart | second click during the settle wait supersedes at once | green |
| scan-pipeline → A trigger during a wait supersedes the scan at once | Click during the fallback wait | test/application/scan_coordinator_wait_test.dart | click during the fallback wait supersedes at once | green |
| scanner-evidence → Scan phase is visible, including fallback | Fallback becomes visible | test/ui/scan_evidence_panel_test.dart | fallback phase shows fallback underway | green |
| scanner-evidence → Scan phase is visible, including fallback | Superseded scan | test/ui/scan_evidence_panel_test.dart | superseded scan shows only the newer phase | green |
| scanner-evidence → Scanner shows the latest scan's evidence | Accepted scan | test/ui/scan_evidence_panel_test.dart | accepted report shows item, pass, score, crop and text | green |
| scanner-evidence → Scanner shows the latest scan's evidence | Rejected scan | test/ui/scan_evidence_panel_test.dart | rejected report labels best candidate not accepted | green |
| scanner-evidence → Scanner shows the latest scan's evidence | Failed scan | test/ui/scan_evidence_panel_test.dart | failed report shows failure and no candidate | green |
| scanner-evidence → Scanner shows the latest scan's evidence | Navigation keeps evidence | test/ui/shell_test.dart | scan evidence survives Map and back | green |
| scanner-evidence → Scanner shows the latest scan's evidence | Newer accepted scan replaces the shown one | test/application/scan_coordinator_flow_test.dart | lastAccepted follows the newest accepted scan only | red |
| scanner-evidence → A later unaccepted scan is shown as a note | Rejection after an accepted item | test/ui/scan_evidence_panel_test.dart | rejection after an accepted item keeps it and shows a note | red |
| scanner-evidence → A later unaccepted scan is shown as a note | Crop and timings after a rejection | test/ui/scan_evidence_panel_test.dart | after a rejection the crop is the accepted scan's and timings are the latest's | red |
| scanner-evidence → A later unaccepted scan is shown as a note | Failure after an accepted item | test/ui/scan_evidence_panel_test.dart | failure after an accepted item shows a failure note | red |
| scanner-evidence → A later unaccepted scan is shown as a note | Accepted again | test/ui/scan_evidence_panel_test.dart | a newer acceptance removes the note | red |
| scanner-evidence → Scan evidence panel is visible without scrolling | Desktop window | test/ui/shell_test.dart | scan evidence panel is fully on screen at 1660x870 | red |
| scanner-evidence → Scan evidence panel is visible without scrolling | Short desktop window | test/ui/shell_test.dart | scan evidence panel is on screen at 1100x720 with a long recent list | red |
| scanner-evidence → Scan evidence panel is visible without scrolling | Narrow window | test/ui/shell_test.dart | compact layout puts evidence right after the Scanner controls | red |
| scanner-evidence → Footer shows the live scan state | Live scan on | test/ui/shell_test.dart | footer says live scan is on when ready | red |
| scanner-evidence → Footer shows the live scan state | Live scan off | test/ui/shell_test.dart | footer says live scan is off and nothing is captured | red |
| scanner-evidence → Footer shows the live scan state | Live scan unavailable | test/ui/shell_test.dart | footer says live scan is unavailable | red |

## 1. ADR and roadmap

- [x] 1.1 Write `docs/adr/0014-scan-settle-and-fallback-waits.md` (MADR-short). It supersedes only ADR-0013's stage-specific supersession bullet and covers:
  - the `waiting` stage and its start-now rule;
  - 50 ms and 200 ms measured from the hook's QPC stamp, with no wait once a deadline has passed;
  - the fork's differences: the settle runs from dequeue, and the fallback deadline from enqueue for automatic scans only.

  Add it to the ADR index in `docs/adr/README.md` and `openspec/architecture.md`, and update the scan pipeline row. Verify: the files exist and the indexes link 0014.
- [x] 1.2 Add change 6 `fix-scan-trigger-timing` to the M2 list in `openspec/roadmap.md`, citing the failed live exit criterion. Verify: `openspec validate --all` shows no new error from this change.

## 2. Coordinator waits

- [x] 2.1 Add the `ScanWaiter` typedef and the constructor parameters `waiter`, `settleDelay` (50 ms) and `fallbackDelay` (200 ms) to `ScanCoordinator`, and forward them from `AppServices` (`scanWaiter`, `scanSettleDelay`, `scanFallbackDelay`). Make the three rigs (`test/application/support/fake_scan_ports.dart`, `test/ui/support/scan_ui_support.dart`, `test/support/m1_widget_harness.dart`) default to an immediate waiter. Verify: `mise run test` is still all green, with no behaviour change yet.
- [x] 2.2 Add `test/application/scan_coordinator_wait_test.dart`, with a recording fake waiter and a fake clock, covering the settle rows (Fresh trigger, Trigger already old, Switched off while waiting) and the fallback rows (Quick and Slow targeted rejection). Verify: each fails for the right reason (no wait requested, or capture before the deadline).
- [x] 2.3 Implement `_Stage.waiting`, `_waitUntil` (remaining time = deadline − now, capped at the delay, no wait when ≤ 0, raced against the scan's `cancelled` completer, then a `_dead` check), and the two call sites in `_flow`. The fallback wait runs after `_setPhase(fallback)`. Verify: the 2.2 tests pass, then flip their rows green.
- [x] 2.4 Add the supersession tests "second click during the settle wait supersedes at once" and "click during the fallback wait supersedes at once". Extend "trigger during the vision stage invalidates at once" to assert that the new scan's settle wait starts before the old job ends. Verify: they fail.
- [x] 2.5 Implement the `_Stage.waiting` case in `_onTrigger` (start now, complete `cancelled`), and make `_abandonScans` complete the active scan's `cancelled`. Verify: the 2.4 tests and the whole `scan_coordinator_*` suite pass, then flip the rows green and re-run the green rows of "One scan in flight".

## 3. Last accepted scan

- [x] 3.1 Add the test "lastAccepted follows the newest accepted scan only": accepted A, rejected, accepted B, failed, so lastAccepted goes A, A, B, B. Verify: it fails (no getter).
- [ ] 3.2 Implement `_lastAccepted` in `_publish` and the `lastAccepted` getter. Its doc comment says crops are kept for it as well as for `latest`. Verify: 3.1 and "crop bytes are kept only on the latest report" pass; update that test's expectation to "latest and lastAccepted" if needed, then flip the row green.

## 4. Evidence panel

- [ ] 4.1 Add widget tests in `test/ui/scan_evidence_panel_test.dart` for the four note rows: Rejection after an accepted item, Crop and timings after a rejection, Failure after an accepted item, Accepted again. Verify: they fail.
- [ ] 4.2 In `lib/ui/scan_evidence_panel.dart`:
  - show `lastAccepted ?? latest` as the main evidence;
  - add the "Last scan not accepted" note, built from `latest` when it differs from `lastAccepted`;
  - decode the crop for the shown report, keyed by its id;
  - move the TIMINGS block out of the main view, drawn for `latest` and labelled with its scan id.

  Verify: the 4.1 tests and every existing panel test pass (re-run the green rows), then flip the rows green.

## 5. Layout and footer

- [ ] 5.1 Add tests in `test/ui/shell_test.dart`: the panel is fully on screen at 1660x870; it is on screen at 1100x720 with a long recent list; the compact order is right at 900 wide; and the three footer states. Replace the footer assertion at `shell_test.dart:23`. Verify: they fail.
- [ ] 5.2 Move the evidence panel into the desktop right column above history (flex 60 to 40), and make the left column the Scanner controls only (`Expanded`, no nested scroll), as in `lib/ui/scanner_screen.dart`. Update "reference panel positions and proportions at Scanner aspect" for the new right-column layout. Verify: the 5.1 layout tests and the existing "does not overflow" tests pass.
- [ ] 5.3 Replace the constant footer text in `lib/ui/shell.dart` with a `ListenableBuilder` on `services.scanner` using the D5 texts. Verify: the 5.1 footer tests pass, then flip the rows green.

## 6. Integration

- [ ] 6.1 Run `mise run analyze` and `mise run test`, and `dart format` the changed files. Verify: both are green and every test-map row is green.
- [ ] 6.2 `mise run build:release`, only after confirming Escape from Tarkov is not running. If that cannot be confirmed, skip the build and record it as unverified. Verify: the build succeeds, or the skip is recorded.

## Workflow follow-up

- The user reruns the live check in-game. Look for the targeted `captureRequested` at about 50 ms, no `FILTERBYITEM` rejections when opening an inspect window, the panel visible, and the footer state. M2 closes only on the user's result.
- Follow-up changes from the audit:
  - recognition parity: blank-title fallback entries, Cyrillic mapping in the primary matcher, the cross-mode confirming catalog, and the ADR-0010:12/32 dpi rationale;
  - safety hardening: widen `capture_source_audit_test.dart` to all of `windows/`, add more bans, add a self-test guard-order test, and add `BEService.exe` to the game guards.
