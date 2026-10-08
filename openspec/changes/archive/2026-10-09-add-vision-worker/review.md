# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Claude Code, specwright reviewer role)
- **Reviewed:** proposal.md, specs/vision-worker/spec.md, design.md; openspec/roadmap.md (M2 change 3), openspec/architecture.md; docs/adr/0002, 0004, 0008, 0010; openspec/specs/vision-runtime/spec.md, openspec/specs/inspection-capture/spec.md; lib/data/capture/capture_service.dart, capture_frame.dart, capture_native.dart; lib/data/vision/vision_runtime.dart, vision_primitives.dart, tesseract_binding.dart, vision_image.dart, vision_failure.dart; windows/vision/vision.h; lib/application/map_session_controller.dart, vision_self_check.dart; test/data/capture/support/holdable_capture_platform.dart, test/data/capture/capture_source_audit_test.dart, test/data/vision/vision_runtime_test.dart
- **Re-check (round 1, 2026-10-08):** M1, M2 and M3 verified as applied in design.md (D2, D5, State & Ownership, T2, Flow & State Gaps) and specs/vision-worker/spec.md; the S1-S4 and S6 edits add no contradiction (the new citations capture_native.dart:207, vision_runtime.dart:362-363 and capture_service.dart:196-200 check out). Two non-blocking leftovers: the Context bullet on CaptureService still lists the held-reply flush trick as a pattern to follow, and the invalidated request's overrun needs a timer that does not answer the caller.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

Most of the design's file:line citations are accurate: capture_service.dart:29-300, :134-160, :257-261, :263-284, :364-391; capture_frame.dart:75-101, :133-154; vision_runtime.dart:100, :225, :342-365; vision_failure.dart:118; vision_primitives.dart:203-230; tesseract_binding.dart:160-192; vision_self_check.dart:239,252; map_session_controller.dart:319-363; vision_image.dart:35. The one wrong citation is listed under S2.

### Critical (blocking)

None.

### Moderate

**M1. A pending frame is held as a bare ticket, so nothing releases it if the owner drops it (this contradicts the inspection-capture spec).**
D5 has the submitter call `frame.handOff()` and pass the ticket. "While the request is pending the service holds the ticket." `handOff()` detaches the `NativeFinalizer` (`capture_frame.dart:166-174`), and a `CaptureFrameTicket` is plain data (`:96-101`). From hand-off until the request is sent or answered, no finalizer covers the frame. The in-force inspection-capture spec says: "A frame its owner drops unreleased SHALL be released by a finalizer" (`openspec/specs/inspection-capture/spec.md:152`). Consequence: if a `VisionService` with a pending request is dropped without `close()` (for example, change 5 replaces the service on a mode change without awaiting close), that frame holds one of the 4 native slots until the process exits. Every later capture then moves closer to `frameBudgetExceeded`, and nothing shows why. The same gap exists between a caller's `handOff()` and `submit()`.
Fix: `submit` takes the `CaptureFrame` itself. While the request is pending the service keeps it as an adopted `CaptureFrame` (finalizer attached) and calls `handOff()` only when it sends the request to the worker. A supersede, invalidate, expire or close then calls `frame.release()`. This also removes the separate "release a ticket through the service's registry" path for pending requests.

**M2. When an invalidated active request is answered is inconsistent, and it conflicts with the deadline rule.**
D1 says keeping the slot on the service "answers `superseded`/`visionTimeout`/`invalidated` immediately". D2 says `invalidate()` "marks the active one so its reply is discarded". The spec ("Results are fenced by generation", spec.md:51, scenario at :57-59) has the active request "answered `invalidated` when its job returns". "Requests have a deadline" (spec.md:66) then says that if the deadline passes before the request is answered, the caller gets `visionTimeout` at once. Consequence: for a request invalidated and then held past its deadline, the spec allows both `invalidated` and `visionTimeout`, so no test can assert one outcome. Also, a caller that has just changed session or mode keeps waiting up to the full job time (or the 1.5 s deadline) for an answer whose content is already known.
Fix: answer the active request `invalidated` at once in `invalidate()` and cancel its deadline timer. Its in-flight seq stays tracked, so the service still waits for the reply (non-overlap is unchanged) and discards the result. If the deadline passes during that wait, the service enters `overrun` without answering again. State this in D2 and update the spec requirement and scenario to "answered `invalidated` at once; the result returned later is discarded".

