# 0011 - Vision worker contract: one warm worker, service-side admission, deadline without kill, job seam, moving input ownership

- Status: accepted
- Date: 2026-10-08 (M2 change `add-vision-worker`)
- Supersedes: none
- Source: change `add-vision-worker` (design D1-D7); [implementation strategy §6](../IMPLEMENTATION_STRATEGY.md#6-scanner-strategy)

## Context and problem

The vision runtime (ADR-0008) is a synchronous owner. OpenCV is built without threads, so calls must be serialised from one owning isolate. Item recognition runs many dependent native steps per request, and a Tesseract call cannot be interrupted. Opening the runtime hashes every file and loads the model, so it must happen once, not per request. Today the only caller is the self-check, which kills its helper after 60 s; that is acceptable because the process exits next, and not for a long-lived worker.

ADR-0004 allows a long-lived isolate for blocking native work and requires the M2 worker to add the duration bound that panel OCR lacks. ADR-0010 set the pattern for a deadline that never kills the worker, and made frame tickets cross isolates. Change 4 (the recognition pipeline) and change 5 (Scanner wiring) code against whatever this change fixes.

## Decision

- **One warm worker per service.** A `VisionService` on the UI side spawns one dedicated worker isolate lazily. The worker opens the vision runtime once and owns the runtime, the templates and the scratch buffers for its lifetime. The Dart API of `VisionRuntime` is unchanged for existing callers.
- **Service-side admission.** The service holds one active request and one replaceable pending slot. It sends a request to the worker only after the worker has replied to the previous one, so there is never more than one request in flight and calls never overlap. The worker has no queue; it receives, runs and replies. A newer request replaces the pending one, which is answered `superseded` at once.
- **Generation fence on the service.** Each request is stamped with its generation at submission. A worker reply is delivered only if it matches the active sequence number, its caller is still waiting and its generation is current; otherwise it is discarded. `invalidate()` advances the generation and answers the pending and the active request `invalidated` immediately. The service keeps tracking the active call until the worker replies, so no second call starts.
- **Deadline from submission, no kill, no respawn.** One service-wide deadline, default 1.5 s, runs from submission, so time spent pending counts. At the deadline the caller gets `visionTimeout` and the service moves to `overrun`: it starts no second call until the worker replies, then discards the late result and sends the pending request if its own deadline has not passed. `Isolate.kill` is never used and the worker is not respawned. Close stops admission and drains for 2 s; if a call is still running it reports `shutdownIncomplete` and does not dispose the runtime under it. A worker exit or error makes the service `unavailable`.
- **Job seam fixed at spawn.** The service is constructed with a top-level `VisionJobFactory<P, R>` that is sent to the worker at spawn. Each request carries an input and sendable parameters `P`. The job runs synchronously in the worker as `R run(VisionJobContext context, VisionJobInput input, P params)` and returns a sendable `R` that holds no native resource. The context exposes the runtime operations, the templates by name and the monotonic clock. Change 4 provides the inspection job; this change ships test jobs only.
- **Input ownership moves with the request.** For a capture frame, the submitter passes the adopted `CaptureFrame`. The service holds it, finalizer attached, while the request is pending, and calls `frame.release()` if the request is superseded, invalidated, expired or closed. It calls `frame.handOff()` only when it sends the request, so a service dropped without `close()` cannot strand a frame slot. After the send, the worker adopts the ticket, lends pixels to the job through `withPixels` and releases the frame before it replies. If the worker dies, the service releases every ticket it sent and has not seen answered; release is generation-checked, so a frame the worker already released is a no-op. For an owned image, the layout is validated in `submit()`, so a malformed image is answered `invalidInput` without displacing the pending request, and the bytes move with `TransferableTypedData`.
- **Templates and scratch.** The service takes named 1-channel templates as constructor input and copies them into the worker at spawn. The worker validates them before the service reports `ready`: layout, exactly 1 channel and non-zero variance. A bad template fails the start with `invalidTemplate`. The worker reuses native scratch buffers instead of allocating per call and frees any buffer above 16 MiB back to 16 MiB after each request.
- **Clock.** Timestamps use the capture DLL's QPC counter (`CapturePlatform.qpcNow`, `bgc_qpc_now`), the same clock that stamps triggers and frames. Tests inject a fake clock through the same factories.
- **Not wired.** Nothing in `lib/main.dart`, `lib/application` or `lib/ui` constructs the service. An offline source-audit test enforces it. Change 5 wires it.

## Rejected alternatives

- **A queue or replaceable slot inside the worker:** the worker is blocked in a native call exactly when replacement matters, so it could not process a replace or invalidate message until the call returns. Answers would be late.
- **Killing the worker at the deadline and respawning (as the self-check does):** `Isolate.kill` cannot interrupt a native call. The native thread keeps running while a second engine opens beside it, doubling memory with an engine nobody deletes, and every overrun pays a full warm start.
- **A deadline measured from job start,** which lets queueing time grow unbounded. **The 500 ms capture deadline:** a fallback recognition of a full-client frame legitimately exceeds it, and 1.5 s is the total p95 budget from the trigger.
- **A fixed request vocabulary (match, OCR, resize messages) driven from the UI side:** one recognition takes many dependent native steps, and round-tripping each one adds latency and lets steps from different requests interleave. **A closure sent per request:** closures that capture caller state are easily non-sendable and hide what crosses the boundary.
- **The worker returning the frame to the service for release:** it holds a frame slot across an extra round trip and creates two holders. **Copying frame pixels into a Dart buffer before submitting:** it doubles memory for full-client frames and moves pixel work onto the UI isolate.
- **Zero-copy native image passing:** it needs a pointer-lending API on `CaptureFrame` and a native image type in the job context. A 1080p BGRX copy is about 8 MiB and costs a few ms against a 300 ms budget, so the gain is unproven.
- **Loading templates from a bundled asset path:** no rights-cleared templates exist, and a path and manifest entry would bind a format before change 4 knows what it needs.
- **Warm-starting at app launch:** nothing would consume it, and it would load the vision runtime on every launch, against the vision-runtime requirement for normal launch.

## Consequences

- **A hung native call leaves recognition `overrun` for the rest of the session.** It is visible as the service state and as `visionTimeout` answers. Respawn is not built until a measured hang rate justifies it.
- **The 1.5 s default is provisional.** It is a constructor parameter; change 5 may tune it or add a per-request deadline once timings exist.
- **Bounded by construction:** 1 active plus 1 pending request, at most 2 of the 4 capture frame slots held, 1.5 s deadline, 2 s close drain, 16 MiB retained scratch per buffer.
- **The job result `R` must be plain sendable data.** Frames and runtime handles never leave the worker. A job that returns a non-sendable value gets `jobFailed`. A request whose parameters `P` are not sendable is answered `invalidInput`: nothing reaches the worker, and the service takes the frame ticket back.
- **A native crash still ends the process** (ADR-0004); no isolate boundary contains it.
- **Generation counters fence results** as in ADR-0002, here on the service rather than in a controller.
- **Not wired yet:** change 5 wires the service into startup and the Scanner.
- **Reversal cost:** low for the pending slot, fences, deadline, input ownership, scratch pool and templates, which are internal to the service and worker. Medium for the job seam: change 4 codes against `VisionJobContext`, so changing it later means rewriting the pipeline.
