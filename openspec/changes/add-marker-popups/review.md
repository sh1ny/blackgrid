# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (omp, PopupDesignReview); no author transcript or author reasoning supplied.
- **Reviewed:** Complete planning artifacts: `openspec/changes/add-marker-popups/proposal.md`, `openspec/changes/add-marker-popups/specs/map-marker-popups/spec.md`, and `openspec/changes/add-marker-popups/design.md`.
- **Reviewed:** Review contract: the review artifact in `openspec/schemas/specwright/schema.yaml`, its effective `openspec instructions review --change add-marker-popups` output, and `openspec/schemas/specwright/templates/review.md`. Planning root was resolved with `openspec list --json`; `openspec context --json` reported no referenced stores or unresolved references.
- **Reviewed:** Architecture and relevant in-force decisions: `openspec/architecture.md`; `docs/adr/0002-sdk-notifiers-and-composition-root.md`; `docs/adr/0005-native-map-prepared-packs.md`, with its applicable amendments in `docs/adr/0033-map-packs-proven-by-reproduction.md`; `docs/adr/0023-project-authored-map-marker-icons.md`; `docs/adr/0029-release-notes-come-from-each-proposal.md`.
- **Reviewed:** Referenced preserved contracts, in full: `openspec/specs/player-facing-text/spec.md`, `openspec/specs/map-help/spec.md`, `openspec/specs/map-zone-labels/spec.md`, `openspec/specs/map-marker-icons/spec.md`, `openspec/specs/marker-preferences/spec.md`, and `openspec/specs/map-rail/spec.md`.
- **Reviewed:** Implementation evidence: `lib/ui/map_workspace.dart:1-944`; relevant ownership/layout sections of `lib/ui/map_screen.dart:190-565`; `lib/ui/theme.dart:215-290`; `lib/ui/shell.dart:145-185`; `lib/application/map_controller.dart:1-749`; `lib/application/catalog_controller.dart:1-188`; composition and effective-mode wiring in `lib/application/app_services.dart:27-205,295-357`; `lib/domain/map_marker_query.dart:1-133`; `lib/domain/map_geometry.dart:215-325`; `lib/domain/catalog.dart:402-475`; `lib/domain/marker_categories.dart:1-53`; `lib/maps/prepared_map.dart:580-700`; source/preparation sections of `tool/maps/pack.dart:1-125,430-485,610-640,1158-1175,1479-1625`; and `tool/maps/quest_markers.dart:1-260`.
- **Reviewed:** Testability evidence, without execution: `test/maps/map_viewport_test.dart:1-110,700-835` and `test/support/map_widget_harness.dart:1-280`. Frozen-data evidence: `assets/maps/active.json` and targeted JSON selections from `assets/maps/versions/ed26414539f458929025f4ef2c3413d3457c7b3e5b9f2e2adfb4dc20c24bba5f/evidence/markers/maps.json` and `maps_en.json`, covering extract field inventory, transfer item shapes, lock facts, same-map switch identities/links, and translated switch names.
- **Skills loaded:** All eight requested installed `SKILL.md` files were read: `dart-use-pattern-matching`, `dart-write-documentation`, `dart-add-unit-test`, `dart-run-static-analysis`, `flutter-add-widget-test`, `flutter-add-widget-preview`, and `flutter-build-responsive-layout` under `.claude/skills/`, plus `codebase-design` at `C:/Users/bgshi/.agents/skills/codebase-design/SKILL.md`. No named skill failed to load. Review-only scope and the supplied handwritten-fake/game-safety policy take precedence over implementation or execution suggestions in those files.
- **Scope:** Independent FULL-tier planning review only. No implementation, artifact edits, task creation, tests, builds, linting, formatting, app/game execution, game inspection, GitHub queries, commits, or pushes. Only this designated scratch file was written.

## Findings

### Critical (blocking)

None found.

### Moderate

None found. The following adversarial checks did not establish a concrete consequential design defect:

