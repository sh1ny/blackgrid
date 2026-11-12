# Review

## Metadata

- **Round:** 2
- **Prior round:** Round 1 approved with required changes; its reviewer re-check recorded those changes applied. The current artifacts subsequently add the unknown trader-requirements contract.
- **Reviewer:** fresh-context subagent (omp, openai-codex/gpt-6.1-sol)
- **Reviewed:** Current OpenSpec review instructions and context; `AGENTS.md`; `openspec/changes/add-task-rules/{proposal.md,design.md,tasks.md,review.md,specs/task-availability/spec.md,specs/task-catalog/spec.md}`; main `task-catalog` specification; relevant architecture entries; ADRs 0003, 0004, 0041, 0042 and 0043; `packages/blackgrid_progress/lib/blackgrid_progress.dart`; relevant catalog, parser, progress, availability, evaluator and edition sources under `lib/src/`; rule, fixture and edition tests; relevant parse/JSON tests and test builders; frozen fixture provenance and requirement-field summaries; package isolation audit and `mise.toml` test commands.
- **Skills loaded:** `dart-use-pattern-matching`, `dart-write-documentation`, `dart-add-unit-test`, `dart-run-static-analysis`, from the four requested installed `SKILL.md` paths. None failed to load.
- **Re-check (Required Changes only):** Same fresh-context reviewer, 2026-11-12. Read the recorded round 2 `review.md` and current proposal, design, task-availability specification and tasks. Re-checked only M3 Required Changes 1 and 2: the fixture-proof wording, retained gate coverage, owner-approved S4 clarification, design D8 and decision summary, test-map description and task 6.1 mapping. No broader review was performed.

This is a design/contract review, not implementation verification. Tasks 6.1/6.2 remain pending and are not represented as implemented or passing. No implementation, build, analyzer, tests, formatters, app launches or game interaction ran. OpenSpec context reports no referenced stores.

## Findings

### Critical (blocking)

None.

### Moderate

**M3. The frozen-data acceptance contract includes uncertainty cases that the unchanged excerpt cannot exercise.** *Resolved in the Required Changes re-check.*

The original round 2 finding concerned the task-availability requirement “Rules are proved on frozen tarkov.dev data”: it required each gate to have a case drawn from the excerpt, and its scenario explicitly included “each unchecked kind.” That included `OtherRequirementUnknownType`, `PrerequisitesUnknown`, and the newly specified `TraderRequirementsUnknown`.

The committed excerpts contain only `dialogue` and `globalVariable` other-requirement types. All 40 regular tasks and all 39 PvE tasks have trader-requirement and prerequisite lists; neither excerpt contains an unknown prerequisite status. Consequently, synthetic player progress alone cannot produce these catalog-uncertainty reasons from those unchanged tasks.

The existing proof strategy deliberately did something different: `test/fixtures/tarkov_dev/SOURCE.md`, “Coverage and preservation,” assigned unknown types and malformed/absent fields to synthetic boundary tests to preserve provenance. `task_rules_gates_test.dart` did this for existing uncertainty cases; tasks 6.1/6.2 correctly planned the new null-trader-list regression at that layer. Task 4.2's fixture coverage enumerated actual data-backed gate kinds instead of every unchecked kind.

**Original consequence:** the proposed test map could be completed while the stated frozen-data acceptance scenario remained unmet. Satisfying that scenario literally would require changing the claimed-real fixtures or a different source excerpt, contrary to the preservation contract. This was a contract/test-map mismatch, not an objection to the synthetic regression or a claim that pending work was missing unexpectedly.

**Re-check:** The specification now explicitly separates unchanged real data-backed gate cases from small synthetic unknown, malformed, absent-field and input-boundary cases. Its scenario retains every data-backed gate enumerated by task 4.2. Proposal S4 records the owner's approval; the proposal's frozen-fixture bullet, design D8, S4 summary and tasks' test-map introduction agree. The introduction explicitly assigns task 6.1's null-versus-empty trader-list boundary to the synthetic proof layer. Both Required Changes are satisfied; no M3 issue remains open.

### Suggestions

None.

The prior round's substantive changes remain represented in the design: non-conflicting seasonal-capable `ProgressMode`, sound unset-loyalty comparisons, the owner-confirmed edition entry, transitive fixture references, unknown-delay visibility and copied catalog fields. The new list-level `TraderRequirementsUnknown` fits ADR-0042's null-versus-empty distinction and ADR-0043's additive reason vocabulary. Its planned precedence and tests are consistent with the rest of the contract. These are retained conclusions from the full round 2 review, not additional re-check scope.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **(M3)** Resolve the fixture-proof contract explicitly. In `specs/task-availability/spec.md`, under “Rules are proved on frozen tarkov.dev data,” require unchanged real excerpt cases for the data-backed gate kinds enumerated by task 4.2, and require small synthetic catalog/progress tests for unknown, malformed, absent-field and input-boundary cases. Replace the scenario's unrestricted “each unchecked kind” wording with that distinction. Preserve real-fixture coverage for global-variable, dialogue, delay, prestige and reputation gates, and preserve the edition test using the real task plus reviewed edition table.
   - **Resolved; accepted by reviewer.** The revised requirement mandates a committed unchanged regular/PvE excerpt with source URLs and fetch date, real cases for data-backed gates, and synthetic tests for unknown/malformed/absent-field and input-boundary cases without fabricated source facts. The revised scenario explicitly retains level, loyalty, prerequisites including failed and active, alternatives, faction, game mode, edition, global variable, dialogue, delay, prestige and reputation. Design D8 and the test-map introduction expressly retain the real edition task plus reviewed table.
2. **(M3)** Carry the same boundary-case distinction into proposal S4, design D8 and the corresponding test-map description, including the synthetic null-versus-empty trader-list regression in task 6.1. Because S4 is user-chosen, obtain the owner's decision before changing that commitment if the exception changes its intended scope; record the approved clarification in the decision entry and summary. Do not fabricate unknown source fields to satisfy the old wording or silently reduce actual gate coverage.
   - **Resolved; accepted by reviewer.** Proposal S4 records the owner's approval on 2026-11-12 and states that actual gate coverage is unchanged. The proposal's What Changes fixture bullet makes the same real-versus-synthetic distinction. Design D8 explicitly covers synthetic unknown types, malformed/absent fields and input boundaries, names task 6.1's null-versus-empty trader list and forbids fabricated excerpt cases. The S4 decision-summary row records the owner clarification. The tasks' test-map introduction preserves task 4.2's data-backed coverage and explicitly maps task 6.1 to the synthetic boundary layer; task 6.1 still specifies null versus empty, coexistence with a checked failure and omission for started/done tasks. This confirms the proof contract and mapping only, not implementation of that pending regression.

CHANGES_APPLIED: yes

## Rebuttals

M3: Fixed in the specification's frozen-data requirement/scenario, proposal S4 and fixture bullet, design D8 and S4 summary, and tasks' test-map description. Owner approval is recorded in the decisions. Both fixes were re-checked and accepted by the reviewer; no Required Changes remain outstanding.
