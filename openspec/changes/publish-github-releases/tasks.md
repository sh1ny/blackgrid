# Tasks

## Test map

Workflow behaviour is proved offline in two layers. `release_workflow_test.dart` and `workflow_test.dart` parse the YAML and assert triggers, job graph, permissions, steps and pins. `release_workflow_scripts_test.dart` extracts the `run:` script of each preflight and publish step from `release.yml` and runs it under `bash`, with a fake `gh` on `PATH` that serves fixture JSON and records every call, and the real `sha256sum` and `jq`. A real GitHub run is not part of `mise run test`; it is the first tag after merge (Workflow follow-up).

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| release-publishing → A pushed release tag starts a publish run | Tag pushed | test/tool/ci/release_workflow_test.dart | triggers are tag pushes matching v* and workflow_dispatch with a tag input | red |
| release-publishing → A pushed release tag starts a publish run | Manual run for an existing tag | test/tool/ci/release_workflow_scripts_test.dart | preflight resolves the dispatch tag input like a pushed tag | red |
| release-publishing → A pushed release tag starts a publish run | Manual run for a missing tag | test/tool/ci/release_workflow_scripts_test.dart | preflight refuses a tag missing on origin, naming it | red |
| release-publishing → A pushed release tag starts a publish run | Manual run from another branch | test/tool/ci/release_workflow_scripts_test.dart | preflight refuses a manual run whose ref is not main | red |
| release-publishing → A pushed release tag starts a publish run | Branch push or pull request | test/tool/ci/release_workflow_test.dart | triggers are tag pushes matching v* and workflow_dispatch with a tag input | red |
| release-publishing → Only a valid release tag is built | Valid final tag | test/tool/release/verify_tag_test.dart | valid final tag writes notes and release metadata | red |
| release-publishing → Only a valid release tag is built | Lightweight tag | test/tool/ci/release_workflow_scripts_test.dart | preflight refuses a lightweight tag | red |
| release-publishing → Only a valid release tag is built | Not a release version | test/tool/release/verify_tag_test.dart | non-SemVer or build-metadata tag is refused | red |
| release-publishing → Only a valid release tag is built | Commit not on main | test/tool/release/verify_tag_test.dart | commit off main's first-parent line is refused | red |
| release-publishing → Only a valid release tag is built | Pubspec disagrees with the tag | test/tool/release/verify_tag_test.dart | pubspec mismatch is refused naming both versions | red |
| release-publishing → Only a valid release tag is built | No changelog section | test/tool/release/verify_tag_test.dart | missing changelog section is refused | red |
| release-publishing → Only a valid release tag is built | Tag predates packaging | test/tool/ci/release_workflow_scripts_test.dart | the tooling guard refuses a tree without release:verify-tag | red |
| release-publishing → The published bundle passed every offline gate | All gates pass | test/tool/ci/release_workflow_test.dart | gates job runs the shared gates workflow and publish needs it | red |
| release-publishing → The published bundle passed every offline gate | A gate fails | test/tool/ci/workflow_test.dart | in release mode the upload step follows Package and no gate step has a condition | red |
| release-publishing → The published bundle passed every offline gate | Gates match CI | test/tool/ci/release_workflow_test.dart | ci and release call the same gates workflow | red |
| release-publishing → A release holds exactly the packaged assets | Assets published | test/tool/ci/release_workflow_scripts_test.dart | publish uploads exactly the zip, setup and sums to the created id | red |
| release-publishing → A release holds exactly the packaged assets | Asset altered between jobs | test/tool/ci/release_workflow_scripts_test.dart | publish refuses a file that fails sha256sum before any POST | red |
| release-publishing → A release holds exactly the packaged assets | Whole set replaced between jobs | test/tool/ci/release_workflow_scripts_test.dart | publish refuses sums that differ from the gates digest output | red |
| release-publishing → A release holds exactly the packaged assets | Asset missing | test/tool/ci/release_workflow_scripts_test.dart | publish refuses a missing or extra file before any POST | red |
| release-publishing → Release notes are the version's changelog section | Notes from the changelog | test/tool/release/verify_tag_test.dart | notes are the lines between the tag heading and the next section | red |
| release-publishing → Release notes are the version's changelog section | Last section in the file | test/tool/release/verify_tag_test.dart | notes of the last section run to the end of the file | red |
| release-publishing → Release notes are the version's changelog section | Empty section | test/tool/release/verify_tag_test.dart | empty changelog section is refused | red |
| release-publishing → Prereleases and Latest follow the version | Beta tag | test/tool/release/verify_tag_test.dart | beta tag is a prerelease and never latest | red |
| release-publishing → Prereleases and Latest follow the version | Highest final version | test/tool/release/verify_tag_test.dart | highest final tag is latest | red |
| release-publishing → Prereleases and Latest follow the version | Older final version published later | test/tool/release/verify_tag_test.dart | lower final tag than an existing final is not latest | red |
| release-publishing → A release is created once and appears whole | Release already exists | test/tool/ci/release_workflow_scripts_test.dart | preflight refuses a published release for the tag | red |
| release-publishing → A release is created once and appears whole | Draft already exists | test/tool/ci/release_workflow_scripts_test.dart | preflight refuses a draft for the tag, naming it | red |
| release-publishing → A release is created once and appears whole | Draft appears while the gates run | test/tool/ci/release_workflow_scripts_test.dart | publish refuses a draft listed just before the POST and makes none | red |
| release-publishing → A release is created once and appears whole | Upload interrupted | test/tool/ci/release_workflow_scripts_test.dart | a failed upload exits non-zero and never sends draft false | red |
| release-publishing → A release is created once and appears whole | Release appears whole | test/tool/ci/release_workflow_scripts_test.dart | publish patches draft false by id only after three uploaded assets | red |
| release-publishing → Only steps that run no repository code can write | Permissions per job | test/tool/ci/release_workflow_test.dart | top-level contents read and only preflight and publish widen to write | red |
| release-publishing → Only steps that run no repository code can write | A write job gains a checkout | test/tool/ci/release_workflow_test.dart | no job with contents write has a checkout, mise or local workflow step | red |
| release-publishing → Only steps that run no repository code can write | Action pinned by tag | test/tool/ci/workflow_test.dart | every uses line in every workflow is pinned to a 40-hex commit SHA | red |
| continuous-integration → The no-games confirmation is scoped to the hosted runner | Native capture test runs on the hosted runner | test/tool/ci/workflow_test.dart | the qualification step of the gates workflow alone sets the no-games confirmation and the bundle inputs | red |
| continuous-integration → The no-games confirmation is scoped to the hosted runner | A game executable is listed | test/tool/ci/qualification_audit_test.dart | the capture guard's refused and unconfirmed reasons are not allowlisted | green |
| continuous-integration → The no-games confirmation is scoped to the hosted runner | Another step or file sets the confirmation | test/tool/ci/workflow_test.dart | no other tracked file, including ci.yml and release.yml, sets the no-games confirmation | red |
| continuous-integration → CI holds least privilege and no secrets | Workflow permissions | test/tool/ci/workflow_test.dart | ci and gates permissions are exactly contents read and no secrets are used | red |
| continuous-integration → CI holds least privilege and no secrets | An action pinned by tag | test/tool/ci/workflow_test.dart | every uses line in every workflow is pinned to a 40-hex commit SHA | red |
| release-versioning → Release tag marks the merged release commit | Release merge tagged | test/tool/release/tag_test.dart | release merge gets annotated tag pushed to origin | green |
| release-versioning → Release tag marks the merged release commit | Squashed release tagged | test/tool/release/tag_test.dart | squashed release gets annotated tag pushed to origin | red |
| release-versioning → Release tag marks the merged release commit | Main moved before the release merge | test/tool/release/tag_test.dart | squashed release onto a moved main refuses naming intervening commits | red |
| release-versioning → Release tag marks the merged release commit | Squash from the wrong branch or with extra commits | test/tool/release/tag_test.dart | squashed release PR from another branch, another merge commit or with two commits refuses | red |
| release-versioning → Release tag marks the merged release commit | PR cannot be read | test/tool/release/tag_test.dart | squashed release refuses when the PR API call fails | red |
| release-versioning → Release tag marks the merged release commit | HEAD is not a release merge | test/tool/release/tag_test.dart | ordinary merge or non-merge HEAD refuses naming its subject | red |
| release-versioning → Release tag marks the merged release commit | Pubspec disagrees with the release commit | test/tool/release/tag_test.dart | pubspec version mismatch refuses naming both versions | green |
| release-versioning → Release tag marks the merged release commit | Push identity cannot be confirmed | test/tool/release/tag_test.dart | missing credential or other login refuses before any tag exists | green |

