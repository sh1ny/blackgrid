# Spec Delta

## ADDED Requirements

### Requirement: Recordings stay local and carry no credentials or progress
Recorded files SHALL be written only to the session folder on this machine, and SHALL NOT be uploaded or sent anywhere. Case lines SHALL hold no credentials or progress data. The scan timing log SHALL stay pixel-free and keep schema v1.

#### Scenario: Recording with local progress recorded
- **WHEN** a scan is recorded while the effective mode's local progress records finished tasks and a player level
- **THEN** no case line in the session folder holds a task state, objective count, station level or player level

#### Scenario: Timing log while recording
- **WHEN** a recorded scan is logged
- **THEN** its `scan-timings.jsonl` line has the same keys as an unrecorded scan's line and holds no pixel bytes

## REMOVED Requirements

### Requirement: Recordings stay local and carry no credentials
**Reason**: Replaced by "Recordings stay local and carry no credentials or progress"; the Tracker token it guarded no longer exists.
**Migration**: None; the same local-only and timing-log rules carry over.
