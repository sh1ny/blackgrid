# Review

## Metadata

- **Round:** 2 — required-change recheck only.
- **Prior round:** Round 1 recorded APPROVE_WITH_CHANGES and CHANGES_APPLIED: no; M1 required an explicit automated validation map for the new metadata refresh branch. S1 requested clarification of the real-data audit's timing.
- **Reviewer:** fresh-context subagent (omp, MetadataDesignRecheck), independent of the planning author and prior reviewer.
- **Reviewed:** `openspec/changes/fix-frozen-map-metadata/review.md`; current `openspec/changes/fix-frozen-map-metadata/proposal.md`, `design.md` and `specs/prepared-map-packs/spec.md`; `AGENTS.md`; `tool/maps/pack.dart:1159-1238,1480-1620,2210-2318`; `tool/maps/calibration.dart:100-155`; `test/support/map_preparation_fixtures.dart:310-415`; `test/maps/map_preparation_test.dart:260-425`; and `test/maps/map_preparation_qualification_test.dart:1290-1572`. The source ranges establish the existing semantic validator, reviewed-volume check, fixture deficiency, ordinary-marker controls and refresh lifecycle; they are not a review of an implemented metadata branch.
- **Project skills:** Loaded all four supplied installed skill files: `.claude/skills/dart-add-unit-test/SKILL.md`, `.claude/skills/dart-run-static-analysis/SKILL.md`, `.claude/skills/dart-use-pattern-matching/SKILL.md`, and `.claude/skills/dart-write-documentation/SKILL.md`. No named skill failed to load. No Specwright workflow skill was invoked.
- **Planning context:** `openspec list --json` resolved `root.path` to `F:/Dev/Dart/blackgrid`. `openspec context --json` returned no referenced stores or unresolved references. Used the FULL review instructions and Review template returned by `openspec instructions review --change fix-frozen-map-metadata --json`.
- **Scope:** Rechecked only Required Changes/M1 and associated S1 ordering clarification. This is the reviewer recheck of the same conditional verdict, not a new full architecture review. The prior review's assessments outside those items are not independently recertified here. No author transcripts or reasoning were consulted.
- **Evidence boundary:** Static planning/source inspection only. No acquisition, generation rebuild, builds, checks, tests, static analysis, formatting, GitHub operations, commits, app/game/process inspection or GUI interaction. The saved diagnostic REST comparison and its reported live-source facts were not independently verified. The newly named tests and audit remain apply-time work; this review confirms their planned coverage, not execution or success. Only the designated scratch review file was written.

## Findings

### Critical (blocking)

None within the scoped recheck.

### Moderate

**M1 — Resolved by the planning correction.**

The current `design.md:88-114` now supplies an explicit scenario-to-check map for all eleven added spec scenarios, names the intended test files and distinguishes focused projection/admission/preservation tests from full refresh qualification. It no longer relies on the existing ordinary-refresh suite to establish the new branch's safety.

The disposition is supported by the existing source:

- `prepareMarkers` checks a reviewed volume only while adding a present marker (`tool/maps/pack.dart:1518-1531`); disappearance can therefore bypass the current check. The new plan explicitly pairs direct removed/changed/lost-ownership comparisons with a real metadata-refresh disappearance regression before promotion (`design.md:104,112`).
- The full-map fixture includes `calibrationFor` results but lacks the reviewed Interchange switch (`test/support/map_preparation_fixtures.dart:330-335,383-401`). The plan now requires the exact console identity, position, height band and outline, preserving the calibration assignment and existing ordinary-marker controls (`design.md:109`). Those facts are available in `tool/maps/calibration.dart:114-146` and the focused console test in `test/maps/map_preparation_test.dart`.
- Candidate validation recomputes markers through `prepareMarkers` (`tool/maps/pack.dart:1194-1203`). The plan appropriately retains that production check while adding independently specified projection facts, semantic corruption mutations and a separate independent real-pack audit, rather than treating a shared parser as independent proof.

The exact required-change disposition appears below. No required planning correction remains open.

### Suggestions

**S1 — Resolved: source check, internal validation and independent audit are explicitly ordered.**

`design.md:75` now distinguishes three checks:

