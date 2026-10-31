# Proposal

## Why

M6 (Windows CI and releases) needs a version to be built and published without the developer's machine. `add-windows-ci` runs every offline gate on a hosted runner and `add-release-packaging` produces the zip, the installer and `SHA256SUMS.txt`, but nothing uploads them. A pushed `v` tag still produces no GitHub Release, and `v0.4.0` and `v0.5.0` exist only as tags. This change serves M6's exit criterion "Pushing a `v` tag builds the Release on CI and publishes a GitHub Release with a zip of the bundle and an installer, with that version's changelog section as its notes. A `-beta.N` tag is published as a prerelease." It also prepares the user-verified criterion "The user installs a published release from the installer and from the zip, and starts it."

The local half of the flow has a gap too. `pr.merge_method` is `squash` and the agent merges, so the next `chore(release)` PR lands on `main` as one squashed commit. `release:tag` accepts only a two-parent merge and would refuse it.

## What Changes

- A new tag-triggered workflow (`.github/workflows/release.yml`). A pushed tag matching `v*` runs the same offline gates as CI on the tagged commit: analyze, test, `build:release`, `ci:qualification` and `package:release`. It then publishes a GitHub Release named after the tag, with the zip, the setup and `SHA256SUMS.txt` as assets and that version's `CHANGELOG.md` section as the notes. A `-beta.N` tag is published as a prerelease. Only the highest final version is marked Latest.
- The workflow also takes a manual run from `main` with a tag input, which publishes the release for an existing tag through the same validation, so a failed publish can be retried. It refuses a tag that already has a release, and a tag whose tree predates `package:release` (`v0.4.0`, `v0.5.0`): those trees have no packaging task, so they are not backfilled.
- Before anything builds, the workflow checks the tag. The tag must be annotated, strict SemVer, and on `main`'s first-parent line. Its commit's `pubspec.yaml` version must equal the tag's version, and its `CHANGELOG.md` must have a section for that version. A tag that fails any check publishes nothing.
- Least privilege by job. The build job keeps `contents: read`, as CI does, and hands the package set to a separate publish job as a workflow artifact. Only the jobs that check out nothing (the preflight check and publish) have `contents: write`, which they need to see draft releases. Publish re-verifies the package against `SHA256SUMS.txt` and a digest passed from the build job before it creates the release.
- CI and release share one gate definition (a reusable workflow), so the steps cannot drift apart, and `BLACKGRID_NO_GAMES_RUNNING` is still set in exactly one file and one step.
- `release:tag` also accepts a squash-merged release: a single-parent `chore(release): v<version> (#N)` commit on `main`. It confirms through the GitHub API that PR #N merged from `release/v<version>` as `HEAD`, and that the release commit's parent is `HEAD`'s parent. In both the merge and the squash shape, the tag is refused if another PR merged between `prepare` and the release merge.
- New `release.dart` subcommands for the workflow: `verify-tag <tag>` (the checks above, plus the prerelease and Latest flags) and `notes <tag>` (extracts the version's changelog section). Both are pure Dart and tested offline.
- README "Releases and changelog" and the release-related ADR notes describe the new flow: prepare, merge, `release:tag`, then CI publishes. A local `build:release`/`package:release` remains for checking a build before tagging.

## Capabilities

### New Capabilities
- `release-publishing`: how a pushed or manually selected `v` tag is validated, built, packaged and published as a GitHub Release, with its notes, prerelease and Latest flags, its assets and checksums, and the permissions the publishing job holds.

### Modified Capabilities
- `continuous-integration`: the no-games confirmation and the least-privilege rule now cover the shared gates workflow that both CI and the release workflow call. The confirmation is still set in exactly one file and one step, and in the release workflow only the preflight and publish jobs, which check out nothing, hold `contents: write`.
- `release-versioning`: "Release tag marks the merged release commit" also accepts a squash-merged release commit, with an equivalent check that no PR merged between `prepare` and the release merge.

## Impact

- New: `.github/workflows/release.yml` and a reusable gates workflow (for example `.github/workflows/gates.yml`). `ci.yml` is changed to call the gates workflow.
- `tool/release/`: `verify-tag` and `notes` subcommands, plus squash handling in `tag_step.dart`, with tests under `test/tool/release/`.
- `test/tool/ci/workflow_test.dart` and `no_games_scan_test.dart`: assert the new workflow shapes (pinned actions, permissions per job, the single setter of the no-games flag).
- New pinned actions: `actions/upload-artifact` and `actions/download-artifact`. The publish job uses the runner's `gh`.
- A new ADR records the release workflow and the squash-merge tag rule. It amends ADR-0009 ("Local release tasks, no CI") and ADR-0024 (the gate steps move into a shared workflow).
- README "Releases and changelog" and the CI section.
- The repository is private, so a published release is visible only to people with access to the repository.
