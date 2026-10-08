# Proposal

## Why

Blackgrid has no release process. `pubspec.yaml` still holds the scaffold `0.1.0+1`, there are no tags, every Windows build reports the same file version, and `CHANGELOG.md` lists each branch commit (`task 3.4 …`, `address review feedback`) under "Unreleased". Bug reports and user-only test results cannot name the build they came from.

This change serves **M2 - capture/recognition proof**. It does not advance an M2 exit criterion directly, but it must land before M2 closes: closing M2 is the first version bump (`0.2.0`), and the user-only M2 checks (clean machine, live capture) need a `-beta.N` build whose version appears in the app and in the self-check report. The plan was agreed with the user on 2026-10-08 ([roadmap: Release versioning](../../roadmap.md#release-versioning-add-release-versioning)).

## What Changes

- **Version scheme.** SemVer 2.0.0 with `v`-prefixed tags. Each milestone close bumps the minor version (`0.2.0` for M2). Fixes between milestones bump the patch version. A build for user-only checks is a prerelease (`-beta.N`). `1.0.0` comes at M6 if the user decides then.
- **Version source.** Only a release commit changes `version:` in `pubspec.yaml`, and that version has no `+build` part. The build number is the commit count of the built `HEAD`, passed in at build time. Data versions (Drift schema, map pack hash, vision manifest, native ABIs) stay independent.
- **Changelog: one entry per merged PR.** `cliff.toml` turns each GitHub merge commit into an entry titled with its PR title and number, grouped by conventional type. `tool/changelog.dart` keeps only commits on `main`'s first-parent line, so branch commits (tasks, amendments, review fixes, planning, archive) never appear. Release commits are skipped. **BREAKING** for the changelog format: merge commits were skipped before, and branch commits were listed.
- **Local release tasks** (`mise`; no CI):
  - `release:prepare -- <version>`: refuses unless it runs on a clean, up-to-date `main` with a valid, increasing version; runs the offline gates; then creates `release/v<version>`, sets the pubspec version, regenerates `CHANGELOG.md` and commits `chore(release): v<version>`.
  - `release:tag`: on `main`, after the release PR has merged, it checks the merge and the pubspec version, then creates and pushes an annotated `v<version>` tag as the configured GitHub login.
  - `build:release`: fetches the vision inputs, builds Windows Release with the version, build number and `BLACKGRID_VERSION` define, then runs `bundle:check` on the output.
- **Version in the app.** The Settings dialog shows `BLACKGRID_VERSION` (`dev` when the build has no define), and the `--vision-self-check` report records it.
- **Workflow rules** in `openspec/config.yaml` context: PR titles are conventional (`type(scope): summary`), and at a milestone close the agent suggests `release:prepare` with the next minor version (a `-beta.N` first while user-only checks are open).
- **Baseline.** An annotated `v0.1.0` tag on `cf02bb7` gives the first changelog its starting point.
- **ADR-0009** records the scheme; the architecture index and the roadmap section point to it.

Not in this change: installers, GitHub Releases, code signing and CI builds (M6).

## Capabilities

### New Capabilities
- `release-versioning`: how a Blackgrid version is chosen, prepared, tagged, built and reported. Covers version validation, the release preconditions, the build number, the per-PR changelog and the version shown by the running app.

### Modified Capabilities
- `vision-runtime`: the self-check report must also record the application version (requirement "Self-check report is complete and authoritative").

## Impact

- **Tooling:** `cliff.toml`, `tool/changelog.dart`, a new `tool/release/` (prepare, tag, build), `mise.toml` tasks, tests under `test/tool/release/`. `git-cliff` 2.14.2 is already pinned in `mise.toml`, and no new dependencies are added.
- **App:** a new `lib/application/app_version.dart` (compile-time define), `lib/ui/settings_dialog.dart` and `lib/application/vision_self_check.dart`, plus their tests.
- **Repository:** `pubspec.yaml` version becomes `0.1.0` (the `+1` is dropped), `openspec/config.yaml` gets two context lines, `docs/adr/0009-*.md` is new, and `openspec/architecture.md` and `openspec/roadmap.md` point to it.
- **Remote:** a `v0.1.0` tag is pushed to `origin` (outward-facing; done with the user's confirmation during apply).
- **Unchanged:** the Drift schema, the map packs, the vision manifest and the ABIs, and `bundle:check` itself.
