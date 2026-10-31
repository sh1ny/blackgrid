# Spec Delta

## Purpose

Publishes each release version as a GitHub Release built on a hosted runner from the tagged commit, with the zip, the installer and their checksums as assets and that version's changelog section as its notes, so a version can be downloaded without the developer's machine.

## ADDED Requirements

### Requirement: A pushed release tag starts a publish run
The repository SHALL start its release workflow when a tag whose name starts with `v` is pushed, and SHALL build and gate the tagged commit on a GitHub-hosted Windows runner. The workflow SHALL also accept a manual run from `main` that names an existing tag, and SHALL treat it like a push of that tag. No other event SHALL publish a release.

#### Scenario: Tag pushed
- **WHEN** `release:tag` pushes annotated tag `v0.6.0` to `origin`
- **THEN** a release workflow run starts for `v0.6.0`

#### Scenario: Manual run for an existing tag
- **WHEN** the user starts the release workflow by hand with tag `v0.6.0`, which exists on `origin` and has no release
- **THEN** the run validates, builds and publishes `v0.6.0` exactly as a push of that tag would

#### Scenario: Manual run for a missing tag
- **WHEN** the user starts the release workflow by hand with tag `v9.9.9`, which does not exist on `origin`
- **THEN** the run fails before building, naming the tag, and no release is created

#### Scenario: Manual run from another branch
- **WHEN** the user starts the release workflow by hand from branch `feat/x` with tag `v0.6.0`
- **THEN** the run fails before building, saying a manual run must start from `main`, and no release is created

#### Scenario: Branch push or pull request
- **WHEN** a commit is pushed to `main` or to a pull request branch
- **THEN** no release workflow run starts

### Requirement: Only a valid release tag is built
Before building, the run SHALL refuse the tag unless all of these hold: the tag is annotated; its name is `v` followed by strict SemVer with no build metadata; its commit is on `main`'s first-parent line on `origin`; that commit's `pubspec.yaml` version equals the tag's version; its `CHANGELOG.md` has a section headed by the tag name; and its tree has the release tooling the run calls (`package:release` and the tag check). A refusal SHALL name the failed check.

#### Scenario: Valid final tag
- **WHEN** annotated tag `v0.6.0` points at a first-parent `main` commit whose pubspec says `0.6.0` and whose `CHANGELOG.md` has a `## v0.6.0` section
- **THEN** validation passes and the build starts

#### Scenario: Lightweight tag
- **WHEN** `v0.6.0` is a lightweight tag
- **THEN** the run fails before building with a message that the tag is not annotated, and no release is created

#### Scenario: Not a release version
- **WHEN** the tag is `v0.6` or `v0.6.0+5`
- **THEN** the run fails before building, naming the tag as not a strict SemVer release version, and no release is created

#### Scenario: Commit not on main
- **WHEN** `v0.6.0` points at a commit that is only on a feature branch, or only reached `main` through a merged branch
- **THEN** the run fails before building, saying the commit is not on `main`'s first-parent line, and no release is created

#### Scenario: Pubspec disagrees with the tag
- **WHEN** `v0.6.0` points at a commit whose pubspec says `0.5.0`
- **THEN** the run fails before building, naming both versions, and no release is created

#### Scenario: No changelog section
- **WHEN** the tagged commit's `CHANGELOG.md` has no `## v0.6.0` section
- **THEN** the run fails before building, naming the missing section, and no release is created

#### Scenario: Tag predates packaging
- **WHEN** the user starts a manual run for `v0.5.0`, whose tree has no `package:release` task and no tag check
- **THEN** the run fails before building, saying the tag predates release publishing, and no release is created

### Requirement: The published bundle passed every offline gate
The run SHALL check out the tagged commit with full history and run, in order and stopping at the first failure, the same gates CI runs: static analysis, the fast tests, the Release build with its bundle check, the qualification tier against that build and packaging of that build. Nothing SHALL be published unless every gate passed.

#### Scenario: All gates pass
- **WHEN** every gate passes for `v0.6.0`
- **THEN** the run proceeds to publishing with the zip, the setup and `SHA256SUMS.txt` that packaging wrote

#### Scenario: A gate fails
- **WHEN** the qualification tier fails for `v0.6.0`
- **THEN** the run fails at that step, packaging does not run, and no release or draft exists for `v0.6.0`

#### Scenario: Gates match CI
- **WHEN** the CI workflow's gate steps and the release workflow's gate steps are compared
- **THEN** both come from the same shared definition, so their steps, order and environment are the same

### Requirement: A release holds exactly the packaged assets
The published release SHALL have exactly three assets: `Blackgrid-<version>-windows-x64.zip`, `Blackgrid-<version>-windows-x64-setup.exe` and `SHA256SUMS.txt`, the files packaging wrote for the tagged commit. Before the release is created, the publishing step SHALL verify `SHA256SUMS.txt` against the digest the build job reported and every file against `SHA256SUMS.txt`, and SHALL refuse a missing, extra or mismatching file.

