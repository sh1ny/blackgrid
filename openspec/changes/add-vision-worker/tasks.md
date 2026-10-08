# Tasks

## Test map

Every test runs offline. Each row is in `test/data/vision/vision_service_test.dart` unless it names another file. A worker blocked inside a native call is modelled by a holdable fake native (group 2), never by real OCR.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Worker opens the vision runtime once and keeps it warm | Warm start | vision_service_test.dart | warm start opens the runtime once in the worker and reuses one engine | green |
| Worker opens the vision runtime once and keeps it warm | Runtime unavailable at start | vision_service_test.dart | runtime failure at start makes the service unavailable without respawn | green |
| Worker opens the vision runtime once and keeps it warm | Invalid template at start | vision_service_test.dart | invalid or zero-variance template fails start with invalidTemplate and disposes the runtime | green |
| Worker opens the vision runtime once and keeps it warm | Caller mutates its template bytes after start | vision_service_test.dart | templates are copied at construction | green |
| Native vision calls never overlap | Requests run one after another | vision_service_test.dart | second job does not start while the first native call is held | green |
| Native vision calls never overlap | Deadline passes during a held call | vision_service_test.dart | deadline never starts a second native call | green |
| One active and one replaceable pending request | Pending request runs after the active one | vision_service_test.dart | pending request runs after the active one | green |
| One active and one replaceable pending request | Newer request replaces the pending one | vision_service_test.dart | newer request supersedes the pending one at once | green |
| Results are fenced by generation | Current result is delivered | vision_service_test.dart | current-generation result is delivered | green |
| Results are fenced by generation | Invalidation during an active job | vision_service_test.dart | invalidate answers the active request at once and discards its late result | green |
| Results are fenced by generation | Invalidation with a pending request | vision_service_test.dart | invalidate answers the pending request without running it | green |
| Requests have a deadline | Request finishes in time | vision_service_test.dart | request within its deadline is delivered and the service is not overrun | green |
| Requests have a deadline | Active request overruns | vision_service_test.dart | active request past its deadline answers visionTimeout and overruns until the call returns | green |
| Requests have a deadline | Pending request expires while waiting | vision_service_test.dart | pending request that expires is answered visionTimeout and never runs | green |
| Request inputs are owned and released exactly once | Frame released after success | vision_service_test.dart | frame input is released exactly once after success | green |
| Request inputs are owned and released exactly once | Superseded frame released at once | vision_service_test.dart | superseded pending frame is released before the newer request is acknowledged | green |
| Request inputs are owned and released exactly once | Malformed owned image | vision_service_test.dart | malformed owned image is rejected at submit and keeps the pending request | green |
| Request inputs are owned and released exactly once | Service dropped with a pending frame | vision_service_test.dart | pending frame keeps its finalizer until it is sent | green |
| A failing job does not break the worker | Job throws | vision_service_test.dart | throwing job answers jobFailed and the worker stays ready | green |
| A failing job does not break the worker | Native failure inside a job | vision_service_test.dart | native failure inside a job reaches the caller typed | green |
| Answers carry monotonic stage timestamps | Timestamps of a completed request | vision_service_test.dart | completed answer reports ordered submit, start and end timestamps | green |
| Answers carry monotonic stage timestamps | Request answered without running | vision_service_test.dart | superseded answer reports submission only | green |
| Shutdown drains the worker before releasing handles | Close while idle | vision_service_test.dart | close while idle disposes once and exits | red |
| Shutdown drains the worker before releasing handles | Close during warm start | vision_service_test.dart | close during warm start disposes the late-opened runtime and exits | red |
| Shutdown drains the worker before releasing handles | Close during a call that returns in time | vision_service_test.dart | close drains a call that returns within 2 s | red |
| Shutdown drains the worker before releasing handles | Close during a call that does not return | vision_service_test.dart | close reports shutdownIncomplete without disposing under a held call | red |
| Worker failure makes the service unavailable | Worker dies during a request | vision_service_test.dart | worker exit answers outstanding requests unavailable and releases their frames | red |
| Normal launch does not start the vision worker | No startup path starts the worker | test/data/vision/vision_worker_audit_test.dart | no startup path imports or starts the vision service | red |
| Normal launch does not start the vision worker | Normal launch loads no vision library | test/app/launch_mode_test.dart | no arguments selects UI mode and never constructs runtime | green |

## 1. Decision record