## 1. ADR and architecture

- [x] 1.1 Write `docs/adr/0026-releases-published-by-a-tag-workflow.md` (Status: accepted, today's date, amends 0009 and 0024) recording design D1-D7, the rejected alternatives and reversal costs. Add its row to the in-force index in `openspec/architecture.md`. Update the CI workflow row (gates now in `gates.yml`, called by `ci.yml`) and add a release workflow row (preflight, gates, publish; permissions; artifact; GitHub Releases). Also add one line to `docs/adr/README.md` if it lists ADRs. Verify: `git diff --stat` shows only those files, and every link in the new ADR resolves (`test -f` on each relative path).

## 2. Tag validation and notes (`release.dart verify-tag`)

Read `.claude/skills/dart-add-unit-test/SKILL.md`, `dart-use-pattern-matching` and `dart-write-documentation` first. Tests build throwaway Git repos in a temp directory, as `test/tool/release/tag_test.dart` does.

- [ ] 2.1 Write `test/tool/release/verify_tag_test.dart` with every verify_tag row of the test map: valid tag, non-SemVer and build metadata, off first-parent (a branch commit, and a commit reached only through a merged branch), pubspec mismatch, missing and empty sections, notes between sections and to end of file, beta prerelease and never latest, highest final latest, older final not latest. Add one fixture test that the changelog `release:prepare` renders for `0.6.0-beta.1` (through `tool/changelog.dart --tag v0.6.0-beta.1 --output`) has a `## v0.6.0-beta.1` heading that `verify-tag` finds. That test settles the design's unverified assumption. Verify: `mise exec -- flutter test test/tool/release/verify_tag_test.dart` fails because `verify-tag` does not exist.
- [ ] 2.2 Implement `tool/release/src/verify_tag_step.dart` and the `verify-tag <tag> --out <dir>` subcommand in `tool/release/release.dart` (usage text included), plus the mise task `release:verify-tag`. It writes `<dir>/notes.md` and `<dir>/release.json` (`tag`, `version`, `prerelease`, `latest`) through a temp file and a rename, exits 1 naming the failed check, and reuses `SemVer.parseRelease` and the existing `Git`/`CommandRunner`. Verify: 2.1's tests pass and their rows flip green; `mise run analyze` is clean.

## 3. `release:tag` accepts a squashed release

- [ ] 3.1 Extend `test/tool/release/tag_test.dart` with the squash rows: tagged, main moved, wrong branch, wrong merge commit, two commits, API failure. Also add a case to "ordinary merge or non-merge HEAD refuses naming its subject" for an ordinary squashed PR subject (`fix(map): x (#5)`). The fake runner serves recorded `gh api` JSON for `pulls/<N>`, `pulls/<N>/commits` and `git/commits/<sha>`, and asserts the calls carry the fenced token only through the environment. Verify: the new tests fail for the right reason (the squash shape is refused as "not a release merge"), and the three rows marked green still pass.
- [ ] 3.2 Implement the squash path in `tool/release/src/tag_step.dart` per design D6. Derive `<owner>/<repo>` from origin's fetch URL, run `gh api` with the confirmed `PushIdentity` environment, and share the pubspec, tag-absent and push steps with the merge path. Change the post-push message to point at the release workflow's Actions page instead of suggesting `build:release` (D7). Verify: all `tag_test.dart` tests pass, the squash rows flip green, and `mise run analyze` is clean.

## 4. Shared gates workflow

- [ ] 4.1 Retarget `test/tool/ci/workflow_test.dart`. Gate-step assertions read `.github/workflows/gates.yml`. `ci.yml` assertions cover its triggers and concurrency (unchanged) and its single job, which calls `./.github/workflows/gates.yml` with no `release_tag`. Add the release-mode assertions: the explicit `ref:` checkout of `refs/tags/<tag>`, the guard and `release:verify-tag` steps after mise install and before Analyze, the upload step after Package with `retention-days: 1`, `if-no-files-found: error`, and the `sums_sha256` output. Every gate step stays unconditional. Rename the no-games, permissions and pin tests as named in the test map. The pin test and the no-games scan cover every file under `.github/workflows/`. Verify: the retargeted tests fail against the current single-file `ci.yml`.
- [ ] 4.2 Create `.github/workflows/gates.yml` (`on: workflow_call`, input `release_tag`, output `sums_sha256`, `permissions: contents: read`) holding today's CI steps unchanged plus the release-mode steps. Reduce `ci.yml` to its triggers, concurrency, `permissions: contents: read` and one `uses: ./.github/workflows/gates.yml` job. Pin `actions/upload-artifact` by full SHA (look up the current release's commit). The tag reaches scripts only through `env:`. Verify: `workflow_test.dart`, `no_games_scan_test.dart` and `qualification_audit_test.dart` pass and their rows flip green (the audit row stays green). Update README's CI section to name `gates.yml` and the `ci / ...` check name in the same task.

