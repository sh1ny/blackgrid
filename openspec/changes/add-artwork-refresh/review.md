# Review

## Metadata

- **Round:** 1 (first FULL review of the simplified revision), with a required-change-only recheck of M1 on 2026-11-05; no new full review round.
- **Prior round:** None for this revision; the discarded design's review and tasks were not used as acceptance criteria.
- **Reviewer:** Fresh-context subagent (OMP, openai-codex/gpt-6.1-sol); required-change recheck by SimplifiedArtworkRecheck.
- **Reviewed:** Original full review: current `openspec/changes/add-artwork-refresh/proposal.md`, `design.md`, and `specs/prepared-map-packs/spec.md`, including the final shortened requirement paragraphs; canonical `openspec/specs/prepared-map-packs/spec.md`; accepted ADR-0005, ADR-0033 and ADR-0034; `tool/maps/prepare.dart`; relevant input, acquisition, builder, validation, reporting, preservation and publication sections of `tool/maps/pack.dart`; `tool/maps/calibration.dart`; `tool/maps/inventory.dart`; `lib/maps/prepared_map_loader.dart:44-152`; relevant fixture and lifecycle tests in `test/maps/map_generation_inputs_test.dart`, `map_preparation_qualification_test.dart`, `map_toolchain_test.dart`, and `test/support/map_preparation_fixtures.dart`; map command declarations in `mise.toml`; `AGENTS.md` Dart/Flutter and map-toolchain sections. This recheck read the original scratch review and `design.md:186-188`, specifically the revised final Validation Map paragraph, against M1 only. It does not repeat the full review or extend its scope.
- **Project skills loaded:** `dart-add-unit-test`, `dart-run-static-analysis`, `dart-use-pattern-matching`, and `dart-write-documentation`, each from its supplied `.claude/skills/<name>/SKILL.md` path. All four were loaded successfully again for this recheck, together with `AGENTS.md`. Their execution workflows were not run. No named skill was unavailable.
- **Planning context:** `openspec list --json` again resolved the planning root to this checkout. The original review's `openspec context --json` reported no referenced stores or unresolved references; this limited recheck did not repeat that context query.
- **Evidence boundary:** Static source/planning review only. No tests, builds, analysis, formatting, network acquisition, application/process inspection, or game interaction ran. The proposed tests and smoke runs are not execution evidence.

## Findings

### Critical (blocking)

None. The simplified stage/build/validate/report/explicit-publication approach is feasible against the existing pipeline without a new preview, onboarding or approval framework.

### Moderate

**M1 — The final owner-check paragraph narrows an in-force contract without identifying that change. — RESOLVED on required-change recheck.**

The following preserves the original finding and its supporting evidence; it describes the wording before correction, not the current paragraph.

Location: `design.md`, Validation Map, paragraph formerly beginning “Per existing change report and repository policy”.

The paragraph said the owner checks maps before merge “only when there are visual changes.” That is narrower than the canonical requirement **One command rebuilds and promotes the committed pack**, which requires the owner's check when anything except `toolchain` changes. Its **Manifest values change without a file change** scenario explicitly requires that check. ADR-0033's rebuild/report decision preserves this boundary, and ADR-0034 plus the canonical **Metadata-only refresh preserves prepared artwork and calibration** requirement keep the owner check for changed metadata even when artwork is unchanged.

This distinction is observable in the implementation: `packChangeReport` accounts for marker/map/pack values and evidence output hashes (`tool/maps/pack.dart:2115-2259`); `refreshActive` emits the owner-check instruction whenever `report.changed` is true, including its metadata branch (`pack.dart:2824-2836`). The qualification test for changed marker metadata explicitly expects “Metadata changed” and “owner must check” (`test/maps/map_preparation_qualification_test.dart:1726-1810`). These are original-review evidence references, not source reinspection during this limited recheck.

**Original consequence:** Applying the former design literally could suppress an existing owner-check instruction for metadata, calibration/manifest or evidence-only changes, or mark that responsibility inapplicable solely because no visible artwork difference was demonstrated. This conflicts with the stated preservation of existing workflows. It does not justify introducing an image gate: successful no-change/evidence-only CLI staging and disposable publication can remain entirely automatic, and owner review before merge is a separate responsibility.

**Recheck disposition:** Resolved by `design.md:188`. The paragraph now explicitly preserves the report and before-merge owner duty for anything except the toolchain record, including metadata, manifest and evidence-only changes; exempts true no-change/toolchain-only outcomes; and separates that responsibility from automatic staging/publication success without adding an image, checklist, acknowledgement or user gate. An applicable exact-generation owner result is recorded or left waiting only if repository-active assets actually change during apply. Repository-active publication is not required merely to complete the tooling change. This satisfies M1 without reversing the approved simplified publication decision. No outstanding requirement remains for M1.

