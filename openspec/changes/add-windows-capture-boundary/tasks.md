# Tasks

## Test map

Test locations:

- **Dart fixtures:** `test/data/capture/`, run by `mise run test`.
- **Real-DLL Dart test:** `test/data/capture/capture_native_qualification_test.dart`, tagged `qualification` and run by `mise run test:qualification`. It skips with a recorded reason when a game process is listed.
- **Native cases:** `windows/capture/selftest.cpp`, run by `mise run capture:selftest`. That task links the DLL's internal sources plus the real `bgc_*` ABI, and refuses to run while the game is running.
- **Bundle check:** `test/tool/vision/check_bundle_test.dart`.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| scan-triggers → Mouse-release trigger records cheap target facts | Release over the target window | windows/capture/selftest.cpp | `filter_accepts_target_release_with_signed_point` | green |
| scan-triggers → Mouse-release trigger records cheap target facts | Release over another window | windows/capture/selftest.cpp | `filter_rejects_other_title` | green |
| scan-triggers → Mouse-release trigger records cheap target facts | Press, right button and wheel | windows/capture/selftest.cpp | `filter_rejects_non_left_release_messages` | green |
| scan-triggers → Mouse-release trigger records cheap target facts | No foreground window | windows/capture/selftest.cpp | `filter_rejects_null_foreground` | green |
| scan-triggers → Hook callback never does capture, recognition or UI work | Event passed on | windows/capture/selftest.cpp | `hook_proc_always_calls_next_hook` | green |
| scan-triggers → Hook callback never does capture, recognition or UI work | Dart isolate is busy | windows/capture/selftest.cpp | `append_returns_without_drain_and_keeps_order` | green |
| scan-triggers → Hook callback never does capture, recognition or UI work | Blackgrid's own window is foreground with a blocked UI thread | windows/capture/selftest.cpp | `filter_skips_own_process_without_title_read` | green |
| scan-triggers → Trigger queue is bounded | Queue overflow | windows/capture/selftest.cpp | `ring_drops_oldest_and_reports_count` | green |
| scan-triggers → Trigger queue is bounded | Coalesced signal | windows/capture/selftest.cpp | `signal_coalesces_until_drain` | green |
| scan-triggers → Trigger queue is bounded | Release during a drain | windows/capture/selftest.cpp | `append_after_drain_resignals` | green |
| scan-triggers → Hook lifecycle is explicit | Start then stop | test/data/capture/capture_native_qualification_test.dart | `hook starts and stops and drains nothing after stop` | red |
| scan-triggers → Hook lifecycle is explicit | Second start | test/data/capture/capture_native_qualification_test.dart | `second hook start returns alreadyStarted` | red |
| scan-triggers → Hook lifecycle is explicit | Installation refused by the OS | windows/capture/selftest.cpp | `install_failure_reports_error_and_ends_thread` | green |
| scan-triggers → Hook lifecycle is explicit | Hook thread does not end in time | test/data/capture/trigger_source_test.dart | `stopTimedOut keeps the listener open and blocks restart` | red |
| scan-triggers → Hook lifecycle is explicit | Normal startup | test/data/capture/capture_source_audit_test.dart | `no startup path imports or starts the trigger source` | red |
| inspection-capture → Target snapshot | Window on a left/top secondary monitor | test/data/capture/capture_policy_test.dart | `snapshot decode keeps signed negative origins` | red |
| inspection-capture → Target snapshot | Window no longer exists | test/data/capture/capture_native_qualification_test.dart | `snapshot of destroyed handle is targetGone` | red |
| inspection-capture → Target identity is validated before capture | Valid target | test/data/capture/capture_policy_test.dart | `valid target passes validation` | red |
| inspection-capture → Target identity is validated before capture | Focus moved after the click | test/data/capture/capture_policy_test.dart | `foreground change is targetNotForeground without capture` | red |
| inspection-capture → Target identity is validated before capture | Minimised target | test/data/capture/capture_policy_test.dart | `minimised target fails without capture` | red |
| inspection-capture → Target identity is validated before capture | Wrong executable behind the title | test/data/capture/capture_policy_test.dart | `wrong executable is wrongTarget without capture` | red |
| inspection-capture → Target identity is validated before capture | Handle reused by another process | test/data/capture/capture_policy_test.dart | `pid change is targetGone without capture` | red |
| inspection-capture → Targeted region is planned in physical client pixels | Sixteen resolution and scaling cells | test/data/capture/capture_geometry_test.dart | `targeted region for all 16 resolution and DPI cells` | red |
| inspection-capture → Targeted region is planned in physical client pixels | Click on a negative-origin monitor | test/data/capture/capture_geometry_test.dart | `negative-origin monitor maps to client and back` | red |
| inspection-capture → Targeted region is planned in physical client pixels | Trigger point outside the client | test/data/capture/capture_geometry_test.dart | `trigger outside client is roiOutsideClient` | red |
| inspection-capture → Fallback region is the visible full client | Full client on one monitor | test/data/capture/capture_geometry_test.dart | `fallback plans the whole client` | red |
| inspection-capture → Fallback region is the visible full client | Client partly off the desktop | test/data/capture/capture_geometry_test.dart | `fallback clips to the virtual desktop` | red |
| inspection-capture → Clipping is explicit, never padded | Region crosses the right edge | test/data/capture/capture_geometry_test.dart | `right-edge region is clipped not padded` | red |
| inspection-capture → Clipping is explicit, never padded | Region crosses the top-left corner | test/data/capture/capture_geometry_test.dart | `top-left region is clipped not padded` | red |
| inspection-capture → Clipping is explicit, never padded | Region entirely off-screen | test/data/capture/capture_geometry_test.dart | `off-desktop region is roiOutsideClient` | red |
| inspection-capture → Capture size is bounded | Large but allowed client | test/data/capture/capture_geometry_test.dart | `3840x2160 fallback is within bounds` | red |
| inspection-capture → Capture size is bounded | Oversized client | test/data/capture/capture_geometry_test.dart | `7680x4320 fallback is captureTooLarge` | red |
| inspection-capture → Capture is coherent with its target | Stable target | test/data/capture/capture_policy_test.dart | `stable pre and post return the frame` | red |
| inspection-capture → Capture is coherent with its target | Focus moved after validation, before acquisition | test/data/capture/capture_policy_test.dart | `pre snapshot differing from validated is targetChanged and releases` | red |
| inspection-capture → Capture is coherent with its target | Window moved during acquisition | test/data/capture/capture_policy_test.dart | `moved client is targetChanged and releases` | red |
| inspection-capture → Capture is coherent with its target | Monitor DPI changed during acquisition | test/data/capture/capture_policy_test.dart | `dpi change is targetChanged and releases` | red |
| inspection-capture → Blank captures are reported | Black frame from an unsupported display mode | test/data/capture/capture_policy_test.dart | `allZero frame is blankCapture and released` | red |
| inspection-capture → Blank captures are reported | Black colour with a non-zero fourth byte | windows/capture/selftest.cpp | `all_zero_ignores_fourth_byte` | green |
| inspection-capture → Blank captures are reported | Dark but not blank | windows/capture/selftest.cpp | `all_zero_false_for_one_colour_byte` | green |
| inspection-capture → Frames have an immutable pixel layout | Frame layout | test/data/capture/capture_policy_test.dart | `targeted frame reports layout and desktop origin` | red |
| inspection-capture → Frames have an immutable pixel layout | Pixel access after release | test/data/capture/capture_frame_test.dart | `pixels after release throw frameReleased` | red |
| inspection-capture → Frames carry their provenance | Frame provenance | test/data/capture/capture_policy_test.dart | `frame carries request id identity and ordered timestamps` | red |
| inspection-capture → Frames carry their provenance | Clipped provenance | test/data/capture/capture_policy_test.dart | `clipped frame reports both rectangles` | red |
| inspection-capture → Frame ownership is single and bounded | Release twice | test/data/capture/capture_frame_test.dart | `second release is a no-op` | red |
| inspection-capture → Frame ownership is single and bounded | Budget exhausted | windows/capture/selftest.cpp | `registry_refuses_fifth_frame` | green |
| inspection-capture → Frame ownership is single and bounded | Hand-off to another isolate | test/data/capture/capture_frame_test.dart | `handOff moves ownership across isolates` | red |
| inspection-capture → Frame ownership is single and bounded | Dropped without release | test/data/capture/capture_native_qualification_test.dart | `finalizer entry releases the slot` | red |
| inspection-capture → Capture runs off the UI isolate with single admission | One capture at a time | test/data/capture/capture_service_test.dart | `second request while active is captureBusy` | red |
| inspection-capture → Capture runs off the UI isolate with single admission | UI stays responsive during a slow capture | test/data/capture/capture_service_test.dart | `caller isolate keeps ticking during a 3 s native hold` | red |
| inspection-capture → Captures have a deadline that never starts a second native call | Native call overruns | test/data/capture/capture_service_test.dart | `overrun times out stays busy and releases late frame` | red |
| inspection-capture → Captures have a deadline that never starts a second native call | Next capture after recovery | test/data/capture/capture_service_test.dart | `request admitted after late reply` | red |
| inspection-capture → Shutdown drains capture | Close while idle | test/data/capture/capture_service_test.dart | `close while idle exits worker and refuses later captures` | red |
| inspection-capture → Shutdown drains capture | Close during a capture | test/data/capture/capture_service_test.dart | `close during capture returns captureClosed and releases` | red |
| inspection-capture → Shutdown drains capture | Native call never returns | test/data/capture/capture_service_test.dart | `close reports shutdownIncomplete after 2 s without killing` | red |
| inspection-capture → Shutdown drains capture | Frame produced after an incomplete shutdown | test/data/capture/capture_service_test.dart | `frame after shutdownIncomplete is released` | red |
| inspection-capture → Shutdown drains capture | Reply after the worker failed | test/data/capture/capture_service_test.dart | `ticket reply in unavailable state is released` | red |
| inspection-capture → The target process is never touched | Source audit | test/data/capture/capture_source_audit_test.dart | `capture sources call no process-access or input APIs` | red |
| inspection-capture → The target process is never touched | Executable name lookup | windows/capture/selftest.cpp | `exe_name_from_toolhelp_for_own_pid` | green |
| inspection-capture → Native self-test captures only its own window | Game not running | windows/capture/selftest.cpp | `captures_own_window_pattern_and_geometry` | green |
| inspection-capture → Native self-test captures only its own window | Game running | windows/capture/selftest.cpp | `guard_refuses_when_listing_contains_game` | green |
| inspection-capture → Native self-test captures only its own window | Own window not foreground | windows/capture/selftest.cpp | `capture_checks_skip_when_not_foreground` | green |
| release-bundle-integrity → Bundle inventory is exact | Complete bundle passes inventory | test/tool/vision/check_bundle_test.dart | `inventory passes on synthetic complete bundle` | green |
| release-bundle-integrity → Bundle inventory is exact | Unexpected DLL | test/tool/vision/check_bundle_test.dart | `inventory fails naming unexpected dll` | green |
| release-bundle-integrity → Bundle inventory is exact | Missing expected file | test/tool/vision/check_bundle_test.dart | `inventory fails naming missing model` | green |
| release-bundle-integrity → Bundle inventory is exact | Capture library missing | test/tool/vision/check_bundle_test.dart | `inventory fails naming missing capture library or binding` | green |
| release-bundle-integrity → Each runtime-verified file matches its binding and pin | Bindings and pins agree | test/tool/vision/check_bundle_test.dart | `hash step passes when manifest, sidecar and lock agree` | green |
| release-bundle-integrity → Each runtime-verified file matches its binding and pin | Binding disagrees with file | test/tool/vision/check_bundle_test.dart | `hash step fails naming file and both hashes` | green |
| release-bundle-integrity → Each runtime-verified file matches its binding and pin | Third-party file differs from pin | test/tool/vision/check_bundle_test.dart | `pin step fails when bound file diverges from lock` | green |
| release-bundle-integrity → Each runtime-verified file matches its binding and pin | Capture binding disagrees with file | test/tool/vision/check_bundle_test.dart | `hash step fails naming capture library and both hashes` | green |

