# Spec Delta

## MODIFIED Requirements

### Requirement: Main windows keep diagnostic detail out of normal use
The Map, the Scanner and their inspectors SHALL NOT show scan codes, OCR text, title crops, marker or match scores, match margins, item IDs of scans, scan numbers, stage timings, the recent scans list, data source URLs, UTC times or record counts. One exception: a scan correction offer shows the text the scan read, because the player picks the item from it; its same-name rows keep their 6-character ID suffix, which tells catalog variants apart.

#### Scenario: Accepted scan on the Scanner
- **WHEN** a scan of item `5449016a4bdc2d6f028b456f` is accepted with OCR text `CAN OF SPRATS` from the targeted pass, and the Scanner is shown with its inspector open
- **THEN** the item's name is shown, and no text on the Scanner contains `5449016a4bdc2d6f028b456f`, `CAN OF SPRATS`, `Marker score`, `Margin`, `Scan #`, ` ms`, `Targeted`, `records` or `Source:`, and none appears on the Map either

#### Scenario: Rejected scan with a correction offer
- **WHEN** scan 7 ends rejected `ambiguous` with OCR text `ANA M1` and candidates scoring 1.0 and 0.974, and the Map and the Scanner are each shown with the offer
- **THEN** the offer shows `ANA M1`, and no text on either contains `#7`, `ambiguous`, `1.00`, `0.97`, `Marker score` or ` ms`

#### Scenario: Corrected scan subtitle
- **WHEN** the answer strip shows an item corrected by hand from scan 7, 3 minutes after the correction
- **THEN** its provenance line reads "Corrected from a scan · 3 min ago · chosen by hand" and contains no `#7`

### Requirement: Problems the player must act on stay on the main windows
Moving diagnostic detail SHALL NOT hide a problem the player must act on. In plain words, the Map and Scanner SHALL keep showing scan rejection and failure reasons, the recording stop note and the live scan state. Catalog and Tracker errors SHALL stay reachable from them: the status bar SHALL show the item data and Tracker status words, which lead to the Settings sections that show the error text (Item and map data, Tracker progress).

#### Scenario: Rejected scan still explains itself
- **WHEN** a scan ends rejected `belowSimilarity` with best candidate X
- **THEN** the Scanner says the name did not match any item closely enough and shows X labelled not accepted, and no text on it contains `belowSimilarity`

#### Scenario: Errors the player must act on stay visible
- **WHEN** the catalog has an error, recording stopped because a write failed, and the Scanner is shown
- **THEN** the Scanner still shows the recording stop note and the status bar says item data is out of date, and following that status opens Settings at Item and map data, which shows the catalog error text

#### Scenario: Tracker error stays reachable
- **WHEN** a Tracker progress refresh fails with an error and the Scanner is shown
- **THEN** the status bar shows the Tracker status, and Settings → Tracker progress shows "Tracker problem: " followed by the error text, in the error ink
