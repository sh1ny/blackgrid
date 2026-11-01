# Spec Delta

## MODIFIED Requirements

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

## REMOVED Requirements

### Requirement: Changelog lists one entry per merged pull request
**Reason**: Release notes now come from each change's `## Release Notes` section instead of PR titles; git-cliff is removed.
**Migration**: Write a `## Release Notes` section in every proposal. Earlier `CHANGELOG.md` sections are rewritten once by hand in the new format and are kept as written from then on.

## ADDED Requirements

### Requirement: Proposals carry release notes in a fixed format
A change's `## Release Notes` section SHALL run to the next `## ` heading or the end of `proposal.md` and hold a summary of at most 600 characters, then one or more of `### Added`, `### Changed`, `### Fixed` and `### Removed`, each at most once and holding only list items of at most 500 characters. HTML comments and blank lines SHALL be ignored, and an indented line SHALL continue the item above it. Anything else SHALL make the section invalid.

#### Scenario: Valid section
- **WHEN** a proposal's section has a one-sentence summary, an `### Added` list with two items and a `### Fixed` list with one
- **THEN** checking it succeeds and reports the summary and the three items

#### Scenario: Continued item
- **WHEN** an item's text goes on in an indented line below it
- **THEN** the item is the two lines joined by one space

#### Scenario: Invalid section
- **WHEN** a section has no summary, an unknown heading such as `### Security`, prose under `### Added`, `### Added` twice, a heading with no items, a summary over 600 characters or an item over 500 characters
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

#### Scenario: Release with no valid section at all
- **WHEN** no change in the range has a valid section
- **THEN** the section holds the summary and the `Changes:` list only, and each change is reported as a warning

### Requirement: Release preparation requires a release summary
Release preparation SHALL require a summary of the whole release, given on the command line or in a file. It SHALL collapse the summary to one line (every run of whitespace, newlines included, becomes one space; the ends are trimmed) and SHALL refuse before running any gate when the result is missing, blank or over 600 characters. The summary SHALL open the release's section, followed by the grouped items.

#### Scenario: Summary given
- **WHEN** preparation for `0.7.0` is given the summary `Blackgrid now follows the whole raid.`
- **THEN** the `v0.7.0` section opens with that line, followed by a blank line and the grouped items

#### Scenario: Multi-line summary file
- **WHEN** the summary file holds `Raid timers arrive.`, a newline and `## Not a heading`
- **THEN** the section's summary is the one line `Raid timers arrive. ## Not a heading`, and `verify-tag` on the tagged release publishes the whole section, grouped items included

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
