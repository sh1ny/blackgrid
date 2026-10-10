# Proposal

## Why

M2 (capture/recognition proof) has every part built but nothing connected. The mouse-release hook and capture service (change 2), the warm vision worker (change 3) and the inspection recognition job and title matcher (change 4) exist, but no app path starts them. Scanner still shows only manual inspection. This is change 5 of 5, the last one in M2. It connects those parts so that a real click over an item inspection produces visible evidence. That lets the user run the remaining live check: "live cursor-triggered capture over the game produces evidence for real items at the user's resolution and DPI, falls back visibly, and the UI stays responsive, with stage timings recorded" (user).

It also serves two agent-verified exit criteria in the running app, not only in harnesses:

- A blocked or slow native call cannot freeze the UI isolate, start a second call on the same OCR handle, or publish after supersession or shutdown.
- The Release bundle's DLLs and models are loaded only from the bundle.

## What Changes

- **Live scan switch.** A persisted Scanner setting, off by default.
  - **On:** load the bound marker template, start the vision worker and wait until it is ready. Only then install the mouse-release hook.
  - **Off, or app shutdown:** remove the hook, abandon the scan in flight, and close the capture and vision workers within their existing drain bounds.
  - **Unavailable:** if the vision runtime, marker template or hook cannot start, Scanner says why and no hook stays installed.
- **One owner of the scan flow.** Each trigger runs targeted capture, then targeted recognition in the vision worker, then title matching off the UI isolate.
  - If the targeted pass is not accepted, a full-client fallback pass runs: capture, recognition, then ranking of both passes.
  - At most one scan is in flight. The newest trigger waits in a single replaceable slot and supersedes the scan in flight. A superseded or stopped scan never publishes.
- **Evidence in Scanner.** A new evidence panel shows the scan phase, including a visible "fallback underway" state. It also shows the marker score, thresholded title crop, OCR text, best and runner-up candidates with their scores and margin, and the accepted item or the typed rejection or failure. Stage timings come last.
  - No keep/sell recommendation, correction or history comes from scan evidence. The existing decision card is still driven only by manual selection (M4).
- **Stage timings.** Each scan records monotonic stage timestamps: trigger, capture, vision queue and run (with job sub-stages), matching and publication, for the targeted pass and, when it runs, the fallback pass.
  - The timings are shown in the panel.
  - Each scan is also appended as one JSON line to a size-capped log in the app's local data folder. The line holds no pixels and no crop.
- **Frame provenance gains the client size.** Each captured frame reports the physical client width and height it was validated against. A targeted region alone cannot give the processing scale that recognition needs.
- **Startup rules change.** Normal launch with live scan off still installs no hook, loads no vision library and starts no worker. With live scan on, the app starts them through the scan pipeline only. This replaces the earlier rule that no startup path may start them.

## Capabilities

### New Capabilities
- `scan-pipeline`: Live scan activation and teardown, the per-trigger targeted→fallback flow, single in-flight scan with a replaceable pending trigger, publication fences, failure visibility, stage timings and the bounded timing log.
- `scanner-evidence`: What Scanner shows for live scans: switch and status, scan phase including fallback, per-scan evidence and timings. It never derives a recommendation from scan evidence.

### Modified Capabilities
- `inspection-capture`: "Frames carry their provenance" adds the validated client width and height.
- `vision-worker`: "Normal launch does not start the vision worker" becomes "the vision worker starts only through live scanning". Launch with live scan off still loads no vision library.
- `vision-runtime`: "Normal app launch does not load the vision runtime" now applies while live scan is off. The scan pipeline's vision worker may load the runtime while live scan is on.
- `inspection-recognition`: "Recognition runs only as a vision-worker job" keeps the worker-only rule. Its "normal launch constructs no job" clause now applies only while live scan is off.

## Impact

- **Code:**
  - New: an application-layer scan coordinator in `lib/application/`, a timing log writer under `lib/data/` and a Scanner evidence panel in `lib/ui/`.
  - Changed: composition root `lib/application/app_services.dart` (owns and disposes the coordinator), `lib/domain/settings.dart` (new `liveScan` key with default false, so no Drift schema migration), `lib/ui/scanner_screen.dart`, and `lib/data/capture/capture_policy.dart` with `capture_frame.dart` (client size in metadata).
- **Tests:**
  - The source audits `test/data/vision/vision_worker_audit_test.dart` and `test/data/capture/capture_source_audit_test.dart` currently forbid any startup path from referencing the service or trigger source. They are narrowed to allow only the coordinator. The ban on calling process-access APIs is kept.
  - New coordinator tests use the existing holdable, fake and clock platforms. New widget tests cover the evidence panel.
- **Docs:**
  - A new ADR records the scan coordinator contract and the timing log format, which the M4 latency gate will read.
  - `openspec/architecture.md` component and ownership rows update. "Not wired" notes are removed.
- **Bundle:** no new native files. The app now opens the existing bundle-bound vision runtime, marker template and capture DLL at runtime while live scan is on.
- **Out of scope (M4):** hotkeys, decisions from scans, correction, history, the accepted Map snapshot (`SessionScanState` producer), and the latency gate itself.
- **Safety:** agents verify only offline, with fakes. Live-game verification belongs to the user (AGENTS.md).
