# Review

## Metadata

- **Round:** 4 (behaviour-change amendment from pre-ship finding F1)
- **Prior round:** 3, `APPROVE`
- **Reviewer:** fresh-context subagent (Claude Code); recorded by the orchestrator through `review-run.sh record`, because the reviewer writes no `review.md` itself.
- **Round 4 scope:** the uncommitted `git diff -- openspec/changes/adopt-proposal-release-notes/ docs/adr/0029-release-notes-come-from-each-proposal.md`. `prepare` now also refuses a collapsed summary that starts with `#`: the spec adds the scenario "Summary starting with a heading", D3 and ADR-0029 are reworded, and the test map gains a row. F2 (an archived proposal missing at `HEAD`) was checked for context.
- **Round 4 read:** the diff; spec.md "Release notes are built…", "A change without valid release notes is still listed" and "Release preparation requires a release summary"; design.md D3, D7, Failure & Visibility and Resource Bounds; `tool/release/src/verify_tag_step.dart` `_section`; `tool/release/src/release_steps.dart` (`_versionHeading`, `_anyHeading`, insert); `tool/release/src/release_notes.dart` (`readReleaseRange`, `_changeLines`); `README.md` and `tool/release/release.dart` help. `openspec validate adopt-proposal-release-notes --strict` passes.
- **Skills:** the request named none, and none were loaded.

### Round 3 metadata (kept)

- **Round:** 3 (structure-only re-check)
- **Prior round:** 2, `APPROVE`
- **Reviewer:** fresh-context subagent (Claude Code)
- **Round 3 scope:** the uncommitted `git diff -- openspec/changes/adopt-proposal-release-notes/`. Round 2's amendment pushed the requirement "Proposals carry release notes in a fixed format" past `openspec validate --strict`'s 500-character limit. To fix that, the parenthetical "(a heading with no items is allowed when another heading has items, as in specwright's `release.sh notes --proposal`)" was moved out of the requirement into a new scenario, "Empty heading beside items". The tasks.md test map gained a row for it, which points at the existing test "an empty heading beside one with items stays valid".
- **Round 3 read:**
  - the diff (specs/release-versioning/spec.md and tasks.md);
  - `test/tool/release/release_notes_test.dart` (the helpers `_valid` and `_texts`, and the tests "headings with no item at all" and "an empty heading beside one with items stays valid");
  - `.claude/skills/specwright-release/scripts/release.sh` lines 1110-1130.
  - The reviewer also ran `openspec validate adopt-proposal-release-notes --strict`, which passes.
- **Skills:** the request named none, and none were loaded.

### Round 2 metadata (kept)

- **Round:** 2 (drift re-check of one apply-time amendment)
- **Prior round:** 1, `APPROVE_WITH_CHANGES`; its Required Changes 1-4 were re-checked and applied (`CHANGES_APPLIED: yes`)
- **Reviewer:** fresh-context subagent (Claude Code)
- **Round 2 scope:** only the amendment that makes the empty-heading rule match specwright's `release.sh notes --proposal`. In `release.sh`, an empty `### Added` beside a `### Fixed` with items is valid; the section is invalid only when it has no item at all. The owner chose parity with `release.sh`, as design D1 and the Mechanism Ledger row "Dart parser matching `release.sh notes --proposal`" already require.
- **Round 2 read:**
  - `git diff -- openspec/changes/adopt-proposal-release-notes/ docs/adr/0029-release-notes-come-from-each-proposal.md openspec/config.yaml`;
  - specs/release-versioning/spec.md ("Proposals carry release notes in a fixed format" and its scenarios), tasks.md 2.1, design.md (Context line 23, Mechanism Ledger lines 154-155, Risks line 164) and proposal.md;
  - ADR-0029's Decision section;
  - `.claude/skills/specwright-release/scripts/release.sh` `parse_release_notes` (lines 1062-1129);
  - `tool/release/src/release_notes.dart` and `test/tool/release/release_notes_test.dart` (the tests "headings with no item at all" and "an empty heading beside one with items stays valid");
  - a grep of the change, ADR-0029, `openspec/config.yaml`, `README.md` and `openspec/roadmap.md` for any remaining statement of the old per-heading rule.
- **Skills:** the request named none, and none were loaded.

### Round 1 metadata (kept)

- **Round 1 prior run:** none (this run re-checks only the four Required Changes of the round 1 APPROVE_WITH_CHANGES review)
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

### Round 4 (pre-ship F1 amendment)

#### Critical (blocking)

None.

#### Moderate