The two existing tests that change (complete bundle, and bindings agree) start red, because their synthetic bundle must now include the capture files.

## 1. Architecture record

- [x] 1.1 Write `docs/adr/0010-windows-input-and-capture-boundary.md` (MADR-short: Status, Date, Supersedes none, Context, Decision, Consequences) from design D1-D9 and the ADRs section. Add it to the In-force ADRs index in `openspec/architecture.md`, and update that file's Components table, Boundaries (capture ABI), Resource bounds (trigger ring, frame slots, capture deadline and drain), the "Not built yet" paragraph and the Strategy-vs-code row on input and capture. Verify: the ADR exists, and `openspec/architecture.md` mentions `blackgrid_capture.dll`, the 16-event ring, the 4 frame slots and the 500 ms deadline.

## 2. Native capture DLL and self-test

- [x] 2.1 Scaffold `windows/capture/` with these files:
  - `capture.h`: the `bgc_*` ABI, `BGC_ABI_VERSION 1`, the snapshot, frame-info and event structs, and status codes.
  - `capture_internal.h`: the filter, ring, all-zero and registry seams.
  - `CMakeLists.txt`: a static-CRT `blackgrid_capture` SHARED target linked against `user32` and `gdi32`, plus a `blackgrid_capture_selftest` executable with `EXCLUDE_FROM_ALL`.
  - `windows/CMakeLists.txt`: `add_subdirectory("capture")`, plus the install and `blackgrid_capture.dll.sha256` steps that mirror panel OCR.
  - `mise.toml`: a `capture:selftest` task that builds the self-test target in the Flutter CMake tree and runs it.

  Verify: `flutter build windows --release` installs the DLL and its sidecar, and the sidecar equals the file's SHA-256.
