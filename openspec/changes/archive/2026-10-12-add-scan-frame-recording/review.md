# Review

## Metadata

- **Round:** 1
- **Prior round:** none (this file also holds the re-check of round 1's Required Changes)
- **Reviewer:** fresh-context subagent (Claude Agent SDK, specwright-reviewer role)
- **Reviewed:** `openspec/changes/add-scan-frame-recording/` proposal.md, design.md, specs/scan-frame-recording/spec.md, specs/scan-pipeline/spec.md, specs/scanner-evidence/spec.md; `openspec/architecture.md`, `openspec/roadmap.md`; ADR-0010 to ADR-0014; `docs/qualification/m2/CORPUS.md`; `docs/IMPLEMENTATION_STRATEGY.md:236`; `test/qualification/support/inspection_corpus.dart`; `lib/application/scan_coordinator.dart` (state, `_set`, `_stop`, `_fail`, `_onTrigger`, `_abandonScans`, `_run`, `_retire`, `_flow`, `_runPass`, `_finish`, `_report`); `lib/data/capture/capture_frame.dart`, `capture_geometry.dart`, `capture_policy.dart`, `capture_service.dart`, `capture_snapshot.dart`; `lib/data/vision/vision_service.dart` (admission, `invalidate`); `lib/application/app_services.dart` (`dispose`); `test/data/capture/capture_source_audit_test.dart`; `test/data/vision/vision_worker_audit_test.dart`; `pubspec.yaml`.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. A clipped full-client frame cannot become a corpus case, and the line loses where the image sits in the client.**
- Evidence: the corpus runner refuses any image whose size is not the declared client size (`test/qualification/support/inspection_corpus.dart:53-58`, `clientSizeMismatch`). `planFallback` clips the client to the virtual desktop (`lib/data/capture/capture_geometry.dart:68-90`), so a clipped frame is `captured.width x captured.height`, not `clientWidth x clientHeight`. ADR-0010 is clip-not-pad.
- The spec scenario "Window partly off the desktop" writes `clipped: true` with the full `client` size. Read as a corpus case, that line fails the run. When the clipping is on the left or top, `captured.left/top > 0`. The PNG then starts at that offset, but the line has no field for it, so the client-pixel `cursor` cannot be mapped onto the image.
- `clipped` is also listed as a "corpus case field", but `CORPUS.md` and `parseCorpus` have no such field.
- Consequence: the spec presents an unusable case as a valid one, and nobody can convert it later without the offset.

**M2. The spec contradicts itself on which scans get a line, and leaves several end states undefined.**
- The requirement "A recorded scan writes a whole-client image and one case line" applies only to scans "that captured a full-client frame". Its scenario "No full-client frame" then writes a line with `image: null`.
- That scenario's example ("a scan fails ... because its extra capture fails with `targetChanged`") describes an accepted scan, because the extra capture runs only after a targeted acceptance (D4). It is not a failed scan.
- Some end states have neither a fallback frame nor an extra capture. These are a targeted rejection with `emptyCatalog` or `catalogModeMismatch`, `catalogUnavailable` (`scan_coordinator.dart:2040-2054`), and targeted failures outside the closed fallback list, such as `captureBusy`, `frameBudgetExceeded` or vision job failures (`:2030-2031`, `:2153-2158`). For each of them, the spec does not say whether a line is written.
- Consequence: the delta's THENs cannot be asserted consistently. An implementer must choose between the requirement text and the scenario, and the tests can pin either one.

**M3. The extra capture can change a later scan, against "Recording never blocks or changes scanning".**
- Evidence: D4 keeps the scan in `_Stage.capture` until the extra capture answers, so a new trigger goes to the pending slot (`scan_coordinator.dart:1950-1955`). Under ADR-0014 capture-stage supersession, if that answer is `captureTimeout`, the capture service stays `overrun` and answers `captureBusy` (`capture_service.dart:97-98`). The user's pending scan then "ends `ScanFailed(captureBusy)` and is logged".
- Even without a timeout, the next click waits up to 500 ms for a capture that exists only because recording is on. That wait shows in its timing line as trigger-to-capture latency.
- The scan-pipeline delta's "Trigger during the extra capture" scenario allows the wait. The scan-frame-recording requirement still says recording "SHALL NOT change any scan's passes, recognition result or publication". Flow & State Gaps and Risks do not cover the `captureTimeout` → `captureBusy` path.
- Consequence: a click made while recording can fail because of recording, and timings from recording sessions understate the latency they are meant to diagnose. The spec claims neither can happen.

**M4. The recorder's start/stop has no `starting` state and no session token, so its lifecycle can race the live-scan state.**
- Evidence: `start()` is asynchronous: folder creation, then `Isolate.spawn` (D3, D5). The state diagram goes `off → on` directly. Meanwhile `_set` can move live scan out of `ready` at any time. Examples are `_fail` from a vision worker exit (`scan_coordinator.dart:1782-1789`, `1901-1915`) and `_stop` (`:1691-1709`).
- If `stop()` arrives while `start()` is still awaiting, the spawn that completes afterwards can leave recording on while live scan is not `ready`. Nothing calls `stop()` again, which breaks the "Live scan switched off" scenario ("turning live scan back on leaves it off").
- Likewise, `setRecording(true)` while the previous session is `stopping` and still draining resets the counters (State & Ownership: "Reset at `start()`"). The old writer's late acks or failures can then land in the new session's written/dropped counts, or stop it with `writeFailed`.
- Consequence: the Scanner can show wrong counts, or recording can stay on unnoticed. The proposal exists to prevent the second.

### Suggestions

**S1. The session cap can be exceeded by the queue.** D6 stops on the ack of the 500th written scan, but up to 2 later scans can already be queued, and `stop()` lets queued scans finish (D5). The session then holds up to 502. Count queued plus written against the cap when a scan is handed to the recorder.

**S2. Case ids collide across sessions.** `_nextReportId` starts at 1 on every launch (`scan_coordinator.dart:1472`), so `scan-0001` and its PNG names repeat in every app run. The corpus needs unique ids and file names in one directory (`inspection_corpus.dart:139-141`). The new `CORPUS.md` section should prescribe a session prefix when merging sessions, or the line `id` could carry one.

**S3. One `capturedAtUtc` for up to two frames.** For a targeted acceptance, the full frame is captured after vision and matching have finished, so its content can differ from the strip, for example if the user closed the inspect window. Record the time per frame, or at least the full frame's, so a labeller can tell when the full image is later than the decision.

**S4. Align the queue wording.** D6 says "at most 2 scans accepted by the recorder and not yet acked". Resource Bounds says "2 queued, 1 encoding and 1 in flight", and the spec says "at most 2 scans waiting to be written". Use one definition so the drop test asserts the same bound everywhere.

### Re-check (round 1, re-check run)

Reviewer: fresh-context subagent (Claude Agent SDK, specwright-reviewer role). Re-checked only M1-M4 and whether the S1-S4 fixes introduced contradictions, against the current proposal.md, design.md and the three spec deltas, with `scan_coordinator.dart` (`_onTrigger`, `_retire`, `_flow`, `_fallsBackAfterRejection`, `_fallsBackAfterCapture`), `capture_frame.dart` (`CaptureFrameMetadata.captured` is in client pixels) and `capture_service.dart` (`overrun` → `CaptureBusy`, `_onDeadline`) as evidence.

- **M1: satisfied.** D7 adds `captured {left,top,width,height}` from `CaptureFrameMetadata.captured`, which the code documents as client pixels (`capture_frame.dart:45-47`), and says the full PNG covers exactly that rectangle. `clipped` is a hint field in D7 and in the spec's "labelling hints" requirement. "Window partly off the desktop" asserts `captured {200,0,1720,1080}` matching the PNG. D7 states a `clipped: true` line is not a valid corpus case as recorded and that `CORPUS.md` says so.
- **M2: satisfied.** One rule: every accepted, rejected or failed end gets a line, superseded ends none, each frame written when it exists and null otherwise. The new scenarios match the code: `catalogUnavailable` after the targeted pass ends without a fallback (`_NoIndex` at `scan_coordinator.dart:2040-2044`), and `captureBusy` is outside the fallback list (`:2153-2158`), so it has no frame at all. The extra-capture failure is now an accepted scan with `fullFailure`, not a failed scan.
- **M3: satisfied.** The requirement is narrowed to the recorded scan, the scan-pipeline delta names the wait and the `captureTimeout` → `captureBusy` outcome, which matches `capture_service.dart:96-98` and `:259-263`. D4, Flow & State Gaps, Risks and D8 record the cost and that latency is judged with recording off.
- **M4: satisfied.** D5 and the state diagram add `starting`, a per-session token checked when the start completes, token-filtered writer messages, `stop()` from `starting` → `off`, and switch-on refused while `stopping`. Both requested spec scenarios exist.
- **S1-S4 fixes:** no new contradiction with a concrete consequence in the design or specs. Three wording leftovers, non-blocking:
  - **S5.** The scan-frame-recording scenario "Switching on while the last session drains" has THEN "the switch stays off until that drain ends, and the new session's counts start at zero". D5 says the switch-on is refused, but this THEN can be read as a deferred start, and the "counts start at zero" part is only assertable after a second, separate switch-on. Reword it, for example: "the switch-on is refused and the switch stays off; a switch-on after the drain starts a new session whose counts start at zero".
  - **S6.** proposal.md still says "A full-client frame for every recorded scan" and lists the corpus case fields as "... cursor in client pixels, plus clipping", without `captured`. The specs and D7 (M1, M2) now say some lines have `image: null` and that `clipped` is a hint. Align the proposal so it does not contradict them.
  - **S7.** D4's extra capture runs after `_onTrigger` has already bumped `_scanGeneration` for a pending trigger (`scan_coordinator.dart:1947-1955`), so the usual `_dead(s)` check would treat the published scan as superseded and drop the extra frame, against "the extra frame is still recorded". Flow & State Gaps tells it apart from `_abandonScans` only in prose. Have the task for D4 name the check it uses (for example `identical(_active, s)` rather than the generation) and pin both cases with a coordinator test.

- **Follow-up re-check of the S5/S6 edits:** consistent with D5, D7 and the specs. The drain scenario now asserts a refusal with no new folder (the folder is created only in `start()`, D5/D6), the new "after the last session drained" scenario makes zero counts assertable, and the two proposal bullets now match the line rule (`image: null`, `captured`, `clipped` not a valid case) and the D4 wait. One non-blocking leftover: the proposal's next heading still reads "Recording is bounded and never blocks scanning", which is narrower in the spec (M3) but now qualified by the bullet above it. The verdict and `CHANGES_APPLIED: yes` stand.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **M1:**
   - Add `captured {left, top, width, height}` (client pixels) to the D7 line format and the spec's field list, and state that the PNG covers exactly `captured`.
   - Remove `clipped` from the "corpus case fields" wording and list it as a hint field.
   - Change the "Window partly off the desktop" scenario so that its THEN also asserts the `captured` rectangle.
   - In D7 and the planned `CORPUS.md` section, state that a `clipped: true` line is not a valid corpus case as recorded, because the runner requires image size equal to client size (ADR-0010 clip-not-pad).
2. **M2:**
   - Rewrite the "A recorded scan writes ..." requirement so that it states one rule for every non-superseded end:
     - which ends get a line (recommended: every published scan while recording is on, with `image: null` when no full-client frame exists);
     - which PNGs each end writes.
   - Fix the "No full-client frame" scenario so that its example matches the rule. Add scenarios for an accepted scan whose extra capture fails, and for a targeted end with no fallback, such as `catalogUnavailable`.
3. **M3:**
   - Narrow the "Recording never blocks or changes scanning" requirement to the recorded scan's own passes, result and publication. State that a trigger during the extra capture waits up to the 500 ms capture deadline, and that a `captureTimeout` there ends the pending scan `ScanFailed(captureBusy)`, per ADR-0014.
   - Add that case to the scan-pipeline delta as a scenario, to Flow & State Gaps, and to Risks.
   - Record in ADR-0015 (D8), and in the `CORPUS.md` note on timings, that latency is judged with recording off.
4. **M4:**
   - Add a `starting` state and a per-session token to D5, the recording state diagram and State & Ownership. `stop()` during `starting` cancels the start: the writer is killed once spawned, and the folder may remain.
   - Make the recorder ignore acks and failures from a session other than the current one.
   - Specify `setRecording(true)` while `stopping`: refused, or started only after the drain.
   - Add a spec scenario: "live scan leaves `ready` while recording is starting → recording is off and stays off".

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
Re-check: all four Required Changes are applied in proposal/design/specs as of this run. S5-S7 are suggestions and do not block.

CHANGES_APPLIED: yes

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. A Critical/Moderate rebuttal counts only once marked "accepted by reviewer". -->

- Reviewer re-check: the fixes for M1-M4 are verified as applied (see Findings, Re-check). No rebuttal needed acceptance; all four were fixed, not rebutted.
- **M1, fixed:**
  - D7 adds `captured {left,top,width,height}`, says the full PNG covers exactly that rectangle, and moves `clipped` to the hint fields.
  - D7 states that a `clipped: true` line is not a valid corpus case as recorded.
  - Spec: the line format is split into two requirements to stay under the 500-character limit, "Each case line carries the corpus case fields" (with `captured`) and "Each case line carries labelling hints" (with `clipped`). The scenario "Window partly off the desktop" now asserts `captured`.
  - The session-folder naming also moved into its own requirement, "Each recording session gets its own folder", for the same length limit; its text is unchanged.
- **M2, fixed:**
  - The requirement is renamed "Every published scan writes one case line and its frames" and states one rule: every accepted, rejected or failed end gets a line. Each frame is written when it exists, and is null otherwise.
  - Scenarios:
    - "Accepted scan whose extra capture fails" (`fullFailure`);
    - "Ended on the targeted pass without a fallback" (`catalogUnavailable`);
    - "No frame at all" (`captureBusy`).
- **M3, fixed:**
  - The recording requirement is narrowed to "Recording never changes the recorded scan, and its only effect on later scans is the extra capture", with the scenario "Later click during the extra capture".
  - The scan-pipeline delta's requirement names the `captureTimeout` → `captureBusy` outcome and adds the scenario "Extra capture overruns with a trigger pending".
  - Design: D4 "Accepted cost", Flow & State Gaps, Risks, and D8 (ADR-0015 records the cost, and that latency is judged with recording off).
- **M4, fixed:**
  - D5 adds the `starting` state, a session token checked when a start completes late, and token-filtered writer messages. A switch-on while `stopping` is refused.
  - The state diagram and State & Ownership are updated.
  - Spec scenarios: "Live scan leaves ready while recording starts" and "Switching on while the last session drains". The requirement text covers both.
- **S1, fixed:** the cap counts hand-offs (D6, the bounds requirement, the "Cap reached" scenario).
- **S2, fixed:** the id is `<session folder name>-NNNN`, and the file names are `<id>-full.png` and `<id>-targeted.png` (D6, spec).
- **S3, fixed:** `stripCapturedAtUtc` and `fullCapturedAtUtc` (D7, the "Full frame taken after the decision" scenario).
- **S4, fixed:** one definition of outstanding scans in D6, used by Resource Bounds and the spec.
- **S5, fixed after the re-check:** the scenario "Switching on while the last session drains" now asserts a refusal (switch stays off, no new folder). A new scenario, "Switching on after the last session drained", asserts that the counts start at 0.
- **S6, fixed after the re-check:** the proposal now says every published scan gets a line, adds `captured`, says a clipped frame is not a valid case, and changes "a full-client frame for every recorded scan" to "whenever one can be had", noting `image: null` ends and the wait for a click during the extra capture.
- **S7, taken into tasks.md:** the extra-capture task names the liveness check (`identical(_active, s)` plus not abandoned, never `_dead(s)`), with coordinator tests for a trigger during the extra capture and for a stop during it.
