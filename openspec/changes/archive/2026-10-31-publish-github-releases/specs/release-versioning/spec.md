# Spec Delta

## MODIFIED Requirements

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