#### Scenario: Assets published
- **WHEN** `v0.6.0` is published
- **THEN** its release lists `Blackgrid-0.6.0-windows-x64.zip`, `Blackgrid-0.6.0-windows-x64-setup.exe` and `SHA256SUMS.txt`, and each file's SHA-256 matches its line in `SHA256SUMS.txt`

#### Scenario: Asset altered between jobs
- **WHEN** the setup the publishing step receives does not match its line in `SHA256SUMS.txt`
- **THEN** publishing fails naming the file, and no release or draft is created

#### Scenario: Whole set replaced between jobs
- **WHEN** the publishing step receives a zip, a setup and a `SHA256SUMS.txt` that agree with each other, but that `SHA256SUMS.txt` does not match the digest the build job reported
- **THEN** publishing fails naming `SHA256SUMS.txt`, and no release or draft is created

#### Scenario: Asset missing
- **WHEN** the publishing step receives no zip
- **THEN** publishing fails naming the missing file, and no release or draft is created

### Requirement: Release notes are the version's changelog section
The release's title SHALL be the tag name. Its notes SHALL be the body of the `## <tag>` section of the tagged commit's `CHANGELOG.md`, from the line after the heading up to the next `## ` heading or the end of the file. Nothing SHALL be generated or added.

#### Scenario: Notes from the changelog
- **WHEN** `v0.6.0`'s `CHANGELOG.md` has a `## v0.6.0 - 2026-11-10` section followed by a `## v0.5.0` section
- **THEN** the release notes hold exactly the lines between those two headings

#### Scenario: Last section in the file
- **WHEN** the tag's section is the last one in `CHANGELOG.md`
- **THEN** the notes run to the end of the file

#### Scenario: Empty section
- **WHEN** the tag's section has no entries
- **THEN** validation fails before building, saying the section is empty, and no release is created

### Requirement: Prereleases and Latest follow the version
A tag whose version has a prerelease part (for example `-beta.1`) SHALL be published as a prerelease and SHALL NOT be marked Latest. A final version SHALL be marked Latest only when it is the highest final version among the release tags on `origin`; otherwise it SHALL be published without the Latest mark.

#### Scenario: Beta tag
- **WHEN** `v0.6.0-beta.1` is published
- **THEN** its release is marked as a prerelease and the Latest release does not change

#### Scenario: Highest final version
- **WHEN** `v0.6.0` is published and it is the highest final tag
- **THEN** its release is marked Latest

#### Scenario: Older final version published later
- **WHEN** `v0.6.1` was already published and a manual run publishes `v0.6.0`
- **THEN** `v0.6.0`'s release is not marked Latest, and `v0.6.1` stays Latest

### Requirement: A release is created once and appears whole
The run SHALL refuse a tag that already has a release, published or draft, naming it: once before building, and again immediately before it creates the release. It SHALL create the release as a draft, upload every asset, and publish that draft, addressed by its own id, only after all uploads succeed. A failure after the draft exists SHALL leave a draft that nobody outside the repository sees, and SHALL NOT publish it.

#### Scenario: Release already exists
- **WHEN** a run starts for `v0.6.0` and a published release for `v0.6.0` already exists
- **THEN** the run fails before building, naming the existing release, and that release is not changed

#### Scenario: Draft already exists
- **WHEN** a run starts for `v0.6.0` and a draft release for `v0.6.0` exists from an earlier failed run
- **THEN** the run fails before building, naming the draft, and the draft is not changed

#### Scenario: Draft appears while the gates run
- **WHEN** a draft for `v0.6.0` is created after the run's pre-build check and before its publishing step
- **THEN** the publishing step refuses before creating a release, naming the draft, and no second draft exists

#### Scenario: Upload interrupted
- **WHEN** the setup upload fails after the draft was created
- **THEN** the run fails, the release for `v0.6.0` stays a draft, and a rerun is refused until that draft is deleted

#### Scenario: Release appears whole
- **WHEN** `v0.6.0` is published
- **THEN** the first time the release is not a draft, it already has all three assets and its notes

### Requirement: Only steps that run no repository code can write
The job that checks out, builds and packages the tagged commit SHALL hold only `contents: read` and SHALL receive no write token. Only the pre-build check and the publishing step, which check out nothing and run no repository code, SHALL hold `contents: write`. The workflow SHALL use no repository secrets other than the run's own token, and SHALL pin every third-party action to a full commit SHA.

#### Scenario: Permissions per job
- **WHEN** the release workflow file is read
- **THEN** its top-level permissions are `contents: read`, only the preflight and publish jobs widen them to `contents: write`, and neither of those jobs has a checkout or `mise` step

#### Scenario: A write job gains a checkout
- **WHEN** a checkout or `mise` step is added to a job that holds `contents: write`
- **THEN** an offline test fails and names the job

#### Scenario: Action pinned by tag
- **WHEN** a `uses:` line in the release workflow names an action by tag or branch
- **THEN** an offline test fails and names the line
