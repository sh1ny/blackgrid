# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer)
- **Reviewed:** proposal.md; design.md; specs/scan-triggers/spec.md; specs/inspection-capture/spec.md; specs/release-bundle-integrity/spec.md (against openspec/specs/release-bundle-integrity/spec.md); openspec/architecture.md; openspec/roadmap.md (M2); docs/adr/0004, 0007, 0008; docs/IMPLEMENTATION_STRATEGY.md §6, §7, §13 "Display and timing matrix"; AGENTS.md; lib/data/raid_panel_ocr.dart; lib/data/vision/vision_failure.dart, vision_image.dart; windows/CMakeLists.txt; windows/runner/runner.exe.manifest; tool/vision/check_bundle.dart; tool/vision/bundle_inventory.json; reference F:\Dev\DotNet\TarkovTracker\Services\GlobalMouseHook.cs and InspectionCaptureService.cs (read-only).

- **Re-check run:** 2026-10-08, by a fresh-context subagent (Claude Code, specwright-reviewer). This run re-checked only Required Changes 1-5 against the current design.md, specs/scan-triggers/spec.md and specs/inspection-capture/spec.md. All five are applied and add no new Critical or Moderate defect. The round stays 1 because this is a re-check, not a new full review.

Arithmetic checked: all 16-cell sizes and origins, the negative-origin conversion (-1233, 307), both clipping scenarios, and the partly-off-desktop fallback match the stated formula. The cited sources hold: PerMonitorV2 is in the manifest, `visionMaxSide`/`visionMaxPixels` are 8192 / 24 Mi, the panel DLL `.sha256` install step and the hash/ABI checks exist, and the reference really does use `dpi/96` scaling with padding.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. Validation and coherence use different snapshots, so the time between them is never checked.** D3 (design.md:81) has the worker call `bgc_snapshot` (S0), validate identity, resolve the executable name (a Toolhelp listing on a cache miss), and plan the desktop rectangle from S0. Then `bgc_capture` takes its own pre snapshot (S1), runs the BitBlt and takes a post snapshot (S2). The coherence requirement (inspection-capture spec:95-96) compares the post snapshot only with "the pre-capture snapshot", and the sequence diagram (design.md:201-205) only checks pre against post. Two failures follow:
- If the user alt-tabs between S0 and S1, both S1 and S2 show the window as not foreground. They agree, so the check passes and the result contains another window's pixels.
- If the window moves between S0 and S1, the region planned from S0 points at the wrong desktop area. S1 and S2 still agree.

Both produce exactly the plausible wrong evidence that §7 and the Mechanism Ledger row "Pre/post coherence snapshot" (design.md:270) say this change prevents. The gap is not negligible: it includes Dart planning and, on a cache miss, a full process listing.

**M2. Reading the title inside the hook can block on Blackgrid's own UI thread, and the OS then silently removes the hook.** D2 (design.md:75) calls `GetWindowTextW` on the foreground window inside the low-level hook callback, justified by "no message is sent for windows of other processes". For a window in Blackgrid's own process, `GetWindowTextW` sends `WM_GETTEXT`. Because the hook runs on a dedicated DLL thread, that is a cross-thread send to the Flutter platform thread, and it waits until that thread pumps messages.

The reference avoids this by accident: it installs its hook on the WPF UI thread (GlobalMouseHook.cs:113-133), so the same call stays on one thread. Here, any click while Blackgrid is foreground and its platform thread is stalled blocks the callback. Examples of a stall: UI-isolate work (ADR-0004 puts map scene composition there), or a synchronous `bgc_hook_stop` join that waits up to 1 s on the platform thread. If the block exceeds `LowLevelHooksTimeout`, Windows silently unhooks. The design records that as "Not detected in this change" (design.md:227). The Mechanism Ledger's reason for not building a watchdog, "this callback does microseconds of work" (design.md:275), is therefore false in this case. During the stop join it can also turn a normal stop into `stopTimedOut`.

**M3. The drain and the hook have no specified order for `signalPending`, so a trigger can be stranded.** D2 says the drain "copies the events out, clears `signalPending`". The hook appends under the SRW lock, then "if the atomic `signalPending` flag was clear, sets it and posts". Neither says whether the flag is tested and cleared inside the same lock as the ring. Consider an implementation that clears the flag after releasing the lock:
1. The drain copies the ring.
2. The hook appends event E, sees the flag still set, and does not post.
3. The drain clears the flag.