### Suggestions

None requiring another mechanism or broader scope.

The following original feasibility conclusions constrain the approval; they are not claims that the implementation already exists and were not reopened by this M1-only recheck:

- **Hidden global dependencies are real and the proposed context addresses the material ones.** The builder currently writes global `artworkNotices` and `sourceLock` (`pack.dart:773-785`) and compares frozen calibration with current `calibrationFor` (`pack.dart:994-1003`). Consequently merely adding a fresh fetch command would break the promised pending-configuration compatibility. D1 correctly requires an explicit context and migration of every caller, including raw rebuild/normalize, `_rebuildActive`, and metadata renewal. Existing candidate validation already derives geometry/floors from carried calibration (`pack.dart:1286-1360`), so generation-owned reproduction does not require a second builder. Remaining canonical inventory/default source-path lookups are consistent with the explicitly limited supported-inventory promise; arbitrary future inventory migration is not promised.
- **Retaining six sources needs a selective acquisition path.** `acquireInputs` currently fetches all six (`pack.dart:376-389`). It cannot be reused unchanged. The design names all six retained paths and keeps fresh interactive metadata separate from those marker/task/trader snapshots. Admission must bind the configured pinned repository evidence as described, not merely reuse the existing acquisition helper's mutable Interchange URL and append revision labels (`pack.dart:390-394`). The existing hash check alone is not the whole planned admission check.
- **Generation verification and fresh admission are different checks.** `verifyCommittedGeneration` verifies the manifest identity and output closure (`pack.dart:2040-2054`); it does not admit bytes against current source locks. Candidate validation checks carried evidence, geometry and reproduction rather than current repository hashes. D1/D2's explicit current-configuration admission for fresh staging/publication and frozen context for old offline/metadata workflows are therefore necessary, not interchangeable. Existing synthetic qualification fixtures are appropriate for deterministic validation/transaction permutations but do not prove real source admission.
- **New-map handling is bounded and actionable.** Current `interactiveMetadata` uses `singleWhere` and produces no authored integration guidance (`calibration.dart:293-306`). The planned supported-identity diagnostics must therefore be implemented deliberately rather than inherited from that function. Comparing discovery identities against the baseline allows pre-existing unsupported entries without silently admitting a map. Runtime's complete supported-set check (`prepared_map_loader.dart:102-114`) supports keeping new-map tool/runtime integration out of this change.
- **Exact staged publication can reuse the existing transaction.** `refreshActive` already owns asset-block staging, validated promotion, pubspec replacement, pruning, cleanup and phase-specific failure messages (`pack.dart:2837-2892`). Extracting that portion, while leaving offline/metadata prechecks and preservation before it, is a direct reuse rather than another publisher. `promoteCandidate` validates and copies the candidate without rebuilding (`pack.dart:1960-2013`); bare `promote` remains pointer-only. The documented operator serialization assumption is honest: a baseline recheck is not represented as a cross-process lock.
- **Coverage can remain at the cheapest complete layer.** Existing small source-index/preservation tests demonstrate that admission and metadata-preservation permutations need not compile vector packs. The validation map appropriately reserves real offline vector reproduction for qualification and uses injected operations/minimal filesystem tests for publication phases. Those tests must not replace actual candidate validation with synthetic hash admission in the real CLI smoke. The described real admitted candidate plus disposable relative pack root/pubspec permits actual command/publication evidence without publishing repository-active assets. If matching admitted evidence cannot be supplied, recording that exact smoke blocker is the correct outcome, not bypassing admission. A successful no-new-artwork/no-change run remains a valid outcome; evidence-only differences must be reported as evidence differences rather than fabricated artwork changes.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **M1 — Resolved and rechecked.** Original required change: replace the “only when there are visual changes” restriction with the existing canonical boundary: retain the existing report and before-merge owner-check responsibility when anything except the toolchain record changes, including metadata/manifest changes, while explicitly keeping that responsibility separate from automated staging/publication success. State that a true no-change/toolchain-only outcome needs no owner check; do not add an image, checklist, acknowledgement or user gate to the CLI smoke. This is preservation of existing behavior, not a reversal of the approved simplified publication decision. If a narrower owner-check policy is actually intended, it instead needs an explicitly approved canonical-contract change; it must not be described as the existing policy. The revised `design.md:188` satisfies this requirement, including evidence-only changes and the conditional applicability of recording the owner result when repository-active assets actually change. No required change remains outstanding.

CHANGES_APPLIED: yes

## Rebuttals

M1: Fixed in `design.md:188`; accepted by reviewer after the required-change-only recheck. The original finding and required edit are retained above for traceability. No other decision was reconsidered. No proposal, spec, design, tasks, implementation or `review.md` file was edited by this reviewer; only the assigned scratch result was updated.
