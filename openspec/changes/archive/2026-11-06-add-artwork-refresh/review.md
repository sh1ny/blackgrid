# Review

## Metadata

- **Round:** 2 — fresh FULL design review, not a required-change-only recheck.
- **Prior round:** Round 1 approved with required changes; its subsequent limited recheck accepted the owner-check wording correction. This round independently reviews the complete current design.
- **Reviewer:** Fresh-context subagent (OMP, openai-codex/gpt-6.1-sol), ArtworkAuthorityReview.
- **Reviewed:** `openspec/changes/add-artwork-refresh/{proposal.md,design.md,tasks.md,review.md}`; its `specs/prepared-map-packs/spec.md`; canonical `openspec/specs/prepared-map-packs/spec.md`; the in-force ADR index in `openspec/architecture.md`; accepted ADR-0005, ADR-0033 and ADR-0034; referenced acquisition, frozen-input, explicit builder-context, calibration, candidate validation, marker ownership, reporting, metadata preservation and publication sections of `tool/maps/pack.dart`; `tool/maps/prepare.dart`; relevant source identities and calibration in `tool/maps/{calibration.dart,inventory.dart}`; `lib/maps/prepared_map_loader.dart:44-152`; relevant fixture and source/preservation tests in `test/support/map_preparation_fixtures.dart` and `test/maps/map_generation_inputs_test.dart`; refresh lifecycle test locations in `test/maps/map_preparation_qualification_test.dart`; existing map command documentation in `README.md` and aliases in `mise.toml`.
- **Project skills loaded:** All four supplied files loaded successfully: `F:/Dev/Dart/blackgrid/.claude/skills/dart-add-unit-test/SKILL.md`, `F:/Dev/Dart/blackgrid/.claude/skills/dart-run-static-analysis/SKILL.md`, `F:/Dev/Dart/blackgrid/.claude/skills/dart-use-pattern-matching/SKILL.md`, and `F:/Dev/Dart/blackgrid/.claude/skills/dart-write-documentation/SKILL.md`. `AGENTS.md`, including its Dart/Flutter and safety sections, was also read. No named skill was unavailable. Their execution workflows were not run.
- **Planning context:** `openspec list --json` resolved the planning root to `F:/Dev/Dart/blackgrid`. `openspec context --json` reported no referenced stores and no unresolved references. The review instruction and complete template were obtained from `openspec instructions review --change add-artwork-refresh --json`.
- **Evidence boundary:** Static design/source review only. No builds, tests, analyzer, formatter, acquisition, application/process inspection or game interaction ran. Current group 1 working-tree changes were read as source evidence; this verdict neither certifies their implementation nor treats pending groups 2–4 as missing deliverables. Proposed tests and smoke runs remain unverified.

## Findings

### Critical (blocking)

None.

The reviewed design has a feasible path through the existing builder and publication transaction. No blocking contradiction with the canonical specification or the applicable accepted ADRs was identified.

### Moderate

None.

The full review examined the following concrete authority and failure boundaries:

