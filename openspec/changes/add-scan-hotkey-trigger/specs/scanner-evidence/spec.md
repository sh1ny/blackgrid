# Spec Delta

## ADDED Requirements

### Requirement: Scanner shows the scan hotkey and lets the user rebind it
Next to the live scan switch, Scanner SHALL show the scan hotkey's binding and state, as the pipeline publishes it, and a control offering Off and F1-F24. The control SHALL be enabled while live scan is `off` or `ready` and no rebind is in progress. An `unavailable` hotkey SHALL show its key and reason, and say that mouse scans still work. A refused or failed rebind SHALL show its error, and the control SHALL show the binding still in force.

#### Scenario: Registered hotkey
- **WHEN** live scan is `ready` and F9 is registered
- **THEN** Scanner shows that F9 scans at the cursor, and the control shows F9

#### Scenario: Hotkey held by another application
- **WHEN** live scan is `ready` and the hotkey state is `unavailable` with F9 and the OS reason
- **THEN** Scanner shows that F9 is unavailable with that reason and that mouse scans still work, and the control stays enabled

#### Scenario: Rebind refused
- **WHEN** the user picks F10 in the control and the rebind is refused because another application holds F10
- **THEN** Scanner shows an error naming F10, and the control shows F9

#### Scenario: Live scan off
- **WHEN** live scan is `off` and the binding is F9
- **THEN** Scanner shows that F9 is used while live scan is on, and the control is enabled

#### Scenario: Live scan starting
- **WHEN** live scan is `starting`
- **THEN** the control is disabled

## MODIFIED Requirements

### Requirement: Scanner shows stage timings and recent scans
Scanner SHALL show the latest scan's stage durations in milliseconds from its trigger, and its total. A stage not reached SHALL be shown as absent, not 0. Scanner SHALL list the 10 most recent published scans, newest first, with end state, item or reason, total time, and whether the hotkey started the scan.

#### Scenario: Timings of an accepted scan
- **WHEN** a scan is accepted with capture ending 40 ms and publication 180 ms after its trigger
- **THEN** Scanner shows 40 ms for the capture stage and 180 ms total

#### Scenario: Early failure
- **WHEN** a scan fails at targeted capture
- **THEN** the vision and matching stages are shown as absent

#### Scenario: Recent list bound
- **WHEN** an 11th scan is published
- **THEN** the list shows the 10 newest scans and the oldest is gone

#### Scenario: Hotkey scan in the list
- **WHEN** a scan started by the hotkey and a scan started by a mouse release are published
- **THEN** the hotkey scan's entry is labelled as a hotkey scan, and the mouse scan's entry carries no such label
