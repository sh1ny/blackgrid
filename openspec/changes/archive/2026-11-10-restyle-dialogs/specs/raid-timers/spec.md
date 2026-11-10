# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: Timer settings live in the Settings dialog`
- TO: `### Requirement: Timer settings live on the Settings page`

## MODIFIED Requirements

### Requirement: Timer settings live on the Settings page
A "Raid timers" section on the Settings page SHALL set: timers on or off (on by default), which of time in raid, run-through and scav cooldown show (all by default), the run-through length (m:ss) and the Fence reputation for the active mode (−7.00 to 6.00, two decimals, 0.00 by default). An invalid entry SHALL be refused with a message and SHALL keep the previous value.

#### Scenario: Valid run-through length
- **WHEN** the run-through length "8:00" is entered
- **THEN** the run-through length becomes 8:00

#### Scenario: Invalid run-through length
- **WHEN** "0:30", "31:00" or "abc" is entered as the run-through length
- **THEN** a message says the length must be between 1:00 and 30:00 and the previous length is kept

#### Scenario: Fence reputation out of range
- **WHEN** "7.5" is entered as the Fence reputation
- **THEN** a message says the reputation must be between −7.00 and 6.00 and the previous value is kept

#### Scenario: Reputation for the detected mode
- **WHEN** the mode chosen in Settings is unknown, the logs detect PvP, and "2.50" is entered as the Fence reputation
- **THEN** the PvP Fence reputation becomes 2.50

#### Scenario: No mode known
- **WHEN** the logs detect no mode and no mode is chosen in Settings
- **THEN** the Fence reputation field is disabled with a note to choose a mode first
