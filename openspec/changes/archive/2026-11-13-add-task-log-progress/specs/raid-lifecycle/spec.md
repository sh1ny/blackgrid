# Spec Delta

## ADDED Requirements

### Requirement: Each task message is published once with its mode
Each task-started, task-failed and task-finished event read from the push-notifications log SHALL be published once as a task transition, carrying its record identity and time, the task ID, its state (started, failed or finished) and the last session mode logged before it in the same folder: no mode when that folder logged none or the last one is not recognised. It SHALL NOT change the raid phase or any raid, and a re-read SHALL publish it with the same identity.

#### Scenario: Task finished in the menus
- **WHEN** session mode PvP is logged, then a task-finished event for task `5936d90786f7742b1420ba5b` is applied while the phase is in menus
- **THEN** one task transition is published with that record's identity and time, that task ID, finished and mode PvP, and the phase is in menus

#### Scenario: Task message before any mode is logged
- **WHEN** a task-failed event is applied before any session mode was logged in the folder
- **THEN** the task transition is published with no mode

#### Scenario: Mode from an earlier folder is not carried
- **WHEN** session mode PvP was logged in one folder, a newer folder starts, and a task-started event is applied before that folder logs a session mode
- **THEN** the task transition is published with no mode

#### Scenario: Unrecognised mode
- **WHEN** a session mode Blackgrid does not recognise is logged, then a task-finished event is applied
- **THEN** the task transition is published with no mode

#### Scenario: Replay after an app restart
- **WHEN** the same session folder is read again from the start after Blackgrid restarts
- **THEN** each task message is published again with the same record identity, task ID and state as before

#### Scenario: Push records recover after a mode change
- **WHEN** one scan reads PvP at 10:00 and PvE at 10:02, then a later scan recovers a task message logged at 10:01 in the same folder
- **THEN** the task transition carries PvP, matching a one-shot read of that folder rather than the latest delivered mode
