---
title: Native M3 Map Proof - Plan
type: feat
date: 2026-10-06
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Native M3 Map Proof - Plan

## Goal Capsule

Objective: Blackgrid users can navigate real multilevel maps, inspect map-specific markers and use their saved pins in the existing Map workspace.

Means: Native Flutter rendering backed by independently prepared local artwork and one calibrated coordinate model (KTD1–KTD4).

Authority: this run's user request and subsequent instructions to follow the source project's prepare-assets-then-build approach and include credited map assets with published licence notices; repository safety rules; `STRATEGY.md`; `docs/IMPLEMENTATION_STRATEGY.md`; this contract. R20 owns attribution and artwork licence handling.

Execution profile: at most two authoring/test workers; expensive checks sequential. Finish implementation, native offline proof, review, explicit-path commits, push and a non-draft PR against `main` in `sh1ny/blackgrid`. Keep the PR open and repository private. Never merge or push directly to main. Stop only for an actual unavailable prerequisite or unsafe verification boundary; report unverified checks honestly.

## Product Contract

### Summary

Replace the Map artwork placeholder with a native interactive workspace for Interchange, Labs and Icebreaker. Deliver a separate Dart acquisition/preparation command and a portable offline asset pack. Preserve M1 state and its distinction between item history and accepted scans.

### Problem Frame

M1 stores map preferences and pins but has no artwork viewport. The references already demonstrate a prepare-assets-then-build pipeline, but depend on PowerShell, System.Drawing and a WebView renderer that Blackgrid must not retain.

### Key Decisions

- **Map-first, three real artwork families.** (session-settled: user-directed — chosen over scanner-first or a single toy map: M3 must stand independently of M2.) Governs R1, R13.
- **Include credited source-shared map assets and proceed with preparation/build.** (session-settled: user-directed — chosen over a separate permission-paperwork gate: the user accepts the published community sharing terms and reference preparation/build approach for this private implementation.) Governs R2, R3, R14, R20.

### Requirements

#### Artwork and preparation

- R1. Qualify and ship one real multilevel vector map, Interchange, together with Labs tiled artwork and all 16 Icebreaker raster floors.
- R2. Independently acquire source inputs from tarkov.dev and prepare them with a small Dart command under `tool/maps/`; never execute, wrap or modify reference scripts/checkouts.
- R3. Freeze source URLs, metadata/terms versions, authors, source spelling, input/output hashes and preparation parameters in a portable manifest; state unresolved permission evidence accurately rather than marking it cleared.
- R4. Rebuild deterministically offline from frozen source bytes, rejecting missing dependencies, invalid PNGs, inconsistent dimensions and unexplained missing tiles; HTTP size alone is not content validation.
- R5. Prepare a fresh candidate and validate the complete artwork/geometry/floor/marker closure before explicit coherent promotion; failures preserve the working pack.
- R6. Preserve local height bands, default floor, exclusivity and base-attached structural groups when refreshing upstream metadata; no silent drops or replacement by display names.

#### Native geometry and interaction

- R7. Give game X/Z plus optional height, normalized artwork, scene and viewport coordinates explicit types, sharing forward/inverse geometry across art, pins, markers, hazards and hits; never clamp finite off-map coordinates.
- R8. Preserve `legacy-normalized` revision 0 and `labs-native-normalized` revision 1 pin identities and existing Labs import conversion; a crop is not permission to reinterpret stored pins.
- R9. Preserve actual SVG group dependencies, definitions, styles, ordering, transforms, references and compositing; essential unsupported features must fail qualification, not disappear or become a flattened vector-map bitmap.
- R10. Implement manual vector/Labs base-plus-overlay visibility and Icebreaker exclusive visibility with base restoration; automatic height selection is limited to Labs/Icebreaker, half-open, with higher minimum then narrower maximum then source order winning overlaps.
- R11. Keep unknown height distinct from zero and use the same visibility predicate for drawing, pointer hits, keyboard focus and details.
- R12. Provide pan, cursor-anchored zoom, fit, map/floor controls, category filters, stable screen-size glyphs/hit targets and accessible map-specific marker details for all three families.

