# Review

## Metadata

- **Round:** 1 (re-check of Required Changes 1-4)
- **Prior round:** none (this run re-checks only the four Required Changes of the round 1 APPROVE_WITH_CHANGES review)
- **Reviewer:** fresh-context subagent (Claude Code)
- **Reviewed:** Round 1 read openspec/changes/adopt-proposal-release-notes/{proposal.md, design.md, specs/release-versioning/spec.md}, together with:
  - main specs: openspec/specs/release-versioning/spec.md and openspec/specs/release-publishing/spec.md;
  - ADRs: docs/adr/0009-release-versioning.md and docs/adr/0026-releases-published-by-a-tag-workflow.md, plus the openspec/architecture.md index;
  - release tooling: tool/changelog.dart, cliff.toml, tool/release/release.dart, tool/release/src/release_steps.dart and tool/release/src/verify_tag_step.dart;
  - configuration and the workflow: mise.toml, .github/workflows/release.yml, openspec/config.yaml, openspec/specwright.yaml, and the Release Notes rules in openspec/schemas/specwright/schema.yaml and templates/proposal.md;
  - CHANGELOG.md, including `git show v0.6.0-beta.1:CHANGELOG.md`;
  - tests: test/tool/release/prepare_test.dart and test/tool/release/verify_tag_test.dart;
  - specwright references: .claude/skills/specwright-release/SKILL.md and scripts/release.sh, and .claude/skills/specwright-commit/SKILL.md;
  - files `git grep` found that mention git-cliff or the changelog tasks: README.md and openspec/roadmap.md;
  - read-only git: `git tag`, the first-parent log, and the D4 range command run on real history.

  This re-check re-read proposal.md, design.md and specs/release-versioning/spec.md, and checked only Required Changes 1-4.

  The skills dart-add-unit-test and dart-run-static-analysis were not loaded, because they were not needed for these findings. The upstream specwright ADR 0015 was not read; the installed release.sh and SKILL.md served as the reference format.

## Findings

### Critical (blocking)

None.

### Moderate

**M1. When `prepare` builds the notes is inconsistent, and the gates may run before a "nothing to release" refusal.** *(Resolved, see Rebuttals.)*
- The Failure & Visibility table refused "nothing to release" before the branch was created.
- The sequence diagram, and the MODIFIED scenario "Changelog generation fails", built the section after `checkout -b`, which is today's step 9 (`tool/release/src/release_steps.dart:107-136`). That is also after `test:all`, the full suite with the qualification tier included (`mise.toml:21-23`).
- So a release with nothing in range was refused only after the longest gate, and possibly with a branch left behind.

**M2. The impact list omitted `test/tool/release/verify_tag_test.dart:259-293`.** *(Resolved.)*
- That test copies `cliff.toml` and runs `tool/changelog.dart --tag ... --output`. It is the fixture proof that ADR-0026 cites for `prepare`'s beta heading, so deleting `cliff.toml` breaks it.
- The impact list also left out the stale references in `README.md` (lines 105, 167 and 353-372) and in `openspec/roadmap.md:74`.

**M3. The release summary had no normalization rule.** *(Resolved.)*
- `verify-tag` cuts a section at any `## ` line (`verify_tag_step.dart:121-129`).
- A summary file with such a line would silently truncate the published GitHub notes.
- The 600-character count was also ambiguous for newlines.

**M4. The hand-edited GitHub release bodies contradicted `release-publishing` and the State table.** *(Resolved.)*
- `release-publishing` ("Release notes are the version's changelog section") requires the body to equal the tagged commit's `CHANGELOG.md` section. The State table also named that section as the body's authoritative copy.
- The new v0.6.0-beta.1 body would have existed in no file in the repository.

### Suggestions

**S1. The specwright skills don't run `release.sh notes --proposal` here.** They run it only when `release.enabled` is true (`specwright-commit` SKILL.md:33), and it is false. Context now says so. The Risks bullet "the authoring check stays `release.sh`" still reads as if they did.

**S2. The "100+ archived proposals" count was wrong.** The archive holds 33. D6 now says 33.

**S3. The PR number is lost when an archive lands outside the PR's merge commit.** For example, `fix-changelog-spec` was archived after #60 merged. Flow & State Gaps now covers this case.

**S4. The GitHub body edits sit outside the change lifecycle.** They happen after merge, so no tracked task covers them. This is still true. Not required.

