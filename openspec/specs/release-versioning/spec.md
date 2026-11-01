# release-versioning Specification

## Purpose

Defines how a Blackgrid version is chosen, prepared, tagged, built and reported, so that every build, changelog entry and test result names a release that can be traced back to `main`.

## Requirements

### Requirement: Release versions are strict increasing SemVer
A release version SHALL be a SemVer 2.0.0 version with no build metadata. Its tag SHALL be the version prefixed with `v`. A new release version SHALL have higher SemVer precedence than every existing release tag in the repository.

#### Scenario: Next minor version accepted
- **WHEN** the latest release tag is `v0.1.0` and `0.2.0` is requested
- **THEN** the version is accepted

#### Scenario: Prerelease ordering
- **WHEN** the latest release tag is `v0.2.0-beta.1` and `0.2.0-beta.2` or `0.2.0` is requested
- **THEN** the version is accepted

#### Scenario: Version not increasing
- **WHEN** the latest release tag is `v0.2.0` and `0.2.0`, `0.1.9` or `0.2.0-beta.3` is requested
- **THEN** the request is refused with a message naming the requested version and the latest tag, and nothing is changed

#### Scenario: Malformed version
- **WHEN** `v0.2.0`, `0.2`, `00.2.0`, `0.2.0-beta.01` or `0.2.0+5` is requested
- **THEN** the request is refused as not a strict SemVer release version, and nothing is changed

### Requirement: Release preparation starts only from a clean, current main
Release preparation SHALL refuse to start unless the checkout is on the main branch, has no tracked changes and no untracked files, and its `HEAD` equals the remote main branch after a fetch. It SHALL also refuse if the release tag or the release branch already exists.

#### Scenario: Clean current main
- **WHEN** preparation runs on a clean `main` whose `HEAD` equals `origin/main`
- **THEN** the precondition checks pass

#### Scenario: Wrong branch or dirty tree
- **WHEN** preparation runs on a feature branch, or with a modified or untracked file
- **THEN** it is refused with a message naming the branch or the files, and no branch, file or commit is created

#### Scenario: Behind or ahead of the remote
- **WHEN** local `main` differs from `origin/main` after the fetch
- **THEN** it is refused with a message naming both commits

#### Scenario: Remote unreachable
- **WHEN** the fetch from `origin` fails
- **THEN** it is refused with the fetch error, and nothing is changed

#### Scenario: Release already started
- **WHEN** tag `v<version>` or branch `release/v<version>` already exists locally or on `origin`
- **THEN** it is refused with a message naming the existing tag or branch

### Requirement: Release preparation runs the offline gates before changing anything
After the preconditions pass, release preparation SHALL run static analysis, the format check and the complete offline test suite. It SHALL NOT create a branch, edit a file or commit unless every gate passes.

#### Scenario: Gates pass
- **WHEN** analysis, the format check and the full test suite all pass
- **THEN** preparation continues to the release commit

#### Scenario: A gate fails
- **WHEN** any gate exits non-zero
- **THEN** preparation stops with that gate's name and exit code, and the branch, working tree and history are unchanged

### Requirement: Release commit records the version and the changelog
Release preparation SHALL create branch `release/v<version>` and set the app version in `pubspec.yaml` to exactly `<version>`, with no build number. It SHALL insert a `## v<version> - <date>` section, built as the release notes requirements describe, directly above the newest existing section of `CHANGELOG.md`, leave every other section byte for byte as it was, except that a final version removes the sections of its own prereleases, and commit both files as one commit with subject `chore(release): v<version>`. Apart from this change's one-time removal of the scaffold build number, no other commit SHALL change the pubspec version.

#### Scenario: Release commit created
- **WHEN** preparation for `0.7.0` passes its gates, with `CHANGELOG.md` holding sections `v0.6.0` and `v0.5.0`
- **THEN** branch `release/v0.7.0` holds one new commit, `chore(release): v0.7.0`, changing only `pubspec.yaml` (`version: 0.7.0`) and `CHANGELOG.md`, where a `v0.7.0` section sits above `v0.6.0` and the `v0.6.0` and `v0.5.0` sections are unchanged