- **Selection ownership and invalidation:** The current duplicate is real: workspace selection is stored and updated in `lib/ui/map_workspace.dart:48-90`, while controller selection is independently stored by `lib/application/map_controller.dart:227-232`. The design removes the workspace marker mirror, retains controller selection across reconstruction, and requires synchronous invalidation through the shared floor/category/quest eligibility predicate (`design.md:143-152`). This addresses the observed distinction between outline-inclusive viewport culling (`map_controller.dart:467-491`) and eligibility (`:564-578`). Offscreen anchor hiding does not require clearing the selection or selection-linked highlights.
- **Stale and out-of-order input:** Browser results already cross an asynchronous modal and are checked against map identity, content generation, and current inventory (`map_workspace.dart:240-309`). The design explicitly retains those fences rather than replacing them with the new selected-marker accessor (`design.md:150,159,177`). Catalog mode changes clear the published snapshot before awaiting cache reads, and publication is generation-fenced (`catalog_controller.dart:64-100,127-166`). The proposed matching-controller-mode and matching-snapshot-mode checks plus notifier listening (`design.md:147,180`) cover stale names and subsequent publication without adding selection-triggered requests.
- **Failure visibility and recovery:** The proposed outcomes distinguish map/content invalidation, a rejected browser result, unavailable catalog names, shortened diagnostics, and hidden offscreen/unusable-space bubbles (`design.md:154-163`). Recovery uses current selection, existing publication, or viewport changes; no new asynchronous popup operation or silent retry path is introduced. Existing map load errors remain visible.
- **Bounds at 10x/100x:** The diagnostic path has output, depth, node, and per-collection bounds, incremental UTF-8 handling, immediate stopping, and an explicit shortening signal (`design.md:170`). This specifically avoids whole-source serialization before truncation, including for a single huge string. The need is supported by prepared quest details retaining the full `sourceTask` and original objective (`tool/maps/quest_markers.dart:124-138`). Selection state is constant-sized; summary work is explicitly limited to the current selection and existing same-map inventory/links, with linear scaling stated rather than a false constant-work claim (`design.md:169-173`). No second catalog, raw-source cache, queue, or request pipeline is proposed.
- **Input and geometry contracts:** The current wheel listener and map key handler are above the canvas (`map_workspace.dart:311-360,469-525`). The design moves the bubble above the canvas input layer as a sibling, explicitly isolates pointer/scroll input, accounts for focused controls and modal Escape, and uses actual layout bounds plus existing projection rather than another transform (`design.md:150,177-178`). Its zero/narrow-area handling and scrolling address constrained viewports without modifying the map view.
- **Fact interpretation:** Preparation retains extract `transferItem`, lock fields, and source identities; boss preparation explicitly copies the boss-wide chance into each location marker (`tool/maps/pack.dart:1479-1617`). Frozen source reads confirm the proposed transfer item and lock shapes, and that switch identity and human-readable translation are separate. The design limits switch resolution to source-linked same-map markers, validates optional shapes and probability range, uses translated prepared quest text, and does not infer availability or location-specific chances (`design.md:179`). Existing catalog names are consumed only as already published data.
- **Spec assertability and preserved behavior:** The new scenarios provide observable selection, contents, geometry, focus, catalog-update, and diagnostic outcomes, with stale/missing/edge coverage. Dismissal cases are complemented by the modal precedence and accessible-dismissal scenarios. The single parent-owned Details flag matches the existing `DetailsSection` lazy builder (`lib/ui/theme.dart:226-278`) and mounted-tab pattern (`lib/ui/shell.dart:165-180`). The design names deterministic pure/controller/widget coverage and preserves the existing hazard-paint and fixed logical-pixel hit proofs while changing obsolete raw-open/offscreen-detail expectations (`design.md:182`; `test/maps/map_viewport_test.dart:711-817`). No nonexistent tasks file was treated as a defect.
- **Mechanism necessity and architectural fit:** Each added mechanism addresses an evidenced seam: shared eligibility/selection, browser fencing, catalog-mode matching, bounded preview, or input/focus routing. The design explicitly rejects extra caching, retries/workers, general selection machinery, and persistence (`design.md:184-194`). SDK notifiers, native prepared geometry, existing painter-owned badges, and proposal release notes remain consistent with the relevant ADRs.

### Suggestions

None. No speculative hardening or additional scope is required by this review.

## Verdict

VERDICT: APPROVE

The three artifacts form a coherent, implementable planning contract. The FULL triage is supported by the referenced code. This approval is for the reviewed design, not a claim that the feature is implemented or that runtime behavior has been verified.

## Required Changes

None.

CHANGES_APPLIED: n/a

## Rebuttals

None.
