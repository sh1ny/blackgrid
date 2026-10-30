# 0024 - Hosted CI runs every offline gate

- Status: accepted
- Date: 2026-10-30 (M6 change `add-windows-ci`)
- Amends: [0009](0009-release-versioning.md), the "Local release tasks, no CI" bullet only: the release tasks stay local, and CI now exists
- Source: [design](../../openspec/changes/add-windows-ci/design.md) D1-D7

## Context and problem

Every gate Blackgrid has ran only on the developer's machine. `pr.validate` runs `mise run analyze && mise run test` before a push, but the Release build, `bundle:check` and the qualification tier ran only when someone remembered to start them. A PR could merge with a broken Release build or a red qualification test, and nobody would see it. The qualification tier takes its inputs from environment variables, and a test without its input skips, which exits 0. A hosted run that only called `flutter test --tags qualification` would be green while running almost none of the tier. The native capture test also needs `BLACKGRID_NO_GAMES_RUNNING=1`, a human confirmation that AGENTS.md forbids agents to give on a developer machine.

## Decision

- **One sequential job on a pinned hosted image (D1, D2).** `.github/workflows/ci.yml` runs one job on `windows-2025` with a 120-minute timeout, on every `pull_request` and every push to `main`. Its steps, in order: checkout with full history and no persisted credentials, restore the vision input cache, install the `mise.toml` tools through `jdx/mise-action`, then `mise run analyze`, `mise run test`, `mise run build:release` (unchanged, so the build number is the real commit count and `bundle:check` runs), save the vision input cache, and `mise run ci:qualification` against the bundle just built. The first failing step fails the run, and no later step runs.
- **Qualification skips only by allowlist (D3).** `tool/ci/qualification.dart` (`mise run ci:qualification`) refuses a missing bundle directory (exit 2), runs `flutter test --tags qualification` with a JSON report in a fresh system-temp directory, and audits that report against `tool/ci/qualification_skips.yaml`. The allowlist names only tests that need private, uncommitted inputs (the inspection corpus, the targeted-region replay and a supplied panel image), each by repo-relative file and exact skip reason. An unlisted skip, a missing or malformed report, a report with no `done` event or no test that ran unskipped fails the gate. A test failure fails it whatever the audit says. The task is CI-only: locally it fails by design, because the capture test's "not confirmed" skip is not on the allowlist. Developers use `mise run test:qualification`.
- **The no-games confirmation is the hosted qualification step's alone (D4).** Only that step's `env:` sets `BLACKGRID_NO_GAMES_RUNNING: "1"`, next to `BLACKGRID_RELEASE_BUNDLE`, `BLACKGRID_PANEL_OCR_RUNTIME` and `BLACKGRID_CMAKE`. The capture guard's `tasklist` refusal stays: a refusal is an unlisted skip and fails the run. No other tracked file sets the variable, and no agent ever sets it on a developer machine, including to make a local `ci:qualification` run pass. An offline test (`test/tool/ci/workflow_test.dart`) enforces the step scope and scans tracked scripts and config for other setters.
- **Least privilege (D5).** Top-level `permissions: contents: read` with no job-level widening, no secrets, never `pull_request_target`. Every `uses:` is pinned to a 40-hex commit SHA with its tag in a trailing comment. PR runs share one concurrency group per PR and cancel in progress. Each push to `main` has its own group keyed by `github.sha`, so no `main` run is cancelled or replaced.
- **Caches never decide correctness (D6).** Only mise's tool downloads and `.dart_tool/blackgrid_vision_inputs` (keyed on `windows/vision/third_party.lock.json`) are cached, and both are re-verified on use. The build tree is not cached, so each run compiles OpenCV.
- **This binds later workflows,** including the tag-triggered publishing in `publish-github-releases`.

## Rejected alternatives

- **Inferring the confirmation from CI environment variables** (for example trusting `GITHUB_ACTIONS=true` in `native_guard.dart`): any local shell can set them, which would turn an explicit human confirmation into an inferable one and widen the rule beyond the hosted runner.
- **Parallel jobs passing the bundle as an artifact:** loses stop-at-first-failure order, moves a large bundle between runners and doubles toolchain setup.
- **`windows-latest`:** the label moves without a commit, so toolchain drift would appear as an unexplained red run.
- **CI-specific build commands:** they would drift from the `build:release` flow, and a shallow clone gives build number 1.
- **Shell glue over the JSON report, or making tests fail when inputs are missing:** the first cannot be unit-tested and a parse slip would pass quietly; the second breaks the offline developer loop, where skipping is intended.
- **Caching the build tree:** a stale tree could hide a CMake regression and is not verified on restore.

## Consequences

- A PR shows a CI check; making it required on `main` is the owner's GitHub setting.
- The native capture and panel OCR tests run on a hosted Server image for the first time. If either cannot run there, it fails visibly; any allowlist entry or change to the no-games scope is the user's decision.
- Every run compiles OpenCV; the first runs' step times are the evidence for a later build cache.
- **Reversal cost:** low. Removing or splitting the workflow edits only `.github/workflows/ci.yml` and `tool/ci/`. Because the no-games scope is a safety policy, widening it needs a new ADR.
