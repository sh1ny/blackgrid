# Proposal

## Why

Milestone **M2 - capture/recognition proof**, change 3 of 5. The vision runtime (change 1) is a synchronous owner that only the self-check helper and tests call, and its OCR and template-match calls can block for an unbounded time (ADR-0004, ADR-0008 both defer the bound to this change). Recognition (change 4) and the Scanner slice (change 5) need one warm place to run those calls off the UI isolate, with latest-wins coordination that never starts a second call on the OCR handle and never publishes stale output.

This change advances the M2 exit criterion: *"A blocked or slow native call cannot freeze the UI isolate, cannot start a second call on the same OCR handle, and cannot publish after supersession or shutdown. Fixture tests use controlled native barriers."* (agent-verified). It also prepares the "UI stays responsive" part of the live criterion that the user checks after change 5.

## What Changes

- A **vision worker**: one long-lived dedicated isolate that opens the vision runtime once (hash check, ABI check, engine init) and keeps it warm. It owns the OCR engine handle, the marker templates it is given at start, and reusable native scratch buffers, and releases all of them on shutdown.
- A **vision service** on the caller side with **one active plus one replaceable pending request**. A newer request replaces the pending one, which is answered `superseded`. A request never starts while another native call is running on the worker.
- **Generation fences**: every request carries the service generation at submission. `invalidate()` (for session or mode changes) advances the generation; results of older generations are dropped, not delivered.
- A **duration bound**: each request has a deadline. When it passes, the caller is answered `visionTimeout` and the service reports `overrun` until the native call returns. No second call starts, and the late result is discarded, never published.
- **Explicit buffer ownership**: requests carry either a capture frame ticket (adopted by the worker under the existing ticket contract, ADR-0010) or an owned image transferred by `TransferableTypedData`. Every input is released exactly once on every path: success, failure, supersession, deadline, invalidation and shutdown.
- **Drain on shutdown**: closing stops admission, invalidates publication, answers pending work `closed`, and waits a bounded time for the active native call before disposing the runtime and ending the worker. If the call has not returned, close reports `shutdownIncomplete` and never disposes handles under a running call.
- A **pluggable job seam**: the worker runs one recognition job per request against a context (runtime operations, templates and scratch). This change ships the seam and test jobs. The real inspection pipeline is change 4.
- Not wired into app startup or the UI. Normal launch still loads no vision library (change 5 wires the service).

## Capabilities

### New Capabilities
- `vision-worker`: the warm worker isolate that owns the vision runtime, its admission (one active plus one replaceable pending request), generation fences, the per-request deadline, input ownership and release, and drain on shutdown.

### Modified Capabilities
None. `vision-runtime` behaviour is unchanged: the runtime still verifies, loads and operates as specified, and normal launch still does not load it. `inspection-capture`'s ticket hand-off already allows a third isolate to adopt a frame.

## Impact

- **New code:** `lib/data/vision/` worker and service (isolate, messages, job seam, scratch arena). Possibly internal changes to `vision_primitives.dart` / `tesseract_binding.dart` so that worker-owned scratch buffers replace per-call `calloc` copies. The `bgv_*` ABI is unchanged.
- **Reuses:** `VisionRuntime.open`/`dispose`, `VisionResult`/`VisionFailure` (`VisionTimeout` already exists), `CaptureFrame.adopt`/`withPixels`/`release` and `openDefaultFrameRegistry`, and the `CaptureService` admission, deadline and drain pattern.
- **Tests:** offline fixture tests with a holdable fake native (a top-level factory over shared control addresses, modelled on `test/data/capture/support/holdable_capture_platform.dart`), so blocked and slow calls are controlled barriers. There are no live-game checks. A qualification-tagged test may exercise the real bundle runtime through the worker.
- **Docs:** architecture.md (component table, resource bounds, "not built yet"), ADR-0004 consequences are honoured but not edited. If the decisions warrant one, a new ADR covers the worker contract.
- **Out of scope:** marker template sourcing and rights (templates are inputs here), the recognition pipeline and its gates (change 4), Scanner wiring, trigger→capture→worker flow and timing UI (change 5), and hotkeys (M4).
