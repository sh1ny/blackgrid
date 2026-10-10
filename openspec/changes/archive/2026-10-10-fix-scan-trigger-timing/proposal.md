# Proposal

## Why

The user's first live check of the M2 Release bundle (2026-10-10) found that live scanning works but misses the item most of the time when an inspect window opens:

- **Capture is too early.** The targeted capture starts under 1 ms after the left-button release, before the game has drawn the inspect window. The frame still shows the right-click menu. The full-client fallback then finds the magnifier on its "FILTER BY ITEM" entry (score about .83, gate .82), reads that label and rejects the scan. Example: opening the Grenade case logged `rejected belowSimilarity`, OCR `FILTERBYITEM HW`.
- **The fork waits.** The reference fork waits 50 ms after the click before its cursor-area capture. It starts the full-client fallback no earlier than 200 ms after the click (`ScannerOrchestrator.cs:42`, `MainWindow.xaml.cs:727-770`). M0 recorded both (`docs/IMPLEMENTATION_STRATEGY.md:35`, M0 plan line 123), but M2 never carried them into the spec.
- **The evidence is out of sight.** The Scanner evidence panel sits under the 760 px Scanner column, so at the user's window size it is below the fold, and nothing hints that it is there.
- **The footer is wrong.** It still says "No capture • no game interaction" while live scan captures the screen.
- **An accepted item is lost.** Every later click, such as closing the inspect window, publishes a rejection that replaces the accepted item. The fork keeps the accepted item and shows the failed scan as a correction note.

This is M2 change 6. It serves the user-checked exit criterion "Live cursor-triggered capture over the game produces evidence for real items at the user's resolution and DPI, falls back visibly, and the UI stays responsive, with stage timings recorded". The first live run left that criterion unmet, so M2 cannot close until this lands and the user retests.

## What Changes

- **Settle before the targeted capture.** A scan waits until its trigger plus 50 ms (QPC clock) before requesting the targeted capture.
- **Fallback not before trigger plus 200 ms.** After a targeted pass that falls back, the fallback capture is not requested before its trigger plus 200 ms. The `fallback underway` phase is still published before that wait.
- **Waits are supersedable.** A trigger that arrives while a scan waits supersedes it at once. The newer scan starts its own wait right away. No native call is in flight during a wait, so nothing needs to drain.
- **Waits are injectable.** Both delays and the wait primitive are constructor parameters, so tests use a fake clock and completers, never real sleeps.
- **The last accepted item stays shown.** Scanner keeps showing the most recent accepted scan's evidence until a newer scan is accepted.
  - A later rejected or failed scan appears as a "not accepted" correction note above it. The note gives the reason, OCR text, marker score and the best candidate, labelled not accepted.
  - Before any scan is accepted, the latest scan's evidence is shown as today.
  - Timings and the recent-scans list still follow every published scan.
- **The evidence panel is visible without scrolling.** On the desktop Scanner layout, the scan evidence panel sits in the right column, above Recent item activity, rather than under the Scanner column. Its own content scrolls.
- **The footer shows the live scan state.** It shows the live scan state (off, starting, on, unavailable) instead of the fixed "No capture • no game interaction".
- **Unchanged:** the timing log stays schema v1. The settle wait shows up as the targeted `captureRequested` offset; no key is added.
- **Unchanged:** scan evidence still never changes the selection, the decision card or history.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `scan-pipeline`:
  - Modified: "One scan in flight, latest trigger wins" keeps the pending slot for the capture stage only.
  - "Targeted capture waits for the inspect window to settle" (50 ms after the trigger).
  - "Fallback capture waits until 200 ms after the trigger".
  - "A trigger during a wait supersedes the scan at once".
- `scanner-evidence`:
  - Modified: "Scan phase is visible, including fallback" starts the fallback phase with the fallback wait.
  - Modified: "Scanner shows the latest scan's evidence" now shows the most recent accepted scan, or the latest scan before any is accepted.
  - Added: "A later unaccepted scan is shown as a note".
  - Added: "Scan evidence panel is visible without scrolling".
  - Added: "Footer shows the live scan state".

## Impact

- **Code:**
  - `lib/application/scan_coordinator.dart`: a wait stage before each capture request; constructor parameters for the settle and fallback delays and the wait primitive; supersession during a wait; `lastAccepted` beside `latest`.
  - `lib/ui/scan_evidence_panel.dart`: the accepted view and the correction note.
  - `lib/ui/scanner_screen.dart`: the panel moves to the right column.
  - `lib/ui/shell.dart`: the footer state.
  - `lib/application/app_services.dart`: forwards the waiter and both delays to the coordinator.
  - Test rigs: they default to an immediate waiter, so no existing test waits in real time.
- **Tests:**
  - Coordinator flow tests with an injected fake wait: settle before capture, fallback deadline, supersession during each wait, a deadline already past.
  - Panel widget tests for the accepted view with a later rejection.
  - A Scanner layout test at 1660×870 checks that the panel is fully on screen without scrolling.
  - The footer test in `test/ui/shell_test.dart` is updated.
- **Docs:** the `openspec/roadmap.md` M2 list gains change 6. `docs/adr/0013` gets a note that the settle wait is visible as the `captureRequested` offset.
- **Bundle:** no new native files and no capture-boundary change.
- **Out of scope:**
  - The fork's 650×50 cursor-strip targeted region, since our targeted region is already specified in `inspection-capture`.
  - A rule against the "FILTER BY ITEM" magnifier: the fork has none, and the settle wait removes the case seen live.
  - Decisions, correction actions and history from scans (M4).
- **Safety:** agents verify only offline, with fakes. The user reruns the live check (AGENTS.md).
