# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer role; `review.cross_model: false` in openspec/specwright.yaml)
- **Reviewed:** proposal.md, specs/release-versioning/spec.md, specs/vision-runtime/spec.md (against openspec/specs/vision-runtime/spec.md), design.md; openspec/roadmap.md (Release versioning section), openspec/architecture.md, docs/adr/0007, docs/adr/0008, cliff.toml, tool/changelog.dart, mise.toml, pubspec.yaml, openspec/specwright.yaml, openspec/config.yaml, lib/ui/settings_dialog.dart, lib/application/vision_self_check.dart, lib/application/launch_mode.dart, windows/runner/Runner.rc, test/qualification/m2_vision_self_check_test.dart, flutter_tools 3.47.6 `cmake.dart`, `git log --first-parent main`, effective `credential.*` git config. Experiments with git-cliff 2.14.2 in scratch repos: (a) a fixture with a GitHub-style merge, branch commits, direct commits, a release branch and a PR merged while the release PR was open; (b) a bare scratch clone of this repo with `v0.1.0` on `cf02bb7`.

Experiment results that confirm design assumptions:
- `commit_preprocessors` see the full message (subject and body). D2's regex turns `Merge pull request #15 from sh1ny/feat/x\n\nfeat(release): add release versioning` into a Features entry `*(release)* add release versioning (#15)`. The D2 fallback is not needed.
- `--context` emits `releases[].commits[]` with full-SHA `id`s, already preprocessed and grouped. A filtered context piped to `--from-context -` renders with groups intact (no re-parse), and it honours `--output` and `--strip header`. `--tag v0.2.0` in stage 1 names the unreleased section. D1 works as described.
- The `^chore\(release\): v` message skip parser drops the preprocessed release merge (`chore(release): v0.2.0 (#18)`). The first-parent filter drops the release commit.
- On real history, the filtered pipeline gives a `v0.1.0` section of PR entries plus direct commits, and an Unreleased section with only `(#14)`.
- Flutter 3.47.6 turns `--build-name 0.2.0-beta.1 --build-number 120` into `FLUTTER_VERSION "0.2.0-beta.1+120"` and `FLUTTER_VERSION_BUILD 120` (`cmake.dart:32-60, 83-107`). Runner.rc:63-77 maps those to FILEVERSION and the version strings as D7 states.
- The qualification self-check test skips without `BLACKGRID_RELEASE_BUNDLE` and checks for the game first, so `test:all` inside `prepare` does not launch the app unguarded. It does not assert on unknown report keys, so D8 holds.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. A PR merged while the release PR is open ends up inside the tagged release, but not in the changelog committed for it. The design states the opposite.**
Design, Flow & State Gaps, "Main moves during `prepare`": "the PR merges a release commit whose changelog misses the newer PRs. Default: they appear in the next release." That is wrong. `tag` puts `v<version>` on the release merge `M`, and `M`'s first-parent line includes every PR merged before it. Reproduced in the fixture: release branch cut, then PR #17 merged to main, then release PR #18 merged and tagged `v0.2.0`. Regenerating lists `late fix (#17)` under `v0.2.0`. Consequences: (a) the `CHANGELOG.md` inside the `v0.2.0` tree omits a change that ships in the `v0.2.0` build; (b) the next release's regeneration silently rewrites the `v0.2.0` section; (c) `release-notes -- --latest` disagrees with the committed changelog. Nothing in `prepare` or `tag` detects the case. D5 accepts any merge whose second parent is a release commit. The spec's tag requirement has no scenario for it either.
Fix: in D5 and the spec, `tag` refuses unless the release commit's parent equals the merge's first parent (`R^1 == M^1`). That means main did not move between `prepare` and the merge. The message names the commits that came in between, and recovery is a new `prepare` (or a patch release). If the author prefers to allow it instead, correct the Flow & State Gaps text so it says the PRs land in this tag's section on regeneration, and that the committed changelog is then stale.

