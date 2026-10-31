# continuous-integration Specification

## Purpose
A hosted continuous-integration run checks every pull request and every push to `main` with the project's offline gates, a Release build and the qualification tier, so no gate runs only on the developer's machine and a failure is visible on the pull request.

## Requirements

### Requirement: CI runs on every pull request and push to main
The repository SHALL run its CI workflow on a GitHub-hosted Windows runner for every pull request event that opens, reopens or updates a pull request, and for every push to `main`. The run's result SHALL be reported as a check on the commit, so a pull request shows a pass or a failure.

#### Scenario: A pull request is opened
- **WHEN** a pull request against `main` is opened or a new commit is pushed to its branch
- **THEN** a CI run starts for that head commit on a GitHub-hosted Windows runner, and its check appears on the pull request

#### Scenario: A push to main
- **WHEN** a commit lands on `main`, by a merge or a direct push
- **THEN** a CI run starts for that commit, and its result is shown on the commit

#### Scenario: Pushes to main in quick succession
- **WHEN** commits `A`, `B` and `C` land on `main` while `A`'s run is still running
- **THEN** runs for `A`, `B` and `C` each complete and report a result, and none of them is cancelled or replaced by a later push

#### Scenario: A newer commit supersedes a running pull request run
- **WHEN** a commit is pushed to a pull request branch while an earlier run for the same pull request is still running
- **THEN** the earlier run is cancelled and only the newest head's run reports a result on the pull request

### Requirement: CI uses the pinned toolchain
The CI run SHALL install its tools from the versions committed in `mise.toml` and SHALL run every gate through the same `mise` tasks a developer runs. It SHALL NOT use a Flutter version that differs from the pinned one.

#### Scenario: Tools match the pin
- **WHEN** a CI run installs its tools
- **THEN** `flutter --version` in the run reports the version pinned in `mise.toml`

#### Scenario: The pinned tool cannot be installed
- **WHEN** the pinned Flutter or another pinned tool cannot be downloaded or fails its checksum
- **THEN** the run fails at the install step, and no gate runs on another version

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

### Requirement: The CI Release build matches a release build
The CI Release build SHALL be made from a full-history checkout, so its build number is the commit count of the built commit, as ADR-0009 requires. It SHALL refuse to build from a working tree with changes, as a local release build does.

#### Scenario: Build number from full history
- **WHEN** CI builds commit `C`
- **THEN** the bundle's executable carries build number `git rev-list --count C`, computed on the full history

#### Scenario: A gate left the tree dirty
- **WHEN** an earlier step leaves a tracked or untracked file changed in the checkout
- **THEN** the build step refuses with the existing "working tree is not clean" error and the run fails

### Requirement: Qualification runs against the CI-built bundle
The qualification tier SHALL run against the bundle that the run built and checked. Every qualification test whose only missing input is a built bundle, the panel OCR runtime in that bundle, or a CMake executable SHALL receive that input, so that it runs and does not skip.

#### Scenario: Bundle-based tests run
- **WHEN** the qualification tier runs on CI
- **THEN** the bundle integrity, vision runtime, vision worker, vision peaks, vision self-check, inspection recognition, panel OCR and vision CMake tests run against the CI build, and none of them is reported as skipped except a test with an allowlisted host-platform skip

#### Scenario: The bundle is missing
- **WHEN** the qualification step starts and the bundle directory it was given does not exist
- **THEN** the step fails, and the tests that need the bundle are not reported as skipped

### Requirement: Qualification skips are audited against a committed allowlist
The CI run SHALL fail when a qualification test is skipped for a reason that a committed allowlist does not list. The allowlist SHALL list only two kinds of skip:
- a test that needs private, uncommitted inputs;
- a host-platform skip: a test that skips because of a host setting that a GitHub-hosted runner cannot provide, such as a UTF-8 system code page. It is allowed only when a qualification test that runs on CI covers the same behaviour, and the entry's `why` names that covering test.

Each entry SHALL name the test file and the skip reason it accepts. A skip caused by a missing environment variable or by the capture guard is never a host-platform skip.

#### Scenario: Only allowlisted tests skip
- **WHEN** the qualification tier finishes and the only skipped tests are the inspection corpus test, the targeted-region replay test, the supplied-panel-image test and the in-process Cyrillic-path vision runtime test (on a non-UTF-8 code page), each with its listed reason
- **THEN** the audit passes and lists each accepted skip in the run log

#### Scenario: A host-platform skip is covered on CI
- **WHEN** the allowlist accepts the in-process Cyrillic-path vision runtime test's non-UTF-8 code page skip
- **THEN** its entry names the vision self-check test that opens the bundle under a Cyrillic path through `blackgrid.exe`, and that test runs on CI and is not reported as skipped

#### Scenario: An unlisted skip
- **WHEN** a qualification test skips with a reason not on the allowlist, for example because an environment variable was not set
- **THEN** the audit fails the run and names the test and its skip reason

#### Scenario: The report is missing or unreadable
- **WHEN** the qualification run produced no machine-readable report, or the report cannot be parsed
- **THEN** the audit fails the run, and a missing report never counts as zero skips

#### Scenario: A test fails
- **WHEN** any qualification test fails
- **THEN** the run fails, whatever the audit reports

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

### Requirement: Caches never decide correctness
CI MAY restore cached tool downloads and verified vision inputs. A restored cache SHALL be re-verified by the same checks a cold run uses, and a missing, stale or corrupt cache SHALL only make the run slower, never pass a check that a cold run would fail.

#### Scenario: Cold cache
- **WHEN** no cache exists for the current `mise.toml` or vision lock file
- **THEN** the run downloads every input, verifies it and produces the same result as a warm run

#### Scenario: A corrupt cached input
- **WHEN** a restored vision input's bytes no longer match the lock file
- **THEN** the fetch step re-downloads it or fails, and the build never uses the mismatching bytes