E then stays in the ring with no signal until the next click. It is then delivered late with an old point, while the window still passes validation, so it is captured at the wrong time. The reverse order (flag set after the drain) causes the spurious empty drain that the "Coalesced signal" scenario (scan-triggers spec:310-312) forbids. Neither spec scenario forces the correct ordering.

**M4. Frame tickets in flight are leaked from a fixed, process-wide 4-slot budget.** `handOff()` detaches the sender's finalizer (design.md:105), so until `adopt` runs, a ticket is the only reference to a live slot. The design then drops tickets in three paths:
- "The service ignores replies once it is closed" (design.md:259).
- After `shutdownIncomplete` (design.md:111), the worker is still in the native call. When the call returns, the worker replies with a ticket for the active request before it processes `close`, and that reply reaches a closed service or a closed port.
- A late reply while the service is `Unavailable` has no transition in the admission diagram (design.md:170-184).

The registry is native and shared by the whole process (State table, design.md:216), and recovery after `unavailable` is "a new `CaptureService`" (design.md:229). Each leaked ticket therefore permanently removes one of the 4 slots, and after four leaks every capture in the process returns `frameBudgetExceeded`. The "Dropped without release" finalizer guarantee (inspection-capture spec:144, 158-160) does not cover tickets.

**M5. Blank detection depends on a byte the spec declares undefined.** The frame format is "32-bit BGRX ... with the fourth byte undefined" (inspection-capture spec:122). Blank detection is "all pixel bytes are zero" (spec:111, scenario 117-119), computed natively as `allZero` over the buffer (D3). If BitBlt writes a non-zero X byte for a black surface, a fully black exclusive-fullscreen frame reports "dark but not blank" and is returned as evidence. That is the silent coverage loss the Mechanism Ledger row "Blank-frame rejection" (design.md:271) exists to prevent. As written, the requirement contradicts itself.

### Suggestions

**S1. Restarting after `stopTimedOut` is undefined.** The scan-triggers spec (329-331) keeps the listener alive after `stopTimedOut`, but neither document says whether the native one-per-process guard is still held. If it is held, every later start returns `alreadyStarted`. If it is released, a second hook thread can coexist with the stuck one, and the stuck one may still append and signal, which breaks "After stop returns, no trigger SHALL be delivered" (spec:315). State which applies, and what change 5 should show.

**S2. Release after hand-off contradicts idempotent release.** The "Hand-off to another isolate" scenario (inspection-capture spec:156) says a release by the sender "fails with `frameReleased`". The requirement (spec:144) and "Release twice" (spec:146-148) say repeated release is a no-op. Pick one result for the sender's `release()`. A no-op with a typed status for reads only is the simpler choice.

**S3. The admission diagram has gaps.** It has no `Overrun → Unavailable` edge (worker error during an overrun) and no rule for replies that arrive in `Unavailable` or `Closed`; this ties in with M4. Add the edges so that the diagram is the full transition table that the tests will be written against.

**S4. Bundle-check roles.** `check_bundle.dart:161` selects sidecar entries with `e.role == 'panel-ocr'` only. "Reuse the panel-sidecar check" (D1) therefore needs a code change to that filter, not just new inventory rows. Name it in the tooling impact so the missing-binding scenario (release-bundle-integrity delta:243-245, 262-264) is not satisfied only by the generic inventory step.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **M1:** In design.md D3 and the sequence diagram, and in the inspection-capture spec, the requirements "Target identity is validated before capture" and "Capture is coherent with its target" must state that both the native pre snapshot and the native post snapshot are compared with the snapshot that was validated and planned against (S0). This covers ids, foreground, minimised state, client rectangle and DPI. Alternatively, pass S0's geometry and identity into `bgc_capture` and fail natively before the BitBlt on any difference. Any difference yields `targetChanged` (or `targetNotForeground`) and the frame is released. Add a scenario: "focus moves after validation but before acquisition → failure, no frame returned, live-frame count unchanged".
2. **M2:** In design.md D2 and the scan-triggers requirement "Hook callback never does capture, recognition or UI work", require that the title read cannot send a message. Either use `InternalGetWindowText`, or skip the title read (no trigger) when the foreground window's process id equals the current process id. Add a scenario: "the foreground window belongs to Blackgrid and its UI thread is blocked → the callback returns without waiting". Correct the Mechanism Ledger's "microseconds of work" justification to match.
3. **M3:** In design.md D2, specify the ordering. The hook's append and its test-and-set of `signalPending` happen under the same SRW lock. The drain clears `signalPending` and copies the ring under that lock in one critical section. Alternatively, give an equivalent ordering that provably has no lost wake-up and no empty signalled drain. Add a scan-triggers scenario for a release that arrives during a drain: it is delivered by a later signal without a further click.
4. **M4:** In design.md D8 and Flow & State Gaps, and in the inspection-capture requirement "Shutdown drains capture", require that `CaptureService` adopts and releases every ticket-carrying reply it receives in any state, including `Overrun`, `Closing`, `Closed` and `Unavailable`, and keeps its response port open until the worker exits. For the `shutdownIncomplete` case, state who releases a frame produced after close returns: for example, the worker releases its result itself when `close` is already queued. Add a scenario: "close returns `shutdownIncomplete`, the native call later returns a frame → the live-frame count returns to its prior value".
5. **M5:** In the inspection-capture requirement "Blank captures are reported" and in D3, define blank over the B, G and R bytes only, ignoring the undefined fourth byte. Add a scenario in which every colour byte is zero and the fourth byte is 0xFF, with the result `blankCapture`.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. A Critical/Moderate rebuttal counts only once marked "accepted by reviewer". -->

