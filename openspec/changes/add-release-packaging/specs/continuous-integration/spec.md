# Spec Delta

## MODIFIED Requirements

### Requirement: CI runs the gates in order and stops at the first failure
The CI run SHALL run, in this order: static analysis (`mise run analyze`), the fast test suite (`mise run test`), the Release build with its offline bundle check (`mise run build:release`), the qualification tier against that build, and packaging of that build (`mise run package:release`). A failing step SHALL fail the run, and no later step SHALL run.

#### Scenario: All gates pass
- **WHEN** analysis, the fast tests, the Release build, the bundle check, the qualification tier and packaging all succeed
- **THEN** the run reports success

#### Scenario: Analysis fails
- **WHEN** `mise run analyze` reports an error or warning that fails it
- **THEN** the run fails at the analysis step, and the tests, the build, the qualification tier and packaging do not run

#### Scenario: The bundle check fails
- **WHEN** the Release build finishes but `bundle:check` reports a failing step
- **THEN** the run fails at the build step, and the qualification tier and packaging do not run

#### Scenario: Packaging fails
- **WHEN** the qualification tier passes but `mise run package:release` exits non-zero
- **THEN** the run fails at the packaging step