**M5. The design and spec did not describe the F2 fallback.** *(Resolved, see Rebuttals.)* The Failure & Visibility "Range reader" row said a git error or a proposal over 64 KB stops `prepare` with the leftover-branch instructions, contradicting Resource Bounds, D7 and the F2 fix (`cat-file -e` fails → the change is kept with `missing: true`). The requirement "A change without valid release notes is still listed" covers the behaviour (listed, warned, never stops the release), but no scenario stated the name-only line for a proposal that cannot be read at `HEAD`, so the F2 regression test mapped to nothing. A clarification, not a behaviour change; also round 1's S6 with a concrete consequence.

#### Suggestions

**S7.** ADR-0029's parenthetical "(a leading heading would end the section)" is imprecise: only a leading `## ` does; say that `## v…` would also read as a version heading, and that any leading `#` is refused for simplicity. *(Applied.)*

**S8.** `README.md`'s Prepare row and `tool/release/release.dart`'s `--summary` help do not mention the `#` rule; the refusal message should name the rule so a summary like `#69 brings…` is easy to fix. *(Applied.)*

**On the boundary:** `#` is right. `## ` is the minimum for correctness (`_section` ends on `## `; `_versionHeading` matches `^## v`), but a leading `# ` would be an H1 in the published body and `### ` would look like the D1 subheadings. The only false positives are summaries opening with a PR reference such as `#69 …`, which are rare and easy to fix. The amendment is consistent across the spec requirement, the new scenario, D3, ADR-0029 and the test map; "Multi-line summary file" still holds because its `##` is not leading.

### Round 3 (structure-only re-check)

**Critical:** none. **Moderate:** none. **Suggestions:** none.

Checks, all passed:
- **The rule means the same as in round 2.**
  - The requirement still says "with at least one item in the section as a whole". "As a whole" already applies the count to the section, not to each heading.
  - "Holding only list items" holds for an empty heading, since an empty heading holds no other line.
  - The removed parenthetical's content is now the new scenario's WHEN/THEN, so no rule was lost, and no new rule was added.
- **The new scenario agrees with the requirement and with "Invalid section".**
  - "Empty heading beside items" (an empty `### Added` and a `### Fixed` with one item) has one item in the section as a whole, so the requirement accepts it.
  - "Invalid section" refuses only "headings with no item at all". That is the opposite case, so the two scenarios do not overlap.
  - The THEN, "as specwright's `release.sh notes --proposal` does", matches `release.sh:1130`, where the section is refused only when `not any(items.values())`.
- **The test asserts the scenario.**
  - `release_notes_test.dart:150-157` parses `### Added` with nothing under it, then `### Fixed` with `- y`.
  - `_valid` expects a `ReleaseNotes` result, not `ReleaseNotesInvalid`, so the check succeeds.
  - `items.keys == ['fixed']` and the `fixed` texts `== ['y']` prove that only the Fixed item is reported.
  - The test sits beside the invalid case "headings with no item at all" (`:144-148`).
  - The tasks.md row names this test, and its status is `green`.
- **Validation.** `openspec validate adopt-proposal-release-notes --strict` passes.
- **No other drift.** The diff changes only these lines. The findings of rounds 1 and 2 stand.

### Round 2 (drift amendment)

**Critical:** none. **Moderate:** none.

**Suggestions:**

**S7 (not blocking). The scenario's "for each error" does not match `release.sh` in one case.** `release.sh` adds "no list item under Added, Changed, Fixed or Removed" only when no other body error exists (`release.sh:1123`, `if not any(items.values()) and not body_errors`). The Dart parser does the same (`release_notes.dart`, `bodyErrors == 0`). So a section whose only heading is `### Security` gets one error, not two. The section is still refused, and the error printed names the real cause, so the THEN "checking it fails, naming the line and the problem for each error" holds in practice. A later spec edit could say so; nothing needs to change now.

