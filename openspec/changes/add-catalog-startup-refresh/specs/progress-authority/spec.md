# Spec Delta

## Purpose

Decides when tracker progress for a mode is fetched without user action and which fetch results may be published, so that decisions do not stay degraded by missing progress while a credential is saved.

Unless a scenario says otherwise, the scenarios in this capability assume the read-only Tracker integration is enabled.

## ADDED Requirements

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
- **THEN** no tracker request is made and the progress status is `failed` with "Protected credential unavailable"

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

### Requirement: A failed automatic progress refresh is not retried
A failed automatic progress refresh SHALL NOT be retried automatically. The next tracker fetch for that mode SHALL happen only on a manual refresh or a later selection of a mode, and a manual refresh during a cooldown SHALL make no request.

#### Scenario: Tracker unavailable at launch
- **WHEN** the automatic progress fetch fails because the tracker cannot be reached
- **THEN** the progress status is `failed` with "Tracker transport unavailable", and no further fetch is made until the user refreshes or selects a mode

#### Scenario: Tracker answers with a cooldown
- **WHEN** the automatic progress fetch is answered with a cooldown until time C
- **THEN** the progress status is `cooldown`, no further fetch is made, and a manual refresh before C makes no request

#### Scenario: Rejected credential
- **WHEN** the automatic progress fetch fails because the tracker rejects the credential
- **THEN** the progress status is `failed`, no progress snapshot is published, and no further fetch is made until the user refreshes or selects a mode

### Requirement: An automatic progress refresh never publishes into another selection
A progress refresh started for one mode selection SHALL NOT publish its result, success or failure, after a different mode is selected, even when the user later switches back to the first mode.

#### Scenario: Switch during the automatic refresh
- **WHEN** the automatic progress refresh for mode A is in flight, the user switches to mode B, and A's fetch then succeeds
- **THEN** B's progress snapshot and status are not replaced by A's result

#### Scenario: Switch back before the old fetch returns
- **WHEN** the automatic progress refresh for mode A is in flight, the user switches to B and back to A, and the first A fetch then returns
- **THEN** the first fetch's result is not published, and A's progress is published only from the fetch started by the latest selection of A
