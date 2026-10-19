# scan-pipeline Specification

## Purpose
Turns each mouse-release trigger over the game into one finished scan. A scan is a targeted pass, then a full-client fallback pass when the targeted pass is not accepted. The pipeline starts and stops with the live scan setting, keeps at most one scan in flight, never publishes stale results, and records stage timings for every scan.

## Requirements

### Requirement: Live scan starts only when enabled
Live scanning SHALL be controlled by a persisted setting that defaults to off. When the setting is on (at launch or when it is switched on), the pipeline SHALL first load the bundle-bound marker template, then start the vision worker and wait for it to be ready. Only then SHALL it install the mouse-release hook, and then register the saved scan hotkey unless it is off. A refused hotkey SHALL NOT stop live scan from reaching `ready`. With the setting off, the process SHALL install no hook, register no hotkey, load no vision library and start no capture or vision worker.

#### Scenario: Launch with live scan off
- **WHEN** the application starts with no saved settings
- **THEN** the live scan setting is off, the pipeline state is `off`, no hook is installed, no hotkey is registered, no vision library is loaded, and no capture or vision worker is running

#### Scenario: Switching live scan on
- **WHEN** live scan is switched on, and the marker template and vision runtime are valid
- **THEN** the setting is saved as on, the state passes through `starting` to `ready`, the hook is installed only after the vision worker reported ready, and the saved hotkey is registered only after the hook is installed

#### Scenario: Hotkey held by another application
- **WHEN** live scan is switched on with the binding F9 while another application holds F9
- **THEN** the state reaches `ready`, mouse releases over the target still start scans, and the hotkey state is `unavailable` with F9 and the OS reason

#### Scenario: Launch with live scan saved on
- **WHEN** the application starts with the live scan setting saved as on
- **THEN** the pipeline starts after app initialisation, as if the setting had just been switched on

#### Scenario: Vision runtime cannot start
- **WHEN** live scan is switched on and a bundled vision file is missing
- **THEN** the state becomes `unavailable` with that runtime failure as its reason, no hook is installed, no hotkey is registered, and the setting stays on

#### Scenario: Marker template is invalid
- **WHEN** live scan is switched on and the marker template's hash does not match the runtime manifest
- **THEN** the state becomes `unavailable` with the template failure as its reason, and no vision worker or hook is started

#### Scenario: Hook installation refused
- **WHEN** the vision worker is ready but the OS refuses to install the hook
- **THEN** the state becomes `unavailable` with the hook failure and its OS error code, no hotkey is registered, and the vision worker is closed

### Requirement: Live scan stops cleanly
Switching live scan off, whether or not the setting is saved, or disposing the application, SHALL stop admission at once, unregister the hotkey, remove the hook, abandon the scan in flight and the pending trigger, and close the capture and vision services within their own drain bounds. A start still in progress when the setting is switched off SHALL be torn down within the vision service's close drain, without waiting for the start to finish. A stop that could not complete SHALL be reported, not hidden.

#### Scenario: Switching live scan off while idle
- **WHEN** live scan is `ready` and is switched off
- **THEN** the setting is saved as off, the hotkey is unregistered, the hook is removed, both workers are closed, and the state is `off`

#### Scenario: Setting cannot be saved when switching off
- **WHEN** live scan is `ready` and is switched off, but saving the setting fails or is refused as busy
- **THEN** the hotkey is unregistered, the hook is removed and both workers are closed, the state is `off` for the rest of the session, and an error says the preference was not saved

#### Scenario: A later save does not reinstall the hook
- **WHEN** a switch-off's save failed, and later an unrelated setting (for example the selected map) is saved successfully
- **THEN** live scan stays `off`, no hook is installed, no hotkey is registered, and no worker is started

#### Scenario: Switching off during start
- **WHEN** live scan is switched off while the vision worker is still starting
- **THEN** within the vision service's close drain, the worker is closed, no hook is installed, no hotkey is registered, and the state is `off`

#### Scenario: Switching off with a scan in flight
- **WHEN** live scan is switched off while a scan waits for its vision answer
- **THEN** that scan publishes no evidence, its frame is released, and the vision service close is awaited within its 2 s drain