- [x] 2.2 Write the native self-test harness with failing cases `guard_refuses_when_listing_contains_game`, `capture_checks_skip_when_not_foreground`, the filter, ring, signal and hook-proc cases, `install_failure_reports_error_and_ends_thread`, `all_zero_*`, `registry_refuses_fifth_frame` and `exe_name_from_toolhelp_for_own_pid`. The guard runs first in `main`, before any hook or capture, over an injectable process listing, and exits 2 when it finds `EscapeFromTarkov.exe` or `EscapeFromTarkov_BE.exe`. Verify: before running, confirm with `tasklist` that no game process is listed (AGENTS.md). Then `mise run capture:selftest` reports each case failing for the missing implementation.
- [x] 2.3 Implement the hook thread per D2: install on a dedicated thread, filter with own-process skip and `InternalGetWindowText`, append and test-and-set under one SRW critical section, post outside the lock, signal from the loop through `WM_APP` to the listener, drain under the same lock, stop with a 1 s join, and keep the guard held on timeout. Verify: the filter, ring, signal, hook-proc and install-failure self-test cases pass; flip their rows green.
- [x] 2.4 Implement `bgc_snapshot` (window queries plus toolhelp executable name; no `OpenProcess`), `bgc_capture` (pre snapshot, DIB section top-down 32 bpp from 4 generation-checked slots, screen-DC `BitBlt`, post snapshot, BGR-only `allZero`), `bgc_frame_info`, `bgc_frame_release`, `bgc_frame_live_count`, a finalizer entry point, `bgc_qpc_now` and `bgc_qpc_frequency`. Verify: `all_zero_*`, `registry_refuses_fifth_frame`, `exe_name_from_toolhelp_for_own_pid` and `captures_own_window_pattern_and_geometry` pass, the last one capturing only the self-test's own foreground window. Flip those rows green, or record `captures_own_window...` as skipped (not passed) if the foreground could not be taken.