- **Frozen reproduction versus fresh admission:** The working-tree `MapBuildContext` separates reviewed configuration from generation-owned calibration, manifest `sourceLock` and exact notice bytes (`tool/maps/pack.dart:309-369`). `rebuildCandidate` requires that context and compares its calibration with the frozen input (`pack.dart:607-635`); `_rebuildActive` and the metadata branch derive it from the verified generation (`pack.dart:2642-2662,2870-2885`). This is the relevant seam for D1. The design correctly keeps new artwork admission separate: existing generation integrity does not establish approval against current source configuration.
- **Actual source authority, not provenance labels:** Existing acquisition hash-checks locked bytes, but downloads Interchange from a served URL and then appends repository information, while three terms documents lack entries in the current primary hash table (`pack.dart:425-481`; `calibration.dart:5-29`). D1 and tasks 2.1–2.2 explicitly require pinned repository evidence where available and reviewed identity/URL/hash/provenance locks for all five required terms documents. They do not mistake the existing acquisition helper or an observed hash for that admission implementation. Raster admission is separately and appropriately defined by reviewed resource/expanded URLs plus frozen acquired hashes, rather than an unavailable pre-reviewed per-tile byte inventory.
- **Selective retention and complete evidence:** Broad acquisition currently fetches the six marker/task/trader responses (`pack.dart:437-451`), so it cannot satisfy artwork-only retention unchanged. The design names all six retained paths and requires selective acquisition. `FrozenInputs.fromGeneration` already supports hash-backed tile carriers and indexed-but-uncarried tiles, with read-time tile verification (`pack.dart:189-267`). The proposed build-read closure preserves that distinction instead of requiring every historical tile to exist. Candidate output and source-evidence checks provide a reusable validation boundary (`pack.dart:1220-1370`); fresh admission still has to enforce the additional current-configured identities and terms requirements described in the plan.
- **Calibration and reviewed ownership:** Existing reconciliation rejects lost or added floor identities and mismatched raster dependency closure (`calibration.dart:306-345`). Builder and validator compare metadata geometry and original SVG frames with frozen calibration (`pack.dart:678-688,1076-1100,1400-1450`). Marker preparation checks the source volume of encountered reviewed assignments (`pack.dart:1738-1783`); metadata preservation additionally rejects removed markers and lost or changed ownership (`pack.dart:2550-2577`). D1 and the calibration/ownership scenario explicitly retain both kinds of protection and require named reviewed correction, rather than assuming encounter-time checks alone prove that no assignment disappeared. The independent-placement limitation remains explicit.
- **Publication and interruption:** `promoteCandidate` validates and copies candidate bytes without rebuilding, validates the copied generation, then switches the pointer (`pack.dart:2020-2078`). `refreshActive` already stages the pubspec replacement, promotes, replaces pubspec, prunes and reports different recovery states after promotion (`pack.dart:2899-2964`). D2 extracts that transaction rather than duplicating it and leaves workflow-specific rebuild/preservation checks before publication. Its candidate revalidation, current baseline comparison and immediate baseline recheck address sequential changes; the explicit operator single-writer rule honestly excludes concurrent writers. The design does not present a stale check as a lock or an explicit command as proof of human review.
- **Existing workflow and owner-check contracts:** ADR-0033 requires generation-owned reproduction and a report/owner check for changes other than toolchain provenance; ADR-0034 adds exact six-source replacement and non-metadata preservation. The delta and tasks retain these gates. The current Validation Map's closing paragraph and task 3.2 preserve owner responsibility for metadata, manifest and evidence-only changes while separating it from automatic staging or disposable publication success. The prior round's owner-check finding is resolved in the current design, without introducing an approval-token or image gate.

### Suggestions

None requiring a design change.

The test map covers all 15 delta scenarios, including failed fetch/build/validation, locked-source and URL drift, missing/corrupt needed evidence, supported identity ambiguity, ownership loss, exact-candidate publication, transaction phase failures, pending configuration and metadata preservation. Service/model checks and injected filesystem transaction failures are appropriate for the cheap permutations; actual compiled-vector reproduction belongs in qualification. Existing small source-index/preservation fixtures demonstrate usable seams without admitting synthetic primary hashes in a real CLI smoke (`test/maps/map_generation_inputs_test.dart:120-245,260-392,724-783`). No assertable scenario is assigned solely to a user task. Human owner checking remains a separate before-merge responsibility if repository-active assets actually change.

The explicit resource trade-offs are consistent with the inherited acquisition implementation: 16×16 tile grids, request batches of eight, whole-response buffering, no explicit fetch deadline and operator-managed stage retention (`pack.dart:492-534`). The design acknowledges these limits and makes no new bounded-memory, timeout or concurrent-writer guarantee. No evidence found in this review warrants adding a new fetch-policy or concurrency subsystem to the approved scope.

## Verdict

VERDICT: APPROVE

## Required Changes

None.

CHANGES_APPLIED: n/a

## Rebuttals

None required. No planning artifact or implementation file was edited by this reviewer; only the assigned scratch review result was written.
