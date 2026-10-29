# Review

## Metadata

- **Round:** 1 (re-check of Required Changes)
- **Prior round:** Round 1 full review: VERDICT: APPROVE_WITH_CHANGES, CHANGES_APPLIED: no. It found no Critical issue and one Moderate: `Not for you` mislabelled a non-FIR copy of a FIR obligation. It made one Required Change (a state label, a scenario, the `remaining` rule and a design line) and four Suggestions.
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:** openspec/changes/polish-requirement-rows/review.md (round 1), specs/requirement-rows/spec.md, design.md (Current State, D5), proposal.md (state list only, for consistency); lib/domain/decision_engine.dart (`_need`, lines 140-270); `openspec validate polish-requirement-rows --strict` (valid).

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

Re-check of Required Change 1, item by item:

1. **Own state label: applied.** The new requirement "An irrelevant row says why it does not count" labels a found-in-raid task or hideout row with more than 0 remaining `Needs found in raid`. The case is not found in raid, but the obligation stands. Checked against `decision_engine.dart`:
   - The engine returns `irrelevant` with `remaining` set only on the FIR branch: `r.foundInRaid == true && fir == FirState.no`, reached after `remaining` > 0.
   - A gate exclusion returns `remaining` 0.
   - Optional objectives, crafts and barters return `irrelevant` with `remaining` null.
   - So the three irrelevant labels for obligations, and `Not for you`, cannot overlap.
2. **Scenario: applied.** The scenario "Non-FIR copy of a FIR obligation" asserts `Needs found in raid`, not `Not for you`, and `2 remaining`. It is assertable.
3. **`remaining` rule: applied.** "Rows show quantities only when they mean something" now lists "needs found in raid" among the states that show `N remaining`. This matches the scenario.
4. **Design line: applied.** D5 has a "FIR-only exclusion" bullet. It names `state == NeedState.irrelevant`, `remaining > 0`, `requirement.foundInRaid == true` and the task or hideout kind, and cites the gate's `remaining` 0 (`decision_engine.dart:163-166`). It states that no decision logic or message parsing moves into the UI (ADR-0001).

**The split.** "Each row tags its kind and states its need in plain words" keeps the kind tags, the four non-irrelevant labels, the rule that no raw state or kind name is shown, and the "Unknown progress" and "Actionable task" scenarios. It points to the next requirement for irrelevant rows. The new requirement holds:
- the `Optional use`, `Optional objective` and `Not for you` labels;
- the "Craft row state" and "Gate excludes the player" scenarios;
- the new FIR scenario.

The meaning is the same. The only change is the FIR carve-out that was asked for. Strict validation passes.

### Critical (blocking)

None.

### Moderate

1. **Round 1 Moderate 1 (non-FIR copy of a FIR obligation labelled `Not for you`): resolved.** See the re-check above.

### Suggestions

1. **Round 1 Suggestions 1-4: still open, not required.**
   - Hideout title source and the old-projection hideout test.
   - `N remaining` whole-count formatting.
   - "Newly inspected item" defined by item id. The spec's "A new item starts collapsed" scenario already says "a different item".
   - The optional-objective reason-line wording, deferred to change 7.

   These are the author's call.
2. **New: the proposal's state list is stale.** `proposal.md:17` lists the human states without `Needs found in raid`. The spec governs, so nothing breaks. Fixing the proposal now, outside its Release Notes section, would void this verdict, so the safer path is to leave it and keep the spec authoritative. An implementer working from the proposal alone would miss one label, and the spec's scenario catches that.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. In `specs/requirement-rows/spec.md` and design.md D5, label the non-FIR copy of a FIR obligation `Needs found in raid`, add its scenario, show `N remaining` for that state, and name the fields the row function uses. Re-checked: applied correctly.

CHANGES_APPLIED: yes

## Rebuttals
