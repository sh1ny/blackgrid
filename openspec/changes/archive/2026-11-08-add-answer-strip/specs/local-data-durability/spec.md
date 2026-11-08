# History verdict durability

## ADDED Requirements

### Requirement: History retains the recorded verdict
Each newly recorded manual, accepted-scan or correction activity SHALL store the verdict displayed at recording time, when available, atomically with its existing identity, mode, source, time and revision. Re-observing the same item and mode SHALL replace the activity as today. FIR edits, refresh, age ticks and viewing history SHALL NOT rewrite its recorded verdict.

#### Scenario: Each source records its verdict
- **WHEN** a manual selection, accepted scan or correction records an activity with a known displayed verdict
- **THEN** the activity reads back with that verdict and its matching item, mode, source, time and revision

#### Scenario: Later data changes
- **WHEN** the current advice changes after a recorded activity, including through a FIR edit or refresh
- **THEN** the activity's recorded verdict stays unchanged until that item and mode is explicitly recorded again

#### Scenario: No available decision or failed write
- **WHEN** an activity has no displayed decision, or its database write fails
- **THEN** the successful activity has no recorded verdict, or the previous stored row is unchanged and the existing recording error is visible, respectively

### Requirement: Missing history verdicts remain readable
Upgrade SHALL preserve existing activity without inventing verdicts. Missing or unrecognised optional verdict values SHALL load as unknown without losing an otherwise readable row. Old imports SHALL remain supported; a history import carrying a supported recorded verdict SHALL retain it under existing merge and replace rules.

#### Scenario: Upgrade and reopen
- **WHEN** a pre-change database with settings, pins and activity is upgraded and reopened
- **THEN** all existing user records are retained and its legacy activities have unknown recorded verdicts

#### Scenario: Import and round trip
- **WHEN** valid history entries with and without verdicts are imported, saved and reopened
- **THEN** known verdicts are retained, missing verdicts stay unknown, and existing import precedence rules are unchanged

#### Scenario: Unrecognised optional value
- **WHEN** an otherwise readable activity has an unrecognised verdict value
- **THEN** the row remains readable with an unknown indicator and loading does not rewrite its stored bytes
