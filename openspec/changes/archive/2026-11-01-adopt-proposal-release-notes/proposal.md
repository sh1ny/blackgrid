# Proposal

## Why

Blackgrid's GitHub release notes are git-cliff output: one line per merged PR, built from its conventional title (`*(add-windows-ci)* run every offline gate on hosted Windows CI (#63)`). They name the work, not what a player or developer gets, and read differently from the user's other project (sh1ny/specwright), whose releases open with a plain-language summary and list `Added:`, `Changed:` and `Fixed:` items. The user asked for that format on every Blackgrid release, before M7 starts. This change is release tooling between milestones; it serves no roadmap milestone.

## What Changes

- Every change's `proposal.md` carries a `## Release Notes` section in specwright's format (ADR 0015 of sh1ny/specwright): a summary of at most 600 characters, then `### Added`, `### Changed`, `### Fixed` and `### Removed` lists, kept although `release.enabled` stays false. A project rule in `openspec/config.yaml` overrides the schema's "delete the section" instruction.
- **BREAKING (release tooling):** git-cliff is removed: `cliff.toml`, its mise tool entry and the PR-title changelog. `CHANGELOG.md` is no longer regenerated from history; each release prepends one section and earlier sections stay as written.
- `release:prepare` builds the new section from the `## Release Notes` sections of the changes archived on main since the last final release, grouped across changes as `Added:`, `Changed:`, `Fixed:` and `Removed:` with each change's PR appended, and opens it with a release summary given to the command. It refuses without a summary. A final release replaces the sections of its own prereleases.
- `mise run release-notes` prints the draft (items, warnings, and main commits no change covers) so the summary can be written before `release:prepare`; `mise run release-notes -- --check <proposal.md>` validates one proposal's section.
- An offline test fails when an in-flight change's proposal has an invalid section.
- The existing `CHANGELOG.md` sections (v0.1.0, v0.4.0, v0.5.0, v0.6.0) are rewritten by hand in the new format. After merge, the bodies of the published GitHub releases v0.6.0-beta.1 and v0.6.0 are replaced with the new text, after the user approves it.
- The release workflow is unchanged: it still publishes the tag's `CHANGELOG.md` section verbatim.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `release-versioning`: the release commit's changelog section comes from the archived proposals' Release Notes plus a given summary instead of regenerated git-cliff output; the per-PR changelog requirement is replaced by proposal-sourced release notes and a proposal section format.

## Impact

- Code: `tool/changelog.dart` (rewritten, no git-cliff), `tool/release/release.dart` and `tool/release/src/release_steps.dart` (prepare), `test/tool/changelog_test.dart`, `test/tool/release/prepare_test.dart`, `test/tool/release/verify_tag_test.dart` (its beta-heading contract test builds the section with the new builder and runs `verify-tag` on it, keeping ADR-0026's proof), a new repo-wide proposal check test.
- Config and docs: `cliff.toml` (deleted), `mise.toml` (git-cliff tool and `changelog` task removed, `release-notes` changed), `openspec/config.yaml` (Release Notes rule, PR-title rule reworded), `CHANGELOG.md`, a new ADR superseding ADR-0009's changelog decision, `openspec/architecture.md` index, `README.md` (prerequisites, the tooling table and the release section name git-cliff), and `openspec/roadmap.md` (its `release-notes -- --unreleased` line).
- External: the two published GitHub release bodies (edited once, by hand, with the user's approval; a recorded one-time exception to `release-publishing`). Tags are not touched.

## Release Notes

Release notes now open with a short summary and list what was added, changed, fixed and removed, written in each change's proposal instead of generated from PR titles.

### Added

- Each change's proposal carries a `## Release Notes` section, and `release:prepare` builds the release's changelog section from them with a summary you give it
- `mise run release-notes` prints the draft notes for the next release, and `-- --check <proposal.md>` validates one proposal's section

### Changed

- The changelog of every earlier release is rewritten in the new format

### Removed

- git-cliff and `cliff.toml`; `CHANGELOG.md` is no longer regenerated from Git history
