# Review

## Metadata

- **Round:** 4
- **Prior round:** Round 3 FULL review recorded APPROVE_WITH_CHANGES with CHANGES_APPLIED: no: M2 was the sole Moderate finding, with two Required Changes addressing eager per-marker search amplification. No Critical findings or Suggestions. Round 1's M1 budget finding was accepted as resolved at the planning gate in round 2; the user-approved compact S7/D5 subsequently superseded the earlier expanded-representation choice. No consecutive REVISE rounds.
- **Reviewer:** fresh-context subagent (OMP, CompactDesignReview), performing the requested focused required-change recheck.
- **Reviewed:** Recorded round-3 `openspec/changes/add-live-map-data/review.md`; amended `design.md:200-250`, including Derived consumer state and Resource Bounds; amended compact/search scenarios and bounded-data requirement in `specs/runtime-map-data/spec.md:50-108`; amended test-map row and task 4.6 in `tasks.md:12-28,84-94`. Prior FULL-review artifact/source/ADR context is retained, not independently re-audited in this focused round.
- **Skills:** All four named skills were loaded from the exact supplied installed paths during the preceding FULL review: `F:/Dev/Dart/blackgrid/.claude/skills/dart-use-pattern-matching/SKILL.md`, `dart-write-documentation/SKILL.md`, `dart-add-unit-test/SKILL.md`, and `dart-run-static-analysis/SKILL.md`. No named skill was unavailable. Repository handwritten-fake, deterministic synchronization and lowest-complete-layer constraints remain applicable. No workflow skill invoked.
- **Planning context:** The preceding FULL review established this checkout as planning root and no referenced stores or unresolved references. No authoring transcript read.
- **Review boundary:** Planning changes only. No implementation verification, tests, builds, analyzer, formatting, commands, app/game interaction, capture or process-memory inspection performed in this recheck. Only this scratch result file was written.

This verdict covers the reviewed contents and verified Required Changes. Other subsequent proposal/spec/design edits, except an edit confined to the proposal's Release Notes section, void it.

## Findings

### Critical (blocking)

None recorded in round 3; no new audit performed.

### Moderate

**M2 — Resolved at the planning/design gate.** Both Required Changes are applied in the reviewed artifacts.

1. **Derived-state representation, ownership and budgets are explicit.** The new Derived consumer state paragraph in `design.md` requires replacing eager per-marker flattened `searchText` with shared fact-aware search or bounded traversal over shared segments. It preserves the existing searchable scalar facts, unknown task/source facts, geometry exclusions, case-insensitive substring/phrase and comma-separated OR behavior, expressly including matches across scalar-separating spaces. This addresses the actual downstream expansion reported in round 3 rather than merely making nested map access local.

   The same paragraph makes normalized text/segments inventory-generation-owned, limits query memoization to the current query, retires derived state with the generation and fences stale results. It requires pre-allocation charges for normalized strings, segment/reference collections, query metadata, projections and transient buffers, including retained old/new generations, under the unchanged 256 MiB cap. Oversized distinct derived state rejects before durable commit or activation. The Resource Bounds section repeats the shared-budget and no-per-occurrence-flattening obligations. The amended `runtime-map-data` resource requirement makes derived search/projection/metadata storage, transient buffers, overlapping generations, retirement and nonaccumulating query caches normative. Neither approved cap nor frozen offline output changes.

2. **The regression plan reaches real publication and search.** The added Shared searchable facts remain compact scenario is assertable: many positions share one large searchable task fact; actual publication and search remain within an injected materialization budget without full-fact strings per marker, while preserving inclusion/exclusion and matching semantics. Its test-map row names `test/maps/map_controller_test.dart` and `test/domain/map_marker_query_test.dart`, with shared-search compactness and distinct-derived-fact authority-preservation coverage marked red, not claimed as passing.

   Revised task 4.6 explicitly requires real `MapController` publication/search with that fixture and a distinct-derived-state overflow case, pre-allocation guarding of derived state, and genuine-oversize authority-preservation regressions before implementation. Combined with the normative resource requirement's rejection-before-persistence/publication and unchanged last-good/active authority, this covers the requested fitting and rejecting paths at the lowest complete model/controller layers. Existing deterministic handwritten-fake constraints remain in force. The separate complete-frozen-runtime qualification scenario and test-map row remain separate acceptance, not a substitute for the synthetic amplification regression.

### Suggestions

None recorded in round 3; no new audit performed.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **M2 — Specify and budget derived consumer state: verified applied.** The new design paragraph, amended Resource Bounds and normative runtime-data requirement explicitly cover compact search representation, semantics, inventory ownership/invalidation, query-cache bounds, pre-allocation accounting, overlapping generations and pre-commit/pre-activation failure under unchanged limits.
2. **M2 — Exercise actual publication/search: verified applied.** The added normative scenario, red test-map row and revised task 4.6 require the real publication/search amplification regression and distinct-derived-state overflow/authority-preservation coverage. Full frozen-source qualification remains separate.

CHANGES_APPLIED: yes

## Rebuttals

- **M2:** Accepted as fixed in the planning artifacts by this reviewer. No waiver or rebuttal needed. This does not assert that compact search, its accounting or the regressions have been implemented or passed; compact implementation remains the parent's subsequent work.
- **Prior M1:** Round 2's accepted planning resolution remains historical context. Incremental budget enforcement, unchanged 256 MiB/64 MiB caps, complete facts/source identities and byte-identical frozen offline output remain required. User-approved compact S7/D5 supersedes only the former expanded-runtime representation choice. The previously reported full-fixture resource failure is not recertified or declared fixed here.
