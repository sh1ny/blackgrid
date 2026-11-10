# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: The decision card can return to the latest scan`
- TO: `### Requirement: The answer strip can return to the latest scan`

- FROM: `### Requirement: Map shows scans in its one decision card`
- TO: `### Requirement: Map shows scans in its one answer strip`

## MODIFIED Requirements

### Requirement: The answer strip can return to the latest scan
When there is a latest accepted scan that the answer strip is not showing as its accepted scan, the strip SHALL offer a "Back to latest scan" action, on Map and on Scanner. The action SHALL make that scan the current selection again, shown as an accepted scan whose provenance line gives the age of its original acceptance time. It SHALL record no history, SHALL NOT change the latest accepted scan, SHALL close an open history view, and SHALL reset FIR to unknown.

#### Scenario: Return after a manual selection
- **WHEN** a scan was accepted for item B, the user selects item A by hand and then uses Back to latest scan
- **THEN** the strip shows item B as an accepted scan, its provenance line giving the age of the original acceptance time, and history has no new entry

#### Scenario: Return closes history
- **WHEN** a scan was accepted for item B and the user has a history row for item C open
- **THEN** the strip offers Back to latest scan, and using it closes the history view and shows item B in the live mode

#### Scenario: Return resets FIR
- **WHEN** a scan was accepted for item B, the user selects item A by hand, sets FIR to yes and then uses Back to latest scan
- **THEN** FIR is unknown and the decision for item B is computed with FIR unknown

#### Scenario: No action while the latest scan is shown
- **WHEN** the strip shows the latest accepted scan
- **THEN** the strip offers no Back to latest scan action

#### Scenario: No action without a latest scan
- **WHEN** no scan has been accepted this session, or the last one was cleared by a mode or session change
- **THEN** the strip offers no Back to latest scan action

#### Scenario: Stale return is refused
- **WHEN** the action is used for a latest scan whose mode or session is no longer current, or whose item the current catalog no longer holds
- **THEN** the selection, FIR and history are unchanged

### Requirement: Map shows scans in its one answer strip
Map SHALL show accepted scans only through the shared answer strip, the same strip Scanner shows. It SHALL have no separate latest-scan panel. Scanning SHALL keep working while Map is the open screen: a scan accepted then SHALL become the current selection and the latest accepted scan, exactly as on Scanner.

#### Scenario: No separate panel
- **WHEN** Map is open
- **THEN** no "Latest accepted scan" panel is shown, and the map picker and the answer strip are shown

#### Scenario: Scan accepted with Map open
- **WHEN** Map is the open screen and a scan is accepted for item B
- **THEN** the answer strip shows item B as an accepted scan, and the latest accepted scan is item B

#### Scenario: Scan fenced with Map open
- **WHEN** Map is the open screen and a scan is published as accepted after the mode changed
- **THEN** the answer strip and the latest accepted scan are unchanged
