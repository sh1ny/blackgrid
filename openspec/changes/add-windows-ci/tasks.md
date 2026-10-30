# Tasks

## Test map

Workflow behaviour that only GitHub can execute is mapped to the offline workflow test, which parses `.github/workflows/ci.yml` and asserts the property that produces the behaviour. The live runs on the PR are collected as evidence under **Workflow follow-up**.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| CI runs on every pull request and push to main | A pull request is opened | test/tool/ci/workflow_test.dart | triggers are pull_request and push to main only | green |
| CI runs on every pull request and push to main | A push to main | test/tool/ci/workflow_test.dart | triggers are pull_request and push to main only | green |
| CI runs on every pull request and push to main | Pushes to main in quick succession | test/tool/ci/workflow_test.dart | a push run has its own concurrency group keyed by github.sha and is never cancelled | green |
| CI runs on every pull request and push to main | A newer commit supersedes a running pull request run | test/tool/ci/workflow_test.dart | pull request runs share one group per PR and cancel in progress | green |
| CI uses the pinned toolchain | Tools match the pin | test/tool/ci/workflow_test.dart | tools come only from mise.toml and every gate runs through mise run | green |
| CI uses the pinned toolchain | The pinned tool cannot be installed | test/tool/ci/workflow_test.dart | the mise install step precedes every gate and has no fallback or continue-on-error | green |
| CI runs the gates in order and stops at the first failure | All gates pass | test/tool/ci/workflow_test.dart | gate steps run in order analyze, test, build:release, ci:qualification | green |
| CI runs the gates in order and stops at the first failure | Analysis fails | test/tool/ci/workflow_test.dart | no gate step has continue-on-error or an always()/failure() condition | green |
| CI runs the gates in order and stops at the first failure | The bundle check fails | test/tool/release/build_test.dart | bundle:check failure fails the build with its output | green |
| The CI Release build matches a release build | Build number from full history | test/tool/ci/workflow_test.dart | checkout uses full history and no persisted credentials | green |
| The CI Release build matches a release build | A gate left the tree dirty | test/tool/release/build_test.dart | dirty tree refuses before building naming files | green |
| Qualification runs against the CI-built bundle | Bundle-based tests run | test/tool/ci/qualification_audit_test.dart | a skipped bundle-based test fails the audit | green |
| Qualification runs against the CI-built bundle | The bundle is missing | test/tool/ci/qualification_runner_test.dart | a missing bundle directory exits 2 before flutter test runs | green |
| Qualification skips are audited against a committed allowlist | Only private-input tests skip | test/tool/ci/qualification_audit_test.dart | allowlisted private-input skips pass and are listed | green |
| Qualification skips are audited against a committed allowlist | An unlisted skip | test/tool/ci/qualification_audit_test.dart | an unlisted skip fails naming the file and reason | green |
| Qualification skips are audited against a committed allowlist | The report is missing or unreadable | test/tool/ci/qualification_audit_test.dart | a missing, malformed or unfinished report fails the audit | green |
| Qualification skips are audited against a committed allowlist | A test fails | test/tool/ci/qualification_runner_test.dart | a failing flutter test exits non-zero even when the audit passes | green |
| The no-games confirmation is scoped to the hosted runner | Native capture test runs on the hosted runner | test/tool/ci/workflow_test.dart | the qualification step alone sets the no-games confirmation and the bundle inputs | green |
| The no-games confirmation is scoped to the hosted runner | A game executable is listed | test/tool/ci/qualification_audit_test.dart | the capture guard's refused and unconfirmed reasons are not allowlisted | green |
| The no-games confirmation is scoped to the hosted runner | Another step or file sets the confirmation | test/tool/ci/workflow_test.dart | no other tracked script or config sets the no-games confirmation | green |
| CI holds least privilege and no secrets | Workflow permissions | test/tool/ci/workflow_test.dart | permissions are exactly contents read and no secrets are used | green |
| CI holds least privilege and no secrets | An action pinned by tag | test/tool/ci/workflow_test.dart | every uses line is pinned to a 40-hex commit SHA | green |
| Caches never decide correctness | Cold cache | test/tool/ci/workflow_test.dart | caches hold only the mise downloads and the vision inputs keyed by their pins, never build output | green |
| Caches never decide correctness | A corrupt cached input | test/tool/vision/fetch_runtime_test.dart | fetch skips a verified cached input and repairs a corrupt one | green |

