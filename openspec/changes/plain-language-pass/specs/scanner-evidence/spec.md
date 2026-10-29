# Spec Delta

## MODIFIED Requirements

### Requirement: Scan phase is visible, including fallback
While a scan runs, Scanner SHALL show its phase in plain words: that it is reading the item while the targeted pass runs, then that it is trying a wider scan from the start of the fallback pass, including its wait before the fallback capture request, until the scan ends. A superseded scan's phase SHALL be replaced by the newer scan's phase.

#### Scenario: Fallback becomes visible
- **WHEN** a scan's targeted pass is rejected and its fallback pass starts
- **THEN** Scanner says it is trying a wider scan before the fallback result arrives, and the phase text contains neither `targeted` nor `fallback`

#### Scenario: Superseded scan
- **WHEN** a scan is superseded during its fallback pass
- **THEN** Scanner says it is reading the item for the new scan, and shows no evidence from the superseded scan

### Requirement: Scanner shows the latest scan's evidence
Scanner SHALL show the evidence of the most recent accepted scan or, before any scan is accepted, of the latest published scan. The open view SHALL show the accepted item's name, or a plain-language rejection or failure reason with the best candidate's name labelled not accepted. A collapsed Details section SHALL hold the end state and winning pass, the marker score, the thresholded title crop, the OCR text, the best and runner-up candidates with their scores and margin, the accepted item's ID, and the rejection or failure code. The evidence SHALL survive switching to Map and back.

#### Scenario: Accepted scan
- **WHEN** a scan is accepted for item ID `5449016a4bdc2d6f028b456f` from the targeted pass
- **THEN** Scanner shows that item's name in the open view, and Details, once expanded, shows the item ID, `Targeted` as the pass, its marker score, crop and OCR text

#### Scenario: Rejected scan
- **WHEN** no scan has been accepted and a scan ends rejected `belowSimilarity` with best candidate X at .41
- **THEN** the open view says the name did not match any item closely enough and shows X labelled not accepted, with no accepted item and no `belowSimilarity`, and Details, once expanded, shows the code `belowSimilarity` and the score .41

#### Scenario: Failed scan
- **WHEN** no scan has been accepted and a scan ends failed with `visionTimeout`
- **THEN** the open view says reading the item took too long and shows no candidate, and Details, once expanded, shows the code `visionTimeout`

#### Scenario: Navigation keeps evidence
- **WHEN** the user switches from Scanner to Map and back after a scan was published
- **THEN** Scanner shows the same scan's evidence

#### Scenario: Newer accepted scan replaces the shown one
- **WHEN** scan 1 is accepted for item A and later scan 2 is accepted for item B
- **THEN** Scanner shows item B's evidence and no longer shows item A's

### Requirement: Scanner shows stage timings and recent scans
Scanner SHALL show, inside the scan evidence Details section, the latest scan's stage durations in milliseconds from its trigger, and its total. A stage not reached SHALL be shown as absent, not 0. Scanner SHALL list the 10 most recent published scans in the open view, newest first, each with its item's name or a plain-language reason and whether the hotkey started the scan. Each entry's end state code and total time SHALL be inside Details.

#### Scenario: Timings of an accepted scan
- **WHEN** a scan is accepted with capture ending 40 ms and publication 180 ms after its trigger, and the user expands Details
- **THEN** Scanner shows 40 ms for the capture stage and 180 ms total

#### Scenario: Timings hidden while collapsed
- **WHEN** a scan is published and Details is collapsed
- **THEN** no stage duration and no total is shown

#### Scenario: Early failure
- **WHEN** a scan fails at targeted capture and the user expands Details
- **THEN** the vision and matching stages are shown as absent

#### Scenario: Recent list bound
- **WHEN** an 11th scan is published
- **THEN** the list shows the 10 newest scans and the oldest is gone

#### Scenario: Recent rejected entry
- **WHEN** a rejected `noMarker` scan is in the recent list
- **THEN** its entry gives a plain-language reason and does not contain `noMarker`

#### Scenario: Hotkey scan in the list
- **WHEN** a scan started by the hotkey and a scan started by a mouse release are published
- **THEN** the hotkey scan's entry is labelled as a hotkey scan, and the mouse scan's entry carries no such label

### Requirement: A later unaccepted scan is shown as a note
When the latest published scan is rejected or failed and an earlier scan was accepted, Scanner SHALL keep showing the accepted scan's evidence and SHALL show, above it, a note that the last scan was not accepted. The note SHALL give that scan's plain-language rejection or failure reason and its best candidate's name labelled not accepted. Its OCR text, marker score and code SHALL be inside the Details section. The stage timings and the recent scans list SHALL still follow the latest published scan.

#### Scenario: Rejection after an accepted item
- **WHEN** scan 1 is accepted for item A and scan 2 then ends rejected `belowSimilarity` with OCR text `FILTERBYITEM` and best candidate C
- **THEN** Scanner still shows item A's evidence, and a note gives the plain reason and C labelled not accepted, and Details, once expanded, shows `belowSimilarity` and `FILTERBYITEM`

#### Scenario: Crop and timings after a rejection
- **WHEN** scan 1 is accepted for item A, scan 2 then ends rejected and the user expands Details
- **THEN** Scanner still shows item A's title crop, and the stage timings shown are scan 2's, labelled with scan 2's id

#### Scenario: Failure after an accepted item
- **WHEN** scan 1 is accepted for item A and scan 2 then fails at targeted capture with `targetNotForeground`
- **THEN** Scanner still shows item A's evidence, and a note says the game window was not in front, with no candidate and no `targetNotForeground` outside Details

#### Scenario: Accepted again
- **WHEN** a note is shown for a rejected scan and a newer scan is accepted
- **THEN** the note is gone and the newer scan's evidence is shown