#### Scenario: Switching off during a rebind
- **WHEN** live scan is switched off while a rebind to F10 waits for the input thread
- **THEN** after the stop no hotkey is registered, the state is `inactive`, and the binding saved is the one in force before the rebind

#### Scenario: Hook thread does not stop
- **WHEN** live scan is switched off and the hook stop reports `stopTimedOut`
- **THEN** the state is `off` with a visible `stopTimedOut` warning that says the hotkey may stay held until the input thread ends, and switching live scan on again retries the stop before reporting `alreadyStarted` as `unavailable`

#### Scenario: Worker drain incomplete at shutdown
- **WHEN** the application is disposed while a native vision call does not return within the drain
- **THEN** disposal completes after the drain bound, and no scan evidence is published after disposal began

### Requirement: Worker loss makes live scan unavailable
If the capture or vision service becomes unavailable while live scan is on, the pipeline SHALL remove the hook and enter `unavailable` with that service's reason. It SHALL NOT respawn either service. Switching live scan off and on again SHALL start fresh services.

#### Scenario: Vision worker exits mid-session
- **WHEN** the vision worker exits while live scan is `ready`
- **THEN** the hook is removed, the state is `unavailable` with the worker's reason, and later mouse releases produce no scan

#### Scenario: Restart after loss
- **WHEN** live scan is `unavailable` after a worker loss, and is switched off and then on
- **THEN** new capture and vision services are created, and the state reaches `ready` if both start

### Requirement: Targeted pass runs first
For each trigger, the pipeline SHALL capture the targeted region for that trigger, recognise the frame in the vision worker as a targeted frame (using the client size reported with the frame), and match its evidence against the current catalog off the UI isolate. An accepted targeted outcome SHALL end the scan as accepted, with no fallback pass.

#### Scenario: Accepted targeted scan
- **WHEN** a trigger arrives over an inspection whose title the matcher accepts
- **THEN** the scan ends `accepted` from the targeted pass with the matched item ID, and no fallback capture is requested

#### Scenario: Targeted capture fails on identity
- **WHEN** the targeted capture fails with `targetNotForeground`
- **THEN** the scan ends `failed` with `targetNotForeground` for the targeted pass, and no fallback capture is requested

### Requirement: Fallback pass runs when the targeted pass is not accepted
A fallback pass SHALL run after a targeted rejection whose reason is not catalog-only (`emptyCatalog`, `catalogModeMismatch`, `catalogUnavailable`), or after a targeted `roiOutsideClient`, `blankCapture` or `targetChanged` capture failure. It SHALL capture the full client for the same trigger, recognise it as full-client, and rank both passes' evidence together. If both passes fail, the scan SHALL end `failed` with the fallback failure.

#### Scenario: Targeted pass finds no marker
- **WHEN** the targeted pass is rejected `noMarker` and the full-client frame holds an inspection the matcher accepts
- **THEN** the pipeline publishes a `fallback` phase before the fallback capture starts, and the scan ends `accepted` from the fallback pass

#### Scenario: Fallback also rejected
- **WHEN** both passes find markers but no title is accepted
- **THEN** the scan ends `rejected` with the ranked outcome's reason and its best candidate, and both passes' evidence is kept

#### Scenario: Targeted vision answer not delivered
- **WHEN** the targeted vision request is answered `visionTimeout`
- **THEN** the scan ends `failed` with `visionTimeout`, and no fallback capture is requested

#### Scenario: Fallback capture fails
- **WHEN** the targeted pass is rejected `belowSimilarity` and the fallback capture then fails with `targetGone`
- **THEN** the scan ends `rejected` with the targeted outcome, and records the fallback failure `targetGone`

#### Scenario: Both passes fail to capture
- **WHEN** the targeted capture fails with `blankCapture` and the fallback capture also fails with `blankCapture`
- **THEN** the scan ends `failed` with the fallback failure `blankCapture`, and records the targeted failure `blankCapture`

#### Scenario: Catalog-only rejection
- **WHEN** the targeted pass is rejected `catalogModeMismatch`
- **THEN** the scan ends `rejected` with that reason and no fallback capture is requested

