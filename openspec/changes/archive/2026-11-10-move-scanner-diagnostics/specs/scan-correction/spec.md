# Spec Delta

## MODIFIED Requirements

### Requirement: The offer lists the scan's best candidates
The offer SHALL list the scan's candidates in the matcher's rank order: up to 5 distinct items, each with its name, that the live catalog holds and that score at least .40. A candidate with no live catalog item SHALL be left out. The offer SHALL show the scan's OCR text and SHALL NOT show the scan's id or any candidate's similarity. It SHALL show no recommendation for any candidate.

#### Scenario: Close-named variants
- **WHEN** a scan ends rejected `ambiguous` with candidates ANA M1 (OD Green) at 1.0 and ANA M1 (Black) at 0.974
- **THEN** the offer lists ANA M1 (OD Green) first and ANA M1 (Black) second, shows neither `1.00` nor `0.97`, and shows no recommendation

#### Scenario: More than five candidates
- **WHEN** the scan's match ranks seven distinct candidates at or above .40
- **THEN** the offer lists only the first five, in rank order

#### Scenario: Weak candidates
- **WHEN** a scan ends rejected `belowSimilarity` and its best candidate scores .31
- **THEN** the offer lists no candidates and still offers the text search

#### Scenario: Candidate gone from the catalog
- **WHEN** a scan's second candidate is not in the live catalog when the offer is shown
- **THEN** the offer lists the other candidates and leaves that one out

#### Scenario: No scan id in the offer
- **WHEN** scan 7 ends rejected `ambiguous` with OCR text `ANA M1` and an offer is shown
- **THEN** the offer says the last scan was not accepted and shows `ANA M1`, and no offer text contains `#7`

### Requirement: Picking a correction makes it the current selection
Picking a candidate or a search result from a current offer SHALL make that item the current selection in the live mode, with its decision from the shared engine. It SHALL close an open history view, reset transient FIR to unknown and clear the offer. The card SHALL label the item as corrected from a scan, without the scan's id, and show how long ago it was corrected. A failed history write SHALL leave the correction shown with an error.

#### Scenario: Pick the runner-up
- **WHEN** an offer for scan 7 lists candidates A and B and the user picks B
- **THEN** the decision card shows B with the shared engine's decision, labelled "Corrected from a scan" with no `#7`, and the offer is gone

#### Scenario: Pick from search
- **WHEN** the user edits the offer's text, and picks search result C
- **THEN** the decision card shows C labelled as corrected from a scan

#### Scenario: FIR from the earlier item
- **WHEN** item A is shown with FIR set to yes and the user picks candidate A from an offer
- **THEN** FIR is unknown and the decision is computed with FIR unknown

#### Scenario: History view open
- **WHEN** a history row is open and the user picks a candidate
- **THEN** the history view closes and the decision card shows the picked item in the live mode

#### Scenario: History write fails
- **WHEN** the user picks candidate B and the history write fails
- **THEN** the decision card shows B with an error saying the correction was not recorded

### Requirement: Same-name candidates are told apart in the offer
When two or more rows the offer lists, candidates and search results together, have the same display name, each of those rows SHALL also show its flea status from the live catalog (`flea`, `no flea`, or `flea unknown` when the catalog does not say) and the last 6 characters of its ID. Unknown SHALL never show as `flea`. Other rows SHALL show as before.

#### Scenario: Weapon case variants
- **WHEN** a scan ends rejected `ambiguous` with candidates "Weapon case" (ID ending `4b423c`, flea-listable) at 1.0 and "Weapon case" (ID ending `045d88`, no flea) at .909
- **THEN** the offer lists "Weapon case · flea · 4b423c" first and "Weapon case · no flea · 045d88" second, shows neither `1.00` nor `0.91`, and shows no recommendation

#### Scenario: Only one listed same-name item
- **WHEN** an offer lists "Weapon case" and "Item case", and the other Weapon case variant is not in the live catalog
- **THEN** both rows show only their names

#### Scenario: Unknown flea status
- **WHEN** an offer lists two "Weapon case" candidates, one flea-listable and one whose catalog entry does not say whether it can be sold on the flea market
- **THEN** the second row shows `flea unknown` and never `flea`

#### Scenario: Variant found through the search
- **WHEN** a scan ends `ambiguous` with a best candidate in a same-name group of 12 items, so 7 variants are not among the candidates, and the user finds a sixth variant through the offer's search
- **THEN** that search row shows the variant's name, flea status and the last 6 characters of its ID

#### Scenario: Picking a variant
- **WHEN** the user picks the "no flea" Weapon case row
- **THEN** the current selection is the no-flea Weapon case and its decision is shown, as for any picked correction
