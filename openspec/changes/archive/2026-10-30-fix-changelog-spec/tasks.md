# Tasks

## Test map

All rows are in `test/tool/changelog_test.dart`, which runs `tool/changelog.dart` and `cliff.toml` against fixture Git repos: the real boundary. Rows marked `green` describe behaviour that already works (design.md D2). Their tests already pass or are added as pins, so they get no red step.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| release-versioning → Changelog lists one entry per merged pull request | Merged PR with branch commits | `test/tool/changelog_test.dart` | merged PR is one entry with title and number; branch commits absent | green |
| release-versioning → Changelog lists one entry per merged pull request | Squash-merged PR | `test/tool/changelog_test.dart` | squash-merged PR is one entry with title and number | green |
| release-versioning → Changelog lists one entry per merged pull request | PR title not conventional | `test/tool/changelog_test.dart` | non-conventional PR title lands under Other | green |
| release-versioning → Changelog lists one entry per merged pull request | Direct commit on main | `test/tool/changelog_test.dart` | direct fix commit on main is listed once under Fixes | green |
| release-versioning → Changelog lists one entry per merged pull request | Local merge into main | `test/tool/changelog_test.dart` | local merge commit and its branch commits are not listed | green |
| release-versioning → Changelog lists one entry per merged pull request | Direct commit that mentions merging | `test/tool/changelog_test.dart` | direct commit that mentions merging is still listed | green |
| release-versioning → Changelog lists one entry per merged pull request | First release with no earlier tag | `test/tool/changelog_test.dart` | --latest with no previous final tag renders from the root | green |
| release-versioning → Changelog lists one entry per merged pull request | Final release after prereleases | `test/tool/changelog_test.dart` | final release folds prerelease sections | green |
| release-versioning → Changelog lists one entry per merged pull request | Release notes and preview after a prerelease | `test/tool/changelog_test.dart` | --latest and --unreleased use final-tag ranges after a final release | green |
| release-versioning → Changelog lists one entry per merged pull request | Preview while a prerelease is the latest tag | `test/tool/changelog_test.dart` | --unreleased while a beta is latest lists everything since last final tag | green |
| release-versioning → Changelog lists one entry per merged pull request | Release commit and merge | `test/tool/changelog_test.dart` | release commit and its merge are not listed | green |

## 1. Pin the entry shapes that already work

- [x] 1.1 Add the test `squash-merged PR is one entry with title and number` to `test/tool/changelog_test.dart`. Its fixture makes one direct commit on main with the subject `fix(map): centre marker tiles (#59)`. Assert the output has the line `- *(map)* centre marker tiles (#59)` under `### Fixes`, exactly once. Verify: `mise exec -- flutter test test/tool/changelog_test.dart --plain-name "squash-merged PR"` passes on unchanged code.
- [x] 1.2 Tighten `direct fix commit on main is listed once under Fixes` to assert the exact entry line `- direct repair` under `### Fixes`, with no `(#` on that line. Verify: that test passes on unchanged code.
- [x] 1.3 Add the test `direct commit that mentions merging is still listed`, with the direct commit `fix: merge duplicate pins`. Assert `- merge duplicate pins` under `### Fixes`, exactly once. Verify: it passes on unchanged code.
- [x] 1.4 Re-run the green rows already in the file: merged PR with branch commits, non-conventional PR title, the first-release (`--latest` from the root), prerelease and release-commit tests. Verify: `mise exec -- flutter test test/tool/changelog_test.dart` passes.

## 2. Skip local merges

- [x] 2.1 Add the test `local merge commit and its branch commits are not listed`. Its fixture has a branch with the commit `docs(close-m9): close M9`, merged into main with `git merge --no-ff -m "merge: docs/close-m9"`, plus a later PR merge as a control. Assert that neither `docs/close-m9` nor `close M9` appears, that `### Other` is absent, and that the control PR's entry is present. Verify: it fails on unchanged code, because `- docs/close-m9` is listed under Other.
- [x] 2.2 Add `{ message = '^merge: ', skip = true }` to the skip block of `cliff.toml`, with a one-line comment saying it skips local `--no-ff` merges. Verify: the 2.1 test and the 1.3 test pass, and the 2.1 row turns green.
- [x] 2.3 Verify the whole change: `openspec validate fix-changelog-spec --strict`, `mise run analyze` and `mise run test` pass, and `dart format` leaves `test/tool/changelog_test.dart` unchanged. Also run `mise exec -- dart run tool/changelog.dart --unreleased --strip header` and check that it has no `sweep-open-issues` or `docs/close-m4.5` entry.

## Workflow follow-up

- Archive this change, which syncs the MODIFIED requirement into `openspec/specs/release-versioning/spec.md`, then ship it as a PR titled `fix(release): clarify changelog entries and skip local merges` with `Closes #17`.
