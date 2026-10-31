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
Release preparation SHALL create branch `release/v<version>` and set the app version in `pubspec.yaml` to exactly `<version>`, with no build number. It SHALL regenerate `CHANGELOG.md` with the unreleased entries under `v<version>`, and commit both files as one commit with subject `chore(release): v<version>`. Apart from this change's one-time removal of the scaffold build number, no other commit SHALL change the pubspec version.

#### Scenario: Release commit created
- **WHEN** preparation for `0.2.0` passes its gates
- **THEN** branch `release/v0.2.0` holds one new commit, `chore(release): v0.2.0`, changing only `pubspec.yaml` (`version: 0.2.0`) and `CHANGELOG.md` (a `v0.2.0` section)

#### Scenario: Changelog generation fails
- **WHEN** the changelog generator exits non-zero after the branch was created
- **THEN** preparation stops with the generator's error, makes no commit, and names the branch and files left to discard

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