### Requirement: One scan in flight, latest trigger wins
At most one scan SHALL be in flight, and at most one trigger SHALL wait. A trigger arriving during a scan SHALL supersede that scan. While the scan is in its capture stage, the new trigger SHALL take the pending slot, and a trigger it replaces there is dropped and counted. During a wait, the vision stage or matching, the new scan SHALL start at once. A superseded scan SHALL publish no evidence. The pending trigger SHALL start once the superseded scan's native stage returns or its vision request is invalidated.

#### Scenario: Burst during capture
- **WHEN** triggers 2 and 3 arrive while scan 1 waits for its targeted capture
- **THEN** scan 1 is superseded and publishes nothing, its frame is released, trigger 2 is dropped, and trigger 3's scan starts once that capture returns, reporting 1 superseded trigger

#### Scenario: Pending trigger meets an overrun capture
- **WHEN** a trigger is pending and the in-flight capture answers `captureTimeout`
- **THEN** the superseded scan is logged, and the pending trigger's scan ends `failed` with `captureBusy` while the capture worker stays overrun, and is logged

#### Scenario: Trigger during the vision stage
- **WHEN** a new trigger arrives while scan 1 waits for its vision answer
- **THEN** scan 1's vision request is invalidated at once, the new scan's settle wait starts without waiting for the old job, and the old job's late result is never published

#### Scenario: Trigger during matching
- **WHEN** a new trigger arrives while scan 1's matching runs off the UI isolate
- **THEN** the new scan starts at once, and scan 1's match result is discarded when it arrives

#### Scenario: Triggers dropped by the native queue
- **WHEN** a trigger arrives reporting 4 events dropped by the native queue before it
- **THEN** the scan it starts records 4 dropped native triggers

### Requirement: Results publish only while current
A scan SHALL publish its phase changes and its final evidence only while it is the current scan, live scan is still on, and the pipeline has not been disposed. Any later result SHALL be discarded and any frame it still holds released.

#### Scenario: Switched off during matching
- **WHEN** live scan is switched off while a scan's matching runs
- **THEN** the match result is discarded and no evidence or phase change is published for that scan

#### Scenario: Late result after dispose
- **WHEN** the pipeline is disposed while a capture is in flight and the capture later succeeds
- **THEN** the frame is released, and no listener is notified after disposal

### Requirement: Matching uses the current catalog index
The pipeline SHALL match against a title index built off the UI isolate from the current catalog snapshot, rebuilt once whenever the snapshot changes. A scan SHALL use the index current when its matching starts, waiting for an index still being built. With no catalog snapshot, the outcome SHALL be the pipeline rejection `catalogUnavailable`, and the recognition evidence SHALL still be kept.

#### Scenario: Catalog loaded
- **WHEN** a scan matches while the catalog snapshot for PvP revision R is current
- **THEN** the outcome records mode PvP and revision R

#### Scenario: Catalog replaced mid-scan
- **WHEN** the catalog snapshot changes after scan 1's matching started
- **THEN** scan 1's outcome records the old revision, and the next scan matches against an index built from the new snapshot

#### Scenario: No catalog
- **WHEN** a scan reaches matching and no catalog snapshot is loaded
- **THEN** the scan ends `rejected` with `catalogUnavailable`, keeps its OCR evidence, and no fallback capture is requested

#### Scenario: Index build fails
- **WHEN** building the index for a new snapshot throws
- **THEN** scans matched against that snapshot end `rejected` with `catalogUnavailable`, and the next snapshot change retries the build

### Requirement: Every scan records stage timings
Each scan SHALL record monotonic timestamps, on the trigger and capture clock, of the trigger, of publication, and, for each pass it ran (targeted, fallback), of every stage that pass reached: capture request, acquisition start and end, capture answer, vision submission, job start, marker, title, preprocess and OCR stages, job end, matching start and end. A pass's job sub-stages SHALL come from that pass's own evidence. A stage not reached SHALL be absent, never zero.

#### Scenario: Accepted targeted scan timings
- **WHEN** a scan is accepted from the targeted pass
- **THEN** its record holds the trigger, publication and every targeted stage, non-decreasing in stage order, and no fallback stages

#### Scenario: Fallback wins
- **WHEN** a scan's targeted pass is rejected after OCR and its fallback pass is accepted
- **THEN** its record holds the targeted pass's own marker, title, preprocess and OCR stages as well as the fallback pass's

