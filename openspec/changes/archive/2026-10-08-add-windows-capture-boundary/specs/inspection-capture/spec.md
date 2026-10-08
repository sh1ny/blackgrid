# Spec Delta

## Purpose

Captures the physical pixels of the game's inspection area, or of the whole game client as a fallback, for exactly the window a trigger named. It returns owned, immutable frames or typed failures, and it never touches the target process or blocks the UI isolate.

## ADDED Requirements

### Requirement: Target snapshot
The capture boundary SHALL report a snapshot of a given window. The snapshot holds the process and thread ids, the executable file name, the title, whether the window still exists, whether it is minimised and whether it is foreground. It also holds the client rectangle in signed physical desktop pixels, the window DPI, the monitor rectangle and the virtual-desktop rectangle. Origins left of or above the primary display SHALL stay negative.

#### Scenario: Window on a left/top secondary monitor
- **WHEN** the target's client area is 2560×1440 at physical desktop origin (-2560, -360) on a 144-DPI monitor
- **THEN** the snapshot reports client rectangle (-2560, -360, 2560, 1440), DPI 144, and a monitor rectangle with a negative left edge

#### Scenario: Window no longer exists
- **WHEN** the snapshot is requested for a window handle that has been destroyed
- **THEN** the result is a typed `targetGone` failure, and no geometry is reported

### Requirement: Target identity is validated before capture
Before acquiring pixels, the boundary SHALL confirm all of the following. The window is the trigger's window, and it is still foreground. Its process and thread ids equal the trigger's. Its title equals the target title, and its executable name is in the target allow-list (`EscapeFromTarkov.exe`, `EscapeFromTarkov_BE.exe`, compared case-insensitively). It is not minimised. Any mismatch SHALL produce a typed failure without capturing.

#### Scenario: Valid target
- **WHEN** the trigger's window is foreground, has the trigger's ids, title `EscapeFromTarkov`, executable `EscapeFromTarkov.exe`, and is not minimised
- **THEN** validation passes and capture proceeds

#### Scenario: Focus moved after the click
- **WHEN** another window became foreground between the trigger and the capture
- **THEN** the result is `targetNotForeground`, and no pixels are acquired

#### Scenario: Minimised target
- **WHEN** the trigger's window is minimised at capture time
- **THEN** the result is `targetMinimised`, and no pixels are acquired

#### Scenario: Wrong executable behind the title
- **WHEN** the foreground window is titled `EscapeFromTarkov` but its executable is `notepad.exe`
- **THEN** the result is `wrongTarget` naming the executable, and no pixels are acquired

#### Scenario: Handle reused by another process
- **WHEN** the trigger's window handle now belongs to a different process id
- **THEN** the result is `targetGone`, and no pixels are acquired

### Requirement: Targeted region is planned in physical client pixels
The targeted region SHALL be anchored at the trigger point converted to client pixels. With scale `s = min(w/1920, h/1080)` of the physical client size, it is computed with exact rational arithmetic as `m = floor(50·s)` and `r = floor(600·s)`, giving the region `(x - m div 2, y - m div 2, m + r, m)`. OS DPI SHALL NOT change the region.

#### Scenario: Sixteen resolution and scaling cells
- **WHEN** the region is planned for a click at client point (900, 500) on clients of 1920×1080, 2560×1440, 3440×1440 and 3840×2160, each at DPI 96, 120, 144 and 192
- **THEN** the planned sizes are 650×50, 866×66, 866×66 and 1300×100 respectively, with origins (875, 475), (867, 467), (867, 467) and (850, 450), identical across the four DPIs of each resolution

#### Scenario: Click on a negative-origin monitor
- **WHEN** the client is 2560×1440 at desktop origin (-2560, -360) and the trigger point is (-1200, 340)
- **THEN** the client point is (1360, 700), and the planned region is client (1327, 667, 866, 66), which is desktop origin (-1233, 307)