**M2. A prerelease uses up the milestone's changelog entries, so the final milestone release gets an empty section.**
The roadmap and D9 have `-beta.N` come first at a milestone close, with the final version "once the user reports them passed". git-cliff splits sections at every tag that matches `tag_pattern`, and that pattern accepts prereleases (cliff.toml). So `release:prepare -- 0.2.0` after `v0.2.0-beta.1` gets only the commits since the beta. That is usually nothing but the beta's release merge, which is skipped, so `## v0.2.0` has no entries (`render_always = true`). The M2 work stays listed under `v0.2.0-beta.1` for good. `release-notes -- --latest` for the milestone also prints nothing. No spec scenario or design section covers a final release that follows a prerelease.
Fix: decide and specify one behaviour. Option A: final releases fold earlier prereleases of the same version into their section, using git-cliff `ignore_tags` for prerelease tags when the requested version has no prerelease part. Verify how `--tag`/`ignore_tags` interact in task 2.x. Option B: keep separate beta sections, and accept and document that the final section lists only post-beta changes. Add a spec scenario for "final release after `-beta.N`" with an assertable THEN. Option A matches the roadmap's intent that the milestone version is the release.

**M3. The fenced push identity depends on one machine's global git config, so the spec's "push as the configured account" is not enforced by the tool.**
D6 sets `GH_TOKEN` in the child environment and relies on "Git's credential helper for `github.com` is `gh auth git-credential`". On this machine that holds only because `~/.gitconfig` resets the helper list with `credential.https://github.com.helper ""` after configuring `store` and Git Credential Manager as general helpers (`git config --show-origin --get-regexp credential`). On any setup without that URL-specific reset (another clone, another machine, a later gitconfig edit), `git push` asks `store`/GCM first. It then pushes as whatever account those return, while the `gh api user` check has already passed. That is the silent wrong-account push the CLAUDE.md fencing exists to prevent. The spec's "Push identity cannot be confirmed" scenario would still pass.
Fix: D6 runs the push (and preferably the `fetch`/`ls-remote` calls in `tag`) with command-line overrides that fix the helper list regardless of user config: `git -c credential.helper= -c "credential.helper=!gh auth git-credential" push origin refs/tags/v<version>` (the token stays only in the environment). Add a test that asserts the push argv carries the override and never the token.

### Suggestions

**S1. Decode and encode git-cliff's context explicitly as UTF-8 in `changelog.dart`.** Today the tool pipes bytes through `addStream`. D1 adds a decode, parse, re-encode round trip, and `Process.run`/`process.stdin` default to `systemEncoding`, a code page on Windows. The real repository's context already contains non-ASCII UTF-8 bytes in commit bodies (Python failed to decode it as cp1252 at byte 150219), and the project uses Cyrillic test paths. Pass `stdoutEncoding: utf8` and set `stdin.encoding = utf8`. Add a fixture commit with a non-ASCII PR title.

**S2. PR #1 and any unconventional direct commit render their whole body, trailer included.** On real history, the `v0.1.0` Other section shows `Merge pull request #1: reproducible …` followed by its body line and `Co-authored-by: KintsugiBot …` as loose lines. Either add a preprocessor for the `Merge pull request #(\d+): (.*)` shape (giving `$2 (#$1)`), or have the template render only the first line for unconventional commits.

**S3. Classify `changelog.dart` arguments with an allowlist.** D1 has to split the caller's arguments between stage 1 (selection) and stage 2 (render), including which flags take a value (`--tag X`, `-o X`, `--strip X`, positional ranges). An unknown or misclassified flag would be dropped or sent to the wrong stage without warning. Refuse unknown flags with a message, and test `release-notes -- --unreleased` and `--latest` through both stages.