- [x] 1.1 Write `docs/adr/0011-vision-worker-contract.md` (MADR-short: Status, Date, Supersedes none, Context, Decision, Consequences). Cover D1-D7: one warm worker per service owning the runtime, templates and scratch; a service-side single pending slot and generation fence; a deadline from submission with `overrun` and no kill or respawn; the job seam fixed at spawn with sendable params and results; input ownership moving with the request, with pending frames keeping their finalizer; the QPC clock. Include the rejected alternatives and the reversal cost (medium for the job seam). Verify: the file exists and the ADR README index lists it.
- [x] 1.2 Update `openspec/architecture.md`. Add a component-table row for the vision worker and `VisionService` ("not wired into startup; change 5 wires it"), an "In-force ADRs" row for 0011, and replace the "Vision call duration: None until the warm worker" resource-bounds row with the 1.5 s deadline, `overrun` and 2 s drain. Adjust the "Not built yet" paragraph. Verify by reading the diff: each change cites ADR-0011.

## 2. Job seam and test harness

- [x] 2.1 Add `lib/data/vision/vision_job.dart`. It holds `VisionJob<P, R>` (`R run(VisionJobContext, VisionJobInput, P)`), the top-level `VisionJobFactory<P, R>`, `VisionJobContext` (runtime operations, `templates` by name, `qpcNow`), `VisionJobInput` (a lent frame via `withPixels` as a BGRX 4-channel `VisionImage`, or an owned `VisionImage`) and `VisionTemplate` (name plus a 1-channel image). Add the typed answer types: `VisionDelivered<R>` with timestamps, and the failures `superseded`, `invalidated`, `visionTimeout`, `closed`, `unavailable(reason)`, `invalidInput`, `invalidTemplate(name)`, `jobFailed(description)` and `visionFailure(VisionFailure)`. Verify: `mise run analyze` is clean.
- [x] 2.2 Add `test/data/vision/support/holdable_vision_native.dart`. It needs a top-level factory over shared `calloc` control addresses, modelled on `test/data/capture/support/holdable_capture_platform.dart`, that returns a fake `VisionNative`/`VisionEngine`/`VisionPrimitives` from inside the worker isolate. The control block holds a hold flag, open-hold flag, concurrent-call counter, max-concurrency, open count, engine-dispose count and a scripted native status. Add a fake QPC clock and reuse `FakeFrameRegistry` (`test/data/capture/support/fake_capture_platform.dart`) for frames. Verify: a small self-test in `test/data/vision/support/holdable_vision_native_test.dart` holds one call from a spawned isolate, and the main isolate observes the counter at 1 and then 0 after release.

## 3. Warm start and templates

- [x] 3.1 Write failing tests for rows "Warm start", "Runtime unavailable at start", "Invalid template at start" and "Caller mutates its template bytes after start". Confirm they fail because `VisionService` does not exist.
- [x] 3.2 Implement `lib/data/vision/vision_service.dart` and `lib/data/vision/vision_worker.dart`. Use lazy or explicit `start()` with a `RawReceivePort` that also receives `onExit`/`onError`, and `debugName: 'bgv_worker'`. The spawn message carries the runtime directory, the `VisionNativeOpener`, the frame-registry/platform factory, the job factory and the templates as `TransferableTypedData` plus layout, copied at construction. The worker opens `VisionRuntime` once and validates the templates (layout, 1 channel, non-zero variance; not `validateTemplate`, which needs a target). It replies `_Ready` or `_OpenFailed`, disposing the runtime on template failure. There is no respawn. Verify: the four rows turn green.

## 4. Admission, pending slot and non-overlap

- [x] 4.1 Write failing tests for rows "Requests run one after another", "Pending request runs after the active one" and "Newer request replaces the pending one", plus "Deadline passes during a held call" (max-concurrency stays ≤ 1).
- [x] 4.2 Implement service-side admission (D1). At most one request is in flight and one pending; a newer request supersedes the pending one with an immediate `superseded` answer. The pending request is sent only after the active reply arrives. A request submitted before `_Ready` is held as unsent. Verify: the four rows turn green.

## 5. Generation fences and deadlines

- [x] 5.1 Write failing tests for rows "Current result is delivered", "Invalidation during an active job", "Invalidation with a pending request", "Request finishes in time", "Active request overruns" and "Pending request expires while waiting".
- [x] 5.2 Implement generations and deadlines (D2, D3). Each request stamps the generation and gets a 1.5 s deadline from submission, set by a constructor parameter. `invalidate()` advances the generation and answers both the active and the pending request `invalidated` at once. It cancels their answering timers but keeps the active seq tracked until the reply. Keep a separate **overrun-only timer** for the active request's original deadline: when it fires it moves the service to `overrun` without answering the caller again (review note 2). A pending request's deadline answers `visionTimeout` and releases its input. Replies whose seq is not active, or whose generation is stale, are discarded. Do not port CaptureService's held-reply flush trick: the worker releases inputs before replying (review note 1). Verify: the six rows turn green.

## 6. Input ownership