#### Scenario: Final release replaces its prereleases
- **WHEN** `CHANGELOG.md` holds sections `v0.7.0-beta.2`, `v0.7.0-beta.1` and `v0.6.0`, and preparation for `0.7.0` passes its gates
- **THEN** the committed `CHANGELOG.md` holds `v0.7.0` followed by `v0.6.0`, with no `v0.7.0-beta.1` or `v0.7.0-beta.2` section

#### Scenario: Prerelease keeps the earlier prerelease
- **WHEN** `CHANGELOG.md` holds `v0.7.0-beta.1` and `v0.6.0`, and preparation for `0.7.0-beta.2` passes its gates
- **THEN** the committed `CHANGELOG.md` holds `v0.7.0-beta.2`, `v0.7.0-beta.1` and `v0.6.0`, in that order

#### Scenario: Changelog generation fails
- **WHEN** writing the built section into `CHANGELOG.md` fails after the branch was created
- **THEN** preparation stops with the error, makes no commit, and names the branch and files left to discard

### Requirement: Proposals carry release notes in a fixed format
A change's `## Release Notes` section SHALL run to the next `## ` heading or the end of `proposal.md` and hold a summary of at most 600 characters, then one or more of `### Added`, `### Changed`, `### Fixed` and `### Removed`, each at most once and holding only list items of at most 500 characters, with at least one item in the section as a whole. HTML comments and blank lines SHALL be ignored, and an indented line SHALL continue the item above it. Anything else SHALL make the section invalid.

#### Scenario: Valid section
- **WHEN** a proposal's section has a one-sentence summary, an `### Added` list with two items and a `### Fixed` list with one
- **THEN** checking it succeeds and reports the summary and the three items

#### Scenario: Continued item
- **WHEN** an item's text goes on in an indented line below it
- **THEN** the item is the two lines joined by one space

#### Scenario: Empty heading beside items
- **WHEN** a section has an empty `### Added` and a `### Fixed` with one item
- **THEN** checking it succeeds and reports only the `### Fixed` item, as specwright's `release.sh notes --proposal` does

#### Scenario: Invalid section
- **WHEN** a section has no summary, an unknown heading such as `### Security`, prose under `### Added`, `### Added` twice, headings with no item at all, a summary over 600 characters or an item over 500 characters
- **THEN** checking it fails, naming the line and the problem for each error

#### Scenario: No section
- **WHEN** a proposal has no `## Release Notes` heading
- **THEN** checking it fails with a message that the proposal has no release notes

#### Scenario: In-flight proposal checked offline
- **WHEN** a change under `openspec/changes/` that is not archived has a proposal with an invalid or missing section
- **THEN** the fast offline test suite fails, naming the proposal and its first error

### Requirement: Release notes are built from the changes archived since the last final release
The release notes SHALL list the changes whose archived `proposal.md` was added on main's first-parent line after the latest final release tag reachable from `HEAD` (all of history when there is none), in that order. Each valid section's items SHALL be grouped under `Added:`, `Changed:`, `Fixed:` and `Removed:` across changes, and an item naming no `#<n>` SHALL get ` (#<PR>)` from the commit that added the proposal.

#### Scenario: Items grouped across changes
- **WHEN** change `a`, squash-merged as PR #80, has `### Added` item `Raid timer` and change `b`, merged as PR #81, has `### Fixed` item `Map centring (#77)` and `### Added` item `Scav cooldown`
- **THEN** the notes list under `Added:` `- Raid timer (#80)` then `- Scav cooldown (#81)`, and under `Fixed:` `- Map centring (#77)`

#### Scenario: Prereleases do not bound the range
- **WHEN** tags `v0.6.0` and `v0.7.0-beta.1` exist and the notes for `0.7.0` are built
- **THEN** every change archived on main since `v0.6.0` is listed, including those before `v0.7.0-beta.1`

#### Scenario: Change archived only on a branch
- **WHEN** a change is archived on a branch that has not reached main's first-parent line
- **THEN** it is not listed

