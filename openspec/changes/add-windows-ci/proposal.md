# Proposal

## Why

Every gate Blackgrid has runs only on the developer's machine. `pr.validate` runs `mise run analyze && mise run test` before a push. The Release build, `bundle:check` and the qualification tier run only when someone remembers to start them, so a PR can merge with a broken Release build or a red qualification test and nobody sees it. This change serves **M6 - Windows CI and releases**, exit criterion 1: every PR and every push to `main` runs `mise run analyze`, `mise run test`, a Release build, `bundle:check` and `mise run test:qualification` against that build on a GitHub-hosted Windows runner, and a red run is visible on the PR. It is the first M6 change. The tag-triggered publishing in `publish-github-releases` reuses the CI build steps.

## What Changes

- Add a GitHub Actions workflow, `.github/workflows/ci.yml`, on a GitHub-hosted Windows runner, triggered by every pull request and every push to `main`. It installs the pinned toolchain from `mise.toml` and runs, in order: `mise run analyze`, `mise run test`, `mise run build:release` (the existing `vision:fetch`, versioned `flutter build windows --release` and `bundle:check` flow from ADR-0009), then `mise run test:qualification` against the built bundle.
- The qualification step points the bundle-based tests at that build (`BLACKGRID_RELEASE_BUNDLE`, `BLACKGRID_PANEL_OCR_RUNTIME`) and gives the CMake test a `cmake.exe` (`BLACKGRID_CMAKE`). Without these variables those tests skip, and CI would pass without running them.
- The qualification step, and only that step, sets `BLACKGRID_NO_GAMES_RUNNING=1`, so the native capture test runs on the ephemeral runner. This is the user's decision (2026-10-30). The guard's `tasklist` refusal of the game executables stays. Agents still never set the variable on the user's machine.
- Add a skip audit: the qualification run writes a machine-readable report, and a new offline tool fails the job when any qualification test skips for a reason that is not on a committed allowlist. The allowlist holds only the tests that need private, uncommitted inputs: the inspection corpus, the targeted-region replay and a supplied panel image. These stay local-only by the user's decision (2026-10-30). One host-platform skip is allowlisted as well, by the user's decision after the pre-ship review (2026-10-30). The in-process Cyrillic-path vision runtime test needs a UTF-8 system code page, which a hosted runner does not have. The `blackgrid.exe` self-check under a Cyrillic path covers the same behaviour on CI.
- Cache the verified vision inputs and mise's tool downloads so repeat runs do not download them again. The cache key is the lock file or `mise.toml`. Correctness never depends on the cache: `vision:fetch` re-verifies every cached input.
- Least-privilege workflow: `contents: read` only, no secrets, and superseded runs on the same PR are cancelled.
- README gains a CI section: what runs, which qualification tests skip on CI and why, and how to reproduce a CI step locally.

## Capabilities

### New Capabilities
- `continuous-integration`: what the hosted CI run must check on every PR and push to `main`, in what order, against which build, and how it fails. This covers the qualification run against the built bundle, the skip allowlist audit and the safety scope of the no-games confirmation.

### Modified Capabilities
None. The release build, `bundle:check` and qualification tests keep their current requirements. CI calls them unchanged.

## Impact

- **New files:** `.github/workflows/ci.yml`, the skip-audit tool under `tool/ci/` with its offline tests under `test/tool/ci/`, and the committed skip allowlist.
- **`mise.toml`:** one CI-only task, `ci:qualification`, that runs the qualification tier with a JSON report and audits its skips. Run locally, it fails by design unless the user confirms that no game is running. Developers keep `mise run test:qualification`.
- **README:** a CI section.
- **AGENTS.md:** one line saying the CI-only confirmation never applies to a developer machine. An agent never sets it, including to make `ci:qualification` pass.
- **Branch protection on `main`:** making the CI check required is a GitHub setting that the user sets. The workflow only makes the run and its result visible on the PR.
- **External dependencies:** `actions/checkout`, `jdx/mise-action` and `actions/cache`, pinned by commit SHA. The runner downloads Flutter, the pub packages and the pinned vision inputs (OpenCV source, Tesseract package, model). Each is already pinned and verified by hash.
- **Run time:** the first run compiles OpenCV (ADR-0008). Later runs reuse only the input caches, so OpenCV is rebuilt on each run. Caching the build tree is a measured follow-up, not part of this change.
- **No app code changes.** CI never launches `blackgrid.exe` as an app and never interacts with a game. The bundle-based tests load the bundle's DLLs, and the vision self-check test starts `blackgrid.exe --vision-self-check`, which runs headless and exits. Both already happen on the developer's machine today.