Consistency checks, all passed:
- **Spec.** The requirement now reads "with at least one item in the section as a whole (a heading with no items is allowed when another heading has items...)". That matches `release.sh:1123` and `release_notes.dart`. The scenario's "headings with no item at all" names the same condition, and the parenthetical rules out the per-heading reading. A section with a summary and no `###` heading at all is also invalid, both under "one or more of" and under the release.sh/Dart check.
- **Design.** D1/Context line 23 ("the Dart parser follows the same rules so both accept the same sections") and the Mechanism Ledger row now agree with the spec. Before the amendment they contradicted it. design.md never stated the per-heading rule, so it needs no edit.
- **Tasks.** 2.1 names "headings with no item at all", with the empty-beside-items case staying valid. Both cases exist as tests (`release_notes_test.dart:141`, `:147`). The valid case expects `items.keys == ['fixed']`, which matches `release.sh` dropping empty headings from `items`.
- **ADR-0029.** The Decision bullet says "with at least one item in the section (an empty heading beside one with items is allowed, as in `release.sh`)". This is the same rule. The ADR is part of this unmerged change, so amending it in place is appropriate.
- **No leftovers.** A grep for "no items", "no item", "empty heading" and "at least one item" finds no remaining statement of the old rule in the change, ADR-0029, `openspec/config.yaml`, `README.md` or `openspec/roadmap.md`. The `rules: proposal:` entry in `openspec/config.yaml` gives the format without a per-heading item count, so it does not conflict.
- **No other drift.** The amendment touches no line outside this rule, so round 1's findings and their resolutions still stand.

### Round 1

#### Critical (blocking)

None.

#### Moderate

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

#### Suggestions

**S1. The specwright skills don't run `release.sh notes --proposal` here.** They run it only when `release.enabled` is true (`specwright-commit` SKILL.md:33), and it is false. Context now says so. The Risks bullet "the authoring check stays `release.sh`" still reads as if they did.

**S2. The "100+ archived proposals" count was wrong.** The archive holds 33. D6 now says 33.

**S3. The PR number is lost when an archive lands outside the PR's merge commit.** For example, `fix-changelog-spec` was archived after #60 merged. Flow & State Gaps now covers this case.

**S4. The GitHub body edits sit outside the change lifecycle.** They happen after merge, so no tracked task covers them. This is still true. Not required.

**S5. A release with only direct commits on main is refused.** The spec and design now say so explicitly.

**S6 (new, from this re-check, not blocking). The "Range reader" row is stale.** The row in Failure & Visibility still says a git error stops `prepare` "with the leftover-branch instructions (`release_steps.dart:109-114`)". Under the new D3 order the range is read before `checkout -b`, so on that path no branch exists, and the message would tell the user to discard a branch that was never created. Change the recovery cell to "refuses before the gates; nothing is changed", and leave the leftover message to the `CHANGELOG.md` write.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

CHANGES_APPLIED: yes

Round 4 approves the `#` refusal as written, with two required clarifications for the F2 fallback (applied, see Rebuttals).

Round 3 approves the restructure. The empty-heading rule means the same as in round 2. The new scenario agrees with the requirement and with "Invalid section", and the mapped test asserts it.

Round 2 approved the drift amendment. It is consistent across the spec, design, tasks and ADR-0029, it matches `release.sh` and the Dart parser, and it leaves no statement of the old rule. Round 1's verdict was APPROVE_WITH_CHANGES, and its Required Changes were applied and re-checked (see Rebuttals).

## Required Changes

Round 4 (all applied):

1. (M5) design.md, Failure & Visibility: reword the "Range reader" row (a git error refuses before the gates and changes nothing; no leftover-branch instructions; drop "or a proposal over 64 KB"), and extend the "Fallback" row to an archived proposal missing at `HEAD` or over 64 KB → listed under `Changes:` by name only, with a warning.
2. (M5) spec.md, "A change without valid release notes is still listed": add a scenario "Proposal not readable at HEAD" (change `d`, PR #83, proposal absent at `HEAD` → `- d (#83)` under `Changes:`, a warning names `d`, the release is not stopped) and its test map row.

Round 3: none. Round 2: none. Round 1 (all applied):

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


## Rebuttals

- **Round 4 Required Change 1 (M5): fixed by the orchestrator.** The "Range reader" row now reads "Git error | `prepare` refuses before the gates and before the branch exists; nothing is changed; the preview exits non-zero". The "Fallback" row covers "archived proposal over 64 KB or no longer at `HEAD` (reverted or moved) | Listed under `Changes:` (by name and PR only when the proposal was not read)". This also closes round 1's S6.
- **Round 4 Required Change 2 (M5): fixed by the orchestrator.** spec.md adds the scenario "Proposal not readable at HEAD" with the reviewer's WHEN/THEN. tasks.md maps it to "a proposal deleted on main is listed under Changes and warned, not fatal" (release_notes_test.dart), which asserts `Changes:
- gone (#1)` and the warning `gone: the archived proposal is no longer at HEAD (reverted or moved)`. ADR-0029's D7 bullet now says the same. `openspec validate --strict` passes.
- **Round 4 S7, S8: applied.** ADR-0029's parenthetical is reworded as suggested; README's Prepare row, the `release.dart` usage and the refusal message name the `#` rule (the message suggests "PR #69", not "#69").

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
