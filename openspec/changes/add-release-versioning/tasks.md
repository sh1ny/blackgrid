# Tasks

## Test map

Test files: `test/tool/release/semver_test.dart` (S), `test/tool/release/prepare_test.dart` (P), `test/tool/release/tag_test.dart` (T), `test/tool/release/build_test.dart` (B), `test/tool/changelog_test.dart` (C), `test/ui/settings_dialog_test.dart` (U), `test/application/vision_self_check_test.dart` (V). The P, T and C tests drive real temporary git repositories, with a bare repo as `origin`. P and T stub only the gates, Flutter and `gh`. C runs the pinned `git-cliff` and fails with a message naming `mise run test` if it is not on `PATH`.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Release versions are strict increasing SemVer | Next minor version accepted | S | `0.2.0 after v0.1.0 is accepted` | red |
| Release versions are strict increasing SemVer | Prerelease ordering | S | `prerelease precedence: beta.2 and final follow beta.1` | red |
| Release versions are strict increasing SemVer | Version not increasing | S | `equal, lower or older-prerelease versions are refused naming latest tag` | red |
| Release versions are strict increasing SemVer | Malformed version | S | `v-prefix, missing patch, leading zeros and build metadata are refused` | red |
| Release preparation starts only from a clean, current main | Clean current main | P | `preconditions pass on clean main equal to origin/main` | red |
| Release preparation starts only from a clean, current main | Wrong branch or dirty tree | P | `wrong branch, modified or untracked file refuses with no change` | red |
| Release preparation starts only from a clean, current main | Behind or ahead of the remote | P | `local main differing from origin/main refuses naming both commits` | red |
| Release preparation starts only from a clean, current main | Remote unreachable | P | `fetch failure refuses with the fetch error and no change` | red |
| Release preparation starts only from a clean, current main | Release already started | P | `existing tag or release branch locally or on origin refuses` | red |
| Release preparation runs the offline gates before changing anything | Gates pass | P | `gates run in order analyze, format:check, test:all and preparation continues` | red |
| Release preparation runs the offline gates before changing anything | A gate fails | P | `failing gate stops with its name and code; branch, tree and history unchanged` | red |
| Release commit records the version and the changelog | Release commit created | P | `release commit changes only pubspec version and CHANGELOG section` | red |
| Release commit records the version and the changelog | Changelog generation fails | P | `changelog failure makes no commit and names branch and files to discard` | red |
| Changelog lists one entry per merged pull request | Merged PR with branch commits | C | `merged PR is one entry with title and number; branch commits absent` | red |
| Changelog lists one entry per merged pull request | PR title not conventional | C | `non-conventional PR title lands under Other` | red |
| Changelog lists one entry per merged pull request | Direct commit on main | C | `direct fix commit on main is listed once under Fixes` | red |
| Changelog lists one entry per merged pull request | Final release after prereleases | C | `final release folds prerelease sections` | red |
| Changelog lists one entry per merged pull request | Release notes and preview after a prerelease | C | `--latest and --unreleased use final-tag ranges after a final release` | red |
| Changelog lists one entry per merged pull request | Preview while a prerelease is the latest tag | C | `--unreleased while a beta is latest lists everything since last final tag` | red |
| Changelog lists one entry per merged pull request | Release commit and merge | C | `release commit and its merge are not listed` | red |
| Release tag marks the merged release commit | Release merge tagged | T | `release merge gets annotated tag pushed to origin` | red |
| Release tag marks the merged release commit | Main moved before the release merge | T | `first-parent mismatch refuses naming intervening commits` | red |
| Release tag marks the merged release commit | HEAD is not a release merge | T | `ordinary merge or non-merge HEAD refuses naming its subject` | red |
| Release tag marks the merged release commit | Pubspec disagrees with the release commit | T | `pubspec version mismatch refuses naming both versions` | red |
| Release tag marks the merged release commit | Push identity cannot be confirmed | T | `missing credential or other login refuses before any tag exists` | red |
| Release builds carry the version and a build number | Release build | B | `build passes build-name, commit-count build-number and version define, then bundle:check` (plus the real build in 6.2) | red |
| Release builds carry the version and a build number | Dirty tree | B | `dirty tree refuses before building naming files` | red |
| Release builds carry the version and a build number | Build number exceeds the file-version field | B | `count above 65535 refuses naming count and limit` | red |
| Release builds carry the version and a build number | Integrity check fails | B | `bundle:check failure fails the build with its output` | red |
| The running app reports its version | Release build shows its version | U | `settings dialog shows the given app version` | red |
| The running app reports its version | Development build | U | `settings dialog shows dev by default` | red |
| vision-runtime → Self-check report is complete and authoritative | Report contents | V | `report has format identity steps and result mirroring code` (extended with `appVersion`) | red |
| vision-runtime → Self-check report is complete and authoritative | Report names the build | V | `report records the given appVersion` | red |
| vision-runtime → Self-check report is complete and authoritative | Development build | V | `report appVersion defaults to dev` | red |
| vision-runtime → Self-check report is complete and authoritative | Report never partially written | V | `report is written to tmp then renamed; previous report survives a …` (existing) | green |

