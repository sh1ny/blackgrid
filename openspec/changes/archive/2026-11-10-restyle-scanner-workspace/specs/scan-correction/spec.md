# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: The offer appears with the decision card on Scanner and Map`
- TO: `### Requirement: The offer appears with the answer strip on Scanner and Map`

## MODIFIED Requirements

### Requirement: An unaccepted scan with a title offers a correction
A scan published rejected `ambiguous` or `belowSimilarity`, with non-empty OCR text, SHALL offer a correction, provided it began in the current mode and session and matched the live mode's catalog. Every other end SHALL NOT offer one: accepted, failed, and rejected for any other reason. Neither SHALL a scan from an earlier mode or session. The offer SHALL NOT change the selection, the decision, the FIR value or the history.

#### Scenario: Ambiguous scan with item A shown
- **WHEN** item A is selected and a scan ends rejected `ambiguous` with OCR text `ANA M1 OD GREEN`
- **THEN** a correction offer for that scan is shown, the answer strip still shows item A and its decision, and no history entry is added

#### Scenario: Below-similarity scan with nothing shown
- **WHEN** nothing is selected and a scan ends rejected `belowSimilarity` with OCR text `FILTRBY`
- **THEN** a correction offer is shown and no recommendation is shown

#### Scenario: Rejections that offer nothing
- **WHEN** a scan ends rejected `noMarker`, `uiChrome`, `titleTooShort`, `emptyCatalog`, `catalogModeMismatch`, `catalogUnavailable` or `matcherFailed`
- **THEN** no correction offer is made for it

#### Scenario: Failed scan
- **WHEN** a scan fails with `visionTimeout`
- **THEN** no correction offer is made for it

#### Scenario: Empty OCR text
- **WHEN** a scan ends rejected `belowSimilarity` with empty OCR text
- **THEN** no correction offer is made for it

#### Scenario: Mode changed before publication
- **WHEN** a scan is triggered in PvP, the live mode changes to PvE, and the scan is then published rejected `ambiguous`
- **THEN** no correction offer is made for it

### Requirement: The offer searches the catalog from the scan's text
The offer SHALL include a text field pre-filled with the scan's OCR text. Its results SHALL be the live catalog's items whose ID, name, short name or normalised name, lower-cased, contains every word of the field's normalised text, in ID order, at most 8. Editing the field SHALL NOT change the selection, the decision or the main item search.

#### Scenario: Words in another order
- **WHEN** the offer's text field holds `ANA M1 OD GREEN` and the catalog holds "ANA Tactical M1 plate carrier (OD Green)"
- **THEN** that item is among the offer's search results

#### Scenario: Edited text
- **WHEN** the offer's text field holds `ANA M1` and the user changes it to `ANA M1 black`
- **THEN** the offer's search results are only items containing all of `ana`, `m1` and `black`, at most 8, and the answer strip still shows the item it showed before

#### Scenario: No results
- **WHEN** the offer's text field holds text that matches no catalog item
- **THEN** the offer shows that nothing matched, and the selection is unchanged

### Requirement: Picking a correction makes it the current selection
Picking a candidate or a search result from a current offer SHALL make that item the current selection in the live mode, with its decision from the shared engine. It SHALL close an open history view, reset transient FIR to unknown and clear the offer. The strip's provenance line SHALL label the item as corrected from a scan, without the scan's id, and say how long ago it was corrected (workspace-shell). A failed history write SHALL leave the correction shown with an error.

#### Scenario: Pick the runner-up
- **WHEN** an offer for scan 7 lists candidates A and B and the user picks B
- **THEN** the answer strip shows B with the shared engine's decision, labelled "Corrected from a scan" with no `#7`, and the offer is gone

#### Scenario: Pick from search
- **WHEN** the user edits the offer's text, and picks search result C
- **THEN** the answer strip shows C labelled as corrected from a scan

#### Scenario: FIR from the earlier item
- **WHEN** item A is shown with FIR set to yes and the user picks candidate A from an offer
- **THEN** FIR is unknown and the decision is computed with FIR unknown

#### Scenario: History view open
- **WHEN** a history row is open and the user picks a candidate
- **THEN** the history view closes and the answer strip shows the picked item in the live mode

#### Scenario: History write fails
- **WHEN** the user picks candidate B and the history write fails
- **THEN** the answer strip shows B with an error saying the correction was not recorded

### Requirement: A correction stops being current on a mode or session change
After a mode or session change, the corrected item SHALL no longer be shown as current advice, and transient FIR SHALL reset to unknown. A correction SHALL be kept when the catalog or progress refreshes; its decision SHALL then follow the shared engine's current result.