#### Scenario: Scan ended early
- **WHEN** a scan ends because the targeted capture failed
- **THEN** its record holds the trigger, the targeted capture request and capture answer, and every later stage is absent

### Requirement: Each finished scan is logged as one JSON line
Every scan that ends (accepted, rejected, failed or superseded) SHALL be appended as one UTF-8 JSON line to `logs/scan-timings.jsonl` in the app's local data folder. The line SHALL hold schema version 2, UTC time, the trigger source (`mouse` or `hotkey`), end state, item ID or rejection or failure reason, per-pass marker and candidate scores, OCR text, per-pass stage durations in milliseconds from the trigger, and dropped and superseded counts. It SHALL hold no pixels or crop bytes.

#### Scenario: Accepted scan line
- **WHEN** a scan started by a mouse release ends accepted from the fallback pass
- **THEN** the log gains one line with `"v":2`, `"trigger":"mouse"`, end state `accepted`, the item ID, `fallback` as the winning pass, and under `ms` a `targeted` and a `fallback` object with a millisecond value for every stage each pass recorded

#### Scenario: Hotkey scan line
- **WHEN** a scan started by the hotkey ends accepted from the targeted pass
- **THEN** the log gains one line with `"v":2` and `"trigger":"hotkey"`

#### Scenario: Superseded scan line
- **WHEN** a scan is superseded during its vision stage
- **THEN** the log gains one line with end state `superseded` and only the stages reached before supersession

### Requirement: Timing log is bounded and never blocks scanning
Log writes SHALL run asynchronously, one at a time and in scan order. At most 32 lines SHALL wait to be written. Further lines SHALL be dropped and counted, and the next written line SHALL carry that count. Before a write would grow the file past 1 MiB, it SHALL be renamed to `scan-timings.1.jsonl`, replacing any earlier one. A failed write SHALL make the log status `unavailable` with the error, and scanning SHALL go on.

#### Scenario: Rotation
- **WHEN** the log file holds 1 MiB minus 10 bytes and a 200-byte line is written
- **THEN** the old file is now `scan-timings.1.jsonl`, and `scan-timings.jsonl` holds only the new line

#### Scenario: Disk stalled
- **WHEN** a write does not complete while 40 more scans end
- **THEN** 32 lines wait, 8 are dropped, and the next line written after the queue drains reports 8 dropped lines

#### Scenario: Log folder not writable
- **WHEN** the log file cannot be opened for writing
- **THEN** the log status is `unavailable` with the error, and the scan still publishes its evidence

### Requirement: Targeted capture waits for the inspect window to settle
A scan started by a mouse release SHALL NOT request its targeted capture earlier than 50 ms after its trigger's timestamp, measured on the trigger and capture clock. A scan whose trigger is already at least 50 ms old SHALL request the capture without waiting. A scan started by the hotkey SHALL request its targeted capture without this wait. The wait SHALL hold no frame and make no native call.

#### Scenario: Fresh trigger
- **WHEN** a mouse trigger is handled 1 ms after its timestamp
- **THEN** the scan waits 49 ms, the remaining time to 50 ms after the trigger, and then requests the targeted capture

#### Scenario: Trigger already old
- **WHEN** a pending mouse trigger starts its scan 120 ms after its timestamp
- **THEN** the targeted capture is requested at once, with no further wait

#### Scenario: Hotkey trigger
- **WHEN** a hotkey trigger is handled 1 ms after its timestamp
- **THEN** the targeted capture is requested at once, with no wait

#### Scenario: Switched off while waiting
- **WHEN** live scan is switched off while a scan waits to settle
- **THEN** no capture is requested for that scan and it publishes nothing

### Requirement: Fallback capture waits until 200 ms after the trigger
A scan started by a mouse release SHALL NOT request its fallback capture earlier than 200 ms after its trigger's timestamp. A scan started by the hotkey SHALL request its fallback capture without this wait. The `fallback` phase SHALL be published before any wait. A fallback whose deadline has already passed SHALL be requested without waiting.

#### Scenario: Quick targeted rejection
- **WHEN** a mouse scan's targeted pass is rejected `noMarker` 80 ms after its trigger
- **THEN** the `fallback` phase is published at once, and the fallback capture is requested no earlier than 200 ms after the trigger