#### Integration, evidence and delivery

- R13. Integrate the existing Map/shell/composition root and preserve settings, pins, import, progression, credentials, decision results and activity; map replay never creates an accepted scan or claims continuous live tracking.
- R14. Bundle all prepared assets, metadata and notices for offline Windows operation independently of the reference checkouts, source caches, .NET, PowerShell and WebView2.
- R15. Fence stale loads on supersession/map/floor/session changes and disposal, bound decoded resources and dispose native pictures/images explicitly.
- R16. Gather actual Windows profile/release frame, decode, floor-switch and retained-memory measurements plus fresh UI/accessibility evidence; compiler success and tests alone are not native rendering proof.
- R17. Use only explicitly authorized offline screenshots/log roots, with independently labelled sanitized fixtures and no raw private evidence committed/uploaded; filenames alone do not prove map or floor.
- R18. Never interact with a game or launch/drive Blackgrid while EFT is running; use only the authorized identity-only closure check before every native verification session.
- R19. Finish on a feature branch with whole-project analysis clean, relevant tests passing, an open private non-draft PR, Codex review requested as `sh1ny`, default identity restored to `KintsugiBot`, and an explicit CI decision; do not merge.
- R20. Include source/creator credit links and published licence notices without claiming ownership of any map artwork, including Labs/Icebreaker; mark preparation changes and retain noncommercial/share-alike conditions on assets covered by CC BY-NC-SA separately from the code licence.

### Acceptance Examples

- AE1. Covers R5: candidate B has a corrupt required image while A is active; validation fails and cold/runtime readers still resolve coherent A.
- AE2. Covers R7–R8: a finite pin at (-0.2, 1.5) survives rebuild, pan, zoom and restart without clamping or frame revision change.
- AE3. Covers R10–R11: Icebreaker height selects Bridge at its lower boundary, never selects it at its upper boundary, and restores Infirmary when no overlay matches; null height is not a Control_Room position.
- AE4. Covers R9–R12: hiding a floor removes its art, marker hits and keyboard targets; Interchange's First_Floor is the displayed second floor, not Ground_Level or an invented group ID.
- AE5. Covers R13: switching Scanner → Map → Scanner retains the item result/history context; loading a map or offline position fixture leaves `SessionScanState.hasAcceptedScan` false.

### Scope Boundaries

M2 recognition, M4/M5 live screenshot watchers, exfil OCR, overlay tracking, full reference parity and all-map expansion are outside this change. Do not narrow R1 or replace real proof with synthetic assets. Other persisted supported-map selections remain valid; unbundled maps show an honest unavailable-artwork state without rewriting the selection or pins.

## Planning Contract

### Key Technical Decisions