## 3. Dart binding, failures and source audit

- [ ] 3.1 Write failing `test/data/capture/capture_source_audit_test.dart`. It scans `windows/capture/*.{h,cpp}` for the banned identifiers (word-boundary match) and checks that nothing under `lib/application/`, `lib/ui/` or `lib/main.dart` imports `lib/data/capture/` or starts the trigger source. Verify: it fails until the sources exist, then passes; flip both audit rows green.
- [ ] 3.2 Add `lib/data/capture/capture_failure.dart`: sealed `CaptureFailure` and `TriggerFailure` with the D3 catalogue, and a `CaptureResult` sealed result. Add `lib/data/capture/capture_native.dart`: an FFI binding that verifies the absolute path, `.sha256` and `bgc_abi()` before any lookup (like `raid_panel_ocr.dart:186-206`), plus a `CapturePlatform` seam interface that fakes implement. Verify: `mise run analyze` is clean.

## 4. Capture geometry (pure Dart)

- [ ] 4.1 Write failing `test/data/capture/capture_geometry_test.dart` covering the planning, fallback, clipping and size rows. Expected values are written independently in the test table, not computed by the code under test. Verify: the tests fail for the missing implementation.
- [ ] 4.2 Implement `lib/data/capture/capture_geometry.dart`: the D4 exact-rational planner, the full-client fallback, clipping against the client and virtual desktop (D5), and the side and pixel bounds (8192 / 25,165,824). Verify: `capture_geometry_test.dart` passes; flip its 10 rows green.