#### Scenario: Slow targeted rejection
- **WHEN** a mouse scan's targeted pass is rejected `belowSimilarity` 260 ms after its trigger
- **THEN** the fallback capture is requested at once

#### Scenario: Quick hotkey rejection
- **WHEN** a hotkey scan's targeted pass is rejected `noMarker` 80 ms after its trigger
- **THEN** the `fallback` phase is published and the fallback capture is requested at once

### Requirement: A trigger during a wait supersedes the scan at once
A trigger arriving while a scan waits before a capture request SHALL supersede that scan at once. The new scan SHALL start right away, without the pending slot, and run its own settle wait if it is a mouse trigger. The superseded scan SHALL request no further capture and publish no evidence.

#### Scenario: Second click during the settle wait
- **WHEN** trigger 2 arrives 20 ms after trigger 1, while scan 1 waits to settle
- **THEN** scan 1 requests no capture and publishes nothing, and scan 2's targeted capture is requested no earlier than 50 ms after trigger 2

#### Scenario: Hotkey during the settle wait
- **WHEN** a hotkey trigger arrives 20 ms after a mouse trigger, while scan 1 waits to settle
- **THEN** scan 1 requests no capture and publishes nothing, and the hotkey scan's targeted capture is requested at once

#### Scenario: Click during the fallback wait
- **WHEN** a new trigger arrives while scan 1 waits for its fallback deadline
- **THEN** scan 1 requests no fallback capture and publishes no evidence, and the new scan shows the `targeted` phase

### Requirement: Recording receives each pass's pixels before vision
While frame recording is on, the pipeline SHALL copy each pass's captured pixels and metadata for the recorder before handing the frame to the vision worker. The frame itself SHALL stay owned and released exactly as without recording. While recording is off, the pipeline SHALL make no copy.

#### Scenario: Recorded fallback scan
- **WHEN** recording is on and a scan runs a targeted and a fallback pass
- **THEN** the recorder receives a copy of both frames with the trigger's client point, and each frame is released once by the vision worker

#### Scenario: Superseded before vision
- **WHEN** a recorded scan is superseded after its capture answer and before its frame reaches the vision worker
- **THEN** the frame is released, and the recorder writes nothing for that scan

### Requirement: Targeted acceptance gets one extra full-client capture while recording
While recording is on, a scan accepted by its targeted pass SHALL, after it is published and logged, request one full-client capture for the same trigger target. That frame SHALL be used only for recording: it is never recognised, never changes the published scan and never adds keys to its timing log line. A trigger arriving during this capture SHALL take the pending slot and wait for its answer, as during a capture stage, including the `captureTimeout` → `captureBusy` outcome.

#### Scenario: Accepted on the targeted pass
- **WHEN** recording is on and a scan is accepted by its targeted pass
- **THEN** the accepted evidence is published first, then one full-client capture is requested and its frame goes to the recorder

#### Scenario: Recording off
- **WHEN** recording is off and a scan is accepted by its targeted pass
- **THEN** no capture is requested after the scan ends

#### Scenario: Trigger during the extra capture
- **WHEN** a new trigger arrives while the extra capture is in flight
- **THEN** the new scan starts once that capture answers, and the extra frame is still recorded

#### Scenario: Extra capture overruns with a trigger pending
- **WHEN** a trigger is pending and the extra capture answers `captureTimeout`
- **THEN** the pending trigger's scan ends `failed` with `captureBusy` and is logged, and the recorded scan's line has `image: null` and `fullFailure: "captureTimeout"`

#### Scenario: Extra capture fails
- **WHEN** the extra capture fails with `targetChanged`
- **THEN** the published scan is unchanged, and the recorder writes the scan's strip with `image: null` and `fullFailure: "targetChanged"`

### Requirement: The scan hotkey is a persisted setting
The scan hotkey SHALL be a persisted setting holding one of F1-F24 or off, defaulting to F9. A saved value that is missing, of the wrong type or outside that set SHALL load as F9 without failing the settings load or changing other settings.

#### Scenario: No saved value
- **WHEN** settings saved before this change are loaded
- **THEN** the scan hotkey is F9 and every other setting keeps its saved value

#### Scenario: Saved off
- **WHEN** the scan hotkey was saved as off and settings are loaded
- **THEN** the scan hotkey is off

