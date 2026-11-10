# Spec Delta

## MODIFIED Requirements

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
On the desktop Scanner layout (window at least 1100 logical pixels wide), the scan evidence panel SHALL lie fully within the window without scrolling the page, at window heights of 720 logical pixels and more. Content that does not fit SHALL scroll inside the panel. On narrower windows the panel SHALL follow the shared answer strip, with scan configuration in Settings.

#### Scenario: Desktop window
- **WHEN** Scanner is shown in a 1660 by 870 logical pixel window
- **THEN** the scan evidence panel's whole frame is on screen with the page unscrolled

#### Scenario: Short desktop window
- **WHEN** Scanner is shown in a 1100 by 720 logical pixel window with a scan phase, a note and an accepted scan, at a text scale large enough that the panel's content is taller than its frame
- **THEN** the panel's frame is still on screen with the page unscrolled, and the content scrolls inside the panel

#### Scenario: Narrow window
- **WHEN** Scanner is shown in a 900 logical pixel wide window
- **THEN** the scan evidence panel comes after the answer strip, with no configuration controls above the answer

## REMOVED Requirements

### Requirement: Scanner shows stage timings and recent scans
**Reason**: The stage timings and the recent scans list are diagnostic detail. The owner's rule of 2026-11-08 keeps them off the main windows, and the owner chose to move the whole recent scans list (S1).
**Migration**: Both are shown in Settings under Diagnostics; see `settings-diagnostics` ("Diagnostics shows stage timings" and "Diagnostics lists the recent scans").