**S4. Make the app-version scenarios testable under `mise run test`.** D7 and D8 read the compile-time `appVersion` const directly. Without a `--dart-define`, the default test run can only observe `dev`, so the "shows `0.2.0+120`" and "report `appVersion` is `0.2.0-beta.1+120`" THENs are not assertable offline. Inject the version, for example a `SettingsDialog`/self-check parameter that defaults to `appVersion`.

**S5. Spec text: "No other commit SHALL change the pubspec version."** This change itself changes `0.1.0+1` to `0.1.0` outside a release commit, and no mechanism enforces the rule. Scope it ("after this change") or rephrase it as a convention.

**S6. Add a spec scenario for the 65535 build-number refusal.** The requirement states it, but there is no failure scenario for it.

**S7. Tagger identity.** D4 states the commit identity comes from the environment, but D5 does not say which identity an annotated tag gets. State that `tag` (and the baseline `v0.1.0`) use the same `GIT_COMMITTER_*` environment (CLAUDE.md identity), so the public tag's tagger is deliberate.

### Re-check of Required Changes (round 1, second run)

This run re-checks only Required Changes 1-3 and whether the suggestion fixes introduced new problems. It read the edited design.md (Context, D1, D2, D5, D6, D7, D10, Flow & State Gaps, Mechanism Ledger) and specs/release-versioning/spec.md. Experiments: git-cliff 2.14.2 with `ignore_tags = '\Av[0-9]+\.[0-9]+\.[0-9]+-'` on a scratch fixture (`v0.1.0` → PR #2 → `v0.2.0-beta.1` release merge → PR #4 → `v0.2.0-beta.2` → `v0.2.0` release merge), plus `git credential fill` under `GIT_TRACE` with the D6 `-c` overrides.

- **RC1 (M1): satisfied.** D5 and the spec require that the release commit's first parent equals `HEAD`'s first parent. On mismatch, tagging is refused, naming the intervening commits (`git log --oneline <release^1>..HEAD^1`). The scenario "Main moved before the release merge" has an assertable THEN, and the Flow & State Gaps bullet and the Mechanism Ledger row are corrected. One wording nit, not blocking: the gap bullet's recovery says "close the release PR", but `tag` only runs after that PR has merged. The workable recovery is to delete `release/vX` locally and on `origin` (D4 step 5 refuses while it exists) and run `prepare` for the same version again. That works because `vX` is still untagged and the pubspec rewrite is idempotent.
- **RC2 (M2): partly satisfied. The full changelog is right; the release-notes paths are not.** D10 plus the spec scenario "Final release after prereleases" hold for full regeneration. With prerelease tags ignored, `--tag v0.2.0` lists PRs #2 and #4 under `v0.2.0` with no beta section. `--tag v0.2.0-beta.2` (a later beta's `prepare`) lists both under the beta, as D10 says. But the experiment shows git-cliff's range options still use ignored tags as boundaries:
  - After `v0.2.0` is tagged on its release merge, `git-cliff --latest` prints an **empty `## v0.2.0`** section. It takes the range from the last two tags (`v0.2.0-beta.2..v0.2.0`) and does not fold the betas. That is the exact consequence M2 named ("`release-notes -- --latest` for the milestone also prints nothing"), and D1's new allowlist explicitly forwards `--latest`.
  - After a beta tag, `--unreleased` (the roadmap's documented preview, `mise run release-notes -- --unreleased`) lists only post-beta PRs, with or without `--tag`. The next `prepare` writes the whole milestone, so the preview and the release disagree.
  - After a beta tag, plain `--latest` prints the beta's commits under an `Unreleased` heading.
  So D10's "git-cliff then treats prerelease tags as if absent" is true for full generation only. See Required Change 4.
- **RC3 (M3): satisfied in the design; the test sentence is missing.** D6 runs every network Git call of `tag` with `-c credential.helper= -c "credential.helper=!gh auth git-credential"`. Verified with `GIT_TRACE`: with these overrides, only the command-line helper runs. The user's `store`, Git Credential Manager and the URL-specific `credential.https://github.com.helper` are all cleared, because command-line config is read last and the empty value resets the list. The Context bullet no longer relies on the ambient chain. The rebuttal places the argv test in tasks.md, but tasks.md does not exist yet, and design.md (D6, Mechanism Ledger) does not state the test. See Required Change 5.
- **Suggestion fixes:** S1 (explicit UTF-8), S3 (allowlist, exit 2 on unknown options), S4 (version as a parameter defaulting to the constant), S5 (one-time baseline exception), S6 (65535 scenario) and S7 (tagger = `GIT_COMMITTER_*`) are applied and introduce no new problem, except that S3's allowlist forwards `--latest`/`--unreleased`, which RC2's residue affects. S2 is accepted as known residue in D2 (frozen `v0.1.0` history); accepted by reviewer.

### Re-check of Required Changes 4 and 5 (round 1, third run)

This run re-checks only Required Changes 4 and 5 and the RC1 wording fix. It read design.md D1, D6 and Flow & State Gaps, and the two new scenarios in specs/release-versioning/spec.md. Experiment: git-cliff 2.14.2 with D10's `ignore_tags` on the scratch fixture (`v0.1.0` → PR #2 → `v0.2.0-beta.1` → PR #4 → `v0.2.0-beta.2` → `v0.2.0` release merge), running the ranges D1 now produces.

- **RC4: satisfied.** D1 no longer forwards `--latest`/`--unreleased`; it turns them into ranges between final tags, and the spec adds "Release notes and preview after a prerelease" and "Preview while a prerelease is the latest tag". Verified:
  - `--latest` → `v0.1.0..v0.2.0 --tag v0.2.0` renders one `## v0.2.0` section with PRs #2 and #4 and no beta section.
  - `--unreleased` after the final tag → `v0.2.0..HEAD` renders an empty Unreleased section.
  - `--unreleased` with HEAD at `v0.2.0-beta.2` → `v0.1.0..HEAD` lists PRs #2 and #4 under Unreleased, including the one before `v0.2.0-beta.1`. The same result comes through the D1 `--context` → `--from-context -` pipeline.

  Both new scenarios hold.
- **RC5: satisfied.** D6 states the test: the recorded `fetch`, `ls-remote` and `push` argument lists each carry both `-c credential.helper` overrides, and the stubbed token appears in no argument list, stdout, stderr or exception message.
- **RC1 wording: fixed.** The Flow & State Gaps recovery now deletes `release/vX` locally and on `origin` and re-runs `prepare` for the same version.
- **Suggestion (non-blocking):** `--tag <latest final tag>` in the `--latest` translation is redundant. The range `v0.1.0..v0.2.0` alone already renders `## v0.2.0`, and passing `--tag` for an existing tag makes git-cliff log `WARN There is already a tag (v0.2.0) for <sha>` on stderr. Dropping `--tag` there avoids that noise. The "from the root when there is no previous final tag" case was not exercised; task tests should cover it.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (M1) design.md D5 and spec "Release tag marks the merged release commit": add the precondition that the release commit's first parent equals `HEAD`'s first parent. If they differ, tagging is refused with a message naming the intervening commits and the recovery (new `prepare`, or a patch release). Add a spec scenario "Main moved before the release merge" with that refusal. Rewrite the Flow & State Gaps bullet "Main moves during `prepare`" to match. **Re-check: done.**
2. (M2) Add a design decision, and a spec scenario under "Changelog lists one entry per merged pull request" (or "Release commit records the version and the changelog"), for a final release prepared after `v<X>-beta.N`. Choose Option A (fold prereleases into the final section) or Option B (separate sections, documented), with an assertable THEN. **Re-check: done for full generation (D10, scenario "Final release after prereleases"). The remainder is Required Change 4, re-checked: done.**
3. (M3) design.md D6: the tag push (and the `tag` subcommand's network git calls) runs with `-c credential.helper= -c "credential.helper=!gh auth git-credential"`, so the fenced `GH_TOKEN` is the only credential source whatever the user's git config. Replace the Context bullet that relies on the ambient helper. Add to the tests that the push argv contains the override and never the token. **Re-check: done; the test statement (Required Change 5) is re-checked: done.**
4. (M2 residue, outstanding) Make `--latest` and `--unreleased` consistent with D10, or stop offering them. For example, `tool/changelog.dart` translates `--latest` into the range `<previous final tag>..<latest final tag>` and `--unreleased` into `<latest final tag>..HEAD`, computed with D3's SemVer parser over final (non-prerelease) tags, with `--tag` still naming the section. Alternatively, remove `--latest`/`--unreleased` from D1's allowlist and document range usage in place of the roadmap's `release-notes -- --unreleased`. State the choice in D10 or D1. Add a spec scenario: "WHEN `v0.2.0-beta.1` and `v0.2.0` exist and the release notes for the latest release are requested, THEN every PR merged since `v0.1.0` is listed under `v0.2.0`". Optionally fix the Flow & State Gaps recovery wording from the RC1 nit. **Re-check (third run): done, verified with git-cliff 2.14.2; RC1 wording also fixed.**
5. (M3 residue, outstanding) design.md D6 (or the Mechanism Ledger row for the credential-helper override) states the test: the push, fetch and ls-remote argv contain the two `-c credential.helper` overrides, and neither argv nor any log contains the token. **Re-check (third run): done.**

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. A Critical/Moderate rebuttal counts only once marked "accepted by reviewer". -->
- M1: fixed. design.md D5 adds the first-parent precondition and its recovery; the Flow & State Gaps bullet "Main moves during `prepare`" is rewritten; the spec adds the requirement sentence and scenario "Main moved before the release merge"; a Mechanism Ledger row is added.
  - Reviewer: confirmed fixed.
- M2: fixed (Option A). New design.md D10: `ignore_tags` for prerelease tags folds betas into the final section. Spec scenario "Final release after prereleases" added; Mechanism Ledger row added.
  - Reviewer: fixed for full generation. `--latest` and `--unreleased` still treat prerelease tags as boundaries (reproduced); open as Required Change 4.
- M3: fixed. design.md D6: every network Git call of `tag` runs with `-c credential.helper= -c "credential.helper=!gh auth git-credential"` and the fenced environment; the Context bullet no longer relies on the ambient helper chain. The argv test is in tasks.md.
  - Reviewer: mechanism confirmed with `GIT_TRACE`. tasks.md does not exist yet, so the test is not recorded in any reviewed artifact; open as Required Change 5.
- S1, S3: fixed in D1 (explicit UTF-8; allowlisted option split, unknown options refused with exit 2).
- S2: accepted as known residue in D2 (frozen `v0.1.0` history).
  - Reviewer: accepted.
- S4: fixed in D7 (version passed as a parameter that defaults to the constant).
- S5: fixed in the spec (the one-time baseline exception).
- S6: fixed: spec scenario "Build number exceeds the file-version field".
- S7: fixed in D5 (tagger = ambient committer identity, set through `GIT_COMMITTER_*`).
- RC4: fixed. D1 no longer forwards `--latest`/`--unreleased`. `changelog.dart` turns them into ranges between final tags by SemVer precedence, and `--current` is removed. The spec adds the scenarios "Release notes and preview after a prerelease" and "Preview while a prerelease is the latest tag".
- RC5: fixed. D6 states the argv/output test: every `fetch`, `ls-remote` and `push` argv carries both overrides, and the token never appears in argv, stdout/stderr or exceptions.
- RC1 wording: the Flow & State Gaps recovery now deletes `release/vX` locally and on `origin` and re-runs `prepare` for the same version.
  - Reviewer (third run): RC4, RC5 and the RC1 wording fix confirmed. All Required Changes are satisfied.