**M3. Closing during warm start is not specified.**
T2 has no `starting -> closing` edge. Neither the Flow & State Gaps nor the spec covers `close()` before the worker sends `_Ready`/`_OpenFailed`. A vision warm start hashes every manifest file and loads the model (`vision_runtime.dart:146-205`), so it is the longest window in the service's life. Close in that window is likely: change 5 starts the service lazily, and the user can leave Scanner straight away. `CaptureService` handles this only because `_onMessage` sends `_Close` when `_Ready` arrives in `closing`/`closed` (`capture_service.dart:196-200`). The vision worker must also dispose a runtime it has only just opened. Consequence: if this path is left unspecified and untested, the worker can end with the engine and libraries still loaded. A replacement service would then open a second engine in a new worker beside the leaked one, which is the doubled-engine state D2 rejects respawn to avoid.
Fix: add `starting -> closing` to T2. Add a Flow & State Gaps entry: close during start answers the unsent and pending requests `closed`, and a later `_Ready` gets `_Close`, which disposes the runtime and ends the worker. A later `_OpenFailed` just completes the exit. Add a spec scenario under "Shutdown drains the worker...": "WHEN the service is closed while the worker is still opening the runtime THEN close completes (or reports `shutdownIncomplete` if the open outlasts the drain), and once the open finishes the runtime's dispose runs exactly once and the worker exits".

### Suggestions

**S1. Validate an owned image on the service side, before admission.** D5(b) and the spec ("Malformed owned image", spec.md:91-93) validate in the worker. Because admission comes first, a malformed request submitted while a valid one is pending supersedes the valid one (spec.md:40), then itself fails `invalidInput`, so the valid work is lost. `VisionImage.validate()` is pure Dart (`vision_image.dart:35-62`) and can run in `submit()` before the pending slot is touched. The worker can keep its check as a second line of defence.

**S2. Fix the audit citation, and match on identifiers rather than imports.** D8 cites `capture_source_audit_test.dart:83-93`, but those lines audit native `.cpp` sources for banned Win32 APIs. The startup-path audit is the "no startup path imports or starts the trigger source" test (around lines 142-169). That test bans any `data/capture/` import. Copied for vision as "no `data/vision/` import", it would fail on day one, because `lib/application/vision_self_check.dart:10-11` legitimately imports `data/vision/`. The vision audit should match the service's file or class name (for example `vision_service.dart` / `VisionService`).

**S3. Remove the held-reply flush trick and the "reply ticket" wording, which no longer apply.** D5 has the worker release the input frame before it replies, and T4's `_Reply` carries no ticket. The Flow & State Gaps entries "Close while a reply is in the worker's held slot: ... releases the frame" and "Out-of-order replies: ... its ticket released" describe capture's design, where the reply carried a frame (`capture_service.dart:364-391`). Here the trick has nothing to release, and the Mechanism Ledger does not list it. Remove both mentions, or state what the trick protects in this design.

**S4. Allocation failure is reported as status -5, not -4.** The Resource Bounds table says a scratch allocation failure gives `nativeFailure(-4)`. `-4` is `BGV_ERR_NO_MEMORY`, a native `std::bad_alloc` (`windows/vision/vision.h`). A failing Dart-side `calloc` throws, and `_run` maps any non-`VisionNativeError` exception to `VisionNativeFailure(-5, ...)` (`vision_runtime.dart:362-363`). Either make the pool throw `VisionNativeError(-4)`, or correct the table, so a test does not assert the wrong code.