## 1. ADR and workflow rules

- [x] 1.1 Write `docs/adr/0009-release-versioning.md` (MADR-short, accepted, date of merge, source: this change's design D1-D10). Cover: the SemVer milestone scheme; the version only in release commits; build number = commit count, ≤ 65535; the first-parent per-PR changelog with prerelease folding; the local `release:prepare`/`release:tag`/`build:release` flow with the fenced push and credential-helper override; the `BLACKGRID_VERSION` define; data versions independent; tag deletion caveat. Add it to the in-force ADR table in `openspec/architecture.md`. Verify: the file exists, the index row links it, and `openspec validate add-release-versioning --strict` passes.
- [x] 1.2 Add two `context` lines to `openspec/config.yaml` (D9): conventional PR titles `type(scope): summary`, and the milestone-close suggestion of `mise run release:prepare -- <next minor>` (`-beta.N` first while user-only checks are open). Verify: `openspec instructions proposal --change add-release-versioning --json` shows both lines in `context`.
- [x] 1.3 Replace the roadmap's "Release versioning" section body with a short pointer to ADR-0009 and the `mise` tasks, keeping the anchor and the M2 "Do next" line. Verify: the roadmap links resolve (`grep -n "0009" openspec/roadmap.md`).

## 2. Changelog: one entry per PR

- [ ] 2.1 Write `test/tool/changelog_test.dart` (rows C). Build a fixture repo with `v0.1.0`, GitHub-shaped merges (`Merge pull request #N from o/b` + blank line + PR title) whose branches hold `task 1.1 …`, `amend specs`, `address review feedback` commits, a non-conventional PR title, a direct `fix:` commit, `v0.2.0-beta.1`, a `chore(release): v0.2.0` release branch merge tagged `v0.2.0`, and one later PR. Cover `--latest` with no previous final tag (range from the root). Run `tool/changelog.dart` as a process. Verify: the tests fail against the current `cliff.toml`/`changelog.dart` for the stated reason (branch commits listed, merges skipped).
- [ ] 2.2 Update `cliff.toml` (D2, D10): remove the `merge_commit` skip, add the GitHub-merge `commit_preprocessors` rule, the `chore(release)` and branch-only-subject skip parsers before the group parsers, and `ignore_tags` for prerelease tags. Settle the design's header Open Question (keep `# blackgrid Changelog` unless a fixture shows a reason). Verify: the C rows for grouping, skipping and folding pass.
- [ ] 2.3 Rewrite `tool/changelog.dart` (D1): two-stage `--context` → first-parent filter → `--from-context -`, explicit UTF-8, the allowlisted option split (unknown options exit 2), `--latest`/`--unreleased` translated to final-tag ranges by SemVer precedence (reuse `tool/release/src/semver.dart` from 3.2 or land that file first), and the unborn-`HEAD` path kept. Verify: all C rows green; `mise run release-notes -- --unreleased` on the real repo prints PR entries only.

## 3. Release preparation

- [x] 3.1 Write `test/tool/release/semver_test.dart` (rows S) and `test/tool/release/prepare_test.dart` (rows P), with injected gates and runner. Verify: they fail because `tool/release/` does not exist.
- [x] 3.2 Implement `tool/release/src/semver.dart` (strict SemVer 2.0.0 parse, §11 precedence, release versions reject build metadata). Verify: rows S green.
- [x] 3.3 Implement `tool/release/src/git.dart`, `tool/release/src/release_steps.dart` (`prepare`, D4 steps 1-11, with `--trailer` forwarding and ambient identity) and the `tool/release/release.dart` CLI (`prepare <version>`, usage errors exit 2). Add `mise` task `release:prepare` (`dart run tool/release/release.dart prepare`). Verify: rows P green; `mise run release:prepare -- 0.1.0` on this branch refuses (not on main) without changing anything.
- [ ] 3.4 Set `pubspec.yaml` to `version: 0.1.0` (the one-time baseline removal of `+1`, D9). Verify: `mise run analyze` passes and `flutter pub get` does not change `pubspec.lock`.

## 4. Release tagging

- [ ] 4.1 Write `test/tool/release/tag_test.dart` (rows T). Use a fixture repo and bare origin with a merged `chore(release): v0.2.0` branch and a stubbed `gh` (token + login). The test records every process invocation and asserts that each `fetch`, `ls-remote` and `push` argv carries `-c credential.helper=` and `-c credential.helper=!gh auth git-credential`. It also asserts that the stub token appears in no argv, no stdout or stderr output, and no exception message, and that a failed push deletes the local tag. Verify: the tests fail because `tag` does not exist.
- [ ] 4.2 Add `yaml: 3.1.4` as a direct dev dependency. Implement `tool/release/src/push_identity.dart` (D6) and the `tag` subcommand (D5, including the first-parent check and tag rollback), plus the `mise` task `release:tag`. Verify: rows T green; `mise run release:tag` on this branch refuses (not on main) and creates no tag.

## 5. Release build and app version

- [ ] 5.1 Write `test/tool/release/build_test.dart` (rows B, with Flutter, `vision:fetch` and `bundle:check` stubbed and a fixture repo for the count). In `test/ui/settings_dialog_test.dart` (rows U) and `test/application/vision_self_check_test.dart` (rows V), extend `report has format identity steps and result mirroring code` to expect `appVersion`. Verify: the new tests fail for the stated reasons, and the existing `report is written to tmp…` test still passes.
- [ ] 5.2 Implement the `build` subcommand (D7: clean tree, count ≤ 65535, `vision:fetch`, `flutter build windows --release --build-name --build-number --dart-define=BLACKGRID_VERSION=<version>+<count>`, then `bundle:check` on `build/windows/x64/runner/Release`) and the `mise` task `build:release`. Verify: rows B green.
- [ ] 5.3 Add `lib/application/app_version.dart` (`const appVersion = String.fromEnvironment('BLACKGRID_VERSION', defaultValue: 'dev')`). Add a `version` parameter to `SettingsDialog` (defaulting to `appVersion`) and show it in the dialog. Add `appVersion` to the self-check report through a parameter defaulting to the constant (D8: format stays 1). Verify: rows U and V green; `mise run analyze` clean.
- [ ] 5.4 Document the release flow in `README.md`: version scheme, the three `mise` tasks, `release-notes -- --unreleased`, and where the version shows. Verify: every command named there exists in `mise.toml`.

## 6. Baseline tag and integration

- [ ] 6.1 Ask the user to confirm, then create annotated tag `v0.1.0` on `cf02bb7` (tagger = the user's identity through `GIT_COMMITTER_*`) and push only that tag to `origin` through the fenced path (`gh auth token --user KintsugiBot`, identity verified, credential-helper override). Verify: `git ls-remote --tags origin v0.1.0` shows `cf02bb7`'s tag object.
- [ ] 6.2 After confirming with `tasklist` that `EscapeFromTarkov.exe` is not running (AGENTS.md; otherwise stop and leave this unverified), run `mise run build:release` on a clean checkout of this branch. Then run `blackgrid.exe --vision-self-check <report>` from the bundle with `Start-Process -Wait -PassThru`. Verify: `bundle:check` passes; the exe's `VersionInfo.FileVersion` is `0.1.0.<count>`; the report's `appVersion` is `0.1.0+<count>`; record the commands and outputs in the commit message.
- [ ] 6.3 Run `mise run release-notes` on the real history (with `v0.1.0` present). Verify: `v0.1.0` and Unreleased list one entry per merged PR (plus the frozen direct commits), and no `task`, `amend` or `address review feedback` line appears (`grep -E "task [0-9]|amend |review feedback"` finds nothing in the unreleased output).
- [ ] 6.4 Run `mise run analyze`, `mise run format:check` and `mise run test`. Verify: all three exit 0; every test-map row is green.

## Workflow follow-up

- Ship the PR with a conventional title (`feat(release): add release versioning`), run review and archive per Specwright.
- At M2 close, run `mise run release:prepare -- 0.2.0-beta.1` for the user-only checks, then `0.2.0` once the user reports them passed.
