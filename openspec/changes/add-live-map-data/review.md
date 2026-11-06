# Review

## Metadata

- **Round:** 2
- **Prior round:** Round 1 approved with changes; M1 was the sole Moderate finding, with two Required Changes, not yet reviewer-verified. No Critical findings or Suggestions were recorded.
- **Reviewer:** fresh-context subagent (OMP, MetadataBudgetRecheck).
- **Reviewed:** Required-change recheck only: recorded `openspec/changes/add-live-map-data/review.md`; amended `design.md` and `specs/runtime-map-data/spec.md`; `proposal.md` and the modified `prepared-map-packs` and `map-marker-popups` capability deltas as dependencies/context; original amplification evidence in `tool/maps/quest_markers.dart:126-194` and `lib/maps/prepared_map.dart:651-653,777-783`; `AGENTS.md:18-41`; current OpenSpec review instructions/template and planning context. Planning root is repo-local; `openspec context --json` reports no referenced stores. All six requested skills loaded from the exact installed paths supplied: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis, flutter-add-widget-test and codebase-design. No authoring transcripts read. No tests, builds, analysis, formatting, app/game launches or implementation verification performed. No files other than this scratch review written.

## Findings

### Critical (blocking)

None recorded in round 1; no new audit performed.

### Moderate

**M1 — Resolved at the planning/design gate.** The original finding remains valid evidence about the existing implementation: quest markers embed complete task/objective/location details once per emitted position (`tool/maps/quest_markers.dart:126-138,148-194`), and immutable marker conversion recursively copies those details (`lib/maps/prepared_map.dart:651-653,777-783`). The amended contract now addresses that amplification rather than relying on transfer caps or elapsed time.

- **Explicit budgets:** `specs/runtime-map-data/spec.md:57-66` specifies 64 MiB serialized normalized output and 256 MiB conservatively accounted recursively materialized marker data, with incremental enforcement before oversized copies or serialization. Both fitting and overflowing candidates have assertable scenarios.
- **Pre-allocation enforcement across stages:** `design.md:218` places injectable counters at the shared normalizer's runtime entry point, charges every repeated occurrence rather than deduplicating shared references, includes container/entry/scalar overhead and UTF-16 string storage, and reserves before subtree construction/copying and immutable `PreparedMarker` conversion. It explicitly accounts for overlapping temporary copies. JSON UTF-8 bytes, including escaping and punctuation, are counted through a bounded sink before allocating the complete encoding. Equivalent guards cover cache deserialization, isolate handoff, storage preparation and publication conversion; stored payload size is checked before decode. This directly covers the recursive-copy and serialization paths identified in M1.
- **Failure and authority:** `design.md:209,218,224-226` requires rejection before transaction/publication, a visible resource failure, retention of last-good/fallback and existing active markers, and bounded normalized durable payloads. The runtime overflow scenario (`specs/runtime-map-data/spec.md:64-66`) expressly preserves prior durable and active authority or bundled fallback. Existing coherent publication remains described in `design.md:200`; there is no new partial-publication path.
- **Fidelity and decision consistency:** User-chosen D5 and its summary (`design.md:94-100,118`) retain the existing representation and frozen offline output rather than introducing a compact-format cutover. `design.md:194,198,218,256` retains candidate-source fidelity and byte-identical frozen reproduction; expanded-data limits are resource failures, not historical content/count gates. This is consistent with the proposal and the two modified capability dependencies.

### Suggestions

None recorded in round 1; no new audit performed.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **M1 — Expanded-inventory contract: verified applied.** `design.md:209,218,224-226` and `specs/runtime-map-data/spec.md:57-66` now provide explicit serialization/materialization limits, incremental pre-copy/pre-encoding enforcement, cache/handoff/publication coverage, resource-error visibility and unchanged durable/active authority on failure. Frozen output and candidate-source fidelity remain protected.
2. **M1 — Regression plan: verified applied.** `design.md:257` requires a small synthetic task with many positions sharing larger task/objective/location records, injected small budgets, and assertions at the normalizer/store seam that rejection precedes oversized recursive materialization or encoding and commit. It explicitly preserves previous durable and active authority, adds a fitting-candidate success case, and uses handwritten fakes without sleeps or app launch. This is the lowest complete test layer for the reported defect, consistent with `AGENTS.md:27-39`.

CHANGES_APPLIED: yes

## Rebuttals

Both round-1 M1 Required Changes are accepted as fixed in the amended planning artifacts by this reviewer. No rebuttal or waiver was needed. This result verifies the required design/specification edits only; it does not claim implemented budget enforcement or passing regression tests. Prior review context is preserved, and no unrelated concern has been added.
