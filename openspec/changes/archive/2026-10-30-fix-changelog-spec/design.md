# Design

## Triage

| Trigger | Applies? | Evidence |
|---|---|---|
| T1 Components (new component, or 3+ with directed relationships) | No | One skip rule in `cliff.toml` and tests; `tool/changelog.dart` is unchanged |
| T2 State (persistent state, caches, 3+ state machine) | No | The changelog is regenerated from Git history on every run (`tool/release/src/release_steps.dart:119-139`); nothing is stored |
| T3 Concurrency (background work, workers/isolates, async, retries) | No | No new processes or async work |
| T4 Boundaries (data format, migration, shared interface, IPC, external) | No | The entry format is unchanged. Only `release_steps.dart` writes `CHANGELOG.md`, and no code reads it back. The change only drops local `merge:` commits from the human-read notes |
| T5 Volume (grows without a fixed bound) | No | No new collection |
| T6 Risk (security, money, data loss, unrecoverable user data) | No | Notes are regenerated from history; a wrong skip is fixed by regenerating |

TIER: LIGHT

## Context

See proposal.md for the four gaps. Current behaviour, checked on `main` at `f5aaeba`:

- `cliff.toml:33-35` rewrites a GitHub merge commit (`Merge pull request #N from …` plus the title as the first body line) to `<PR title> (#N)`. `tool/changelog.dart:180-222` then drops every commit that is not on `main`'s first-parent line, so branch commits never appear.
- A squash-merged PR is a single-parent commit on `main` whose subject GitHub ends with `(#N)`. It is parsed as a direct commit and renders as `*(map)* centre marker preference tile badges and labels (#59)`. That is the same shape as a merge-commit PR (`dart run tool/changelog.dart --unreleased`, run 2026-10-30).
- A direct commit renders as its description with its scope and no number, e.g. `*(specwright)* update Specwright to 0.10.0`. The test `direct fix commit on main is listed once under Fixes` (`test/tool/changelog_test.dart:191-197`) checks only the count, not that shape.
- First release: `changelog.dart:172-178` renders the whole history when there is no earlier final tag. The test `--latest with no previous final tag renders from the root` (`changelog_test.dart:263-288`) covers it.
- A local `--no-ff` merge with the subject `merge: <name>` is on the first-parent line, so it is not filtered. It is not a GitHub merge, so the preprocessor does not rewrite it. It parses as conventional type `merge`, matches no group, and lands under Other as the bare name (`- sweep-open-issues`, `- docs/close-m4.5` in today's preview). Specwright's local finish and roadmap steps write that subject.
- Skip rules come before group parsers in `cliff.toml:38-42` and match the raw message (`'^chore\(release\): v'`).

ADR-0009 (one entry per merged PR, first-parent filter) constrains this change. The change is coherent with it: a local merge is not a PR, and its branch commits are already excluded by the first-parent filter.

## Decisions

### D1: Skip local merges by subject with a `cliff.toml` skip rule

- **Choice:** Add `{ message = '^merge: ', skip = true }` to the skip block in `cliff.toml`. It matches only commits whose conventional type is exactly `merge`, so `fix: merge duplicate pins` is still listed.
- **Rejected:** Drop every first-parent merge commit that is not a GitHub PR merge in `tool/changelog.dart`, using parent counts. This puts the rule in the Dart filter and decides by commit topology instead of subject. It lost because it needs the Dart filter to know which merges the cliff preprocessor will rewrite, which splits one rule across two files. The subject is fixed by the Specwright skills that create these merges, and the existing skips already work on subjects.
- **Rejected:** Render a local merge as the subject of its merged branch's commit. The user chose skipping on 2026-10-30. Planning merges are not user-facing releases.
- **Reversal cost:** low. One line in `cliff.toml`.

### D2: Pin the existing squash, direct-commit and first-release behaviour with tests, not code

- **Choice:** No code change for these three. Add a test in which a squash-merged PR is one direct commit with `(#N)` and renders as one entry with its number. Make the direct-commit test assert the exact entry line. Keep the first-release test as the evidence for its new scenario.
- **Rejected:** Teach `changelog.dart` to recognise squash commits (a trailing `(#N)`) and render them through the PR path. It lost because the output would be identical and the change would add a second parse path.
- **Reversal cost:** low.

### D3: Rewrite the requirement as one MODIFIED block

- **Choice:** Replace the requirement "Changelog lists one entry per merged pull request" whole. Keep every existing scenario, pin the direct-commit shape, and add the squash, local-merge, mentions-merging and first-release scenarios. The description stays under 500 characters.
- **Rejected:** Split it into separate ADDED requirements for PR entries, direct commits and skipped commits. It lost because the rule is one behaviour, choosing the entries of one release, and a split would scatter shared scenarios.
- **Reversal cost:** low.
