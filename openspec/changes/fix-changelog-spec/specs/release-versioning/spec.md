# Spec Delta

## MODIFIED Requirements

### Requirement: Changelog lists one entry per merged pull request
The changelog SHALL list each pull request merged into main as one entry, `<PR title> (#N)`, grouped by the title's conventional type, whether GitHub merged it with a merge commit or squashed it. A non-merge commit made directly on main SHALL be listed as one entry: its description, with no number. Commits that reached main only through a merged branch, release commits and local merge commits with the subject `merge: <name>` SHALL NOT be listed.

#### Scenario: Merged PR with branch commits
- **WHEN** main holds a merge of PR #15 titled `feat(release): add release versioning`, whose branch had task, amendment and review-fix commits
- **THEN** the changelog has exactly one entry for it, `add release versioning (#15)` with scope `release` under Features, and no entry for any of its branch commits

#### Scenario: Squash-merged PR
- **WHEN** PR #59 titled `fix(map): centre marker tiles` is squash-merged, so main holds one non-merge commit with the subject `fix(map): centre marker tiles (#59)`
- **THEN** the changelog has exactly one entry for it, `centre marker tiles (#59)` with scope `map` under Fixes

#### Scenario: PR title not conventional
- **WHEN** a merged PR's title has no conventional type
- **THEN** its entry is listed under Other with the title as written

#### Scenario: Direct commit on main
- **WHEN** the commit `fix(map): restore pins` is made directly on main
- **THEN** it is listed once under Fixes as `restore pins` with scope `map` and no PR number

#### Scenario: Local merge into main
- **WHEN** a branch is merged into main locally with `--no-ff` and the merge commit's subject is `merge: docs/close-m4.5`
- **THEN** no changelog section has an entry for that merge commit or for any commit of the merged branch

#### Scenario: Direct commit that mentions merging
- **WHEN** the commit `fix: merge duplicate pins` is made directly on main
- **THEN** it is listed once under Fixes as `merge duplicate pins`

#### Scenario: First release with no earlier tag
- **WHEN** `v0.1.0` is the only final tag, and the latest release's notes are generated
- **THEN** the `v0.1.0` section lists every PR and direct commit on main's first-parent line from the first commit up to `v0.1.0`, and nothing made after `v0.1.0`

#### Scenario: Final release after prereleases
- **WHEN** tag `v0.2.0-beta.1` exists after `v0.1.0`, and the changelog is generated for `v0.2.0`
- **THEN** every PR merged since `v0.1.0` is listed under `v0.2.0`, and the changelog has no `v0.2.0-beta.1` section

#### Scenario: Release notes and preview after a prerelease
- **WHEN** tags `v0.1.0`, `v0.2.0-beta.1` and `v0.2.0` exist, and the latest release's notes or the unreleased preview is generated
- **THEN** the latest release's notes list every PR merged since `v0.1.0` under `v0.2.0`, and the unreleased preview lists only PRs merged after `v0.2.0`

#### Scenario: Preview while a prerelease is the latest tag
- **WHEN** tags `v0.1.0` and `v0.2.0-beta.1` exist and the unreleased preview is generated
- **THEN** it lists every PR merged since `v0.1.0`, including those before `v0.2.0-beta.1`

#### Scenario: Release commit and merge
- **WHEN** main holds the merge of the `chore(release): v0.2.0` PR
- **THEN** neither that merge nor the release commit appears in any changelog section
