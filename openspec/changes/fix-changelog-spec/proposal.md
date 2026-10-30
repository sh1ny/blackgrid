# Proposal

## Why

The release-versioning spec's changelog rule does not match how changes reach `main` today. Its entry rule says every entry carries a PR title and number, but a direct commit has no PR (#17). It has no scenario for a first release with no earlier tag (#17). It predates `pr.merge_method: squash`, under which a merged PR is a plain commit and not a merge. It is also silent on local `--no-ff` merges (`merge: <name>`), which `finish: local` and planning-only edits create. The unreleased preview lists those today as bare names under Other (`- sweep-open-issues`, `- docs/close-m4.5`), while the commits they merged stay hidden.

This change serves milestone **M4.6 - open-issue sweep** (change 2). It advances the exit criterion "each fix-now issue is closed by the PR of the change that fixes it, with a regression test at the lowest layer that reproduces it" for #17, the only fix-now issue from `sweep-open-issues`. It is constrained by ADR-0009 (one changelog entry per merged PR, titled and grouped by its PR title).

## What Changes

- **Split the entry rule.** A PR merged with a GitHub merge commit is one entry, `<PR title> (#N)`. A commit made directly on `main` is one entry, its conventional description without a number. Each shape is pinned in a scenario.
- **Squash-merged PRs.** A PR squash-merged into `main` is one direct commit whose subject GitHub ends with `(#N)`, so it is one entry, `<PR title> (#N)`, like a merge-commit PR. The tool already renders it this way; the spec and a test now say so.
- **First release.** With no earlier final tag, the release lists everything on `main`'s first-parent line from the start of history. The tool already does this, and an existing test covers it; the spec now says so.
- **Local merges are not listed.** A local `--no-ff` merge commit with the subject `merge: <name>` gets no entry. Its branch commits stay unlisted as before. This is one skip rule in `cliff.toml` plus a test. It changes the next release's notes: the two bare `merge:` names disappear from Other.
- Squash-merged PR titles, direct commits and first-release behaviour need no code change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `release-versioning`: the requirement "Changelog lists one entry per merged pull request" is split into PR entries and direct-commit entries. It also gains scenarios for squash-merged PRs, the first release, and local `merge:` commits, which are skipped.

## Impact

- `openspec/specs/release-versioning/spec.md`: one requirement rewritten, scenarios added.
- `cliff.toml`: one `commit_parsers` skip rule for `merge: ` subjects.
- `test/tool/changelog_test.dart`: tests for squash-merged PR entries, the direct-commit entry shape and skipped local merges.
- Release notes from the next `release:prepare` on: no `merge: <name>` entries under Other. Nothing else in the app changes.