- KTD1. Use immutable prepared map packs and Flutter-native vector pictures/raster tiles rather than a browser bridge, per R9, R14 (session-settled: user-directed — chosen over WebView/C# reuse: the product must be standalone Dart/Flutter).
- KTD2. Start with pinned `vector_graphics`/compiler and XML-based style/dependency normalization, qualifying the actual source before permanent renderer commitment. Precompile layer scenes with complete inherited context; compiled pictures do not provide a DOM for live group toggling. A bounded native correction must retain vector fidelity if qualification exposes unsupported essential features (R9).
- KTD3. Use manifest-owned game→artwork geometry, an artwork-frame identity separate from display crop, and one view matrix with its inverse. Separate native PNG pixels, Labs display tile stride and crop units (R7–R8).
- KTD4. Keep a capability-owned map controller with generation/disposal fences and bounded lazy scene resources, composed by `AppServices`; do not add an event bus, service locator or repository-per-table hierarchy (R13, R15).
- KTD5. Stage a self-contained versioned directory and promote through one validated version boundary, rather than overwriting config/assets piecemeal. No build step downloads from a mutable URL implicitly (R4–R5).
- KTD6. Independently retrieve source marker datasets from tarkov.dev, recording their provenance; do not copy generated reference JSON or invent production coordinates. Separate stable data markers from pins and offline qualification observations (R12, R17).

### High-Level Technical Design

These sketches describe ownership and invariants, not prescribed class signatures.

Component/data flow: source metadata + artwork + marker snapshots → Dart acquisition/preparation → complete validated pack → asset loader → map controller → native viewport and details. Settings/pins enter the controller through existing M1 collaborators; accepted-scan state remains read-only.

Preparation protocol: acquire/freeze → inspect/decode → normalize dependency-closed layers and crop/calibration → build candidate → validate all hashes/frame/floors/markers → explicit promotion → bundle. Failure before promotion never changes the active version.

Loader state machine: idle → loading(generation, map, floor) → ready(snapshot) or error(previous-good snapshot). Supersession/disposal invalidates publication before awaiting work; obsolete decoded resources are released, not committed.

Lifecycle: app root opens map services → Map subscribes and owns viewport transform → map/floor selection replaces scene demand → tab switching retains view state → app disposal cancels demand and releases scene resources.

Decision flow: frame/revision validation → game projection or persisted-pin interpretation → floor/filter visibility → viewport transform → drawing and shared hit testing → details. Invalid frame is rejected, unknown height remains unknown, off-map finite points remain representable.

Mode combinations: vector/Labs use base-plus-optional overlays; Icebreaker uses base-or-one-overlay. Only Labs/Icebreaker may apply a known height band. Manual controls always remain available.

### Grounding and risks

- `lib/ui/map_screen.dart`, `lib/ui/shell.dart` and `lib/application/app_services.dart` own the existing screen, IndexedStack retention and app lifetime.
- `lib/domain/settings.dart`, `lib/data/legacy_import.dart` and `test/data/legacy_import_test.dart` own persisted pin frames. `SettingsController` can reject a busy save; do not assume a map selection persisted or save every pan/zoom.
- Current read-only reference floor config has bands only for Labs/Icebreaker. Labs uses First_Level, Second_Level and Technical_Level. Icebreaker uses Infirmary base and 15 overlays; preserve source typo `05_storage_ecurity` in provenance mapping.
- Both reference pipelines were inspected; their old size/error-swallowing/in-place output behavior is not a correctness model. The newer candidate pipeline still needs coherent config+asset promotion.
- `flutter_svg` documents incomplete CSS support; compiler documentation excludes filters and some text attributes. Qualification is an execution-time gate, not an assumed pass.
- Raster credits currently differ from old local re3mr attribution: interactive Icebreaker is credited to TarkovBOT.eu, Labs to Tarkov.dev. Record the discrepancy and published evidence under R3; do not invent a grant or broaden the user's instruction into public release/visibility permission.
- Execution-time vector selection: the originally recommended Streets source fails dependency closure (`stairs-85`, `stairs-86`, `stairs-87` have no definitions). The user required a representative inspected multilevel vector map, not Streets specifically. Select the inspected current Interchange source instead; do not repair, strip or substitute missing Streets artwork. Interchange's served SVG matches authoritative repository revision `5a8b6115d1c0cf56f2ebaac1a96fa5ae3074d178`, SHA-256 `31a44112cd5fe33484ce6be7b7dc80d13db6077cba2583a4425ed94c665f47c4`, and viewBox `0 0 1127.6852 947.02582`. This changes a technical recommendation, not the settled three-family scope. Native fidelity qualification remains mandatory.

### Assumptions

The user-authorized private preparation/build proceeds with the inclusion and attribution direction in R20. Preserve the actual origin and published licence evidence for each family rather than assigning another creator's identity or a website software licence to external artwork. Dependency pins and performance budgets are fixed before the corresponding verification run; changes require recorded rationale rather than retrospective pass criteria.

### Sequencing

U1 supplies frozen inputs to U2. U3 and the runtime skeleton can develop alongside U1 using independent mathematical fixtures. U2 renderer proof gates integration of prepared real scenes in U4. U5 joins existing state/lifecycle. U6 collects independently labelled controls. U7 verifies the integrated packaged result. Maximum two workers; one owner integrates shared interfaces.

## Implementation Units

### U1. Independent acquisition and candidate preparation

Goal: produce complete reproducible prepared packs without reference/runtime dependencies.

Requirements: R1–R6, R14, R20; KTD2, KTD5–KTD6. Dependencies: none.

Files: new `tool/maps/` command/helpers, portable manifests under `assets/maps/`, `pubspec.yaml`/lock, selected-input notices in `THIRD_PARTY_NOTICES.md`.

Approach: freeze real Interchange SVG and dependencies, Labs tile families and Icebreaker16 floors plus their metadata/marker inputs. Validate decoded alpha/content and required tile closure; retain one frame across floors and preserve local layer metadata. Make acquisition, offline rebuild, validation and promotion explicit operations.

Test scenarios (`test/maps/map_preparation_test.dart`): identical frozen inputs produce identical outputs; changed hash, absent tile, invalid PNG, dimension mismatch, unsafe href and excluded content fail without modifying A; changed upstream metadata retains local bands/exclusivity and refuses silent layer loss; promotion interruption never exposes mixed versions. Use isolated temporary directories and small independently authored images for permanent tests.

Verification: exercise real source acquisition, clean candidate validation, two network-disabled offline rebuilds and failed-candidate preservation; record hashes and timings. Execution note: do not use HTTP length heuristics or copy reference payloads.

### U2. Actual-source native renderer qualification

Goal: choose a proven native renderer before embedding a permanent viewport.

Requirements: R1, R9, R14, R16; KTD1–KTD2. Dependencies: U1.

Files: new `lib/maps/` scene loader/prepared-layer support, `test/maps/map_scene_test.dart`, qualification evidence under `docs/qualification/m3/`.

Approach: inspect exact source features, normalize CSS and preserve defs/use/ancestor transforms/clip/mask dependencies and legal floor composition. Render the complete Interchange scene and every Labs/Icebreaker floor on Windows. Compare independently labelled visual controls, not merely decoded nonempty pictures.

Test scenarios: unresolved referenced definition or image fails; inherited transform/order/opacity remains correct in an independently authored nested SVG fixture; floor extraction retains a shared gradient/clip definition and attached-base content. Never assert source-text wiring or implementation defaults.

Verification: actual rendered pixels and fresh native screenshot/accessibility evidence, source/dependency pins, supported-feature inventory and explicit discrepancies. Remove temporary qualification scaffolding after proof.

### U3. Typed geometry and floor policy

Goal: prove placement and layer selection independently of widgets.

Requirements: R6–R8, R10–R11; KTD3. Dependencies: metadata contract from U1; math fixtures may start independently.

Files: new pure-Dart map coordinate/geometry/floor types under `lib/domain/`, `test/maps/map_geometry_test.dart`, `test/maps/map_floors_test.dart`; preserve existing pin/import symbols and callers.

Test scenarios: anisotropic affine rotation and bounds-only mappings round-trip corners/interior/off-map points; nonzero crop and differing native/display tile size apply translation once; singular/nonfinite inputs reject; Labs revision1 and converted revision0 retain their interpretation; null height differs from zero; every half-open boundary, overlap tie and Icebreaker gap/base restoration; conventional vector floors never infer height bands.

Verification: official Dart MCP unit tests and independent geometric controls from U6; reference transforms alone are not a correctness oracle.

### U4. Native viewport, visible markers and accessible controls

Goal: make all three map families usable in the existing workspace.

Requirements: R9–R12; KTD1–KTD3, KTD6. Dependencies: U2, U3.

Files: `lib/ui/map_screen.dart`, new viewport/painter/marker-detail widgets under `lib/ui/`, `test/ui/map_screen_test.dart`, `test/maps/map_viewport_test.dart`.

Approach: retain broad map workspace and compact status/filter rail from `docs/vision/mapscreen.png`; do not reproduce decorative mockup claims as real status. Implement pan/zoom/fit and actual source-specific floor controls. Paint glyphs and select hits in viewport space after shared projection; use semantic controls and a visible focused marker/details path.

Test scenarios: cursor zoom preserves its scene anchor; pan and fit are invertible after resize; a hidden/filtered floor marker cannot receive click/keyboard details; zoom changes artwork scale but not glyph/hit-target size; actual map selection changes marker identities/details; off-map pins remain editable; wide/compact/text-scaled layouts retain usable controls and tab state. Delete obsolete placeholder wording assertions instead of repinning incidental text.

Verification: exercise pointer/keyboard, resize, floor switches and details on actual Windows surface for every family; preserve fresh visual evidence.

### U5. M1 state and lifecycle integration

Goal: preserve existing user state while safely loading scenes.

Requirements: R8, R13, R15; KTD4. Dependencies: U3, U4.

Files: `lib/application/app_services.dart`, new map controller under `lib/application/`, necessary settings/pin-editor integration, `test/maps/map_controller_test.dart`, existing shell/import/persistence tests.

Approach: reuse constructor injection and controller generation/disposed fences. Retain per-map view state without durable writes on gestures. Keep saved settings authoritative when a save is busy/rejected; preserve explicit import acceptance and pin frame/revision. Do not add an accepted-scan producer.

Test scenarios: slow A finishes after B and cannot publish; a late floor decode cannot reintroduce a hidden floor; disposal releases late decoded resources and suppresses notification; map save failure leaves consistent selection; map switch/import/restart preserve pins; Scanner↔Map preserves result/history/mode and accepted-scan false.

Verification: focused controller/widget tests plus offline app restart/import flow and existing M1 regression coverage.

### U6. Independent controls and offline evidence

Goal: establish actual placement/floor truth without game interaction.

Requirements: R7–R8, R17–R18. Dependencies: U1, U3.

Files: sanitized `test/fixtures/m3/` controls and `docs/qualification/m3/` evidence with portable source hashes; no raw screenshots/logs.

Approach: revalidate only explicitly authorized roots and configured non-sensitive log setting if needed. Independently label identifiable map landmarks and compare scene placement across every selected family. Document uncertainty where screenshot/map/floor identity is not independently established; retain only minimal sanitized numeric/control evidence.

Test scenarios (`test/maps/map_controls_test.dart`): independently known corner/interior landmarks meet stated scene tolerance; known floor controls select the intended layer; filenames alone cannot label a floor or emit accepted scans; unknown/ambiguous observations remain unknown.

Verification: manual independent labels, documented source identity/calibration residuals and deterministic fixture checks. No automated live-game checks.

### U7. Integrated Windows and standalone package proof

Goal: demonstrate the actual integrated product, not just tests or a debug renderer.

Requirements: R1, R12–R20. Dependencies: U1–U6.

Files: `integration_test/m3_windows_smoke_test.dart` if existing integration infrastructure is appropriate, qualification tooling under `tool/maps/`, `docs/qualification/m3/`, `README.md`, release notes through repository changelog tooling.

Approach: after the permitted EFT-name closure check, run Windows profile/release and exercise all families/floors. Measure build/raster FrameTiming, cold/warm decode, map/floor switch and retained resources over repeated cycles. Fixed initial budgets: p95 build and raster each ≤16.7 ms during warmed pan/zoom; p95 warm floor switch ≤200 ms; cold scene availability ≤2 s; decoded raster/picture policy ≤192 MiB, with no accumulating retained-resource growth over repeated map cycles. Report measured OS memory separately from managed resource accounting.

Test scenarios: package runs offline with source cache/reference paths unavailable; every declared asset resolves; rapid switches/disposal never stale-publish; repeated floor/map cycles remain within fixed resource bounds; broken candidate retains working pack; M1 import/results/pins/settings still work after cold restart.

Verification: official Dart MCP tests with concurrency ≤2, whole-project analysis clean, actual UI evidence and standalone release launch outside checkout. Record skipped game-dependent proof as unverified, never passed. No absent-scan-producer exception may be concealed.

## Verification Contract

Use pinned Flutter 3.47.6/Dart 3.13.5 and project-local `DART_DATA_HOME`. Run tests through the official Dart MCP `run_tests` route, not shell test commands, and analyze the whole root through official analysis tooling. Use available Dart LSP references before exported-symbol changes. Format only after related edits settle.

Qualification order: isolated preparation/math/controller/widget checks → real offline rebuild/candidate-failure proof → actual Windows native interactions/profile measurement → standalone release cold start → sequential M1 regressions and whole-project analysis → review/shipping. Record actual commands/tool arguments, source/output hashes, renderer versions, Windows size/DPI, measurements and observations in portable qualification evidence. Hot reload/restart only a Blackgrid session that meets R18.

Before shipping, inspect the complete diff, remove experimental paths, update notices/docs/changelog, commit only run-owned explicit paths with repository identity/trailer policy, and request Codex review using the required account exception. Decide CI from the existing workflows and captured local evidence; never call an absent workflow a passed check. No public release, raw private evidence publication or merge is authorized.

## User-approved verification exception (2026-10-06)

After reviewing the native interactions, the user instructed: "Pass on all the gates and move on. I can't test, until we have map tracking capabilities. My interactions were good."

This explicitly waives the remaining M3 qualification prerequisites for review and delivery: independent numeric Icebreaker placement/pixel-fidelity evidence, the remaining native resolution/DPI interaction matrix, stable multi-run performance and retained-memory qualification, and outside-checkout offline launch/cold-restart/import verification. Record these as waived and unverified, never as passed. Existing successful tests, analysis, native observations and Release/output-integrity checks retain their own evidence; historical failures remain recorded.

The exception changes the verification completion requirement, not implemented scope or safety. Preserve the three real artwork families, original Icebreaker coordinates/shared transform, additive Interchange/Labs floors, exclusive Icebreaker floors and M1 contracts. Map tracking remains a separate future capability; do not add it to M3. Continue simplification, review/fixes, accurate documentation/notices, attributed commits, feature-branch push and a private open PR against main. No merge or visibility change is authorized. New defects and pre-publication security checks are not waived.

## Definition of Done

- U1–U7 and R1–R20 are implemented and exercised, with per-unit evidence and no placeholder, mock-production fallback or narrowed corpus.
- Real multilevel vector, Labs tiled and Icebreaker16-floor scenes work in the existing native Map workspace with correct geometry, visible markers/details and durable pin frames.
- Deterministic offline preparation, failed-candidate preservation, resource bounds and independent packaged launch are observed.
- Relevant permanent tests catch consumer-visible correctness failures; obsolete incidental wording tests and throwaway scaffolding are removed.
- M1 user-state behavior remains intact and accepted-scan absence remains honest.
- Whole-project analysis is clean; source/provenance/licence evidence and unresolved grant facts are accurate, never marked owner-cleared by inference.
- The non-draft private PR is open against main, review requested and CI decided; no merge, direct-main push or visibility change.

## Appendix

Primary sources: [reference preparation pipeline](https://github.com/sayser/TarkovTracker/blob/master/tools/README.md), [tile builder](https://github.com/sayser/TarkovTracker/blob/master/tools/build_tile_map.ps1), [Icebreaker builder](https://github.com/sayser/TarkovTracker/blob/master/tools/build_icebreaker_layers.ps1), [map metadata](https://raw.githubusercontent.com/the-hideout/tarkov-dev/main/src/data/maps.json), [SVG source and stated terms](https://github.com/the-hideout/tarkov-dev-svg-maps), [native compiler limitations](https://github.com/flutter/packages/tree/main/packages/vector_graphics_compiler), [FrameTiming](https://api.flutter.dev/flutter/dart-ui/FrameTiming-class.html).

The external map metadata inspected this run had SHA-256 `c53a327dcdcff67a49b9fe2d150731edb4c1611dfc2f75db2ce97444dee2ef77`. Fresh source snapshots of both read-only references were hashed without upstream Git operations. These research identities are not renderer qualification or hashes of newly acquired artwork.