#### Scenario: Malformed value
- **WHEN** the saved scan hotkey is `"Ctrl+Q"` or the number `9`
- **THEN** the scan hotkey loads as F9 and the settings load succeeds

### Requirement: The pipeline publishes the hotkey state
The pipeline SHALL publish the hotkey's state: `inactive` while live scan is not `ready`, `disabled` when the binding is off, `registered` with its key, or `unavailable` with its key and reason. The state SHALL change only through activation, rebinding, stop, worker loss and dispose, and SHALL describe what the OS holds for the process. The one exception: after a stop reported `stopTimedOut`, the stuck input thread may hold the key while the state is `inactive`, as the stop warning says.

#### Scenario: Ready with a free key
- **WHEN** live scan reaches `ready` with the binding F9 and F9 is free
- **THEN** the hotkey state is `registered` with F9

#### Scenario: Binding off
- **WHEN** live scan reaches `ready` with the binding off
- **THEN** the hotkey state is `disabled` and no hotkey is registered

#### Scenario: Live scan off
- **WHEN** live scan is `off`, `starting` or `unavailable`
- **THEN** the hotkey state is `inactive` and no hotkey is registered

#### Scenario: Worker loss
- **WHEN** live scan is `ready` with F9 registered and the vision worker exits
- **THEN** F9 is no longer registered and the hotkey state is `inactive`

#### Scenario: Registration does not answer at activation
- **WHEN** live scan is switched on with the binding F9 and the hotkey request returns `hotkeyTimedOut`
- **THEN** live scan reaches `ready` and the hotkey state is `unavailable` with F9 and the timeout as its reason

### Requirement: Rebinding the hotkey
A rebind while live scan is `ready` SHALL register the new key first and save it only after the OS accepts it. A refused key SHALL keep the old registration and saved binding, and SHALL show the refusal. A failed save SHALL restore the previous registration. A rebind while live scan is not `ready` SHALL only save. Rebind and live-scan saves SHALL wait for each other, never refused as busy. One rebind SHALL run at a time; another is refused as busy.

#### Scenario: Rebind while ready
- **WHEN** live scan is `ready` with F9 registered and the user picks F10, which is free
- **THEN** F10 is registered, F9 is released, the setting is saved as F10, and the state is `registered` with F10

#### Scenario: Rebind to a held key
- **WHEN** live scan is `ready` with F9 registered and the user picks F10 while another application holds F10
- **THEN** F9 stays registered and saved, the state stays `registered` with F9, and an error names F10 and the OS reason

#### Scenario: Save fails after registration
- **WHEN** live scan is `ready` with F9 registered, the user picks F10, F10 registers, and saving the setting fails
- **THEN** F9 is registered again, F10 is released, the state is `registered` with F9, and an error says the preference was not saved

#### Scenario: Save fails after leaving an unavailable key
- **WHEN** the state is `unavailable` with F9, the user picks F10, F10 registers, and saving the setting fails
- **THEN** F10 is no longer registered, the state is `unavailable` with F9, and an error says the preference was not saved

#### Scenario: Old key taken during a failed save
- **WHEN** live scan is `ready` with F9 registered, the user picks F10, F10 registers, saving fails, and another application took F9 in the meantime
- **THEN** F10 is no longer registered, the state is `unavailable` with F9 and the OS reason, and an error says the preference was not saved

#### Scenario: Live scan switched off while a rebind saves
- **WHEN** a rebind to F10 has registered F10 and its save is still running when the user switches live scan off
- **THEN** the switch-off save waits for the rebind save instead of being refused as busy, both are saved, no "not saved" error is shown, and no hotkey is registered after the stop

#### Scenario: Rebind while off
- **WHEN** live scan is `off` and the user picks F10
- **THEN** the setting is saved as F10, no hotkey is registered, and the state stays `inactive`

#### Scenario: Rebind during another rebind
- **WHEN** a rebind to F10 is still in progress and the user picks F11
- **THEN** the F11 rebind is refused as busy and the F10 rebind completes as if alone

#### Scenario: Rebind out of an unavailable state
- **WHEN** the state is `unavailable` with F9 and the user picks F10, which is free
- **THEN** F10 is registered and saved, and the state is `registered` with F10