**S5. A release with only direct commits on main is refused.** The spec and design now say so explicitly.

**S6 (new, from this re-check, not blocking). The "Range reader" row is stale.** The row in Failure & Visibility still says a git error stops `prepare` "with the leftover-branch instructions (`release_steps.dart:109-114`)". Under the new D3 order the range is read before `checkout -b`, so on that path no branch exists, and the message would tell the user to discard a branch that was never created. Change the recovery cell to "refuses before the gates; nothing is changed", and leave the leftover message to the `CHANGELOG.md` write.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (M1) design.md: state that `prepare` reads the range and builds and validates the section in memory before the gates. This covers the range read, parsing, the bounds and the "nothing to release" refusal. Only the pubspec edit and inserting the section into `CHANGELOG.md` happen after `checkout -b`. Update the sequence diagram to match. In the spec, the "No change archived since the last release" refusal comes before any gate, and "Changelog generation fails" covers failures while writing `CHANGELOG.md`.
2. (M2) proposal.md Impact and design.md:
   - add `test/tool/release/verify_tag_test.dart`, with its beta-heading contract test rewritten to use the new builder or insert and to run `verify-tag`;
   - add `openspec/roadmap.md`;
   - make `README.md` an unconditional entry.
3. (M3) In the spec's summary requirement:
   - collapse the summary to one line and trim it;
   - apply the 600-character limit and the blank check after collapsing;
   - add a multi-line summary-file scenario in which a `## ` line does not cut the section that `verify-tag` publishes.
4. (M4) In design.md D8, the State & Ownership table and the ADR-0029 contents:
   - record the one-time, owner-approved exception to `release-publishing` for the v0.6.0 and v0.6.0-beta.1 bodies, and where their authoritative copies live;
   - keep the beta.1 body in the repository.

CHANGES_APPLIED: yes

## Rebuttals

- **Required Change 1 (M1): fixed, verified by reviewer.**
  - D3 now has an "Order inside `prepare`" paragraph (design.md:43): first the summary checks, then the preconditions, then the in-memory build and validation from `HEAD` (range, parsing, bounds and the nothing-to-release refusal), then the gates. Only the pubspec edit and the `CHANGELOG.md` insert come after `checkout -b`.
  - The sequence diagram (design.md:103-110) matches that order.
  - The Failure & Visibility "Notes builder" row says the refusal comes before the gates and before the branch.
  - In the spec, "No change archived since the last release" now refuses "before any gate runs, and no branch, file or commit is created".
  - The kept scenario name "Changelog generation fails" now has the WHEN "writing the built section into `CHANGELOG.md` fails after the branch was created". That satisfies the requirement; keeping the name for `openspec validate` is accepted.
  - A minor stale cell remains in the "Range reader" row; it is noted as S6 and does not block.
- **Required Change 2 (M2): fixed, verified by reviewer.**
  - proposal.md Impact lists `test/tool/release/verify_tag_test.dart`, with its beta-heading contract test building the section with the new builder and running `verify-tag`, which keeps ADR-0026's proof.
  - Impact lists `README.md` without a condition, naming the prerequisites, the tooling table and the release section, and lists `openspec/roadmap.md` (the `release-notes -- --unreleased` line).
  - design.md Risks adds the matching bullet.
- **Required Change 3 (M3): fixed, verified by reviewer.**
  - The requirement "Release preparation requires a release summary" collapses every whitespace run, newlines included, to one space and trims the ends.
  - It refuses before any gate when the collapsed result is missing, blank or over 600 characters. The "too long" scenario says "601 characters after collapsing".
  - The new scenario "Multi-line summary file" asserts a one-line summary `Raid timers arrive. ## Not a heading`, and that `verify-tag` publishes the whole section with its grouped items.
  - D3 records the same rule and its reason (`verify_tag_step.dart:121-129`).
- **Required Change 4 (M4): fixed, verified by reviewer.**
  - D8 records the one-time, owner-approved exception to `release-publishing` for the v0.6.0 and v0.6.0-beta.1 bodies. The requirement still governs every publish.
  - D8 names the authoritative copies: the v0.6.0 section of `CHANGELOG.md` on main, and `release-bodies/v0.6.0-beta.1.md`, archived in this change's directory.
  - The State & Ownership row for the GitHub release body names those approved texts.
  - The ADRs section says ADR-0029 records the exception and where the copies live.
  - proposal.md Impact calls it "a recorded one-time exception to `release-publishing`".