#### Scenario: No change archived since the last release
- **WHEN** no proposal was archived on main since the latest final tag, even if direct commits landed
- **THEN** preparation is refused with a message that there is nothing to release, before any gate runs, and no branch, file or commit is created

### Requirement: A change without valid release notes is still listed
A change in the release's range whose proposal has no valid `## Release Notes` section SHALL be listed under `Changes:`, after the grouped items, as `- <name> (#<PR>): <first sentence of its ## Why>`, and SHALL be reported as a warning naming the change and its first error. It SHALL NOT stop the release.

#### Scenario: Change without a valid section
- **WHEN** change `c`, merged as PR #82, has no `## Release Notes` section and its Why starts `The map ignores floors. It should not.`
- **THEN** the notes list under `Changes:` `- c (#82): The map ignores floors.`, and a warning names `c` and its error

#### Scenario: Proposal not readable at HEAD
- **WHEN** change `d`, merged as PR #83, had its archived proposal added in the range, but the file is no longer at `HEAD` (the change was reverted or its archive moved)
- **THEN** the notes list `- d (#83)` under `Changes:`, a warning names `d`, and the release is not stopped

#### Scenario: Release with no valid section at all
- **WHEN** no change in the range has a valid section
- **THEN** the section holds the summary and the `Changes:` list only, and each change is reported as a warning

### Requirement: Release preparation requires a release summary
Release preparation SHALL require a summary of the whole release, given on the command line or in a file. It SHALL collapse the summary to one line (every run of whitespace, newlines included, becomes one space; the ends are trimmed) and SHALL refuse before running any gate when the result is missing, blank, over 600 characters, or starts with `#`. The summary SHALL open the release's section, followed by the grouped items.

#### Scenario: Summary given
- **WHEN** preparation for `0.7.0` is given the summary `Blackgrid now follows the whole raid.`
- **THEN** the `v0.7.0` section opens with that line, followed by a blank line and the grouped items

#### Scenario: Multi-line summary file
- **WHEN** the summary file holds `Raid timers arrive.`, a newline and `## Not a heading`
- **THEN** the section's summary is the one line `Raid timers arrive. ## Not a heading`, and `verify-tag` on the tagged release publishes the whole section, grouped items included

#### Scenario: Summary starting with a heading
- **WHEN** preparation is given the summary `## Highlights Raid timers arrive.`
- **THEN** it is refused before any gate runs, because as the section's first line that heading would end the section in `verify-tag`, and no branch, file or commit is created

#### Scenario: Summary missing or too long
- **WHEN** preparation is started without a summary, with a blank one, or with one that is 601 characters after collapsing
- **THEN** it is refused with a message saying so, before any gate runs, and no branch, file or commit is created

### Requirement: The next release's notes can be previewed
A preview command SHALL print, without changing any file, the items the next release's section would hold, the warnings, and every non-merge commit on main's first-parent line since the latest final tag that is not a release commit and added no archived proposal.

#### Scenario: Preview
- **WHEN** two changes and the direct commit `docs(readme): fix typo` landed on main since `v0.6.0`
- **THEN** the preview prints both changes' grouped items and lists `docs(readme): fix typo` as not covered by a change, and the working tree is unchanged

#### Scenario: Nothing to preview
- **WHEN** nothing landed on main since the latest final tag
- **THEN** the preview prints that there is nothing to release and exits 0

### Requirement: Release tag marks the merged release commit
Tagging SHALL refuse unless the checkout is a clean `main` that equals `origin/main` after a fetch, and `HEAD` is the merged release in one of two shapes. A merge: `HEAD` merges a PR whose second parent is a `chore(release): v<version>` commit, and that commit's first parent equals `HEAD`'s first parent. A squash: `HEAD` is a single-parent commit with the subject `chore(release): v<version> (#N)`, PR #N merged from `release/v<version>` with `HEAD` as its merge commit, that PR has exactly one commit, a `chore(release): v<version>` commit whose parent equals `HEAD`'s parent and whose tree equals `HEAD`'s tree. The pubspec version SHALL equal `<version>`, and tag `v<version>` SHALL NOT exist locally or on `origin`. It SHALL create an annotated tag `v<version>` on `HEAD` and push only that tag to `origin` as the configured GitHub account.

