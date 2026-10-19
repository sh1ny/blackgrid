# scanner-evidence Specification

## Purpose
Shows the user, in the Scanner area, what live scanning is doing and what each scan found: the switch and its status, the current phase including a visible fallback, and per-scan evidence and timings. It never turns scan evidence into keep/sell advice.

## Requirements

### Requirement: Scanner shows the live scan switch and status
Scanner SHALL show a live scan switch reflecting the session's intent (the saved setting at launch, then the user's last switch) and the pipeline state: `off`, `starting`, `ready`, or `unavailable` with its reason, plus any stop warning. A switch SHALL save the setting; a failed save SHALL revert a switch-on but SHALL NOT undo a switch-off, which shows an error instead. An `unavailable` log status SHALL be shown.

#### Scenario: Switching on from Scanner
- **WHEN** the user turns the live scan switch on and the pipeline reaches `ready`
- **THEN** the switch shows on and the status reads that live scan is ready

#### Scenario: Unavailable runtime
- **WHEN** the pipeline is `unavailable` because a bundled vision file is missing
- **THEN** the status names the missing file, and the switch still shows on

#### Scenario: Setting cannot be saved
- **WHEN** the user turns the switch on and saving the setting fails
- **THEN** the switch shows off, the pipeline is not started, and an error message is shown

#### Scenario: Setting cannot be saved when switching off
- **WHEN** the user turns the switch off and saving the setting fails or is refused as busy
- **THEN** the switch shows off, live scan is stopped, and an error says the preference was not saved

### Requirement: Scan phase is visible, including fallback
While a scan runs, Scanner SHALL show its phase: `targeted` while the targeted pass runs, then `fallback underway` from the start of the fallback pass, including its wait before the fallback capture request, until the scan ends. A superseded scan's phase SHALL be replaced by the newer scan's phase.

#### Scenario: Fallback becomes visible
- **WHEN** a scan's targeted pass is rejected and its fallback pass starts
- **THEN** Scanner shows `fallback underway` before the fallback result arrives

#### Scenario: Superseded scan
- **WHEN** a scan is superseded during its fallback pass
- **THEN** Scanner shows the new scan's `targeted` phase, and no evidence from the superseded scan

### Requirement: Scanner shows the latest scan's evidence
Scanner SHALL show the evidence of the most recent accepted scan or, before any scan is accepted, of the latest published scan. It SHALL show its end state and winning pass, the marker score, the thresholded title crop, the OCR text, the best and runner-up candidates with their scores and margin, and either the accepted item's name and ID or the rejection or failure reason. A rejected best candidate SHALL be labelled not accepted. The evidence SHALL survive switching to Map and back.

#### Scenario: Accepted scan
- **WHEN** a scan is accepted for item ID `5449016a4bdc2d6f028b456f` from the targeted pass
- **THEN** Scanner shows that item's name and ID, `targeted` as the pass, its marker score, crop and OCR text

#### Scenario: Rejected scan
- **WHEN** no scan has been accepted and a scan ends rejected `belowSimilarity` with best candidate X at .41
- **THEN** Scanner shows reason `belowSimilarity`, X and .41 labelled not accepted, and no accepted item

#### Scenario: Failed scan
- **WHEN** no scan has been accepted and a scan ends failed with `visionTimeout`
- **THEN** Scanner shows failure `visionTimeout` and no candidate

#### Scenario: Navigation keeps evidence
- **WHEN** the user switches from Scanner to Map and back after a scan was published
- **THEN** Scanner shows the same scan's evidence

#### Scenario: Newer accepted scan replaces the shown one
- **WHEN** scan 1 is accepted for item A and later scan 2 is accepted for item B
- **THEN** Scanner shows item B's evidence and no longer shows item A's

### Requirement: Scanner shows stage timings and recent scans
Scanner SHALL show the latest scan's stage durations in milliseconds from its trigger, and its total. A stage not reached SHALL be shown as absent, not 0. Scanner SHALL list the 10 most recent published scans, newest first, with end state, item or reason, total time, and whether the hotkey started the scan.

#### Scenario: Timings of an accepted scan
- **WHEN** a scan is accepted with capture ending 40 ms and publication 180 ms after its trigger
- **THEN** Scanner shows 40 ms for the capture stage and 180 ms total

#### Scenario: Early failure
- **WHEN** a scan fails at targeted capture
- **THEN** the vision and matching stages are shown as absent

#### Scenario: Recent list bound
- **WHEN** an 11th scan is published
- **THEN** the list shows the 10 newest scans and the oldest is gone

#### Scenario: Hotkey scan in the list
- **WHEN** a scan started by the hotkey and a scan started by a mouse release are published
- **THEN** the hotkey scan's entry is labelled as a hotkey scan, and the mouse scan's entry carries no such label

