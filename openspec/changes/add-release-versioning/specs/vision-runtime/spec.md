# Spec Delta

## MODIFIED Requirements

### Requirement: Self-check report is complete and authoritative
The self-check report's `result` field SHALL be the authoritative outcome, and the exit code SHALL mirror it. The report SHALL be replaced in one step, so that it is either absent or whole. It SHALL include a format version, the application version, the runtime identity (file names, SHA-256 and versions), each step's result and duration, and any typed failure.

#### Scenario: Report contents
- **WHEN** a self-check run finishes
- **THEN** the report holds `format`, `appVersion`, `runtimeIdentity` with each vision file's SHA-256 and the engine and ABI versions, one entry per step with its result and duration, and `result` equal to `pass` exactly when the exit code is 0

#### Scenario: Report names the build
- **WHEN** the self-check runs from a bundle built with app version `0.2.0-beta.1+120`
- **THEN** the report's `appVersion` is `0.2.0-beta.1+120`

#### Scenario: Development build
- **WHEN** the self-check runs from a build made without an app version
- **THEN** the report's `appVersion` is `dev`

#### Scenario: Report never partially written
- **WHEN** the self-check is interrupted while writing its report
- **THEN** the report path holds either no file or a previous complete report, never a truncated one