## 1. ADR-0024 and the architecture index

- [x] 1.1 Write `docs/adr/0024-hosted-ci-runs-every-offline-gate.md` (MADR-short, `Status: accepted`, today's date) from design.md's ADRs section and D1-D6:
  - the hosted gate sequence;
  - the allowlist-only qualification skips;
  - `BLACKGRID_NO_GAMES_RUNNING=1` only in the hosted qualification step, never on a developer machine;
  - rejected: inferring the confirmation from CI environment variables;
  - reversal cost.

  State that it amends ADR-0009's "Local release tasks, no CI" bullet (review S4), without editing ADR-0009. Add the 0024 row to the in-force index in `openspec/architecture.md`, noting the amendment, and add one CI line to its build/release section. Verify: the file exists, the index row links to it, and `git diff docs/adr/0009-release-versioning.md` is empty.

## 2. Qualification runner and skip audit

- [x] 2.1 Read the `dart-add-unit-test`, `dart-use-pattern-matching` and `dart-write-documentation` skills. Then write failing tests in `test/tool/ci/qualification_audit_test.dart` for every audit row in the Test map. Use small synthetic JSON-reporter lines, with `suite` events carrying `path`, `testStart` with `metadata.skipReason`, `testDone` and `done`.
  - Accepted private-input skips: the three allowlist reasons, copied verbatim from `inspection_corpus_test.dart`, `targeted_region_replay_test.dart` and `m5_panel_ocr_test.dart`.
  - Unlisted skips, including a bundle-based test and the capture guard's "set BLACKGRID_NO_GAMES_RUNNING=1 ..." and "refused: ... is running" reasons from `native_guard.dart`.
  - The report problems: missing file, malformed line, no `done` event, zero unskipped tests.
  - Hidden `loading` tests are ignored.

  Verify: `mise exec -- flutter test test/tool/ci/qualification_audit_test.dart` fails because the audit does not exist yet.
- [x] 2.2 Implement the pure audit in `tool/ci/src/audit.dart`:
  - It takes report lines and an allowlist and returns a typed result with a sealed `AuditFinding`.
  - It matches files on `suite.path` made relative to the repo (review S1), not on the test `url`.
  - It matches the exact `skipReason`.

  Add `tool/ci/qualification_skips.yaml` with the three entries (`file`, `reason`, `why`), loaded with `package:yaml`. Document the public API with `///`. Verify: the 2.1 tests pass; flip their rows green.
- [x] 2.3 Write failing tests in `test/tool/ci/qualification_runner_test.dart` with a hand-written fake command runner, injected through a parameter as in `tool/release/src/git.dart`'s `CommandRunner`:
  - A missing or non-directory `BLACKGRID_RELEASE_BUNDLE` exits 2 and never invokes `flutter`.
  - `flutter test --tags qualification --file-reporter json:<path>` is invoked with the report path in a fresh system-temp directory outside the repository.
  - A non-zero test exit gives a non-zero tool exit, even with a clean audit.
  - An audit finding gives a non-zero exit with a zero test exit.
  - Both results are printed.

  Verify: the tests fail before 2.4.
- [x] 2.4 Implement `tool/ci/qualification.dart`, a thin `main` over an injectable `runQualification`, and add the mise task `ci:qualification` (description: CI-only qualification gate; fails locally by design unless the user confirms no game is running). Verify: the 2.3 tests pass, rows flipped green; `mise run analyze` is clean; `dart format` leaves the files unchanged.

## 3. CI workflow, offline workflow test and docs

- [x] 3.1 Write failing tests in `test/tool/ci/workflow_test.dart` for every workflow row in the Test map:
  - Parse `.github/workflows/ci.yml` with `package:yaml` and assert the properties named in D1-D6:
    - the triggers;
    - the PR concurrency group and cancellation;
    - a push group containing `github.sha`;
    - `windows-2025`, `timeout-minutes: 120`;
    - checkout `fetch-depth: 0` and `persist-credentials: false`;
    - mise-action with no version or tool overrides;
    - gate order and no `continue-on-error` or `always()`/`failure()` conditions on gates;
    - `permissions` exactly `{contents: read}` with no job-level widening;
    - no `secrets.` references;
    - every `uses:` pinned to `@[0-9a-f]{40}`;
    - caches only on mise and `.dart_tool/blackgrid_vision_inputs`, keyed on `third_party.lock.json`;
    - `BLACKGRID_NO_GAMES_RUNNING: "1"` only in the `ci:qualification` step's `env`, next to `BLACKGRID_RELEASE_BUNDLE`, `BLACKGRID_PANEL_OCR_RUNTIME` and `BLACKGRID_CMAKE`.
  - Scan the tracked files (`git ls-files`) for setters of `BLACKGRID_NO_GAMES_RUNNING` other than that step:
    - `mise.toml` `[env]`/task `env` keys;
    - `$env:` assignments in `*.ps1`;
    - `set` in `*.cmd`/`*.bat`;
    - `export` in `*.sh`;
    - YAML `env:` keys.

    Comments, descriptions and Markdown are ignored.

  Verify: the tests fail because the workflow is absent.
- [x] 3.2 Write `.github/workflows/ci.yml` per D1-D6:
  - Steps: checkout; `actions/cache/restore` for the vision inputs; `jdx/mise-action` (with its cache); `mise run analyze`; `mise run test`; `mise run build:release`; `actions/cache/save` for the vision inputs right after `build:release`, so a red qualification step does not lose the cache (review S2); a qualification step that resolves `BLACKGRID_CMAKE` from `(Get-Command cmake).Source` and runs `mise run ci:qualification` with the step-level `env` from 3.1.
  - Pin each action to its current major tag's commit SHA, looked up with `git ls-remote` and kept as a trailing `# vX` comment.
  - Add `mise trust` only if the first PR run shows it is needed (design Open Questions).

  Verify: the 3.1 tests pass, rows flipped green; `mise run analyze`, `mise run test` and `dart format` are clean.
- [x] 3.3 Add the docs (D7):
  - **README** gets a "Continuous integration" section:
    - what runs on every PR and push to `main`, and its order;
    - the runner image, with a link to its software list;
    - the three allowlisted local-only qualification tests and why;
    - `mise run ci:qualification` is CI-only and fails locally by design unless the user confirms that no game is running; developers use `mise run test:qualification`;
    - branch protection is the owner's GitHub setting.
  - **README task table:** a `ci:qualification` row.
  - **AGENTS.md:** one line under the Escape from Tarkov testing boundary: the CI workflow's `BLACKGRID_NO_GAMES_RUNNING=1` applies only to GitHub-hosted runners, and agents never set it on a developer machine, including to make a local `ci:qualification` run pass.

  Verify: both files render; `git grep -n "ci:qualification" README.md AGENTS.md` shows the new lines.

## 4. Integration check

- [x] 4.1 Run the full offline loop, `mise run analyze` and `mise run test`. Confirm with `mise run test -- --reporter expanded` output (or the file list) that the new `test/tool/ci/` tests run in the fast loop and are not tagged `qualification`. Confirm every Test map row reads green. Do not run `ci:qualification` or set `BLACKGRID_NO_GAMES_RUNNING` locally (AGENTS.md; design D3).

## Workflow follow-up

- After ship, the PR's first CI run is the live evidence for M6 exit criterion 1. Record from its log:
  - the install step's Flutter version equals `mise.toml`;
  - each gate step's duration, including the OpenCV build (D6 evidence);
  - the audit's accepted skips, exactly the three allowlisted tests;
  - the native capture and panel OCR tests ran unskipped.
- If the capture test or the panel OCR test fails on the hosted image (design Risks; review S3), stop and ask the user. The agent never adds an allowlist entry for it or changes the no-games scope on its own.
- A red run visible on the PR is shown by any failing CI run during the PR's life. At milestone close, if none occurred, the exit-criterion check uses the failure-path tests above plus the GitHub check conclusion on a run.
- Making the CI check required on `main` is the owner's GitHub setting, offered at ship time, never changed by the agent.