#### Scenario: Release merge tagged
- **WHEN** `HEAD` on a clean, current `main` merges `chore(release): v0.2.0` and the pubspec says `0.2.0`
- **THEN** annotated tag `v0.2.0` points at `HEAD` locally and on `origin`

#### Scenario: Squashed release tagged
- **WHEN** `HEAD` on a clean, current `main` is `chore(release): v0.6.0 (#70)`, PR #70 merged from `release/v0.6.0` as `HEAD`, its one commit `chore(release): v0.6.0` has `HEAD`'s parent as its parent and `HEAD`'s tree, and the pubspec says `0.6.0`
- **THEN** annotated tag `v0.6.0` points at `HEAD` locally and on `origin`

#### Scenario: Main moved before the release merge
- **WHEN** another PR merged into `main` after `release:prepare` and before the release PR merged, so the release commit's first parent differs from `HEAD`'s first parent, or for a squash, from `HEAD`'s parent
- **THEN** tagging is refused, naming the intervening commits and saying to prepare the release again, and no tag is created

#### Scenario: Squash from the wrong branch or with extra commits
- **WHEN** `HEAD`'s subject is `chore(release): v0.6.0 (#70)` but PR #70's head branch is not `release/v0.6.0`, its merge commit is not `HEAD`, or it has more than one commit
- **THEN** tagging is refused naming PR #70 and the failed check, and no tag is created

#### Scenario: PR cannot be read
- **WHEN** `HEAD` is a squashed release commit and the GitHub API call for its PR fails
- **THEN** tagging is refused naming the PR and the API error, and no tag is created

#### Scenario: HEAD is not a release merge
- **WHEN** `HEAD` is an ordinary PR merge, an ordinary squashed PR, or a non-merge commit whose subject is not `chore(release): v<version> (#N)`
- **THEN** tagging is refused with a message naming `HEAD`'s subject, and no tag is created

#### Scenario: Pubspec disagrees with the release commit
- **WHEN** the release commit says `v0.2.0` but the pubspec version is `0.2.0-beta.1`
- **THEN** tagging is refused naming both versions, and no tag is created

#### Scenario: Push identity cannot be confirmed
- **WHEN** no credential exists for the configured GitHub account, or the authenticated identity differs from it
- **THEN** tagging is refused naming the expected account, before any tag is created

### Requirement: Release builds carry the version and a build number
A release build SHALL take its version from `pubspec.yaml` and its build number from the commit count of the built `HEAD`. It SHALL embed both in the executable's version resource and as the app version `<version>+<build number>`. It SHALL refuse a working tree with changes, and a build number above 65535. After building, it SHALL run the offline bundle integrity check and fail if the check fails.

#### Scenario: Release build
- **WHEN** a release build runs on a clean checkout whose pubspec says `0.2.0` at a `HEAD` with 120 commits
- **THEN** the bundle's app version is `0.2.0+120`, the executable's file version is `0.2.0.120`, and the bundle integrity check passes

#### Scenario: Dirty tree
- **WHEN** a release build is started with a modified tracked file
- **THEN** it is refused before building, naming the files

#### Scenario: Build number exceeds the file-version field
- **WHEN** a release build is started at a `HEAD` with 65536 commits
- **THEN** it is refused before building, naming the count and the 65535 limit

#### Scenario: Integrity check fails
- **WHEN** the built bundle fails the bundle integrity check
- **THEN** the release build exits non-zero, reporting the integrity check's failure

### Requirement: The running app reports its version
The application SHALL show its app version in the Settings dialog. A build made without a release version SHALL report `dev`.

#### Scenario: Release build shows its version
- **WHEN** the Settings dialog opens in a build made with app version `0.2.0+120`
- **THEN** the dialog shows `0.2.0+120`

#### Scenario: Development build
- **WHEN** the Settings dialog opens in a build made without an app version
- **THEN** the dialog shows `dev`
