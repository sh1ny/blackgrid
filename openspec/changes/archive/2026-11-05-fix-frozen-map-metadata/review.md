# Review

## Metadata

- **Round:** 3 — full design review of the amended artifacts, not a required-change-only recheck.
- **Prior round:** Round 2 rechecked Round 1's conditional approval and accepted its validation-map and audit-ordering corrections. The subsequent generation-backed staging amendment requires this renewed full review.
- **Reviewer:** fresh-context subagent (omp, GenerationViewReviewRestart), independent of the planning author; subagent route with `review.cross_model: false`.
- **Reviewed:** `openspec/changes/fix-frozen-map-metadata/{proposal.md,design.md,specs/prepared-map-packs/spec.md,tasks.md,review.md}`; canonical `openspec/specs/prepared-map-packs/spec.md`; archived `openspec/changes/archive/2026-11-02-unpin-map-toolchain/design.md`; `docs/adr/0005-native-map-prepared-packs.md`, `0029-release-notes-come-from-each-proposal.md`, `0033-map-packs-proven-by-reproduction.md`, and `0034-metadata-refresh-preserves-prepared-artwork.md`; `AGENTS.md`; relevant source in `tool/maps/pack.dart:145-254,449-750,764-827,1104-1325,1577-1858,1899-1991,2249-2532,2695-2841`, `tool/maps/calibration.dart:1-165`, `test/support/map_preparation_fixtures.dart:1-145,310-460`, `test/maps/map_generation_inputs_test.dart:1-950`, `test/maps/map_preparation_test.dart:482-972`, and `test/maps/map_preparation_qualification_test.dart:1-155,440-593,1490-1800,1830-2086`.
- **Project skills:** Loaded all four supplied installed files: `.claude/skills/dart-add-unit-test/SKILL.md`, `.claude/skills/dart-run-static-analysis/SKILL.md`, `.claude/skills/dart-use-pattern-matching/SKILL.md`, and `.claude/skills/dart-write-documentation/SKILL.md`. No named skill failed to load. No workflow skill was invoked.
- **Planning context:** `openspec list --json` resolved `root.path` to `F:/Dev/Dart/blackgrid`. `openspec context --json` returned no referenced stores or unresolved references. Used the FULL instructions and official template from `openspec instructions review --change fix-frozen-map-metadata --json`.
- **Evidence boundary:** Static artifact/source inspection only. No acquisition, implementation, builds, tests, analysis, formatting, app/game/process/UI inspection or launch, commits, or task-state changes. Existing green task-map rows and diagnostic live-source observations are records in the supplied artifacts, not results independently exercised by this reviewer. The new staging method, real generation, independent audit and owner result remain outstanding implementation/qualification work. Only the designated scratch file was written; `review.md` was not edited.

## Findings

### Critical (blocking)

None.

### Moderate

None. The full review found no concrete design defect requiring an artifact amendment. The following assessments explain the evidence behind that conclusion; they are not claims that the outstanding implementation has passed verification.

- **Ownership and input closure:** The staging correction matches the existing source abstraction rather than weakening it. `FrozenInputs.fromGeneration` resolves non-tile evidence, maps tile hashes to carried outputs, and explicitly records indexed tiles with no carrier (`pack.dart:180-224`); `bytes` fails if such an input is actually requested (`pack.dart:244-254`). The archived toolchain design explicitly distinguishes 8,960 indexed tiles from 8,483 carried tiles and explains the unread SVG-floor remainder. The builder reads tiles only through selected floor/dependency paths and carries non-tile evidence separately (`pack.dart:575-586,623-644,660-672,709-716`). D1's six-path instance method can therefore retain the established missing-input semantics without reconstructing unused historical artwork or changing `open`/`fromGeneration`. D1 also requires a separately derived index, unchanged baseline, and replacement hash verification on reads, including after staging; the new regression plan exercises those properties.

