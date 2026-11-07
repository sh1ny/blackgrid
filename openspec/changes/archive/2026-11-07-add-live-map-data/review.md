# Review

## Metadata

- **Round:** 5
- **Prior round:** Round 3 FULL review identified M2, eager per-marker search amplification, and required two planning/test-plan changes. Round 4 verified both and recorded APPROVE_WITH_CHANGES with CHANGES_APPLIED: yes. Round 1's M1 incremental-budget finding was accepted at the planning gate in round 2; user-approved compact S7/D5 subsequently superseded only the prior expanded-runtime representation choice. No consecutive REVISE rounds.
- **Reviewer:** fresh-context subagent (OMP, CompactDesignReview), performing the requested wording-only recheck against the accepted Required Changes.
- **Reviewed:** Current `openspec/changes/add-live-map-data/specs/runtime-map-data/spec.md:50-102`, particularly the shortened requirements and expanded scenario clauses at lines 57-85; recorded round-4 `review.md`; retained compact/derived-state/publication/resource design in `design.md:208-240`; retained test-map row and task 4.6 in `tasks.md:18-26,88-94`. Prior FULL-review source and ADR context is preserved, not re-audited.
- **Skills:** The four requested skills were loaded from the supplied installed paths during the preceding FULL review: `F:/Dev/Dart/blackgrid/.claude/skills/dart-use-pattern-matching/SKILL.md`, `dart-write-documentation/SKILL.md`, `dart-add-unit-test/SKILL.md`, and `dart-run-static-analysis/SKILL.md`. No named skill was unavailable. Repository handwritten-fake, deterministic synchronization and lowest-complete-layer rules remain applicable. No workflow skill invoked.
- **Planning context:** Previously established repo-local planning root, with no referenced stores or unresolved references. No authoring transcript read.
- **Review boundary:** Planning-wording equivalence only. No tests, builds, analyzer, formatting, command execution, implementation verification, app/game interaction, captures or process-memory inspection. No validation result independently exercised. Only this scratch result file was written.

This verdict covers the reviewed wording and retained Required Changes. Other subsequent proposal/spec/design edits, except an edit confined to the proposal's Release Notes section, void it.

## Findings

### Critical (blocking)

None from the preceding FULL review; no new audit performed.

### Moderate

**M2 — Remains resolved at the planning/design gate.** The concise requirements and existing scenario clauses retain both Required Changes:

- The compact requirement still mandates direct normalization into shared immutable facts and lightweight references through serialization, cache loading and publication, local reads, unchanged shared parser/frozen offline bytes, and no quest-tracking scope. Its Shared facts remain local and complete scenario expressly retains complete source/derived facts, optional-field absence, logical marker/source identities, quest/objective/item relationships, business identities distinct from pool references, and no recursive occurrence copies or network reads. Moving this specificity into the scenario does not remove it.
- Shared searchable facts remain compact still requires real publication and search within an injected budget without per-marker flattened full-fact strings, preserving searchable fields, geometry exclusions, case-insensitive substring/phrase and comma-separated OR semantics. The retained Derived consumer state paragraph in `design.md` additionally preserves unknown source facts and cross-scalar-space matches, inventory ownership/retirement, stale-result fencing and current-query-only memoization.
- The shortened bounded-data requirement retains 256 MiB materialized and 64 MiB serialized limits, conservative reservation before allocation across the pipeline, derived state, transient buffers, overlapping generations, charging shared ownership/references and full copies, non-expanding unchanged search semantics, inventory retirement and no past-query cache. The existing overflow scenario now explicitly names distinct facts, reference/marker collections, derived search/projection/metadata state, transient buffers and expanded intermediates; rejection precedes oversized allocation/copy/serialization and persistence/publication, reports a resource failure and preserves durable/active authority or bundled fallback. The retained design clarifies accounting once per actual owned fact representation plus every reference slot; this is not a discount for copied references or expanded intermediates.
- The red test-map row and task 4.6 still require the actual `MapController` publication/search repeated-task regression and distinct-derived-state overflow/authority preservation at model/controller layers. Full frozen-source runtime qualification remains a separate scenario and mapped test. No passing test or completed implementation is inferred from these plans.

The wording change introduces no new decision and does not reopen M2.

### Suggestions

None from the preceding FULL review; no new audit performed.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **M2 — Derived consumer representation, ownership and budget: verified retained.** The concise runtime requirements, explicit shared-search and overflow scenarios, and retained design cover shared/non-expanding search, complete semantics, generation ownership, query-cache bounds, pre-allocation accounting and unchanged authority on rejection under unchanged caps.
2. **M2 — Actual publication/search regression plan: verified retained.** The mapped red tests and task 4.6 retain fitting shared-task publication/search and distinct-derived-state overflow/authority-preservation cases. The separate complete-frozen qualification requirement remains intact.

CHANGES_APPLIED: yes

## Rebuttals

- **M2:** Round 4's acceptance remains valid for the reviewed wording clarification. Both Required Changes remain applied at the planning gate; no waiver or substantive reversal was introduced.
- **Prior M1:** Its accepted incremental-budget contract remains in force. Compact S7/D5 supersedes the former expanded-runtime choice, not complete facts/source identities, the 256 MiB/64 MiB limits, or byte-identical frozen offline output.
- **Implementation boundary:** This review does not establish that compact implementation or regressions are complete, that any test passes, or that the previously reported full-source runtime resource failure is fixed.

## Post-review revision (2026-11-07)

The user directed a simplification after the materialization budget rejected the complete baseline dataset on repeat refreshes. S7 and D5 were revised: the compact fact pool, the runtime codec and the 256 MiB/64 MiB budgets were removed, the cache stores only the six source bodies and validators and is re-derived on load, and M2's budgeted shared-search requirement no longer applies (search keeps its existing per-marker representation). This revision edits the proposal, spec and design, so it voids the verdict above. It has not been re-reviewed.