#### Scenario: Trigger point outside the client
- **WHEN** the trigger point lies outside the target's client rectangle
- **THEN** the result is `roiOutsideClient`, and no pixels are acquired

### Requirement: Fallback region is the visible full client
A fallback request SHALL plan the target's entire client rectangle, intersected with the virtual desktop, under the same validation as a targeted request.

#### Scenario: Full client on one monitor
- **WHEN** a fallback is requested for a 2560×1440 client fully inside the virtual desktop
- **THEN** the planned region is the whole client, 2560×1440 at client origin (0, 0)

#### Scenario: Client partly off the desktop
- **WHEN** the client is 1920×1080 at desktop origin (-100, 0) and the virtual desktop starts at x = 0
- **THEN** the planned region is client (100, 0, 1820, 1080), and the frame is marked clipped

### Requirement: Clipping is explicit, never padded
A planned region SHALL be intersected with the client rectangle and the virtual desktop. A non-empty intersection SHALL be captured at its real size, with both the requested and captured rectangles reported. The frame SHALL be marked clipped exactly when the captured rectangle differs from the requested one. An empty intersection SHALL fail with `roiOutsideClient`. Missing area SHALL NOT be filled with padding.

#### Scenario: Region crosses the right edge
- **WHEN** a targeted region is planned for a click at client point (1500, 500) on a 1920×1080 client
- **THEN** the requested rectangle is (1475, 475, 650, 50), the captured rectangle is (1475, 475, 445, 50), the frame is 445×50 and marked clipped

#### Scenario: Region crosses the top-left corner
- **WHEN** a targeted region is planned for a click at client point (10, 10) on a 1920×1080 client
- **THEN** the captured rectangle is (0, 0, 635, 35), and the frame is marked clipped

#### Scenario: Region entirely off-screen
- **WHEN** the planned region lies entirely outside the virtual desktop
- **THEN** the result is `roiOutsideClient`, and no frame is produced

### Requirement: Capture size is bounded
A captured rectangle SHALL have each side between 1 and 8192 pixels and at most 25,165,824 pixels in total. A larger rectangle SHALL fail with `captureTooLarge` before any pixels are acquired.

#### Scenario: Large but allowed client
- **WHEN** a fallback is requested for a 3840×2160 client
- **THEN** a 3840×2160 frame is produced

#### Scenario: Oversized client
- **WHEN** a fallback is requested for a 7680×4320 client
- **THEN** the result is `captureTooLarge` naming the size, and no pixels are acquired

### Requirement: Capture is coherent with its target
The boundary SHALL snapshot the target immediately before and immediately after acquiring pixels. It SHALL compare both snapshots with the snapshot the request was validated and planned against: window, ids, foreground and minimised state, client rectangle and DPI. On any difference it SHALL release the frame, and the result SHALL be `targetChanged`.

#### Scenario: Stable target
- **WHEN** nothing about the target changes between validation and the end of acquisition
- **THEN** the frame is returned with the validated snapshot's identity and geometry

#### Scenario: Focus moved after validation, before acquisition
- **WHEN** another window becomes foreground after the request was validated but before pixels are acquired
- **THEN** the result is `targetChanged`, no frame is returned, and the live-frame count is unchanged

#### Scenario: Window moved during acquisition
- **WHEN** the client origin changes from (0, 0) to (40, 0) between the validated snapshot and the post-capture snapshot
- **THEN** the result is `targetChanged`, the frame is released, and the live-frame count returns to its prior value

#### Scenario: Monitor DPI changed during acquisition
- **WHEN** the window DPI changes from 96 to 144 between the validated snapshot and the post-capture snapshot
- **THEN** the result is `targetChanged`, and the frame is released

### Requirement: Blank captures are reported
A frame whose blue, green and red bytes are all zero SHALL be released and reported as `blankCapture`, not returned as evidence. The undefined fourth byte SHALL be ignored.

#### Scenario: Black frame from an unsupported display mode
- **WHEN** the acquired pixels of a 650×50 region are all zero
- **THEN** the result is `blankCapture`, and the frame is released

