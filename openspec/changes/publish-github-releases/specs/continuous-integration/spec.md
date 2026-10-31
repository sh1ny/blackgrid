# Spec Delta

## MODIFIED Requirements

### Requirement: The no-games confirmation is scoped to the hosted runner
The confirmation that no game is running (`BLACKGRID_NO_GAMES_RUNNING=1`) SHALL be set only by the shared gates workflow that the CI and release workflows both call, only for its qualification step, and only on a GitHub-hosted runner. The capture guard's own refusal of a listed game executable SHALL still apply on CI. No other repository file SHALL set the confirmation.

#### Scenario: Native capture test runs on the hosted runner
- **WHEN** the qualification step runs on a GitHub-hosted Windows runner, for CI or for a release
- **THEN** the native capture qualification test runs and is not reported as skipped

#### Scenario: A game executable is listed
- **WHEN** the process listing on the runner contains a known game executable
- **THEN** the capture test skips with its "refused" reason, which is not on the allowlist, so the audit fails the run

#### Scenario: Another step or file sets the confirmation
- **WHEN** a repository file other than the shared gates workflow, including the CI or release workflow, or a step of the gates workflow other than the qualification step, sets `BLACKGRID_NO_GAMES_RUNNING`
- **THEN** an offline test fails and names the file

### Requirement: CI holds least privilege and no secrets
The CI workflow and the shared gates workflow SHALL request read-only repository contents and no other token permission. They SHALL use no repository secrets. Every workflow in the repository SHALL pin each third-party action to a full commit SHA.

#### Scenario: Workflow permissions
- **WHEN** the CI workflow and the shared gates workflow are read
- **THEN** each one's top-level `permissions` are exactly `contents: read`, and no job in either widens them

#### Scenario: An action pinned by tag
- **WHEN** a `uses:` line in any workflow references an action by tag or branch instead of a 40-character commit SHA
- **THEN** an offline test fails and names the file and the line