### Requirement: A later unaccepted scan is shown as a note
When the latest published scan is rejected or failed and an earlier scan was accepted, Scanner SHALL keep showing the accepted scan's evidence and SHALL show, above it, a note that the last scan was not accepted. The note SHALL give that scan's rejection or failure reason, its OCR text and marker score when present, and its best candidate labelled not accepted. The stage timings and the recent scans list SHALL still follow the latest published scan.

#### Scenario: Rejection after an accepted item
- **WHEN** scan 1 is accepted for item A and scan 2 then ends rejected `belowSimilarity` with OCR text `FILTERBYITEM` and best candidate C
- **THEN** Scanner still shows item A's evidence, and a note shows `belowSimilarity`, `FILTERBYITEM` and C labelled not accepted

#### Scenario: Crop and timings after a rejection
- **WHEN** scan 1 is accepted for item A and scan 2 then ends rejected
- **THEN** Scanner still shows item A's title crop, and the stage timings shown are scan 2's, labelled with scan 2's id

#### Scenario: Failure after an accepted item
- **WHEN** scan 1 is accepted for item A and scan 2 then fails at targeted capture with `targetNotForeground`
- **THEN** Scanner still shows item A's evidence, and a note shows the failure `targetNotForeground` with no candidate

#### Scenario: Accepted again
- **WHEN** a note is shown for a rejected scan and a newer scan is accepted
- **THEN** the note is gone and the newer scan's evidence is shown

### Requirement: Scan evidence panel is visible without scrolling
On the desktop Scanner layout (window at least 1100 logical pixels wide), the scan evidence panel SHALL lie fully within the window without scrolling the page, at window heights of 720 logical pixels and more. Content that does not fit SHALL scroll inside the panel. On narrower windows the panel SHALL follow the Scanner controls directly.

#### Scenario: Desktop window
- **WHEN** Scanner is shown in a 1660 by 870 logical pixel window
- **THEN** the scan evidence panel's whole frame is on screen with the page unscrolled

#### Scenario: Short desktop window
- **WHEN** Scanner is shown in a 1100 by 720 logical pixel window with a long recent scans list
- **THEN** the panel's frame is still on screen and the list scrolls inside the panel

#### Scenario: Narrow window
- **WHEN** Scanner is shown in a 900 logical pixel wide window
- **THEN** the scan evidence panel comes right after the Scanner controls

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
Scanner SHALL show a "Record scan frames" switch next to the live scan switch, enabled only while live scan is `ready`. While a session exists it SHALL show:
- the number of scans written;
- the number dropped;
- the session folder path.

When recording turns itself off, Scanner SHALL say why: cap reached, or the write error.

#### Scenario: Recording runs
- **WHEN** recording is on and 12 scans were written and 1 dropped
- **THEN** Scanner shows 12 written, 1 dropped and the session folder path

#### Scenario: Live scan not ready
- **WHEN** live scan is `off`, `starting` or `unavailable`
- **THEN** the record switch shows off and cannot be turned on

#### Scenario: Write failure
- **WHEN** recording turned itself off because a write failed
- **THEN** the switch shows off and Scanner shows the error and the folder path

### Requirement: Unaccepted scan evidence never produces a recommendation
Publishing a scan that is not accepted, whether rejected or failed, SHALL NOT change the current selection, the decision card, the needs and sources panels, or the history. Only an accepted scan reaches keep/sell advice, through the scan-decisions rules; the evidence panel itself never shows a recommendation.

#### Scenario: Accepted scan drives the decision card
- **WHEN** the user has manually selected item A and a scan is accepted for item B
- **THEN** the decision card shows item B, and history gains one entry for B with source `scan`

#### Scenario: Rejected scan with a best candidate
- **WHEN** a scan is rejected with best candidate C
- **THEN** no decision, recommendation or history entry for C is shown

### Requirement: Scanner shows the scan hotkey and lets the user rebind it
Next to the live scan switch, Scanner SHALL show the scan hotkey's binding and state, as the pipeline publishes it, and a control offering Off and F1-F24. The control SHALL be enabled while live scan is `off` or `ready` and no rebind is in progress. An `unavailable` hotkey SHALL show its key and reason, and say that mouse scans still work. A refused or failed rebind SHALL show its error, and the control SHALL show the binding still in force.

#### Scenario: Registered hotkey
- **WHEN** live scan is `ready` and F9 is registered
- **THEN** Scanner shows that F9 scans at the cursor, and the control shows F9

#### Scenario: Hotkey held by another application
- **WHEN** live scan is `ready` and the hotkey state is `unavailable` with F9 and the OS reason
- **THEN** Scanner shows that F9 is unavailable with that reason and that mouse scans still work, and the control stays enabled

#### Scenario: Rebind refused
- **WHEN** the user picks F10 in the control and the rebind is refused because another application holds F10
- **THEN** Scanner shows an error naming F10, and the control shows F9

#### Scenario: Live scan off
- **WHEN** live scan is `off` and the binding is F9
- **THEN** Scanner shows that F9 is used while live scan is on, and the control is enabled

#### Scenario: Live scan starting
- **WHEN** live scan is `starting`
- **THEN** the control is disabled