#### Scenario: Black colour with a non-zero fourth byte
- **WHEN** every blue, green and red byte of the frame is zero and every fourth byte is 0xFF
- **THEN** the result is `blankCapture`, and the frame is released

#### Scenario: Dark but not blank
- **WHEN** the acquired pixels are all near-black, but at least one blue, green or red byte is non-zero
- **THEN** the frame is returned

### Requirement: Frames have an immutable pixel layout
A returned frame SHALL expose its width, height, row stride in bytes, pixel format, row order and signed desktop origin, unchanged for its lifetime. The pixel format SHALL be 32-bit BGRX, top-down, with the fourth byte undefined.

#### Scenario: Frame layout
- **WHEN** a targeted capture succeeds on a 1920×1080 client at desktop origin (0, 0) for client point (900, 500)
- **THEN** the frame reports 650×50, stride ≥ 2600, format BGRX top-down, and desktop origin (875, 475)

#### Scenario: Pixel access after release
- **WHEN** a frame's pixels are read after it was released
- **THEN** the read fails with a typed `frameReleased` error, and no native memory is accessed

### Requirement: Frames carry their provenance
A returned frame SHALL also expose the requested and captured client rectangles, the clipped flag, the DPI, and the target identity (window handle, process id, thread id, executable name). It SHALL expose monotonic timestamps from before and after acquisition, on the same clock as trigger timestamps, plus the UTC capture time and the caller's request id.

#### Scenario: Frame provenance
- **WHEN** a targeted capture with request id 42 succeeds unclipped for a trigger stamped at monotonic time T
- **THEN** the frame reports request id 42, clipped false, the trigger's window handle and process id, a pre-acquisition timestamp not earlier than T, and a post-acquisition timestamp not earlier than the pre-acquisition one

#### Scenario: Clipped provenance
- **WHEN** a targeted capture is clipped at the right client edge
- **THEN** the frame reports differing requested and captured rectangles and clipped true

### Requirement: Frame ownership is single and bounded
Each frame SHALL have exactly one owner, which releases it exactly once. Repeated release SHALL be a no-op. At most 4 frames SHALL be live at once. Another capture SHALL then fail with `frameBudgetExceeded` before acquiring pixels. A frame handed to another isolate SHALL move ownership: the sender can no longer read or release it. A frame its owner drops unreleased SHALL be released by a finalizer.

#### Scenario: Release twice
- **WHEN** an owner releases a frame and then releases it again
- **THEN** the second release does nothing, and the live-frame count dropped by exactly one

#### Scenario: Budget exhausted
- **WHEN** 4 frames are live and another capture is requested
- **THEN** the result is `frameBudgetExceeded`, and the live-frame count stays at 4

#### Scenario: Hand-off to another isolate
- **WHEN** an owner hands a frame to another isolate
- **THEN** the receiver can read and release it, a read by the sender fails with `frameReleased`, and a release by the sender is a no-op that leaves the receiver's frame live

#### Scenario: Dropped without release
- **WHEN** an owner loses its last reference to an unreleased frame and the frame is finalised
- **THEN** the live-frame count drops by one

### Requirement: Capture runs off the UI isolate with single admission
Native capture calls SHALL run in a dedicated long-lived worker isolate, never on the UI isolate. The worker SHALL admit one capture at a time. A request arriving while another is active SHALL fail at once with `captureBusy` and SHALL NOT be queued.

#### Scenario: One capture at a time
- **WHEN** a second capture is requested while the first is still acquiring
- **THEN** the second returns `captureBusy` at once, and the first completes normally

#### Scenario: UI stays responsive during a slow capture
- **WHEN** a native capture call is held for 3 s by a controlled barrier
- **THEN** the UI isolate keeps processing events during those 3 s, and no native capture call runs on it

### Requirement: Captures have a deadline that never starts a second native call
A capture SHALL report `captureTimeout` to its caller if the worker has not answered within 500 ms. The worker SHALL stay busy until the native call returns. A frame that arrives after its deadline SHALL be released, not delivered.

