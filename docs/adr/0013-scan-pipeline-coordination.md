# 0013 - Scan pipeline coordination: one app-scoped coordinator, template-vision-hook start order, latest-wins supersession, closed fallback list, JSONL timing log v1

- Status: accepted
- Date: 2026-10-10 (M2 change `add-scanner-evidence-slice`)
- Supersedes: none
- Source: change `add-scanner-evidence-slice` (design D1-D10); [implementation strategy §6](../IMPLEMENTATION_STRATEGY.md#6-scanner-strategy)

## Context and problem

Changes 2 to 4 built the parts of live scanning and left them unstarted: the mouse-release trigger source and `CaptureService` (ADR-0010), `VisionService` and its warm worker (ADR-0011), and the recognition job and off-UI matching adapters (ADR-0012). Nothing in `lib/application`, `lib/ui` or `lib/main.dart` references them, and two source audits enforce that. This change starts them and shows what they find in the Scanner, without letting scans drive any decision.

Several things have to be fixed together, because M4 (hotkeys, decisions, history) codes against them:

- who owns the activation and the scan flow, and in what order the pieces start;
- what happens when a click arrives while an earlier scan is still running, given that native capture and OCR calls cannot be cancelled;
- when a failed targeted pass is retried as a full-client pass;
- how recognition learns the client size, which the policy knows and frames did not carry;
- what the on-disk timing log looks like, since M4 tooling will read it.

## Decision

- **One app-scoped `ScanCoordinator`** (`lib/application/scan_coordinator.dart`, a `ChangeNotifier`) is built by `AppServices` and disposed first. It owns the activation state, the scan flow, the published evidence and the trigger source. Per activation it creates a fresh `CaptureService` and `VisionService<InspectionRequest, InspectionRecognition>` through injected factories. Its work on the UI isolate is bookkeeping only (drain signal, stage hand-offs, fences, notifications). Native and CPU work stays in the capture worker, the vision worker and `Isolate.run`. The trigger source and the UI-side capture platform are created once and kept for the app's lifetime, because a process can have one hook.
- **Start order is template, then vision, then hook.** Load the marker template in one `Isolate.run`, construct the services and `await vision.start()`, then open the capture platform and start the trigger source. Each step checks an activation token. Switching off or disposing during `starting` advances the token and closes every service already constructed at once, so a hung runtime open is bounded by the 2 s vision close drain. The hook step is skipped when the token is stale. Because the hook starts last, a trigger can never arrive before `ready`.
- **Session intent is owned by the coordinator.** `liveScan` is a new `AppSettings` key (JSON default `false`, no Drift migration). `ScanCoordinator.setLiveScan(bool)` is the sole writer of the session intent. The coordinator reads `settings.liveScan` once, after `AppServices.initialize()`, and never listens to settings changes afterwards. Switching on sets the intent only after a successful `SettingsController.save`; a failed or busy save reverts the switch and starts nothing. Switching off stops the pipeline at once, before and regardless of the save; a failed save shows that the preference was not saved, keeps the switch off for the session and never reinstalls the hook.
- **Latest trigger wins, with stage-specific supersession.** The coordinator holds one in-flight scan and one pending trigger slot. A new trigger marks the active scan superseded and drops (and counts) any older pending trigger. How the new one starts depends on the old scan's stage:
  - *Capture:* wait for the capture answer (within the 500 ms deadline), release the old frame, then start the pending trigger. If that answer is `captureTimeout`, the capture service stays `overrun` and answers `captureBusy`. The pending scan still starts at once, ends `ScanFailed(captureBusy)` and is logged. It does not wait for the overrun worker, because `CaptureService` exposes no completion signal for it.
  - *Vision:* call `vision.invalidate()`, which answers the old request `invalidated` at once (ADR-0011), and start the pending trigger now. Its request waits in the service's pending slot and the 1.5 s deadline counts that wait.
  - *Matching:* start now. The `Isolate.run` result is discarded by its generation. A new match starts only when no superseded match is still running.

  A superseded scan is logged and never published. Every stage hand-off checks the scan generation.
- **Fallback eligibility is a closed list.** A full-client fallback pass (same `TriggerEvent`, `CaptureMode.fallback`, `InspectionFrameKind.fullClient`) runs after a targeted pass ends in one of:
  - an `OutcomeRejected` whose reason is not `emptyCatalog` or `catalogModeMismatch`, and not the pipeline's `catalogUnavailable`;
  - a capture failure of `RoiOutsideClient`, `BlankCapture` or `TargetChanged`.

  Every other end state ends the scan: identity failures, `captureBusy`, `captureTimeout`, `captureClosed`, `captureUnavailable`, `frameBudgetExceeded`, and any vision non-delivery or job failure. Those would fail again or overload a worker that is already `overrun`. If the fallback also fails after a targeted capture failure, the scan ends `ScanFailed` with the fallback failure and records the targeted one. If it fails after a targeted rejection, the scan ends `ScanRejected` with the targeted outcome and records the fallback failure. The `fallback` phase is published before the fallback capture request. The matcher gets `targeted: null` when the targeted pass produced no recognition. There is no other retry.
- **Frames carry the validated client size.** `CaptureFrameMetadata` gains `clientWidth` and `clientHeight`, filled by `CapturePolicy` from the validated snapshot `s0.client`. The coordinator builds `InspectionRequest(kind, clientWidth, clientHeight)` from the frame it holds, before `submitFrame`.
- **One title index per catalog snapshot.** The coordinator listens to `CatalogController`; when the snapshot identity changes it starts `buildTitleMatchIndexOffUi` and caches one `(snapshot, Future<TitleMatchIndex?>)`, mapping a build error to null. With no snapshot or a failed build, a scan is rejected `catalogUnavailable`, and the next snapshot change retries.
- **Timings are QPC stamps converted once.** Each scan keeps a timeline of nullable QPC stamps (trigger, coordinator reads of `CapturePlatform.qpcNow()`, frame `qpcBefore`/`qpcAfter`, vision answer `submittedQpc`/`startedQpc`/`finishedQpc`, and each pass's evidence stamps). They are converted to milliseconds from the trigger when the scan ends, using `qpcFrequency()` read once per activation. A pass's sub-stage stamps come from its own evidence (winning entry, else first entry), so a winning fallback does not overwrite the targeted job timings.
- **The timing log is JSONL, schema v1.** `ScanTimingLog` (`lib/data/scan_timing_log.dart`) writes `<root>/logs/scan-timings.jsonl` (`LocalPaths.logs`), one line per ended scan, appended exactly once by the coordinator. Line shape:

  ```
  {"v":1,"utc":…,"end":"accepted|rejected|failed|superseded","item":…,"reason":…,"pass":"targeted|fallback",
   "targeted":{"bestMarker":…,"candidates":[{"id":…,"score":…}],"text":…,"failure":…},"fallback":{…},
   "ms":{"trigger":0,"published":…,
         "targeted":{"captureRequested":…,"acquireStart":…,"acquireEnd":…,"captureAnswered":…,"visionSubmitted":…,
                     "jobStarted":…,"marker":…,"title":…,"preprocess":…,"ocr":…,"jobFinished":…,
                     "matchStarted":…,"matchFinished":…},
         "fallback":{…same keys…}},
   "droppedTriggers":n,"supersededTriggers":n,"droppedLines":n}
  ```

  All `ms` values are milliseconds from the trigger; keys of stages not reached, and a pass that did not run, are omitted. One async loop writes lines in order (open with append, write, close). Before a write that would take the file past 1 MiB, the current file is renamed to `scan-timings.1.jsonl`, replacing any earlier one, so at most 1 MiB current plus 1 MiB previous exist. The write queue holds 32 lines; when full the new line is dropped and counted, and the next written line carries `droppedLines`. A write error sets the log status to `unavailable(error)` and later appends keep trying. Closing in `AppServices.dispose` (after the coordinator) flushes the queue within 1 s and drops the rest. The log holds OCR text but no pixels.
- **Failure values are mapped in the coordinator.** `ScanReport` holds no `data/capture/` or `VisionService*` types. `scan_coordinator.dart` maps every capture failure, trigger failure, vision answer and start failure into UI-facing values defined there: a `ScanFailureCode` enum plus a message. It is the only file under `lib/application` or `lib/ui` that the two narrowed source audits (`vision_worker_audit_test.dart`, `capture_source_audit_test.dart`) allow to reference the capture and vision services. The panel needs no `data/capture/` import and no `VisionService*` name. Recognition results (`inspection_evidence.dart`) and outcomes (`domain/title_matching.dart`) stay allowed imports.
- **No decisions from scans before M4.** `ScanCoordinator` takes `CatalogController` (read only) and `SettingsController`, never `SelectionController` or `HistoryController`. Accepted identities are shown as evidence and do not reach keep/sell advice (ADR-0001). A unit test asserts selection and history are unchanged after accepted and rejected scans, and a widget test asserts the decision card is unchanged.

## Rejected alternatives

- **Capture, recognition and fallback policy together inside the vision worker,** triggered by frame tickets from the hook: it merges the capture and vision isolates that ADR-0010 and ADR-0011 keep apart, puts retry and fallback policy in the worker, and lets a blocked OCR call block the next capture.
- **Hook first, hold triggers until vision is ready:** a system-wide hook that can do nothing useful, and the bounded native ring would silently drop the held clicks.
- **A session-only switch:** the user chose persistence.
- **Following settings changes after init:** a later unrelated save that still carries `liveScan: true` (after a failed switch-off save) would restart the pipeline.
- **FIFO queueing of every trigger:** clicks in a raid are frequent, so the queue goes stale, which strategy §6 forbids.
- **Ignoring triggers while busy:** loses the user's most recent intent.
- **A completion signal from `CaptureService` for an overrun worker,** to start the pending trigger then: it changes a finished boundary (ADR-0010) for a rare case that the log already shows.
- **Targeted and fallback captures in parallel for every trigger:** capture admits one request at a time, and it would double full-client work on every click.
- **Fallback only on `noMarker`:** the reference also falls back on title rejections, and parity is the target.
- **A separate snapshot call for the client size,** or deriving it from `requested`: the first adds a native call on the UI isolate and races with resizes; the second is wrong for targeted frames and for fallback frames clipped by the desktop.
- **Building the title index per scan,** or on the UI isolate: the first adds work to every click, the second causes a jank spike.
- **`Stopwatch` timings on the UI isolate:** its clock differs from the trigger and frame clocks and it misses the time before Dart received the trigger.
- **A Drift table for the log:** it adds a migration and contention with the database isolate, and blurs M4 history, which has different retention.
- **Synchronous log writes on the UI isolate:** a stalled disk would freeze the UI.
- **Fsync or crash-safe atomic rotation:** it is a diagnostic log; a crash between rename and append leaves a missing current file that the next append recreates.
- **The vision worker encoding a PNG per evidence entry:** adds worker time on the latency path for a UI-only need.
- **Feeding accepted identities into `SelectionController` now:** that is M4 scope and would make advice depend on evidence not yet qualified.
- **No ADR:** M4 reads the log format and codes against the supersession and fallback behaviour.

## Consequences

- **A global low-level mouse hook is installed in production,** but only after an explicit switch-on, and it is removed on switch-off and exit. The hook callback contract is unchanged (ADR-0010) and the process-access audit stays.
- **Fallback runs a full-client recognition on every unaccepted click** (parity with the reference). Latest-wins plus the vision pending slot bound the work to about one job, and the log shows the cost.
- **Rapid clicks cost evidence.** Superseded scans are logged but not published, and the log counts dropped and superseded triggers.
- **A `captureTimeout` is followed by a `captureBusy` scan** until the capture worker replies. This is visible in the log, not avoided.
- **An overrun vision worker turns later scans into `visionTimeout`** until the native call returns (no kill, ADR-0011).
- **The first scan after activation includes the capture worker spawn,** because `CaptureService` has no warm-up API. The timings show it.
- **A mode change mid-scan** matches against the old cached index and records the old mode and revision; the next scan sees `catalogUnavailable` until the new snapshot loads. M4 adds the fences for decisions.
- **The log is a diagnostic aid, not an audit trail:** up to about 2 MiB of history, no durability across crashes, older lines discarded by design. Reports are memory-only (10 newest); M4 history owns persistence.
- **The log format is a contract with M4 tooling.** A change to the keys needs a new `v`.
- **The source audits narrow to exactly one allowed file,** and keep rejecting every other startup or UI reference. A test proves an off launch loads no vision library and installs no hook.
- **Reversal cost:** medium for the coordinator shape, latest-wins supersession and the log schema, which shape the M4 latency profile and tooling. Low for the start order details, fallback list, index caching and client size in the metadata (internal, sendable, never persisted).
