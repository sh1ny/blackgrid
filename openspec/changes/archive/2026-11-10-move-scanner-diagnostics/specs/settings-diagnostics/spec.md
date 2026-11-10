# Spec Delta

## Purpose

Defines what the collapsed Diagnostics section of Settings shows about scans and data sources, so the Map and Scanner can stay clean of detail that only helps diagnose the app.

## ADDED Requirements

### Requirement: Main windows keep diagnostic detail out of normal use
The Map, the Scanner and their inspectors SHALL NOT show scan codes, OCR text, title crops, marker or match scores, match margins, item IDs of scans, scan numbers, stage timings, the recent scans list, data source URLs, UTC times or record counts. One exception: a scan correction offer shows the text the scan read, because the player picks the item from it; its same-name rows keep their 6-character ID suffix, which tells catalog variants apart.

#### Scenario: Accepted scan on the Scanner
- **WHEN** a scan of item `5449016a4bdc2d6f028b456f` is accepted with OCR text `CAN OF SPRATS` from the targeted pass, and the Scanner is shown with its inspector open and its Inspection details, Requirements and Sources sections expanded
- **THEN** the item's name is shown, and no text on the Scanner contains `5449016a4bdc2d6f028b456f`, `CAN OF SPRATS`, `Marker score`, `Margin`, `Scan #`, ` ms`, `Targeted`, `records` or `Source:`, and none appears on the Map either

#### Scenario: Rejected scan with a correction offer
- **WHEN** scan 7 ends rejected `ambiguous` with OCR text `ANA M1` and candidates scoring 1.0 and 0.974, and the Map and the Scanner are each shown with the offer
- **THEN** the offer shows `ANA M1`, and no text on either contains `#7`, `ambiguous`, `1.00`, `0.97`, `Marker score` or ` ms`

#### Scenario: Corrected scan subtitle
- **WHEN** the decision card shows an item corrected by hand from scan 7, 3 minutes after the correction
- **THEN** its subtitle reads "Corrected from a scan • 3 min ago • chosen by hand" and contains no `#7`

### Requirement: Problems the player must act on stay on the main windows
Moving diagnostic detail SHALL NOT hide a problem the player must act on. In plain words, the Map and Scanner SHALL keep showing scan rejection and failure reasons, the recording stop note, catalog and Tracker errors, and the live scan state.

#### Scenario: Rejected scan still explains itself
- **WHEN** a scan ends rejected `belowSimilarity` with best candidate X
- **THEN** the Scanner says the name did not match any item closely enough and shows X labelled not accepted, and no text on it contains `belowSimilarity`

#### Scenario: Errors the player must act on stay visible
- **WHEN** the catalog has an error, recording stopped because a write failed, and the Scanner is shown with its inspector open and its Sources section expanded
- **THEN** the Scanner still shows the recording stop note, and the inspector's Data sources panel still shows the catalog error

### Requirement: Diagnostics shows the latest scans' evidence
Expanded, Diagnostics SHALL show the evidence of the scan the Scanner shows: its scan number, end state, winning pass, marker score, title crop, OCR text, best and runner-up candidates with their scores and margin, the accepted item's ID, and the rejection or failure code with any wider-scan failure. When a later scan was not accepted, it SHALL show that scan's number, code, OCR text and marker score too. Before any scan is published it SHALL say no scan is published yet.

#### Scenario: Accepted scan
- **WHEN** scan 4 is accepted for item ID `5449016a4bdc2d6f028b456f` from the targeted pass, and the user opens Settings and expands Diagnostics
- **THEN** Diagnostics shows `Scan #4`, the item ID, `Targeted` as the pass, the marker score, the title crop and the OCR text

#### Scenario: Rejection after an accepted item
- **WHEN** scan 1 is accepted for item A, scan 2 then ends rejected `belowSimilarity` with OCR text `FILTERBYITEM`, and Diagnostics is expanded
- **THEN** Diagnostics shows scan 2's code `belowSimilarity` and `FILTERBYITEM`, and still shows scan 1's title crop

