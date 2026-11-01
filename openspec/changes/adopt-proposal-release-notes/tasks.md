# Tasks

## Test map

Parsing, grouping and rendering are pure and proved in `release_notes_test.dart`. The range reader needs real first-parent history, so those rows use small temporary git repos, following the existing `changelog_test.dart` fixture style. `prepare` keeps its `FakeRunner` (real git, stubbed gates) from `prepare_test.dart`.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| release-versioning → Release commit records the version and the changelog | Release commit created | test/tool/release/prepare_test.dart | release commit inserts the new section above the newest and keeps every other section | red |
| release-versioning → Release commit records the version and the changelog | Final release replaces its prereleases | test/tool/release/prepare_test.dart | a final release removes the sections of its own prereleases | red |
| release-versioning → Release commit records the version and the changelog | Prerelease keeps the earlier prerelease | test/tool/release/prepare_test.dart | a prerelease keeps the earlier prerelease section below it | red |
| release-versioning → Release commit records the version and the changelog | Changelog generation fails | test/tool/release/prepare_test.dart | a failing CHANGELOG write stops with no commit and names the branch and files to discard | red |
| release-versioning → Proposals carry release notes in a fixed format | Valid section | test/tool/release/release_notes_test.dart | a valid section yields its summary and items | red |
| release-versioning → Proposals carry release notes in a fixed format | Continued item | test/tool/release/release_notes_test.dart | an indented line continues the item above with one space | red |
| release-versioning → Proposals carry release notes in a fixed format | Invalid section | test/tool/release/release_notes_test.dart | each invalid form is reported with its line and problem | red |
| release-versioning → Proposals carry release notes in a fixed format | No section | test/tool/release/release_notes_test.dart | a proposal without the heading reports no release notes | red |
| release-versioning → Proposals carry release notes in a fixed format | In-flight proposal checked offline | test/tool/release/proposal_release_notes_test.dart | in-flight proposals of this repository have valid release notes; and: a fixture tree with an invalid in-flight proposal fails naming it | red |
| release-versioning → Release notes are built from the changes archived since the last final release | Items grouped across changes | test/tool/release/release_notes_test.dart | items are grouped across changes in first-parent order with the PR appended | red |
| release-versioning → Release notes are built from the changes archived since the last final release | Prereleases do not bound the range | test/tool/release/release_notes_test.dart | the range starts at the last final tag, not a prerelease | red |
| release-versioning → Release notes are built from the changes archived since the last final release | Change archived only on a branch | test/tool/release/release_notes_test.dart | a change archived only on an unmerged branch is not listed | red |
| release-versioning → Release notes are built from the changes archived since the last final release | No change archived since the last release | test/tool/release/prepare_test.dart | nothing archived since the last final tag is refused before any gate | red |
| release-versioning → A change without valid release notes is still listed | Change without a valid section | test/tool/release/release_notes_test.dart | a change without a valid section is listed under Changes with its Why sentence and warned | red |
| release-versioning → A change without valid release notes is still listed | Release with no valid section at all | test/tool/release/release_notes_test.dart | with no valid section the notes are the summary and Changes only | red |
| release-versioning → Release preparation requires a release summary | Summary given | test/tool/release/prepare_test.dart | the summary opens the section followed by the grouped items | red |
| release-versioning → Release preparation requires a release summary | Multi-line summary file | test/tool/release/verify_tag_test.dart | a multi-line summary file becomes one line and verify-tag publishes the whole section | red |
| release-versioning → Release preparation requires a release summary | Summary missing or too long | test/tool/release/prepare_test.dart | a missing, blank or over-long summary is refused before any gate | red |
| release-versioning → The next release's notes can be previewed | Preview | test/tool/changelog_test.dart | preview prints grouped items and uncovered direct commits and changes no file | red |
| release-versioning → The next release's notes can be previewed | Nothing to preview | test/tool/changelog_test.dart | preview with nothing since the last final tag says so and exits 0 | red |

## 1. ADR-0029 and the architecture index

