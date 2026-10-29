# Spec Delta

## MODIFIED Requirements

### Requirement: Selecting a known mode with a saved credential starts one progress refresh
After the app selects a known mode, at launch or by switching, and reads a saved tracker credential for it while the read-only Tracker integration is enabled, the app SHALL start one progress refresh without user action and without delaying startup or the mode switch. With no saved credential, an unreadable one, the Tracker integration disabled or `unknown` mode, it SHALL make no tracker request. A selection superseded before its credential read ends SHALL start no refresh.

#### Scenario: Launch with a saved credential
- **WHEN** the app launches into a known mode with a saved credential, and the tracker returns valid progress
- **THEN** startup completes before the fetch returns, exactly one tracker fetch is made for that mode, and the progress status then becomes `current`

#### Scenario: No saved credential
- **WHEN** the selected known mode has no saved credential
- **THEN** no tracker request is made and the progress status is `missing`

#### Scenario: Unreadable credential
- **WHEN** reading the saved credential for the selected mode fails
- **THEN** no tracker request is made and the progress status is `failed` with "Tracker token unavailable"

#### Scenario: Tracker integration disabled
- **WHEN** the selected known mode has a saved credential and the read-only Tracker integration is disabled
- **THEN** no tracker request is made

#### Scenario: Unknown mode makes no request
- **WHEN** the selected mode is `unknown`
- **THEN** no tracker request is made

#### Scenario: Selection superseded during the credential read
- **WHEN** the user switches from mode A to mode B before A's credential read has ended, and both modes have saved credentials
- **THEN** no tracker fetch is made for A, and exactly one is made for B

#### Scenario: Saving a credential does not refresh
- **WHEN** the user saves a valid credential for the selected mode, or enables the Tracker integration
- **THEN** no tracker request is made until the user refreshes or selects a mode
