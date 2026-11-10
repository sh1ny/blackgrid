# Spec Delta

## MODIFIED Requirements

### Requirement: An accepted scan becomes the current selection
When a scan is published as accepted for item X, the app SHALL make X the current selection: the answer strip SHALL show X and its decision on Scanner and on Map, and the Scanner's Why and Prices sections SHALL show X's needs and prices. The newest selection SHALL win: an accepted scan, a manual selection, a history selection and a picked scan correction each replace whatever was shown, in the order they happened.

#### Scenario: Accepted scan replaces a manual selection
- **WHEN** the user has manually selected item A and a scan is then accepted for item B
- **THEN** the answer strip shows item B and its decision

#### Scenario: Manual selection after a scan
- **WHEN** a scan was accepted for item B and the user then manually selects item A
- **THEN** the answer strip shows item A, and a later refresh does not bring back item B

#### Scenario: Accepted scan while a history row is open
- **WHEN** the user has a history row for item A open and a scan is accepted for item B
- **THEN** the history view closes and the answer strip shows item B in the live mode

#### Scenario: Accepted scan after a correction
- **WHEN** the user picked item C from a scan's correction offer and a scan is then accepted for item B
- **THEN** the answer strip shows item B as an accepted scan, no longer labelled as corrected

### Requirement: Unaccepted scans never change the selection
A scan that ends rejected or failed SHALL NOT change the current selection, the decision, the FIR value or the history, even when it has a best candidate.

#### Scenario: Rejected scan with a candidate
- **WHEN** item A is selected and a scan ends rejected with best candidate C
- **THEN** the answer strip still shows item A, and no history entry for C is added

#### Scenario: Failed scan after an accepted one
- **WHEN** a scan was accepted for item B and the next scan fails at capture
- **THEN** the answer strip still shows item B with the FIR value the user set

### Requirement: Each accepted scan is consumed once
Each accepted scan SHALL become the selection at most once and SHALL be recorded in history at most once. Re-publication, a listener notification without a new accepted scan, a catalog or progress refresh, the periodic age update and opening history SHALL NOT be taken as a new accepted scan.

#### Scenario: Refresh after an accepted scan
- **WHEN** a scan is accepted for item B, and the catalog and progress then refresh
- **THEN** history holds one entry for B from that scan, and the scan's acceptance time is unchanged

#### Scenario: Unrelated notification
- **WHEN** a scan was accepted for item B, the user then selects item A by hand, and the scanner then notifies for a phase change with no new accepted scan
- **THEN** the answer strip still shows item A

### Requirement: Accepted scans are recorded in history as scans
Each accepted scan that drives a decision SHALL record activity for its item in the live mode, with source `scan` and the acceptance time. The entry is one per item and mode, revised on each accepted scan. If recording fails, the decision SHALL still be shown, together with an error saying the scan was not recorded.

#### Scenario: Two scans of the same item
- **WHEN** two scans are accepted for item B in PvP
- **THEN** history holds one PvP entry for B with source `scan`, at revision 2, observed at the second acceptance time

#### Scenario: History write fails
- **WHEN** a scan is accepted for item B and the history write fails
- **THEN** the answer strip shows item B with an error that the scan was not recorded

### Requirement: Scan advice shows its age and stops being current on a mode or session change
The selection SHALL keep each accepted scan's item, mode, catalog revision, acceptance time and decision at acceptance unchanged. The answer strip SHALL show the current decision for it, and its provenance line SHALL say how long ago it was scanned (workspace-shell). After a mode or session change the scanned item SHALL no longer be shown as current advice.

#### Scenario: Prices go stale after a scan
- **WHEN** a scan is accepted for item B, the user sets FIR to yes and the strip shows Flea, and B's Flea quote then becomes older than one hour
- **THEN** the strip shows Check for B, and the scan's acceptance time and decision at acceptance (Check, computed with FIR unknown) are unchanged

#### Scenario: Mode changes after a scan
- **WHEN** a scan is accepted for item B in PvP and the live mode then changes to PvE
- **THEN** the strip no longer shows B as current advice and no history entry is added for PvE