- [x] 1.1 Write `docs/adr/0029-release-notes-come-from-each-proposal.md` (MADR-short, `Status: accepted`, today's date, `Supersedes: 0009 (changelog decision only)`) from design D1-D4, D7 and D8. It covers: the section format and its limits, `CHANGELOG.md` as the durable store with one section inserted per release, the summary given to `prepare` and collapsed to one line, the first-parent archive range with offline PR numbers, the `Changes:` fallback, and D8's one-time exception to `release-publishing` for the `v0.6.0` and `v0.6.0-beta.1` bodies with where their authoritative copies live. Include the rejected alternatives. Add its row to `openspec/architecture.md`'s ADR index and mark ADR-0009's row as partly superseded by 0029. Do not edit ADR-0009. Verify: `grep 0029 openspec/architecture.md` finds the row, and `git diff --stat docs/adr/0009-*` is empty.

## 2. Section parser

Load `dart-add-unit-test`, `dart-write-documentation` and `dart-use-pattern-matching` first.

- [ ] 2.1 Write failing tests in `test/tool/release/release_notes_test.dart` for the rows "Valid section", "Continued item", "Invalid section" (one case per form: no summary, unknown heading, prose under a heading, a duplicate heading, a heading with no items, a summary of 601 characters, an item of 501 characters) and "No section". Also cover HTML comments (single- and multi-line) and blank lines being ignored, and the section ending at the next `## ` heading. Use the cases specwright's `release.sh notes --proposal` decides the same way (run it once by hand on the fixtures to confirm, and record the result in the commit message). Verify they fail for the missing library.
- [ ] 2.2 Implement the parser in `tool/release/src/release_notes.dart`: a sealed result (valid section with summary and items per heading, or errors with line numbers), plus the first-sentence-of-Why extractor (specwright's `first_sentence` rules, 300-character cut). Verify group 2's tests pass and flip their rows green.

## 3. Range reader and renderer

- [ ] 3.1 Write failing tests in `release_notes_test.dart` for the rows "Items grouped across changes", "Prereleases do not bound the range", "Change archived only on a branch", "Change without a valid section" and "Release with no valid section at all". Build small temporary git repos: squash commits ending in `(#N)`, one `Merge pull request #N` merge, a direct commit, tags. Also cover: an item that already names `#77` gets no PR appended, a proposal with no PR in its commit is listed as written, the 150-item and 100-line caps, and a proposal over 64 KB falling back to its name with a warning. Verify they fail.
- [ ] 3.2 Implement the range reader through the existing `Git`/`CommandRunner` seam (`tool/release/src/git.dart`), using `git log --first-parent --diff-merges=first-parent --diff-filter=A` over `openspec/changes/archive/*/proposal.md` since the last final tag reachable from `HEAD`, `git cat-file -s` before each read, `git show HEAD:<path>`, and the 1 000-change bound. Also implement the renderer: summary, then `Added:`/`Changed:`/`Fixed:`/`Removed:`, then `Changes:`, separated by blank lines as in specwright's `build_notes`, with a list of warnings. Verify group 3's tests pass and flip their rows green.

## 4. CLI, git-cliff removal and the in-flight check

- [ ] 4.1 Write failing tests: rewrite `test/tool/changelog_test.dart` for the rows "Preview" and "Nothing to preview", plus `--check <proposal.md>` (exit 0 with the summary; exit 1 with each error and its line; exit 2 for a missing file) and an unknown option (exit 2). Write `test/tool/release/proposal_release_notes_test.dart` for "In-flight proposal checked offline": one test over this repository's `openspec/changes/*/proposal.md` (not `archive/`), and one over a temporary fixture tree with an invalid in-flight proposal, through the same helper. Verify they fail.
- [ ] 4.2 Rewrite `tool/changelog.dart` as the CLI over the library: preview by default (grouped items, warnings, and non-merge, non-release first-parent commits since the last final tag that added no archived proposal, listed as uncovered), and `--check <proposal.md>`. Delete `cliff.toml`. In `mise.toml`, remove the git-cliff tool and the `changelog` task, and point `release-notes` at the new CLI with a matching description. Implement the in-flight helper. Verify group 4's tests pass, flip their rows green, and `grep -rn cliff tool test mise.toml` finds nothing.

## 5. `release:prepare` builds the section

- [ ] 5.1 Write failing tests in `test/tool/release/prepare_test.dart` for the rows "Release commit created", "Final release replaces its prereleases", "Prerelease keeps the earlier prerelease", "Changelog generation fails", "No change archived since the last release", "Summary given" and "Summary missing or too long". Fixtures hold archived proposals with sections. Also add: a git error while reading the range, before the branch exists, is refused without the leftover-branch instructions (review S6); and `--summary` and `--summary-file` are exclusive. In `test/tool/release/verify_tag_test.dart`, rewrite the beta-heading contract test to build the section with `prepare`'s in-process insert instead of git-cliff, then run `verify-tag` on it. Add the "Multi-line summary file" row there. Remove the `changelogCode` stub from `FakeRunner`. Verify the new tests fail.
- [ ] 5.2 Implement D3 in `tool/release/src/release_steps.dart` and `tool/release/release.dart`:
  - add the `--summary <text>` / `--summary-file <path>` options and collapse the summary;
  - check it before the preconditions;
  - build and validate the section in memory after the preconditions and before the gates;
  - after `checkout -b`, set the pubspec and insert the section above the newest `## v` section, dropping the same version's prerelease sections on a final;
  - print the warnings;
  - remove the git-cliff next-version hint;
  - update the usage text.

  Verify group 5's tests pass, flip their rows green, and re-run `test/tool/release/` as a whole.

## 6. Authoring rules and docs

- [ ] 6.1 In `openspec/config.yaml`, add a `rules: proposal:` entry: keep the `## Release Notes` section in every proposal although `release.enabled` is false, keep it current during apply, and check it with `mise run release-notes -- --check <proposal.md>`. Reword the context's PR-title line and the milestone-close line so that the notes come from proposals and `release:prepare` needs a summary (preview first). Verify: `openspec instructions proposal --change adopt-proposal-release-notes --json` shows the new rule in `rules`.
- [ ] 6.2 Update `README.md`: drop git-cliff from the prerequisites and the tooling table, rewrite the release table's Preview and Prepare rows and the changelog paragraph and examples for the new flow. Update `openspec/roadmap.md`'s `release-notes -- --unreleased` line. Verify: `grep -n -i "cliff\|--unreleased\|--latest" README.md openspec/roadmap.md` finds nothing.

## 7. Rewrite the existing release notes

- [ ] 7.1 Rewrite the `v0.6.0`, `v0.5.0`, `v0.4.0` and `v0.1.0` sections of `CHANGELOG.md` in the new format: a summary, then `Added:`/`Changed:`/`Fixed:`/`Removed:` items with PR numbers. Write them from each range's archived proposals and merged PRs (`git log --first-parent v<prev>..v<tag>`). Keep the headings and dates as they are, and title the file `# Blackgrid Changelog`. Verify: every PR number in the old sections appears in, or is deliberately folded into, the new ones (list any dropped release or docs-only commits in the commit message); each section passes `release:verify-tag`'s section parse (non-empty, no inner `## ` line).
- [ ] 7.2 Write `openspec/changes/adopt-proposal-release-notes/release-bodies/v0.6.0-beta.1.md`: the beta's notes in the new format, covering only what landed by `v0.6.0-beta.1` (`git log --first-parent v0.5.0..v0.6.0-beta.1`). Verify: every PR it names is an ancestor of `v0.6.0-beta.1`.

## 8. Integration checks

- [ ] 8.1 Run `mise run analyze`, `mise run test`, `dart format --output=none --set-exit-if-changed .` and `openspec validate adopt-proposal-release-notes --strict`. Run `mise run release-notes` on this branch and confirm it prints this change's items with nothing refused. Run `mise run release-notes -- --check openspec/changes/adopt-proposal-release-notes/proposal.md` and confirm exit 0. Record the outputs in the commit.

## Workflow follow-up

- After the PR merges: show the user the new bodies for `v0.6.0` (its `CHANGELOG.md` section on main) and `v0.6.0-beta.1` (the archived `release-bodies/v0.6.0-beta.1.md`). Only after they approve, run `gh release edit <tag> --notes-file <file>` for each, fenced to `KintsugiBot`, and report each result. Tags are not touched.
- The next release (`release:prepare`) is the first to build its section from proposals.