#### Scenario: Session change after a correction
- **WHEN** the user picks B from an offer and the game session then changes
- **THEN** the strip no longer shows B as current advice, and FIR is unknown

#### Scenario: Prices go stale after a correction
- **WHEN** the user picks B from an offer, sets FIR to yes and the strip shows Flea, and B's Flea quote then becomes older than one hour
- **THEN** the strip still shows B labelled as corrected, with decision Check

### Requirement: A correction is never a new accepted scan
A correction SHALL NOT change the scanner's latest or last accepted scan. It SHALL NOT be counted as an accepted scan, and SHALL NOT record activity with source `scan`. It SHALL NOT be presented as an accepted scan anywhere an accepted scan is shown, including the session's latest accepted scan on Map. Its evidence panel SHALL still show the scan as not accepted.

#### Scenario: Correction after an accepted scan
- **WHEN** scan 1 is accepted for item A, scan 2 is rejected `ambiguous`, and the user picks B from scan 2's offer
- **THEN** the last accepted scan is still scan 1 for item A, no `scan` activity is recorded for B, and the evidence panel still shows scan 2 as not accepted

#### Scenario: Refresh after a correction
- **WHEN** the user picks B from an offer and the catalog and progress then refresh
- **THEN** the strip still shows B labelled as corrected, no new activity is recorded, and no accepted scan is added

### Requirement: Only the newest offer is current
Each unaccepted report SHALL be offered at most once. A newer offer SHALL replace an older one. The offer SHALL be cleared by a newer accepted scan, a manual or history selection, a picked correction, Dismiss, and a mode or session change. A newer scan with nothing to offer SHALL leave the current offer in place. Dismiss SHALL change nothing else.

#### Scenario: Newer offer
- **WHEN** scan 2 offers a correction and scan 3 then ends rejected `ambiguous` with OCR text
- **THEN** only scan 3's offer is shown

#### Scenario: Accepted scan clears the offer
- **WHEN** scan 2 offers a correction and scan 3 is then accepted for item D
- **THEN** no offer is shown and the answer strip shows D

#### Scenario: Failure keeps the offer
- **WHEN** scan 2 offers a correction and scan 3 then fails at targeted capture
- **THEN** scan 2's offer is still shown

#### Scenario: Manual selection clears the offer
- **WHEN** an offer is shown and the user selects item E from the main item search
- **THEN** no offer is shown and the answer strip shows E as a manual inspection

#### Scenario: Closing a history view keeps the offer
- **WHEN** a history row is open, a scan then offers a correction, and the user closes the history view
- **THEN** the offer is still shown and the answer strip shows the live selection

#### Scenario: Dismiss
- **WHEN** item A is shown, an offer is shown, and the user dismisses it
- **THEN** no offer is shown, the answer strip still shows A with the same FIR value, and no history entry is added

#### Scenario: Session change
- **WHEN** an offer is shown and the game session changes
- **THEN** no offer is shown

#### Scenario: Re-notification
- **WHEN** the user dismisses scan 2's offer and the scanner then notifies again with scan 2 still its latest report
- **THEN** no offer is shown

### Requirement: A stale pick changes nothing
A pick SHALL apply only while its offer is still the current one, the mode and session are those it was offered in, and its item is in the live mode's catalog. Otherwise it SHALL leave the selection, the decision, the FIR value, the offer and the history unchanged.

#### Scenario: Offer replaced before the pick
- **WHEN** scan 2's offer is shown, scan 3 is accepted for item D, and a pick from scan 2's offer then arrives
- **THEN** the answer strip shows D and no history entry is added for the picked item

#### Scenario: Item removed by a catalog refresh
- **WHEN** an offer lists candidate B, a catalog refresh removes B, and the user then picks B
- **THEN** the selection is unchanged and no history entry is added for B

#### Scenario: Mode changed before the pick
- **WHEN** an offer is made in PvP, the live mode changes to PvE, and a pick from it then arrives
- **THEN** the selection is unchanged and no history entry is added

### Requirement: The offer appears with the answer strip on Scanner and Map
The offer SHALL be shown in the answer strip on Scanner and on Map, next to the item the strip shows, never in its place. It SHALL survive switching between Scanner and Map. Its candidates, search and Dismiss SHALL work in both places.

#### Scenario: Offer on Map
- **WHEN** Map is open with item A shown in its answer strip and a scan offers a correction
- **THEN** Map's answer strip shows item A and the offer with its candidates, and picking one makes it the selection

#### Scenario: Navigation keeps the offer
- **WHEN** an offer is shown on Scanner and the user switches to Map and back
- **THEN** the same offer is shown, with the same text in its field
