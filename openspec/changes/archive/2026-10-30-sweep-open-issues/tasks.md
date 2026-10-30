# Tasks

## Test map

This change has no specs (`skip_specs: true`), so it has no scenarios to map.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| n/a | n/a (no specs) | `openspec validate sweep-open-issues --strict` | mechanical check | n/a |

## 1. Record verdicts on GitHub

All GitHub writes run as `KintsugiBot` through the fenced `gh` credential, using the reasons in design.md's Verdicts table.

- [x] 1.1 Create the `post-1.0` label on `sh1ny/blackgrid` if it is missing. Verify: `gh label list` shows it.
- [x] 1.2 Close #30 with a comment giving its design.md reason and evidence. Verify: `gh issue view 30` shows it closed with that comment.
- [x] 1.3 Comment on #17 that it will be fixed by `fix-changelog-spec` in M4.6. Verify: the comment is on #17 and the issue stays open.
- [x] 1.4 For each deferred issue (#10, #16, #19, #20, #21, #23, #24, #25, #28, #29, #33, #34, #38, #48, #52, #55), post its design.md reason and apply `post-1.0`. Verify: `gh issue list --label post-1.0` lists exactly those 16.

## 2. Update the roadmap

- [x] 2.1 In `openspec/roadmap.md` M4.6 Changes, replace the placeholder "2. The fix changes the sweep adds..." with `fix-changelog-spec`. It closes #17: split the changelog entry rule into PR entries and direct-commit entries, add a first-release scenario, and describe squash-merged PRs. Verify: the roadmap lists it as change 2 with #17.
- [x] 2.2 Run `openspec validate sweep-open-issues --strict`. Verify: it passes.

## Workflow follow-up

- Archive this change, then ship it (PR per `finish: pr`). The `fix-changelog-spec` change is started by a later `/specwright-roadmap next`.
