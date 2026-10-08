# 0010 - Windows input and capture boundary: hash-bound capture DLL, native hook ring, frame slots, Dart policy

- Status: accepted
- Date: 2026-10-08 (M2 change `add-windows-capture-boundary`)
- Supersedes: none
- Source: change `add-windows-capture-boundary` (design D1-D9); [implementation strategy §6, §7](../IMPLEMENTATION_STRATEGY.md#7-windows-integration-strategy)

## Context and problem

Item scanning starts from a mouse release over the game window and needs a region of that window's pixels. A global input hook and a screen capture are privacy-sensitive and, near the game, risky: anti-cheat can treat a handle to the game process, memory access or injected input as prohibited, and a ban is unrecoverable. ADR-0007 left the packaging of input and capture open, and ADR-0004 requires blocking native work to run off the UI isolate.

The process is PerMonitorV2 (`windows/runner/runner.exe.manifest`), so hook points, `GetClientRect`/`ClientToScreen` and screen-DC `BitBlt` are all in physical pixels. The reference companion is system-DPI aware and multiplies its client-pixel region by `dpi/96`, which would misplace the region at any OS scale above 100%.

## Decision

- **Packaging.** A standalone `blackgrid_capture.dll` under `windows/capture/`, static CRT, exporting a versioned `bgc_*` C ABI (ABI v1). CMake writes `blackgrid_capture.dll.sha256` at install. Dart verifies the sidecar, then `bgc_abi()`, before any symbol lookup. The bundle inventory gains `capture` and `capture-binding` roles that reuse the panel-sidecar check.
- **Trigger delivery.** `bgc_hook_start` creates one native thread that installs `WH_MOUSE_LL` and runs its own `GetMessage` loop. The hook procedure filters `WM_LBUTTONUP`, skips Blackgrid's own process, reads the target title with `InternalGetWindowText` (no message is sent), and under one SRW lock appends to a bounded 16-event ring (drop oldest, counted) and test-and-sets a `signalPending` flag. Only the call that set the flag posts `WM_APP` to the hook thread, which invokes a payload-less `NativeCallable.listener` signal. Dart then calls `bgc_hook_drain`, which copies and empties the ring and clears the flag in one critical section under the same lock, so wake-ups are never lost and at most one signal is pending. Nothing is captured in the callback. Stop unhooks on the hook thread and joins within 1 s (`stopTimedOut` otherwise).
- **Physical-pixel, DPI-independent ROI.** The trigger point is converted to client pixels with the signed client origin. With `s = min(w/1920, h/1080)` (exact rational), `m = floor(50s)` and `r = floor(600s)`, the region is `(x - m~/2, y - m~/2, m + r, m)`. DPI is metadata only. The fallback is the full client.
- **Clip, never pad.** The region is intersected with the client and the virtual desktop and captured at its real size, with requested and captured rectangles and a clipped flag reported. An empty intersection fails.
- **Frames.** The native registry has 4 generation-checked slots, each a 32 bpp top-down DIB section. A frame id is `(slot << 32) | generation`, and `bgc_frame_release` is a no-op for stale ids. `CaptureFrame` holds a `NativeFinalizer` backstop; `handOff()` detaches it and returns a sendable `CaptureFrameTicket`, and `CaptureFrame.adopt` attaches a new one in the receiver. Frame side is at most 8192 and at most 25,165,824 px, equal to the vision bounds.
- **Native facts, Dart policy.** Native code returns facts only: `bgc_snapshot` (identity, geometry), `bgc_capture` (pre snapshot, BitBlt, post snapshot, `allZero` over the B, G, R bytes only) and `bgc_frame_*`. Validation, ROI planning, clipping, bounds, coherence and blank detection are pure Dart. Coherence compares both the pre and post snapshots with the validation snapshot S0, so a change between validation and the BitBlt is caught. Failures are a sealed `CaptureFailure`; nothing throws.
- **Capture worker.** One long-lived `CaptureService`-owned worker isolate runs snapshot, plan, capture and validate. Admission is 1 active and 0 queued (`captureBusy`). The deadline is 500 ms from admission; after it the caller gets `captureTimeout` and the service stays in `overrun`, so no second native call starts, until the worker replies. Any ticket that is not delivered to a waiting caller is adopted and released in every state. Close stops admission, drains for 2 s and reports `shutdownIncomplete` rather than killing a worker still in a native call. A worker error makes the service `unavailable`; there is no respawn.
- **No contact with the target process.** The code opens no handle to the game process, reads or writes none of its memory, and sends it no input. The executable name comes from a `CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS)` listing, cached for one `(hwnd, pid, tid)` key. An offline source-audit test fails if the capture sources mention `OpenProcess`, `ReadProcessMemory`, `WriteProcessMemory`, `CreateRemoteThread`, `SendInput`, `PostMessage`, `SendMessage` or `PrintWindow`.
- **Self-test.** `blackgrid_capture_selftest.exe` is an `EXCLUDE_FROM_ALL` CMake target, never installed, run by `mise run capture:selftest`. It exits 2 unless `BLACKGRID_NO_GAMES_RUNNING=1` confirms that no game is running, and while a known game executable is listed. Otherwise it captures only its own window. The `qualification` capture test skips under the same two conditions.

## Rejected alternatives

- **Runner-embedded method channel** for input and capture: handlers run on the platform thread, so pixels would cross the UI channel (strategy §7).
- **Adding exports to `blackgrid_vision.dll`:** couples capture to the OpenCV build and the vision manifest, and bumps an ABI that later changes code against.
- **A listener invocation per event carrying a struct pointer:** the pointer outlives the callback and the Dart port queue is unbounded. **A Dart polling timer:** adds up to one period of latency per click and wakes the CPU while idle.
- **Native validation and planning:** puts policy in C++ and makes the fixtures need a real window and game.
- **Matching the reference's `dpi/96` scaling,** and **its black padding:** the first misplaces the ROI under PerMonitorV2, the second hides a wrong ROI and makes padding look like dark pixels.
- **`OpenProcess` with `QueryFullProcessImageNameW`:** more precise, but a handle to the game process can be flagged by anti-cheat.
- **Copying pixels into `TransferableTypedData`** (up to 96 MiB per fallback frame) and **raw `malloc` pointers released by address** (a double free is undefined behaviour).
- **Capturing inside the future vision worker** (couples change 2 to 3 and delays recognition admission) and **`Isolate.run` per capture** (spawn plus hash verification on every click).
- **A `--capture-self-check` app mode,** and **a Dart test that captures the foreground window:** the first adds a launch path to the shipped app and complicates foreground control; the second could capture the game.

## Consequences

- **A global input hook exists in the product,** with a minimal non-blocking callback. If the OS removes the hook after a `LowLevelHooksTimeout`, triggers stop silently; there is no watchdog in this change.
- **Bounded by construction:** 16-event ring, at most 1 pending signal, 4 live frames, 1 active capture, 500 ms capture deadline, 1 s hook join, 2 s close drain.
- **The ROI may diverge from the reference** at OS scales above 100%. The user's live check in change 5 settles it; the fixtures pin the formula.
- **BitBlt can return black** (exclusive fullscreen, protected surfaces). That is a typed `blankCapture`, never evidence. Desktop Duplication or Windows Graphics Capture are deferred until a live check shows blank frames.
- **Not wired yet:** the trigger source and service are not connected to app startup or the UI. Hotkeys (M4) will reuse the hook thread and ring; change 5 wires the Scanner.
- **The hash sidecar proves the DLL matches its build; it is not tamper-proof,** as with panel OCR.
- **Reversal cost:** low for the DLL packaging, ROI, clip and policy split; medium for the hook ring and the ticket contract, which later changes consume.
