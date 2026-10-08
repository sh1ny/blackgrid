# 0009 - Release versioning: SemVer milestone versions, commit-count build numbers, per-PR changelog, local release tasks

- Status: accepted
- Date: 2026-10-08 (change `add-release-versioning`)
- Supersedes: none
- Source: [design](../../openspec/changes/add-release-versioning/design.md) D1-D10; [roadmap: Release versioning](../../openspec/roadmap.md#release-versioning-add-release-versioning)

## Context and problem

Blackgrid had no release process. `pubspec.yaml` held the scaffold `0.1.0+1`, there were no tags, every Windows build reported the same file version, and `CHANGELOG.md` listed every branch commit (`task 3.4 …`, `address review feedback`) under "Unreleased". Bug reports and user-only test results could not name the build they came from. Closing M2 is the first version bump, and its user-only checks need a prerelease build whose version the app reports.

## Decision

- **SemVer 2.0.0, `v`-prefixed tags, one minor version per milestone.** A milestone close bumps the minor version (M2 → `0.2.0`). Fixes between milestones bump the patch version. A build handed to the user for user-only checks is a prerelease (`-beta.N`); the final version follows once the user reports them passed. `1.0.0` comes at M6 if the user decides then. A new release version must be strict SemVer with no build metadata, and must have higher precedence than every existing release tag (an owned parser in `tool/release/src/semver.dart`).
- **Only release commits change the version.** `version:` in `pubspec.yaml` is changed only by a `chore(release): v<version>` commit, and holds no `+build` part. Feature and fix PRs never touch it.
- **Build number = commit count of the built `HEAD`** (`git rev-list --count HEAD`), passed at build time. It must stay ≤ 65535, the limit of each Windows file-version field; the build refuses above it.
- **Changelog: one entry per merged PR.** `cliff.toml` rewrites each GitHub merge commit (`Merge pull request #N from …` plus the PR title as the first body line) into `<PR title> (#N)`, grouped by its conventional type. `tool/changelog.dart` runs git-cliff in two stages (`--context`, then `--from-context -`) and keeps only commits on `main`'s first-parent line, so branch commits never appear. Release commits and their merges are skipped. Prerelease tags are ignored as section boundaries, so a final release lists the whole milestone, and `--latest`/`--unreleased` are translated to ranges between final tags. PR titles are conventional (`type(scope): summary`), a rule recorded in `openspec/config.yaml`.
- **Local release tasks, no CI.**
  - `mise run release:prepare -- <version>`: refuses unless on a clean `main` equal to `origin/main`, with an increasing version and no existing tag or release branch; runs `analyze`, `format:check` and `test:all`; only then creates `release/v<version>`, sets the pubspec version, regenerates `CHANGELOG.md` and commits.
  - `mise run release:tag`: on `main` after the release PR merged, derives the version from the merge's second parent, checks that the release commit's first parent equals `HEAD`'s first parent and that pubspec agrees, then creates an annotated `v<version>` tag and pushes only that tag. The push is fenced: the token for `github.login` in `openspec/specwright.yaml` comes from `gh auth token --user`, the identity is confirmed with `gh api user`, and every network Git call runs with `-c credential.helper= -c "credential.helper=!gh auth git-credential"`, so no other helper can supply a different account. A failed push deletes the local tag.
  - `mise run build:release`: refuses a dirty tree, runs `vision:fetch`, `flutter build windows --release --build-name <version> --build-number <count> --dart-define=BLACKGRID_VERSION=<version>+<count>`, then `bundle:check` on the output.
- **The app reports its version** through the compile-time define `BLACKGRID_VERSION` (`lib/application/app_version.dart`, `dev` without it). The Settings dialog shows it, and the `--vision-self-check` report records it as `appVersion` (report format stays 1).
- **Data versions stay independent**: the Drift `schemaVersion`, the map pack hash, the vision runtime manifest and the native ABI versions keep their own numbers.
- **Baseline:** an annotated `v0.1.0` tag on `cf02bb7` starts the first changelog.

## Rejected alternative

- **A build counter stored in pubspec or a file.** Every PR would conflict on it, and it is not monotonic across branches.
- **Passing branch commits to git-cliff as `--skip-commit` or a `.cliffignore`.** The command line overflows on Windows after a few hundred commits; the ignore file must be written and cleaned up.
- **Separate changelog sections per prerelease.** The final milestone section would hold only what landed after the last beta, often nothing.
- **`release:tag -- <version>`.** A typed version can disagree with the merged release; the merge already records it.
- **Pushing with whichever `gh` account is active.** Other agents can switch it concurrently.
- **PowerShell release scripts and `pub_semver`.** Hard to unit-test; `pub_semver` accepts forms the scheme refuses.

## Consequences

- **Release notes name PRs, not branch commits.** PR titles must be conventional; a non-conventional title lands under **Other**. Earlier non-conventional history inside `v0.1.0` is frozen as it is.
- **A release is three local steps** (prepare, merge the PR, tag) plus a build when one is needed. `release:tag` refuses when another PR merged between `prepare` and the release merge; recovery is to delete `release/v<version>` locally and on `origin` and prepare again.
- **Builds off a branch** carry the last release's version with their own commit count.
- **A pushed tag is public.** It can be deleted (`git push origin :refs/tags/v<version>`), but other clones may keep it, so a wrong tag is fixed by a new release rather than by moving the tag.
- **Installers, GitHub Releases, code signing and CI builds** are out of scope until M6.
- **Reversal cost: low** for the tooling and the changelog (regenerated from history); the tags themselves are permanent.
