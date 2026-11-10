# scanner-evidence Specification

## Purpose
Shows the user, in the Scanner area, what live scanning is doing and what each scan found: the switch and its status, the current phase including a visible fallback, and the latest scan's result in plain words. Scan evidence, stage timings and the recent scans list are in Settings under Diagnostics. It never turns scan evidence into keep/sell advice.

## Requirements

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

### Requirement: Scan phase is visible, including fallback
While a scan runs, Scanner SHALL show its phase in plain words: that it is reading the item while the targeted pass runs, then that it is trying a wider scan from the start of the fallback pass, including its wait before the fallback capture request, until the scan ends. A superseded scan's phase SHALL be replaced by the newer scan's phase.

#### Scenario: Fallback becomes visible
- **WHEN** a scan's targeted pass is rejected and its fallback pass starts
- **THEN** Scanner says it is trying a wider scan before the fallback result arrives, and the phase text contains neither `targeted` nor `fallback`

#### Scenario: Superseded scan
- **WHEN** a scan is superseded during its fallback pass
- **THEN** Scanner says it is reading the item for the new scan, and shows no evidence from the superseded scan

### Requirement: Scanner shows the latest scan's evidence
Scanner SHALL show the result of the most recent accepted scan or, before any scan is accepted, of the latest published scan, in plain words: the accepted item's name, or a plain-language rejection or failure reason with the best candidate's name labelled not accepted. Scanner SHALL NOT have a Details section; the scan's codes, scores, title crop, OCR text, candidates and item ID SHALL be shown only in Settings under Diagnostics. The result SHALL survive switching to Map and back.

#### Scenario: Accepted scan
- **WHEN** a scan is accepted for item ID `5449016a4bdc2d6f028b456f` from the targeted pass
- **THEN** Scanner shows that item's name, and shows no item ID, pass, marker score, title crop or OCR text

#### Scenario: Rejected scan
- **WHEN** no scan has been accepted and a scan ends rejected `belowSimilarity` with best candidate X at .41
- **THEN** Scanner says the name did not match any item closely enough and shows X labelled not accepted, with no accepted item, no `belowSimilarity` and no `0.41`

#### Scenario: Failed scan
- **WHEN** no scan has been accepted and a scan ends failed with `visionTimeout`
- **THEN** Scanner says reading the item took too long and shows no candidate and no `visionTimeout`

#### Scenario: No scan yet
- **WHEN** no scan has been published
- **THEN** Scanner says no scan is published yet

#### Scenario: Navigation keeps evidence
- **WHEN** the user switches from Scanner to Map and back after a scan was published
- **THEN** Scanner shows the same scan's result

#### Scenario: Newer accepted scan replaces the shown one
- **WHEN** scan 1 is accepted for item A and later scan 2 is accepted for item B
- **THEN** Scanner shows item B's name and no longer shows item A's

### Requirement: A later unaccepted scan is shown as a note
When the latest published scan is rejected or failed and an earlier scan was accepted, Scanner SHALL keep showing the accepted scan's result and SHALL show, above it, a note that the last scan was not accepted. The note SHALL give that scan's plain-language rejection or failure reason and its best candidate's name labelled not accepted. Its OCR text, marker score and code SHALL be shown only in Settings under Diagnostics.

#### Scenario: Rejection after an accepted item
- **WHEN** scan 1 is accepted for item A and scan 2 then ends rejected `belowSimilarity` with OCR text `FILTERBYITEM` and best candidate C
- **THEN** Scanner still shows item A's name, and a note gives the plain reason and C labelled not accepted, and no Scanner text contains `belowSimilarity` or `FILTERBYITEM`

#### Scenario: Crop and timings after a rejection
- **WHEN** scan 1 is accepted for item A and scan 2 then ends rejected
- **THEN** Scanner shows no title crop and no stage timing, and Settings' Diagnostics, once expanded, shows item A's title crop and scan 2's timings labelled with scan 2's number

#### Scenario: Failure after an accepted item
- **WHEN** scan 1 is accepted for item A and scan 2 then fails at targeted capture with `targetNotForeground`
- **THEN** Scanner still shows item A's name, and a note says the game window was not in front, with no candidate and no `targetNotForeground`

#### Scenario: Accepted again
- **WHEN** a note is shown for a rejected scan and a newer scan is accepted
- **THEN** the note is gone and the newer scan's name is shown

### Requirement: Scan evidence panel is visible without scrolling
On the Scanner, scan evidence SHALL be a section of the main column that follows Why and Prices, as the scanner-workspace capability places it, and SHALL scroll with the column rather than inside a frame of its own. On a desktop window (at least 1100 logical pixels wide) of 870 logical pixels or more in height, with an item selected and ordinary single-line needs, its title SHALL be on screen with the column unscrolled. On every width the section SHALL follow the shared answer strip, with scan configuration in Settings.

#### Scenario: Desktop window
- **WHEN** Scanner is shown in a 1660 by 870 logical pixel window with an item that has up to three requirement rows
- **THEN** the Scan evidence title is on screen with the main column unscrolled, below Why and Prices

#### Scenario: Short desktop window
- **WHEN** Scanner is shown in a 1100 by 720 logical pixel window with a scan phase, a note and an accepted scan, at a text scale large enough that the column's content is taller than the window
- **THEN** the main column scrolls as one, every Scan evidence line can be scrolled into view, and nothing overflows

#### Scenario: Narrow window
- **WHEN** Scanner is shown in a 900 logical pixel wide window
- **THEN** Scan evidence comes after the answer strip, Why and Prices, with no configuration controls above the answer

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

### Requirement: Unaccepted scan evidence never produces a recommendation
Publishing a scan that is not accepted, whether rejected or failed, SHALL NOT change the current selection, the answer strip, the Why and Prices sections, or the history. Only an accepted scan reaches keep/sell advice, through the scan-decisions rules; the evidence panel itself never shows a recommendation.

#### Scenario: Accepted scan drives the decision card
- **WHEN** the user has manually selected item A and a scan is accepted for item B
- **THEN** the answer strip shows item B, and history gains one entry for B with source `scan`

#### Scenario: Rejected scan with a best candidate
- **WHEN** a scan is rejected with best candidate C
- **THEN** no decision, recommendation or history entry for C is shown

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

### Requirement: Scanner workspace omits configuration rail
Scanner SHALL present its working evidence without the legacy manual/configuration rail. Top search SHALL provide item selection; game mode, data refresh, Tracker and live-scan controls SHALL remain reachable from the status bar or Settings.

#### Scenario: Scanner functions remain reachable without the old rail
- **WHEN** Scanner is shown with the legacy left panel removed
- **THEN** no duplicated mode/status/manual-search instructions occupy its workspace, and top search plus status or Settings retain item selection, mode authority, refresh, Tracker and live-scan functions
