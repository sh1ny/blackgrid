# Proposal

## Why

Milestone **M2 - capture/recognition proof** needs real pixels from the game's inspection tooltip, captured at the user's resolution and DPI without freezing the UI. Nothing in `lib/` or `windows/` captures input or the screen yet (architecture.md, "Not built yet"). This is roadmap change 2. It does not depend on change 1 (`add-native-vision-runtime`). It advances these M2 exit criteria:

- **Deterministic capture-geometry fixtures** cover all 16 resolution/scaling cells, signed negative monitor origins and clipped ROIs, and produce typed failures for changed, minimised or wrong targets. (agent) This change closes this criterion.
- **A blocked or slow native call cannot freeze the UI isolate.** (agent) This change covers capture and the input hook. Recognition calls come in change 3.
- **Live cursor-triggered capture over the game.** (user) This change provides the trigger and capture halves. Change 5 wires them into Scanner, and the user verifies them there.

The reference companion's capture has defects that this change must not copy. Its hook queues only screen coordinates, so a later capture re-queries the foreground and may capture a different target. It copies the full client and then crops. It pads clipped regions with black. It also scales a client-pixel region by `dpi/96`. Blackgrid runs PerMonitorV2, where hook points and client geometry are already physical pixels, so that scaling would misplace the targeted region at any OS scaling above 100%.

## What Changes

- **Mouse-release trigger.** A dedicated native thread owns a low-level mouse hook and its own message loop. On a left-button release it records only cheap facts: the physical screen point, the foreground window, its process and thread ids, and a monotonic timestamp. It records a release only when the foreground window's title matches the configured target title. The callback returns immediately. Events go into a bounded native queue, and the oldest events are dropped and counted when it is full. A coalesced signal tells Dart to drain them. The hook is installed only on an explicit start and is removed on stop or dispose.
- **Target identity and geometry query.** One call snapshots a window: process and thread ids, the executable name read from a system process listing (no handle to the target process is ever opened), title, minimised and foreground state, client rectangle in signed physical desktop coordinates, window DPI, monitor rectangle and the virtual-desktop rectangle.
- **Capture planning in pure Dart.** The marker-scan ROI is anchored at the click and scaled by `min(w/1920, h/1080)` of the physical client. OS DPI never scales it. The full-client fallback region is planned the same way. Both are clipped explicitly to the client and the virtual desktop, never padded. Oversized or empty regions get typed failures.
- **Direct ROI capture.** A desktop-GDI BitBlt copies the planned physical-pixel rectangle straight into an owned 32-bit BGRX buffer. The full client is captured only when it is requested as the fallback. The target is snapshotted again right after the copy. A changed, minimised, defocused, destroyed or wrong target yields a typed failure, and the frame is released rather than returned.
- **Owned-buffer contract.** Each frame carries immutable metadata: width, height, stride, pixel format, signed desktop origin, requested and captured rectangles, DPI, target identity, monotonic and UTC capture timestamps, and the request id. A native registry caps the number of live frames. Release happens exactly once and is idempotent; a finalizer is the backstop. A frame can be handed off explicitly to another isolate. Frames that are entirely zero are reported as blank captures.
- **Off-UI capture worker.** A long-lived capture isolate admits one request at a time. A request that arrives while one is running gets a busy failure. A capture that overruns its deadline returns a timeout to the caller while the native call finishes; its late frame is released, not published. Shutdown stops admission and drains the active capture.
- **Packaging.** A new standalone `blackgrid_capture.dll`, bound to its build hash like the panel OCR DLL, plus an offline-bundle inventory update. A native self-test executable, not shipped in the bundle, captures its own window only, and refuses to run while the game is running.
- **Not in this change:** RegisterHotKey triggers (M4), wiring into Scanner or AppServices (change 5), recognition and the worker that consumes frames (changes 3-4), and occluded or exclusive-fullscreen capture guarantees. Normal app startup does not install the hook in this change.

## Capabilities

### New Capabilities
- `scan-triggers`: Global input that starts a scan. In this change that is the mouse-release hook: ingress, filtering, the bounded queue, lifecycle and delivery. Later hotkey triggers join this capability.
- `inspection-capture`: Target identity and geometry, capture-region planning, direct physical-pixel capture, the owned-frame contract with typed failures, off-UI admission, timeouts and shutdown, and the rule that the target process is never touched.

### Modified Capabilities
- `release-bundle-integrity`: the exact inventory and the runtime-verified binding check now include the capture library and its hash binding.

## Impact

- **New native code:** `windows/capture/` (DLL, hook thread, self-test executable, CMake), installed from `windows/CMakeLists.txt` with a `.sha256` binding.
- **New Dart code:** `lib/data/capture/` (FFI binding, platform seam, pure geometry, frame ownership, capture worker, trigger source). No UI and no controller wiring.
- **Tooling:** `tool/vision/bundle_inventory.json` and the bundle check gain the capture files. A new `mise` task builds and runs the native self-test after confirming the game is not running.
- **Docs:** a new ADR for the input/capture boundary (packaging, delivery, physical-pixel contract, no target-process handles), plus an update to architecture.md. No third-party code is added, so THIRD_PARTY_NOTICES does not change.
- **Dependencies:** none new (`dart:ffi`, `package:ffi`, Win32 and GDI only).
