# Spec Delta

## Purpose

Turns an accepted live scan into the current item selection and its keep/sell decision from the shared engine, recorded once in activity history and fenced so stale or repeated scan results never become current advice.

## ADDED Requirements

### Requirement: An accepted scan becomes the current selection
When a scan is published as accepted for item X, the app SHALL make X the current selection: the decision card, needs and sources panels SHALL show X and its decision, on Scanner and on Map. The newest selection SHALL win: an accepted scan, a manual selection and a history selection each replace whatever was shown, in the order they happened.

#### Scenario: Accepted scan replaces a manual selection
- **WHEN** the user has manually selected item A and a scan is then accepted for item B
- **THEN** the decision card shows item B and its decision

#### Scenario: Manual selection after a scan
- **WHEN** a scan was accepted for item B and the user then manually selects item A
- **THEN** the decision card shows item A, and a later refresh does not bring back item B

#### Scenario: Accepted scan while a history row is open
- **WHEN** the user has a history row for item A open and a scan is accepted for item B
- **THEN** the history view closes and the decision card shows item B in the live mode

### Requirement: Scan decisions come from the shared engine
The decision for a scanned item SHALL be the shared decision engine's result for that item. The engine SHALL get the current catalog of the live mode, the session's progress for that mode, and FIR unknown unless the user set it for this scan. Every rule of the precedence table SHALL give the same outcome for a scanned item as for the same item selected by hand.

#### Scenario: Confirmed current need
- **WHEN** a scan is accepted for an item with a confirmed active quest need
- **THEN** the decision is Keep and shows the need

#### Scenario: Unknown progress
- **WHEN** a scan is accepted for an item with no need found and progress unavailable
- **THEN** the decision is Check and names progress as the missing fact, never Flea or Trader

#### Scenario: Every precedence rule
- **WHEN** fixture items for each of the six precedence rules (Keep, Keep for later, Check, Flea, Trader, Price Unavailable) are accepted by scan, and for Flea, Trader and Price Unavailable the user then sets FIR to yes
- **THEN** each decision equals the engine's decision for the same item selected by hand with the same catalog, progress and FIR (FIR yes for those three)

### Requirement: Unaccepted scans never change the selection
A scan that ends rejected or failed SHALL NOT change the current selection, the decision, the FIR value or the history, even when it has a best candidate.

#### Scenario: Rejected scan with a candidate
- **WHEN** item A is selected and a scan ends rejected with best candidate C
- **THEN** the decision card still shows item A, and no history entry for C is added

#### Scenario: Failed scan after an accepted one
- **WHEN** a scan was accepted for item B and the next scan fails at capture
- **THEN** the decision card still shows item B with the FIR value the user set

### Requirement: Each accepted scan is consumed once
Each accepted scan SHALL become the selection at most once and SHALL be recorded in history at most once. Re-publication, a listener notification without a new accepted scan, a catalog or progress refresh, the periodic age update and opening history SHALL NOT be taken as a new accepted scan.

#### Scenario: Refresh after an accepted scan
- **WHEN** a scan is accepted for item B, and the catalog and progress then refresh
- **THEN** history holds one entry for B from that scan, and the scan's acceptance time is unchanged

#### Scenario: Unrelated notification
- **WHEN** a scan was accepted for item B, the user then selects item A by hand, and the scanner then notifies for a phase change with no new accepted scan
- **THEN** the decision card still shows item A

### Requirement: Scans from an older mode or session drive no decision
A scan SHALL drive a decision only when, at publication, the live mode and the game session are the same as when its trigger was taken, and its item exists in the current catalog of that mode. Otherwise the scan's evidence SHALL still be shown, the selection SHALL stay as it was, and nothing SHALL be recorded.

#### Scenario: Mode changes mid-scan
- **WHEN** a scan is triggered in PvP and the live mode changes to PvE before the scan is published as accepted
- **THEN** the selection is unchanged and no history entry is added

#### Scenario: Session changes mid-scan
- **WHEN** a scan is triggered and the game session changes before the scan is published as accepted
- **THEN** the selection is unchanged and no history entry is added

#### Scenario: Item missing from the current catalog
- **WHEN** a scan is accepted for an item that the current catalog of the live mode does not hold
- **THEN** the selection is unchanged and no history entry is added

### Requirement: Accepted scans are recorded in history as scans
Each accepted scan that drives a decision SHALL record activity for its item in the live mode, with source `scan` and the acceptance time. The entry is one per item and mode, revised on each accepted scan. If recording fails, the decision SHALL still be shown, together with an error saying the scan was not recorded.

#### Scenario: Two scans of the same item
- **WHEN** two scans are accepted for item B in PvP
- **THEN** history holds one PvP entry for B with source `scan`, at revision 2, observed at the second acceptance time

#### Scenario: History write fails
- **WHEN** a scan is accepted for item B and the history write fails
- **THEN** the decision card shows item B with an error that the scan was not recorded

### Requirement: FIR resets on every new accepted scan
Transient FIR SHALL reset to unknown on every accepted scan that drives a decision, even when it is the same item as before. It SHALL also reset on a mode or session change. A FIR value the user sets SHALL apply only to the current scan.

#### Scenario: Same item scanned again
- **WHEN** a scan is accepted for item B, the user sets FIR to yes, and a second scan is accepted for item B
- **THEN** FIR is unknown and the decision is computed with FIR unknown

#### Scenario: Session change
- **WHEN** a scan is accepted for item B, the user sets FIR to yes, and the game session then changes
- **THEN** FIR is unknown

### Requirement: Scan advice shows its age and stops being current on a mode or session change
The selection SHALL keep each accepted scan's item, mode, catalog revision, acceptance time and decision at acceptance unchanged. The card SHALL show the current decision for it and how long ago it was scanned. After a mode or session change the scanned item SHALL no longer be shown as current advice.

#### Scenario: Prices go stale after a scan
- **WHEN** a scan is accepted for item B, the user sets FIR to yes and the card shows Flea, and B's Flea quote then becomes older than one hour
- **THEN** the card shows Check for B, and the scan's acceptance time and decision at acceptance (Check, computed with FIR unknown) are unchanged

#### Scenario: Mode changes after a scan
- **WHEN** a scan is accepted for item B in PvP and the live mode then changes to PvE
- **THEN** the card no longer shows B as current advice and no history entry is added for PvE
