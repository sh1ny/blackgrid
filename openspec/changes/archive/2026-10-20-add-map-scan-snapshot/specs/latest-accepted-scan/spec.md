# Spec Delta

## Purpose

Keeps the session's latest accepted scan as its own record, separate from whatever the decision card shows, so the player can return to it on Map or Scanner and no other selection can pass as a new accepted scan.

## ADDED Requirements

### Requirement: Only an accepted scan that drives a decision advances the latest scan
The session's latest accepted scan SHALL change only when a scan is accepted and becomes the current selection. It SHALL then hold that scan's item, mode, acceptance time and report. A manual selection, a history selection, a correction offer, a picked correction, a catalog or progress refresh, the periodic age update and returning to the latest scan SHALL NOT change it.

#### Scenario: Accepted scan advances the latest scan
- **WHEN** no scan has been accepted this session and a scan is accepted for item B
- **THEN** the latest accepted scan is item B, with that scan's acceptance time

#### Scenario: Other selections leave it unchanged
- **WHEN** a scan was accepted for item B, and the user then selects item A by hand, opens a history row for item C and picks item D from a later scan's correction offer
- **THEN** the latest accepted scan is still item B, with its original acceptance time

#### Scenario: Refresh and age update leave it unchanged
- **WHEN** a scan was accepted for item B, and the catalog and progress then refresh and the age update runs
- **THEN** the latest accepted scan is still item B, with its original acceptance time

#### Scenario: Fenced scan does not advance it
- **WHEN** a scan was accepted for item B, and a later scan for item E is published as accepted after the mode changed, or with an item missing from the current catalog
- **THEN** the latest accepted scan is not item E

#### Scenario: Unaccepted scan does not advance it
- **WHEN** a scan was accepted for item B and the next scan ends rejected with best candidate C
- **THEN** the latest accepted scan is still item B

### Requirement: The latest scan advances once per scan and never goes back
Each accepted scan SHALL advance the latest accepted scan at most once. A scan SHALL NOT replace a newer one: a scan whose report is older than the current latest SHALL leave it unchanged. Re-publication or a notification without a new accepted scan SHALL NOT change it or its acceptance time.

#### Scenario: Newer scan replaces older
- **WHEN** a scan is accepted for item B and a newer scan is then accepted for item E
- **THEN** the latest accepted scan is item E

#### Scenario: Repeated notification
- **WHEN** a scan was accepted for item B and the scanner notifies again with the same accepted scan
- **THEN** the latest accepted scan is item B with its first acceptance time

#### Scenario: Same item scanned again
- **WHEN** two scans are accepted in turn for item B
- **THEN** the latest accepted scan is item B with the second acceptance time

### Requirement: The latest scan is session-only and clears on a mode or session change
The latest accepted scan SHALL exist only in memory for the running app. It SHALL be empty at startup and SHALL be cleared when the live mode changes or the game session changes. It SHALL NOT be restored from history or storage.

#### Scenario: Empty at startup
- **WHEN** the app starts with scan activity already in history
- **THEN** there is no latest accepted scan

#### Scenario: Mode change clears it
- **WHEN** a scan was accepted for item B in PvP and the live mode then changes to PvE
- **THEN** there is no latest accepted scan

#### Scenario: Session change clears it
- **WHEN** a scan was accepted for item B and the game session then changes
- **THEN** there is no latest accepted scan

### Requirement: The decision card can return to the latest scan
When there is a latest accepted scan that the decision card is not showing as its accepted scan, the card SHALL offer a "Back to latest scan" action, on Map and on Scanner. The action SHALL make that scan the current selection again, shown as an accepted scan with its original acceptance time. It SHALL record no history, SHALL NOT change the latest accepted scan, SHALL close an open history view, and SHALL reset FIR to unknown.

#### Scenario: Return after a manual selection
- **WHEN** a scan was accepted for item B, the user selects item A by hand and then uses Back to latest scan
- **THEN** the card shows item B as an accepted scan, scanned at its original acceptance time, and history has no new entry

#### Scenario: Return closes history
- **WHEN** a scan was accepted for item B and the user has a history row for item C open
- **THEN** the card offers Back to latest scan, and using it closes the history view and shows item B in the live mode

#### Scenario: Return resets FIR
- **WHEN** a scan was accepted for item B, the user selects item A by hand, sets FIR to yes and then uses Back to latest scan
- **THEN** FIR is unknown and the decision for item B is computed with FIR unknown

#### Scenario: No action while the latest scan is shown
- **WHEN** the card shows the latest accepted scan
- **THEN** the card offers no Back to latest scan action

#### Scenario: No action without a latest scan
- **WHEN** no scan has been accepted this session, or the last one was cleared by a mode or session change
- **THEN** the card offers no Back to latest scan action

#### Scenario: Stale return is refused
- **WHEN** the action is used for a latest scan whose mode or session is no longer current, or whose item the current catalog no longer holds
- **THEN** the selection, FIR and history are unchanged

### Requirement: Map shows scans in its one decision card
The Map rail SHALL show accepted scans only through its decision card, the same card Scanner shows. It SHALL have no separate latest-scan panel. Scanning SHALL keep working while Map is the open screen: a scan accepted then SHALL become the current selection and the latest accepted scan, exactly as on Scanner.

#### Scenario: No separate panel
- **WHEN** Map is open
- **THEN** no "Latest accepted scan" panel is shown, and the Active map picker and the decision card are shown

#### Scenario: Scan accepted with Map open
- **WHEN** Map is the open screen and a scan is accepted for item B
- **THEN** Map's decision card shows item B as an accepted scan, and the latest accepted scan is item B

#### Scenario: Scan fenced with Map open
- **WHEN** Map is the open screen and a scan is published as accepted after the mode changed
- **THEN** Map's decision card and the latest accepted scan are unchanged