**S5. Do not start a pending request whose remaining budget cannot cover a run.** With the deadline measured from submission (D3), a pending request that starts with only a little budget left almost always times out mid-run. The service then sits in `overrun` while a run whose result will be discarded blocks a fresher request. Consider a minimum remaining budget at dispatch, below which the request is answered `visionTimeout` without running. It can wait for change 5's timings, but it belongs in the ledger's "Evidence that would change the call".

**S6. Name the template check and the clock seam precisely.** D7 says templates are checked with "`validateTemplate` layout plus non-zero variance". `VisionImage.validateTemplate` needs a target image (`vision_image.dart:65-80`), and none exists at start. The start-time check is `validate()` plus `channels == 1` plus variance. Separately, the spec requires submission, job start and job end on the same QPC clock as capture (spec.md:107). Today the only QPC source is `CapturePlatform.qpcNow()` (`capture_native.dart:475`), so the design should name the sendable clock function used on both the service side and the worker side.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (M1) In D5, the State & Ownership row "Pending request's frame ticket" and the spec requirement "Request inputs are owned and released exactly once": the service accepts the `CaptureFrame`, holds it adopted (finalizer attached) while pending, calls `handOff()` only when it sends the request to the worker, and releases it with `frame.release()` on supersede, invalidate, expire or close. Add a spec scenario: "WHEN a service with a pending frame request is dropped without close THEN the frame is released by its finalizer".
2. (M2) In D2 and in the spec requirement "Results are fenced by generation" with its scenario "Invalidation during an active job": the active request is answered `invalidated` at once when `invalidate()` is called. Its deadline timer is cancelled, the in-flight seq stays tracked until the worker replies, and the late result is discarded. If the job outlasts the original deadline, the service enters `overrun` but does not answer the caller again.
3. (M3) Add `starting -> closing` to the T2 state machine, add a Flow & State Gaps entry for close during warm start (a late `_Ready` gets `_Close`, which disposes the runtime and ends the worker), and add the matching spec scenario under "Shutdown drains the worker before releasing handles".

CHANGES_APPLIED: yes

## Rebuttals

Author, after round 1:

- **M1 fixed:** D5 (the service holds the adopted `CaptureFrame` with its finalizer while pending and calls `handOff()` on send), the State & Ownership row, the spec requirement "Request inputs are owned and released exactly once" (pending frames keep their finalizer), and the new scenario "Service dropped with a pending frame".
- **M2 fixed:** D2, and the spec requirement "Results are fenced by generation" (both requests are answered `invalidated` at once, and the late result is discarded without a second answer). The scenario "Invalidation during an active job" now asserts no `visionTimeout` and `overrun` until the call returns. The "Requests have a deadline" text covers an invalidated active request entering `overrun`.
- **M3 fixed:** a `starting --> closing` edge in T2, a Flow & State Gaps entry "Close during warm start", and the spec scenario "Close during warm start".
- **S1 fixed:** owned images are validated in `submit()` (D5), and the scenario "Malformed owned image" keeps the pending request.
- **S2 fixed:** the D8 citation is corrected, and the audit matches the service's file and class name, not every `data/vision/` import.
- **S3 fixed:** the flush-trick gap is replaced by "Close while the worker is finishing a job", and the "ticket released" wording is gone from the out-of-order replies entry.
- **S4 fixed:** the scratch-pool row now says -5 (Dart allocation, through `_run`) or -4 (native).
- **S5 recorded as not built:** a mechanism-ledger row "Minimum remaining budget", with the evidence that would change the call.
- **S6 fixed:** D7 drops `validateTemplate` at start (layout, 1 channel and variance only), and D4 names the clock (`CapturePlatform.qpcNow` / `bgc_qpc_now`, on both the service and the worker side).