#### Scenario: Native call overruns
- **WHEN** a native capture call is held for 2 s by a controlled barrier
- **THEN** the caller receives `captureTimeout` at about 500 ms, a new request made at 1 s returns `captureBusy`, and the late frame is released when the call returns

#### Scenario: Next capture after recovery
- **WHEN** the overrunning call has returned and its late frame has been released
- **THEN** the next capture request is admitted

### Requirement: Shutdown drains capture
Closing the capture service SHALL stop admission at once and wait up to 2 s for an active native call to return, then end the worker. Later captures SHALL fail with `captureClosed`. If the call has not returned in time, close SHALL report `shutdownIncomplete` without ending the worker mid-call. Every frame produced after its caller stopped waiting SHALL be released, in any service state.

#### Scenario: Close while idle
- **WHEN** the service is closed with no capture active
- **THEN** close completes, the worker has exited, and a later capture returns `captureClosed`

#### Scenario: Close during a capture
- **WHEN** close is called while a native capture is held for 300 ms
- **THEN** that capture's caller receives `captureClosed`, its frame is released after the call returns, and close completes after the worker exits

#### Scenario: Native call never returns
- **WHEN** close is called while a native capture is held indefinitely
- **THEN** close returns `shutdownIncomplete` after 2 s, and the worker isolate is not killed

#### Scenario: Frame produced after an incomplete shutdown
- **WHEN** close has returned `shutdownIncomplete` and the held native call later returns a frame
- **THEN** that frame is released, and the live-frame count returns to its value before the capture

#### Scenario: Reply after the worker failed
- **WHEN** the service became unavailable while a capture was in flight, and a reply carrying a frame arrives afterwards
- **THEN** the frame is released, and nothing is delivered to a caller

### Requirement: The target process is never touched
The capture boundary SHALL NOT open a handle to the target process, read or write its memory, inject code or messages into it, or send it input. Identity SHALL come from window queries and a system process listing only. Pixels SHALL come only from the visible desktop.

#### Scenario: Source audit
- **WHEN** the native capture sources are scanned by the offline audit test
- **THEN** they contain no calls to `OpenProcess`, `ReadProcessMemory`, `WriteProcessMemory`, `CreateRemoteThread`, `SendInput`, `PostMessage`, `SendMessage` or `PrintWindow`, and the audit fails if any is added

#### Scenario: Executable name lookup
- **WHEN** the executable name of the target's process id is resolved
- **THEN** it comes from a system process listing, and no process handle is opened

### Requirement: Native self-test captures only its own window
A native self-test, not shipped in the Release bundle, SHALL exercise real hook installation and removal, the target snapshot and pixel capture against a window it creates. It SHALL capture only while its own window is foreground. It SHALL refuse to start unless the run explicitly confirms that no game is running (`BLACKGRID_NO_GAMES_RUNNING=1`), because no process listing can identify every game. It SHALL also refuse to start when an `EscapeFromTarkov.exe` or `EscapeFromTarkov_BE.exe` process is running.

#### Scenario: Game not running
- **WHEN** the self-test runs with `BLACKGRID_NO_GAMES_RUNNING=1` and no game process present
- **THEN** it captures a known pattern from its own window, checks its pixels and geometry, and exits 0

#### Scenario: No-games confirmation missing
- **WHEN** the self-test starts without `BLACKGRID_NO_GAMES_RUNNING=1`
- **THEN** it exits non-zero with a message asking for that confirmation, before listing processes, installing any hook or capturing anything

#### Scenario: Game running
- **WHEN** the self-test starts while an `EscapeFromTarkov.exe` process is listed
- **THEN** it exits non-zero with a message saying it refused because the game is running, before installing any hook or capturing anything

#### Scenario: Own window not foreground
- **WHEN** the self-test cannot make its own window foreground
- **THEN** it reports the capture checks as skipped and captures nothing
