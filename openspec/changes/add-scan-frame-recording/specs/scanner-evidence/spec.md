# Spec Delta

## ADDED Requirements

### Requirement: Scanner shows the record switch and its status
Scanner SHALL show a "Record scan frames" switch next to the live scan switch, enabled only while live scan is `ready`. While a session exists it SHALL show:
- the number of scans written;
- the number dropped;
- the session folder path.

When recording turns itself off, Scanner SHALL say why: cap reached, or the write error.

#### Scenario: Recording runs
- **WHEN** recording is on and 12 scans were written and 1 dropped
- **THEN** Scanner shows 12 written, 1 dropped and the session folder path

#### Scenario: Live scan not ready
- **WHEN** live scan is `off`, `starting` or `unavailable`
- **THEN** the record switch shows off and cannot be turned on

#### Scenario: Write failure
- **WHEN** recording turned itself off because a write failed
- **THEN** the switch shows off and Scanner shows the error and the folder path
