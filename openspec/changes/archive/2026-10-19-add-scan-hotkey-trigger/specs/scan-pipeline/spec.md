# Spec Delta

## ADDED Requirements

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

## MODIFIED Requirements

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
