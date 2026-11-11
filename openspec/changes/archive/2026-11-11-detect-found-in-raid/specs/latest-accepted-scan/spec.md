# Spec Delta

## MODIFIED Requirements

### Requirement: The answer strip can return to the latest scan
When a latest accepted scan exists but is not the strip's current accepted scan, Map and Scanner SHALL offer "Back to latest scan". It SHALL restore that scan with its original acceptance age and detected FIR, discard any manual override, close history, record no activity and leave the latest-scan record unchanged. A stale mode/session or missing catalog item SHALL refuse the return without changing selection, FIR or history.

#### Scenario: Return after a manual selection
- **WHEN** a scan was accepted for item B, the user selects item A by hand and then uses Back to latest scan
- **THEN** the strip shows item B as an accepted scan, its provenance line giving the age of the original acceptance time, and history has no new entry

#### Scenario: Return closes history
- **WHEN** a scan was accepted for item B and the user has a history row for item C open
- **THEN** the strip offers Back to latest scan, and using it closes the history view and shows item B in the live mode

#### Scenario: Return resets FIR
- **WHEN** B's scan detected No, the player overrides it to Yes, selects A and then uses Back to latest scan
- **THEN** FIR is No from B's original scan, the old override is gone and B's decision is recomputed with No

#### Scenario: Return restores unknown evidence
- **WHEN** the latest scan had unreadable FIR and the player leaves it, sets another selection's FIR to Yes and returns
- **THEN** the restored scan has FIR Unknown with its original unreadable reason, not the other selection's Yes

#### Scenario: No action while the latest scan is shown
- **WHEN** the strip shows the latest accepted scan
- **THEN** the strip offers no Back to latest scan action

#### Scenario: No action without a latest scan
- **WHEN** no scan has been accepted this session, or the last one was cleared by a mode or session change
- **THEN** the strip offers no Back to latest scan action

#### Scenario: Stale return is refused
- **WHEN** the action is used for a latest scan whose mode or session is no longer current, or whose item the current catalog no longer holds
- **THEN** the selection, FIR and history are unchanged