- **M1 fixed - verified by reviewer (re-check).** design.md D3 (line 42), the sequence diagram (S0, lines 164-168) and Flow & State Gaps (line 216) compare both pre and post with S0. Spec "Capture is coherent with its target" (inspection-capture:95-104) states the rule and adds the focus-after-validation scenario. Because this requirement now covers the S0 comparison, "Target identity is validated before capture" needs no separate edit. Author's note: The spec requirement "Capture is coherent with its target" now compares the pre and post snapshots with the validated snapshot, and adds the scenario "Focus moved after validation, before acquisition". Matching edits: design D3 and the sequence diagram (S0), plus Flow & State Gaps.
- **M2 fixed - verified by reviewer (re-check).** D2 (line 36) skips own-pid windows and uses `InternalGetWindowText`. scan-triggers:29 forbids a message-sending title read, and scan-triggers:39-41 adds the scenario. The Mechanism Ledger justification (line 239) is corrected. Author's note: The scan-triggers requirement now says the title read sends no message, with a new scenario for a foreground Blackgrid window whose UI thread is blocked. Design D2 skips own-process windows and uses `InternalGetWindowText`. The Mechanism Ledger justification is corrected.
- **M3 fixed - verified by reviewer (re-check).** D2 (line 36) puts the append and the test-and-set in one critical section, and the copy, empty and clear in one critical section under the same lock. It posts outside the lock and writes out the ordering argument. scan-triggers:54-56 adds the scenario. A minor wording point: the State table (line 178) still says "atomic compare-exchange" for the flag. That is consistent with the lock and not a defect. Author's note: Design D2 now puts the append and the test-and-set in one SRW critical section, and the drain's copy, empty and clear in one critical section under the same lock, with the ordering argument written out. The scan-triggers scenario "Release during a drain" is added.
- **M4 fixed - verified by reviewer (re-check).** D8 (line 72) adds the ticket rule for every state, keeps the port open until the worker exits, and has the worker release its own result when close is queued. The admission diagram (lines 145-146), Flow & State Gaps (line 223) and the spec "Shutdown drains capture" (inspection-capture:193, 207-213) match. Author's note: Design D8 now has the ticket rule for every state, keeps the port open until the worker exits, and has the worker release its own result when close is queued. The admission diagram gains the Overrun→Unavailable edge and a note. Flow & State Gaps is updated. The spec "Shutdown drains capture" now covers frames released in any state, and adds the scenarios "Frame produced after an incomplete shutdown" and "Reply after the worker failed".
- **M5 fixed - verified by reviewer (re-check).** D3 (line 42) computes `allZero` over B, G and R only. inspection-capture:115 and the scenario at 121-123 match. Author's note: The spec "Blank captures are reported" now checks only the B, G and R bytes, with the scenario "Black colour with a non-zero fourth byte". Design D3 says `allZero` covers BGR only.
- **S1 applied.** The scan-triggers "Hook thread does not end in time" scenario now says a later start returns `alreadyStarted`, and Flow & State Gaps has a matching entry.
- **S2 applied.** In the hand-off scenario, a sender release is now a no-op and a sender read fails with `frameReleased`.
- **S3 applied.** See M4.
- **S4 applied.** The design Context now says that `check_bundle.dart` needs a code change for the capture roles. This goes into tasks.