## 5. Release workflow

- [ ] 5.1 Write `test/tool/ci/release_workflow_test.dart`, covering the structure rows: triggers, jobs and `needs`, permissions per job, no checkout, `mise` or local-workflow step in a write job, `concurrency` `release-<tag>` without cancel, and that ci and release call the same gates file. Write `test/tool/ci/release_workflow_scripts_test.dart`, covering the preflight and publish script rows. It needs a test helper (`test/tool/ci/support/`) that extracts a named step's `run:` from the parsed YAML, writes a fake `gh` script that answers from per-test fixtures and logs its argv, and runs the step under `bash` with the step's `env:` and a temp working directory. Tag the scripts test `@Tags(['qualification'])` only if it exceeds a few seconds; otherwise keep it in the fast loop. Verify: both files fail because `release.yml` does not exist.
- [ ] 5.2 Create `.github/workflows/release.yml` per design D2, D4 and D5:
  - preflight: main-only dispatch, annotated tag via `git/ref/tags`, the `tag_object` output, and the paginated release listing;
  - gates: `uses: ./.github/workflows/gates.yml` with `release_tag`;
  - publish: download into an empty directory, exact file set, `sums_sha256`, `sha256sum -c`, the second listing, the tag re-read, POST draft → id, upload per file to that id, then `GET` id for exactly three `uploaded` assets and `PATCH` id `draft: false` with `make_latest`.

  Pin `actions/download-artifact` by full SHA, use timeouts of 15 min for preflight and publish, and keep `run:` scripts `set -euo pipefail` with no `${{ }}` inside. Verify: both 5.1 test files pass and their rows flip green; `mise run analyze` and `mise run test` pass.
- [ ] 5.3 Update README "Releases and changelog": add a Publish row (automatic on tag push), the "Retry or backfill" note (manual run from `main`, a tag with no release, delete a leftover draft first, `v0.4.0`/`v0.5.0` not backfillable), and the squash merge accepted by `release:tag`. Mark local `build:release`/`package:release` as optional pre-tag checks. Verify: `rg -n "release.yml|Retry or backfill|squash" README.md` shows each point, and every relative link in the section resolves.

## 6. Integration

- [ ] 6.1 Run `dart format .`, `mise run analyze` and `mise run test`, and `openspec validate publish-github-releases --strict`. Confirm every test map row is green except those marked n/a. Verify: all four commands exit 0 and `tasks.md` shows no `red` row.

## Workflow follow-up

- The PR's own CI run is the first real run of `gates.yml` through `ci.yml`; its check name changes to `ci / ...`.
- The first real release run is the next tag after merge: the M6 close prerelease (`mise run release:prepare -- 0.6.0-beta.1`, merge, `mise run release:tag`). That run is the end-to-end check of publish and of the squash path. It is agent-verifiable through the Actions run and the Releases page. Installing it is M6's user-verified criterion.
