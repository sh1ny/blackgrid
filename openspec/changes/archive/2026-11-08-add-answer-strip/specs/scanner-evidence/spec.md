# Scanner evidence delta

## ADDED Requirements

### Requirement: Scanner workspace omits configuration rail
Scanner SHALL present its working evidence without the legacy manual/configuration rail. Top search SHALL provide item selection; game mode, data refresh, Tracker and live-scan controls SHALL remain reachable from the status bar or Settings. This SHALL NOT remove or restyle the interim Map rail controls.

#### Scenario: Scanner functions remain reachable without the old rail
- **WHEN** Scanner is shown with the legacy left panel removed
- **THEN** no duplicated mode/status/manual-search instructions occupy its workspace, and top search plus status or Settings retain item selection, mode authority, refresh, Tracker and live-scan functions

## MODIFIED Requirements

### Requirement: Scanner shows the live scan switch and status
The Live scan section of Settings SHALL show a live scan switch reflecting the session's intent (the saved setting at launch, then the user's last switch) and the pipeline state: `off`, `starting`, `ready`, or `unavailable` with its reason, plus any stop warning. A switch SHALL save the setting; a failed save SHALL revert a switch-on but SHALL NOT undo a switch-off, which shows an error instead. An `unavailable` log status SHALL be shown.

#### Scenario: Switching on from Scanner
- **WHEN** the user opens Settings' Live scan section and turns the live scan switch on and the pipeline reaches `ready`
- **THEN** the switch shows on and the status reads that live scan is ready

#### Scenario: Unavailable runtime
- **WHEN** the pipeline is `unavailable` because a bundled vision file is missing
- **THEN** the status names the missing file, and the switch still shows on

#### Scenario: Setting cannot be saved
- **WHEN** the user opens Settings' Live scan section and turns the switch on and saving the setting fails
- **THEN** the switch shows off, the pipeline is not started, and an error message is shown

#### Scenario: Setting cannot be saved when switching off
- **WHEN** the user opens Settings' Live scan section and turns the switch off and saving the setting fails or is refused as busy
- **THEN** the switch shows off, live scan is stopped, and an error says the preference was not saved

### Requirement: Scan evidence panel is visible without scrolling
On the desktop Scanner layout (window at least 1100 logical pixels wide), the scan evidence panel SHALL lie fully within the window without scrolling the page, at window heights of 720 logical pixels and more. Content that does not fit SHALL scroll inside the panel. On narrower windows the panel SHALL follow the shared answer strip, with scan configuration in Settings.

#### Scenario: Desktop window
- **WHEN** Scanner is shown in a 1660 by 870 logical pixel window
- **THEN** the scan evidence panel's whole frame is on screen with the page unscrolled

#### Scenario: Short desktop window
- **WHEN** Scanner is shown in a 1100 by 720 logical pixel window with a long recent scans list
- **THEN** the panel's frame is still on screen and the list scrolls inside the panel

#### Scenario: Narrow window
- **WHEN** Scanner is shown in a 900 logical pixel wide window
- **THEN** the scan evidence panel comes after the answer strip, with no configuration controls above the answer

### Requirement: Footer shows the live scan state
The app footer SHALL show the live scan pipeline state: `off`, `starting`, `ready`, `stopping` or `unavailable`. It SHALL NOT claim that nothing is captured while live scan is `starting` or `ready`.

#### Scenario: Live scan on
- **WHEN** live scan is `ready`
- **THEN** the footer says live scan is on, and does not say "No capture"

#### Scenario: Live scan off
- **WHEN** live scan is `off`
- **THEN** the footer says live scan is off and nothing is captured

#### Scenario: Live scan unavailable
- **WHEN** live scan is `unavailable` because a bundled vision file is missing
- **THEN** the footer says live scan is unavailable

### Requirement: Scanner shows the record switch and its status
The Live scan section of Settings SHALL show a "Record scan frames" switch next to the live scan switch, enabled only while live scan is `ready`. While a session exists it SHALL show:
- the number of scans written;
- the number dropped;
- the session folder path.

The counters and folder path SHALL appear in Settings beside the switch. When recording turns itself off, Scanner SHALL retain a visible note saying why (cap reached or write error), including after Settings closes. The failed session folder path SHALL remain reachable by reopening Settings.

#### Scenario: Recording runs
- **WHEN** Settings' Live scan section is open, recording is on and 12 scans were written and 1 dropped
- **THEN** Settings shows 12 written, 1 dropped and the session folder path

#### Scenario: Live scan not ready
- **WHEN** live scan is `off`, `starting` or `unavailable`
- **THEN** the record switch shows off and cannot be turned on

#### Scenario: Write failure
- **WHEN** recording turned itself off because a write failed
- **THEN** the Settings switch shows off with the error and folder path; closing Settings leaves the error note visible on Scanner, and reopening Settings still shows the failed session folder path

### Requirement: Scanner shows the scan hotkey and lets the user rebind it
Next to the live scan switch in Settings' Live scan section, the app SHALL show the scan hotkey's binding and state, as the pipeline publishes it, and a control offering Off and F1-F24. The control SHALL be enabled while live scan is `off` or `ready` and no rebind is in progress. An `unavailable` hotkey SHALL show its key and reason, and say that mouse scans still work. A refused or failed rebind SHALL show its error, and the control SHALL show the binding still in force.

#### Scenario: Registered hotkey
- **WHEN** Settings' Live scan section is open and live scan is `ready` and F9 is registered
- **THEN** that section shows that F9 scans at the cursor, and the control shows F9

#### Scenario: Hotkey held by another application
- **WHEN** Settings' Live scan section is open and live scan is `ready` and the hotkey state is `unavailable` with F9 and the OS reason
- **THEN** that section shows that F9 is unavailable with that reason and that mouse scans still work, and the control stays enabled

#### Scenario: Rebind refused
- **WHEN** Settings' Live scan section is open and the user picks F10 in the control and the rebind is refused because another application holds F10
- **THEN** that section shows an error naming F10, and the control shows F9

#### Scenario: Live scan off
- **WHEN** Settings' Live scan section is open and live scan is `off` and the binding is F9
- **THEN** that section shows that F9 is used while live scan is on, and the control is enabled

#### Scenario: Live scan starting
- **WHEN** Settings' Live scan section is open and live scan is `starting`
- **THEN** the control is disabled
