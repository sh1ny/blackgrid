# Spec Delta

## Purpose

Shows the user, in the Scanner area, what live scanning is doing and what each scan found: the switch and its status, the current phase including a visible fallback, and per-scan evidence and timings. It never turns scan evidence into keep/sell advice.

## ADDED Requirements

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
While a scan runs, Scanner SHALL show its phase: `targeted` while the targeted pass runs, then `fallback underway` from the fallback capture request until the scan ends. A superseded scan's phase SHALL be replaced by the newer scan's phase.

#### Scenario: Fallback becomes visible
- **WHEN** a scan's targeted pass is rejected and its fallback pass starts
- **THEN** Scanner shows `fallback underway` before the fallback result arrives

#### Scenario: Superseded scan
- **WHEN** a scan is superseded during its fallback pass
- **THEN** Scanner shows the new scan's `targeted` phase, and no evidence from the superseded scan

### Requirement: Scanner shows the latest scan's evidence
For the latest published scan, Scanner SHALL show its end state and winning pass. It SHALL also show the marker score, the thresholded title crop, the OCR text, the best and runner-up candidates with their scores and margin, and either the accepted item's name and ID or the rejection or failure reason. A rejected best candidate SHALL be labelled not accepted. The evidence SHALL survive switching to Map and back.

#### Scenario: Accepted scan
- **WHEN** a scan is accepted for item ID `5449016a4bdc2d6f028b456f` from the targeted pass
- **THEN** Scanner shows that item's name and ID, `targeted` as the pass, its marker score, crop and OCR text

#### Scenario: Rejected scan
- **WHEN** a scan ends rejected `belowSimilarity` with best candidate X at .41
- **THEN** Scanner shows reason `belowSimilarity`, X and .41 labelled not accepted, and no accepted item

#### Scenario: Failed scan
- **WHEN** a scan ends failed with `visionTimeout`
- **THEN** Scanner shows failure `visionTimeout` and no candidate

#### Scenario: Navigation keeps evidence
- **WHEN** the user switches from Scanner to Map and back after a scan was published
- **THEN** Scanner shows the same scan's evidence

### Requirement: Scan evidence never produces a recommendation
Publishing a scan, accepted or not, SHALL NOT change the current selection, the decision card, the needs and sources panels, or the history. Keep/sell advice from scans belongs to M4.

#### Scenario: Accepted scan leaves the decision card alone
- **WHEN** the user has manually selected item A and a scan is accepted for item B
- **THEN** the decision card still shows item A, and no history entry is added

#### Scenario: Rejected scan with a best candidate
- **WHEN** a scan is rejected with best candidate C
- **THEN** no decision, recommendation or history entry for C is shown

### Requirement: Scanner shows stage timings and recent scans
Scanner SHALL show the latest scan's stage durations in milliseconds from its trigger, and its total. A stage not reached SHALL be shown as absent, not 0. Scanner SHALL list the 10 most recent published scans, newest first, with end state, item or reason and total time.

#### Scenario: Timings of an accepted scan
- **WHEN** a scan is accepted with capture ending 40 ms and publication 180 ms after its trigger
- **THEN** Scanner shows 40 ms for the capture stage and 180 ms total

#### Scenario: Early failure
- **WHEN** a scan fails at targeted capture
- **THEN** the vision and matching stages are shown as absent

#### Scenario: Recent list bound
- **WHEN** an 11th scan is published
- **THEN** the list shows the 10 newest scans and the oldest is gone