1. Before calling refresh, the disposable orchestrator checks the acquired source for the reported Reserve/Streets records.
2. Inside refresh, production source-to-candidate validation and preservation finish before promotion.
3. After refresh returns, the independent all-map audit uses the exact returned active generation, recording its id, source hashes, mismatches and empty coverage before merge. Audit failure blocks delivery/merge.

This matches the existing single-call lifecycle: `refreshActive` rebuilds, reports, stages assets, promotes, replaces assets, prunes and deletes the candidate before returning (`tool/maps/pack.dart:2259-2300`). The clarification does not pretend the independent audit runs before promotion, require access to the deleted candidate, or add a callback or duplicate real-pack rebuild. `design.md:114,175` separately binds the audit and owner judgment to the generation; the user is not assigned automated integrity assertions.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

The required planning edits have been applied and independently rechecked. This retains Round 1's conditional verdict with its required change satisfied; it is not a claim that implementation, automated checks, the real-pack audit or the generation-bound owner check have passed. Later changes to proposal, specs or design outside the review rules require renewed review.

## Required Changes

1. **M1: Applied and accepted by reviewer — add the validation/scenario map before tasks are generated.** Each part of the original correction is now recorded:
   - **Independent boss projection fixtures:** `design.md:71-73,96,98,100-101` covers boss-wide versus location chance, independently specified preserved facts across distinct maps, translated names, repeated occurrences, explicit empty arrays, absent/wrongly typed structures, malformed identifiers/dictionaries/coordinates/chances and nullable-height controls. Ordinary optional-category, null and unavailable-name behavior remains explicitly unchanged.
   - **Semantic candidate mutations:** `design.md:99,111` covers missing, extra, wrong-map and same-count fact corruption, including mob/name/location/coordinate/rate changes. Required outer hashes are updated so the regression reaches semantic validation rather than passing merely because integrity validation rejects a stale hash.
   - **Successful full metadata refresh and a valid reviewed fixture:** `design.md:94,102,109-110` requires all supported maps, the exact reviewed Interchange console volume without deleting or weakening its calibration, a non-boss change as well as a boss change, independently asserted facts, complete preserved map/output comparisons, changed-map/owner reporting, returned generation identity, pointer/pubspec replacement and pruning. The existing Icebreaker helipad and ordinary controls are retained.
   - **Admission and preservation refusal:** `design.md:95,97,103-104,108,112-113`, together with the source/map/property diagnostics specified in the delta and `design.md:71,181-183`, covers forbidden paths/URLs/non-replacement hashes/source records, missing or duplicate supported identities, altered evidence, preserved artifact/property drift and removed/changed/lost reviewed ownership. Qualification failures preserve pointer/pubspec/generation inventory; failures after rebuilding name and retain the candidate. The plan chooses pure comparison functions over already-valid artifact structures for preservation cases unreachable through public refresh inputs, and a real refresh disappearance case proves the gate's placement. No generic candidate-injection API is introduced (`design.md:61,112`).
   - **Existing behavior and failure ordering:** `design.md:113` retains ordinary-refresh qualification and the omitted-argument behavior, prechecks, candidate retention, existing failure wrapper and post-promotion recovery paths. Earlier admission failures leave no promotable candidate; metadata errors after rebuild begins use `MapPackRefreshFailure`. The existing implementation's prechecks and recovery distinctions remain the lifecycle reference (`tool/maps/pack.dart:2248-2250,2301-2318`), not a newly promised filesystem-wide transaction.
   - **Independent audit versus owner check:** `design.md:65,75,114,175` records the source-derived all-map multiset audit separately from the generation-bound human presentation/source-versus-game judgment. Automated malformed-input, preservation, corruption and refresh-state checks are not delegated to the user. S1's source-check → internal pre-promotion validation → returned-generation audit ordering is explicit.

These dispositions accept a planning and test-plan correction only. They do not authorize artwork, calibration, runtime or CLI expansion, and they do not reverse a user-owned decision.

CHANGES_APPLIED: yes

## Rebuttals

No rebuttal was needed. M1 is fixed in the current design and accepted by this reviewer on the evidence above; S1 is likewise clarified and accepted. There are no outstanding required changes within this recheck's scope.