- [x] 6.1 Write failing tests for rows "Frame released after success", "Superseded frame released at once", "Malformed owned image" and "Service dropped with a pending frame". The finalizer test drops a service holding a pending frame, forces GC as the capture finalizer tests do, and asserts that `FakeFrameRegistry` `effectiveReleases` and `liveCount` return to baseline.
- [x] 6.2 Implement D5. `submit` accepts a `CaptureFrame` (kept adopted, finalizer attached, while pending; `handOff()` only on send) or an owned `VisionImage` (validated in `submit()` with `VisionImage.validate`; `invalidInput` does not touch the pending slot). The worker adopts the ticket with its registry, lends pixels to the job as a BGRX 4-channel image, and releases the frame before replying on every path. The service releases each pending frame on supersede, invalidate, expire, close and unavailable. Verify: the four rows turn green, and `liveCount` is at baseline in every test's tearDown.

## 7. Job failures and timestamps

- [x] 7.1 Write failing tests for rows "Job throws", "Native failure inside a job" (scripted native status -3), "Timestamps of a completed request" and "Request answered without running". Add an extra test: a job returning a non-sendable result is answered `jobFailed`.
- [x] 7.2 Implement job error isolation (catch in the worker, reply `jobFailed(description)` or `visionFailure`, worker stays ready) and timestamps. The service reads QPC at submission; the worker reads QPC for job start and end, through the capture platform's `qpcNow` (`capture_native.dart:207`) in production and a fake clock in tests. Verify: the four rows and the extra test turn green.

## 8. Shutdown and worker failure

- [x] 8.1 Write failing tests for rows "Close while idle", "Close during warm start" (open held by the open-hold flag), "Close during a call that returns in time", "Close during a call that does not return" and "Worker dies during a request". Add an extra test that a late `_OpenFailed` during closing is ignored.
- [ ] 8.2 Implement close (D2, Flow & State Gaps). It stops admission and advances the generation. It answers the unsent, active and pending requests `closed` and releases the pending inputs. It waits up to 2 s for the in-flight call, then sends `_Close`, and the worker disposes the runtime and scratch and then exits. A late `_Ready` gets `_Close`. On drain expiry it returns `shutdownIncomplete` without disposing. Worker exit or error answers outstanding requests `unavailable` and releases sent-but-unanswered frames by id. Verify: the five rows and the extra test turn green, and the dispose count is 1 or 0 as each scenario requires.

## 9. Scratch pool

- [ ] 9.1 Write failing tests in `test/data/vision/vision_scratch_test.dart`. Repeated primitive and OCR calls of the same size allocate no new native buffer; a request above 16 MiB is trimmed back to 16 MiB retained afterwards; dispose frees everything; outputs are identical to the per-call path for each primitive on fixed fixtures.
- [ ] 9.2 Implement D6. Add a scratch pool used by `FfiVisionPrimitives` (`vision_primitives.dart:203-230`) and the Tesseract `recognise` copy (`tesseract_binding.dart:160-192`), owned per runtime and freed in `VisionRuntime.dispose`. The worker trims it after each request. Keep the `bgv_*` ABI and the public `VisionRuntime` API unchanged. Verify: 9.1 is green, `test/data/vision/vision_runtime_test.dart` and `test/application/vision_self_check_test.dart` still pass, and `mise run analyze` is clean.

## 10. Startup audit

- [ ] 10.1 Write `test/data/vision/vision_worker_audit_test.dart`. Following the capture startup audit (`test/data/capture/capture_source_audit_test.dart`, "no startup path" test), assert that no file under `lib/main.dart`, `lib/application` or `lib/ui` imports `vision_service.dart`/`vision_worker.dart` or references `VisionService`. Include a non-vacuity check that the pattern matches a planted string. Do not ban every `data/vision/` import, because `vision_self_check.dart` uses the runtime. Verify: the row turns green; re-run `test/app/launch_mode_test.dart` "no arguments selects UI mode and never constructs runtime" and confirm it stays green.

## 11. Integration check

- [ ] 11.1 Run `mise run analyze && mise run test` (the offline gate from `openspec/specwright.yaml` `pr.validate`). Verify: both pass and every test-map row is green.
- [ ] 11.2 Optional, only when a Release bundle is already built and the environment confirms Escape from Tarkov is not running: add a `@Tags(['qualification'])` test `test/qualification/m2_vision_worker_test.dart`. It starts the service against the real bundle runtime with an owned-image job that runs the self-check template match and OCR, and skips unless the bundle directory env var is set, like `m2_vision_runtime_test.dart`. Verify: `mise run test:qualification` passes it, or record it as skipped and unverified.

## Workflow follow-up

- Live checks (UI responsiveness during a real held recognition, real timings) belong to change 5 and to the user. They are not part of this change.
- After apply: `specwright-commit` verification, then `/opsx:archive` → `specwright-finish` (PR mode).
