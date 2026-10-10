# 0014 - Scan settle and fallback waits: a supersedable `waiting` stage, 50 ms and 200 ms deadlines from the trigger's QPC stamp

- Status: accepted
- Date: 2026-10-10 (M2 change `fix-scan-trigger-timing`)
- Supersedes: [ADR-0013](0013-scan-pipeline-coordination.md), its "Latest trigger wins, with stage-specific supersession" bullet only. The rest of ADR-0013 stays in force.
- Source: change `fix-scan-trigger-timing` (design D1, D2); [implementation strategy §6](../IMPLEMENTATION_STRATEGY.md#6-scanner-strategy)

## Context and problem

The user's first live check of the M2 Release bundle (2026-10-10) showed the targeted capture starting under 1 ms after the left-button release, before the game had drawn the inspect window. The frame still showed the right-click menu. The full-client fallback then found the magnifier on its "FILTER BY ITEM" entry, read that label and rejected the scan (`rejected belowSimilarity`, OCR `FILTERBYITEM HW`).

The reference fork waits 50 ms before its cursor-area capture (`ScannerOrchestrator.cs:42`, `AutomaticSettle`) and starts its full-client fallback no earlier than 200 ms after the click (`MainWindow.xaml.cs:727-770`). M0 recorded both (`docs/IMPLEMENTATION_STRATEGY.md:35,196`), but ADR-0013 did not carry them over. A wait also adds a fourth scan stage, and ADR-0013's supersession rules are stated per stage.

## Decision

- **A `waiting` stage before each capture request.** `ScanCoordinator._flow` waits before the targeted capture request and again before the fallback capture request. A wait makes no native call and holds no frame.
- **Deadlines are measured from the trigger's QPC stamp.** The targeted deadline is the trigger's QPC plus 50 ms (`settleDelay`), and the fallback deadline is the trigger's QPC plus 200 ms (`fallbackDelay`), converted with the activation's QPC frequency. The wait lasts `deadline − now`, capped at the configured delay so that a missing clock cannot produce a long wait. Once a deadline has passed there is no wait: a pending trigger that starts late, or a targeted pass slower than 200 ms, goes straight to its capture.
- **The `fallback` phase is published before the fallback wait,** so the fallback stays visibly underway while it waits.
- **Latest trigger wins, with stage-specific supersession** (replaces the ADR-0013 bullet). The coordinator holds one in-flight scan and one pending trigger slot. A new trigger marks the active scan superseded and drops (and counts) any older pending trigger. How the new one starts depends on the old scan's stage:
  - *Waiting:* start now, with no pending slot. The trigger completes the old scan's `cancelled` completer, so its wait ends at once; the old scan sees it is dead, requests no capture and is logged as superseded.
  - *Capture:* unchanged from ADR-0013. Wait for the capture answer (within the 500 ms deadline), release the old frame, then start the pending trigger. If that answer is `captureTimeout`, the pending scan ends `ScanFailed(captureBusy)` and is logged.
  - *Vision:* unchanged. Call `vision.invalidate()` and start now; the new scan's settle wait starts without waiting for the old job.
  - *Matching:* unchanged. Start now and discard the old `Isolate.run` result by its generation.

  Switching off, losing the pipeline or disposing also completes the active scan's `cancelled`, so a waiting scan ends superseded at once with no capture request. A superseded scan is logged and never published.
- **The waits are injectable.** `ScanCoordinator` takes `waiter` (a `ScanWaiter`, `Future<void> Function(Duration)`, defaulting to a `Timer`-backed future), `settleDelay` and `fallbackDelay`; `AppServices` forwards them. Test rigs default to an immediate waiter, and wait tests use a recording fake waiter with a fake clock, never real sleeps.
- **The timing log stays schema v1.** The settle wait shows as the targeted `captureRequested` offset (about 50 ms) and the fallback wait as the fallback `captureRequested` offset (at least 200 ms). No key is added.
- **Differences from the fork, chosen on purpose:**
  - The fork's settle starts when its worker dequeues the request and always waits the full 50 ms (`ScannerOrchestrator.cs:182-183`). Blackgrid measures from the hook's QPC stamp, so time already spent before the coordinator handled the trigger counts toward the 50 ms.
  - The fork measures its fallback deadline from enqueue (`EnqueuedAtUtc`) and applies it to automatic scans only (`MainWindow.xaml.cs:763-768`). Blackgrid applies both waits to every scan the coordinator runs. Whether the M4 hotkey keeps the fallback wait is M4's call.

## Rejected alternatives

- **A debounce in the native hook or in `MouseReleaseTriggerSource`:** it puts scan policy into the capture DLL boundary (ADR-0010), cannot express the fallback deadline, and a held trigger could not be superseded without native queue changes.
- **Measuring from when the coordinator receives the trigger:** it adds Dart scheduling jitter. The QPC stamp is the closest equivalent to the fork's enqueue time.
- **Putting a trigger that arrives during a wait into the pending slot:** it would delay the newer click by up to 200 ms for no reason; no native call is in flight that needs draining.
- **New timing-log keys for the waits:** ADR-0013 freezes v1, and the `captureRequested` offsets already show them.
- **Configurable delays in the settings UI:** the fork's constants are fixed, and parity is the target.
- **Re-capturing when the frame still shows the context menu, or a rule against the "FILTER BY ITEM" magnifier:** the fork has neither, and the settle wait removes the case seen live.

## Consequences

- **Every scan's targeted capture starts about 50 ms after the click,** and a fallback no earlier than 200 ms after it. That latency is spent inside the M4 latency budget (targeted ≤300 ms p95).
- **Rapid clicks cancel waits at once.** A superseded waiting scan holds only a timer until it fires (≤200 ms), and no frame.
- **If 50 ms proves too short on the user's machine,** the log's `captureRequested` offset and OCR text show it, and the delay is a single constant.
- **Reversal cost:** low. Internal to the coordinator; the defaults are single constants.
