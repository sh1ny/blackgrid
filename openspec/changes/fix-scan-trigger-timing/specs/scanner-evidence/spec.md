# Spec Delta

## MODIFIED Requirements

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

## ADDED Requirements

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