#### Scenario: Failed scan
- **WHEN** no scan has been accepted, the latest scan failed with `visionTimeout`, and Diagnostics is expanded
- **THEN** Diagnostics shows the code `visionTimeout` and the failure message, and no title crop

#### Scenario: No scan yet
- **WHEN** no scan has been published and Diagnostics is expanded
- **THEN** its scan part says no scan is published yet and shows no timings

#### Scenario: A scan arrives while open
- **WHEN** Diagnostics is expanded and a new scan is accepted
- **THEN** Diagnostics shows the new scan's evidence without Settings being reopened

### Requirement: Diagnostics shows stage timings
Expanded, Diagnostics SHALL show the latest published scan's stage durations in milliseconds from its trigger for each pass it ran (capture, vision, matching) and its total, labelled with that scan's number. A stage not reached SHALL be shown as absent, not 0.

#### Scenario: Timings of an accepted scan
- **WHEN** scan 3 is accepted with capture ending 40 ms and publication 180 ms after its trigger, and Diagnostics is expanded
- **THEN** Diagnostics shows `Timings • Scan #3`, 40 ms for the capture stage and 180 ms total

#### Scenario: Early failure
- **WHEN** a scan fails at targeted capture and Diagnostics is expanded
- **THEN** the vision and matching stages are shown as absent

#### Scenario: Timings follow the latest scan after a rejection
- **WHEN** scan 1 is accepted for item A, scan 2 then ends rejected, and Diagnostics is expanded
- **THEN** the timings shown are scan 2's, labelled with scan 2's number

### Requirement: Diagnostics lists the recent scans
Expanded, Diagnostics SHALL list the 10 most recent published scans, newest first. Each entry SHALL show its scan number, its item's name or a plain-language reason, whether the hotkey started it, its end state and its total time.

#### Scenario: Recent list bound
- **WHEN** an 11th scan is published and Diagnostics is expanded
- **THEN** the list shows the 10 newest scans and the oldest is gone

#### Scenario: Hotkey and mouse scans
- **WHEN** a scan started by the hotkey and a scan started by a mouse release are published, and Diagnostics is expanded
- **THEN** the hotkey scan's entry is labelled as a hotkey scan, and the mouse scan's entry carries no such label

#### Scenario: Rejected entry
- **WHEN** a rejected `noMarker` scan is in the list
- **THEN** its entry gives a plain-language reason with the end state `Rejected`

#### Scenario: No scans
- **WHEN** no scan has been published and Diagnostics is expanded
- **THEN** the list says there are no scans yet

### Requirement: Diagnostics shows data source detail
Expanded, Diagnostics SHALL describe the item data behind the item shown (a history item's saved data, else the live catalog): its source, its download time in UTC, the items source update time, the record count of each dataset, the price time in UTC, the Tracker progress update time in UTC, the cooldown end time while refresh is cooling down, and the age limits after which item data, prices and progress count as old. With no complete catalog it SHALL say so.

#### Scenario: Current catalog
- **WHEN** a catalog downloaded at 2026-11-10T08:05:00Z is current and Diagnostics is expanded
- **THEN** Diagnostics shows the source, `2026-11-10T08:05:00.000Z` and each dataset's record count

#### Scenario: No catalog
- **WHEN** no complete catalog is available and Diagnostics is expanded
- **THEN** Diagnostics says there is no complete item data download and shows no record counts

#### Scenario: Tracker in cooldown
- **WHEN** Tracker progress is in cooldown and Diagnostics is expanded
- **THEN** Diagnostics shows when refresh is available again

### Requirement: Collapsed Diagnostics does no scan or source work
While Diagnostics is collapsed, its scan and data source parts SHALL NOT be built: no title crop is decoded and nothing listens for scans for them. Expanding SHALL show the current state. Collapsing SHALL release any decoded crop.

#### Scenario: Collapsed with an accepted scan
- **WHEN** a scan with a title crop is accepted and Settings is open with Diagnostics collapsed
- **THEN** no title crop image and no scan evidence text is in the widget tree

#### Scenario: Expand after scans
- **WHEN** three scans were published while Diagnostics was collapsed, and the user expands it
- **THEN** it shows the latest scan's evidence and all three in the recent list