## 5. Validation, coherence and frames

- [ ] 5.1 Write failing `test/data/capture/capture_policy_test.dart` (snapshot decode, identity validation, coherence, blank, layout and provenance rows) against a fake `CapturePlatform` that records release calls. Write failing `test/data/capture/capture_frame_test.dart` (release twice, read after release, hand-off across two isolates through a fake registry). Verify: both fail for the missing implementation.
- [ ] 5.2 Implement `lib/data/capture/capture_target.dart` (title and executable allow-list), `capture_policy.dart` (validate against S0, plan, capture, compare pre and post with S0, blank check, release on every reject, executable-name cache keyed by `(hwnd, pid, tid)`) and `capture_frame.dart` (`CaptureFrame implements Finalizable`, `NativeFinalizer` on the release entry, `pixels` view, `handOff`/`adopt` tickets, idempotent release). Verify: both test files pass; flip their rows green.

## 6. Capture service and worker isolate

- [ ] 6.1 Write failing `test/data/capture/capture_service_test.dart`. Use a fake native platform, created in the worker from a top-level factory and controlled by barrier ports, covering admission, the 3 s responsiveness hold (count caller-isolate timer ticks), overrun and late release, recovery, the three close cases, a frame after `shutdownIncomplete`, and a ticket in the unavailable state. Use `fake_async` only where no real isolate is involved. Verify: the tests fail for the missing implementation.
- [ ] 6.2 Implement `lib/data/capture/capture_service.dart` per D8: lazy worker spawn, single admission, the 500 ms deadline, the `overrun` state, request-id matching, releasing ticket replies in every state, the port kept open until worker exit, close with a 2 s drain and `shutdownIncomplete`, and the worker releasing its own result when close is queued. Verify: `capture_service_test.dart` passes; flip its 9 rows green.

## 7. Trigger source

- [ ] 7.1 Write failing `test/data/capture/trigger_source_test.dart` with a fake native. It covers draining on a signal, delivering drop counts, `alreadyStarted`, `unavailable(win32)`, and `stopTimedOut` keeping the `NativeCallable` open and blocking restart. Implement `lib/data/capture/mouse_release_trigger_source.dart`: a `NativeCallable.listener` signal, drain into a non-buffering stream (events without a listener are dropped), and ordered stop then close of the callable. Verify: the test passes; flip its row green.

## 8. Bundle integrity

- [x] 8.1 Update `test/tool/vision/check_bundle_test.dart`: the synthetic complete bundle gains `blackgrid_capture.dll` and its sidecar, and new failing cases cover a missing capture library or binding and a capture binding mismatch. Verify: the new and changed cases fail.
- [x] 8.2 Add `capture` and `capture-binding` rows to `tool/vision/bundle_inventory.json`, and generalise the sidecar step in `tool/vision/check_bundle.dart:159-172` from role `panel-ocr` to every sidecar-bound role. Verify: `check_bundle_test.dart` passes, including the unchanged green rows; flip the red rows green.

## 9. Integration checks

- [ ] 9.1 Write `test/data/capture/capture_native_qualification_test.dart` (tag `qualification`): ABI and struct sizes, `targetGone` for a destroyed or invalid handle, hook start then drain-empty then stop, a second start returning `alreadyStarted`, and the finalizer entry releasing a slot reserved by a self-owned capture. Before any native call, it skips with a recorded reason if a game process is listed. Verify: after confirming with `tasklist` that the game is not running, `flutter build windows --release`, then `mise run test:qualification` passes the new tests; flip the rows green.
- [ ] 9.2 Full offline gates: `mise run analyze`, `mise run test`, `mise run build:release` (which runs `bundle:check`) and `mise run capture:selftest`. Verify: all pass, with any skipped self-test capture case recorded as skipped, not passed. No step launches the app against the game.

## Workflow follow-up

- **User-verified, in change 5, not here:** live cursor-triggered capture over the game at the user's resolution and DPI, including the D4 DPI-independent ROI at 125% and 150% and `blankCapture` behaviour in their display mode. Until the user reports, it stays unverified.
- **Design note for apply:** the State & Ownership table says the drain clears `signalPending` by "atomic compare-exchange". D2 (authoritative) does it under the SRW lock. Implement D2.