- **Admission and preservation authority:** D2 leaves the transaction in `refreshActive`, with source-index admission and preservation inside the metadata branch. The existing implementation checks the baseline and source index before rebuilding, and preservation before reporting or promotion (`pack.dart:2769-2783`). Source admission compares complete path inventories, record order, non-replacement records, and replacement fields other than hashes (`pack.dart:2282-2354`). Preservation compares complete non-marker map records, non-metadata output inventories/hashes and top-level settings, while allowing provenance and metadata bindings to change (`pack.dart:2361-2510`). These comparisons cover notices, calibration, frames/crops, vectors, compiler inputs, raster outputs and witnesses without a second artifact writer. The proposed generation-backed view supplies inputs to these gates rather than replacing them.

- **Reviewed ownership:** Checking only present markers would miss a removed console. The existing projection checks a present reviewed volume (`pack.dart:1654-1668`), while the preservation gate checks disappearance, retained assignment, actual volume and floor (`pack.dart:2434-2459`). The design explicitly retains that second gate. The exact console calibration and fixture preserve the historical evidence and complete reviewed volume rather than deleting the assignment to obtain a passing fixture (`calibration.dart:114-146`; `map_preparation_fixtures.dart:408-427`). Direct preservation tests and the real-refresh disappearance qualification case cover the two distinct responsibilities.

- **Failure and ordering:** The design does not promise a new filesystem-wide transaction. Staging/acquisition failure cannot promote; admission failure precedes candidate creation; failures after rebuilding retain and name the candidate. Refresh already stages the asset rewrite, promotes, replaces the asset declarations, prunes, then removes its candidate, with explicit post-promotion recovery messages (`pack.dart:2794-2841`). D3 correctly places the reported-location source check before refresh, production validation/preservation before promotion, and the independent audit after refresh against its exact returned generation. Audit failure blocks delivery/merge; it is not misrepresented as pre-promotion protection. Single-orchestrator operation is explicit, and no new concurrent writer is introduced.

- **Bounds and mechanism cost:** The fixed six-source acquisition is sequential and has a finite invocation deadline. The design openly retains existing whole-file/offline memory costs and fails rather than dropping records or introducing runtime accumulation. One stage/candidate per attempt and explicit failure retention avoid an automatic retry queue. A narrow input-view method and two comparison functions are justified by the actual closure/preservation boundary. A permanent network command, generic overlay, candidate callback, second production boss parser, new pack format, and runtime fetch/cache are correctly excluded.

- **Spec assertability and cheapest complete test layer:** All twelve scenarios have named automated coverage. Projection, identities, malformed boss facts, multiplicity and explicit empties are focused preparation tests; source-record admission and otherwise-unreachable preservation drift use direct comparison tests; transaction success/refusal and promotion placement use existing qualification infrastructure. The newly added scenario has both a small generation-view regression and a real-refresh qualification flow, with explicit missing-needed-input and post-staging mutation failures. This is necessary because the existing qualification staging helper copies a full raw directory (`map_preparation_qualification_test.dart:17-93`) and cannot by itself prove an unused uncarried source is tolerated. Keeping the new row red until exercised accurately distinguishes that gap from the existing tests. The independent multiset audit includes map identity, all specified boss facts and occurrence counts instead of comparing totals or calling the production projection for expected results. The user task is confined to generation-bound presentation and source-versus-game judgment, not automated integrity checks.

- **Decisions and ADR consistency:** The build-read-closure clarification is consistent with ADR-0033 D4's requirement to carry every source the build reads and with the archived decision not to vendor unread tiles. It preserves ADR-0034's six-source boundary, baseline-preservation gate, refresh ownership and owner check. Toolchain provenance remains descriptive, while changed artwork still fails the metadata-only gate. No user-owned scope decision needs reversal, no runtime/format cutover is introduced, and the proposal retains the release-notes section required by ADR-0029.

### Suggestions

None requiring a planning change.

## Verdict

VERDICT: APPROVE

Approval covers the amended proposal, design, spec delta and task plan as reviewed, including the generation-backed staging correction. It is not implementation approval or evidence that task 4.1, the real all-map refresh, the independent returned-generation audit, integration gates or the exact-generation owner check have passed. Those remain the explicit apply/delivery gates already recorded in the plan. No reduction in their scope or weakening of existing integrity/ownership checks is authorized.

## Required Changes

None.

CHANGES_APPLIED: n/a

## Rebuttals

None. This full review identifies no open Critical or Moderate finding and requires no author-applied artifact correction.
