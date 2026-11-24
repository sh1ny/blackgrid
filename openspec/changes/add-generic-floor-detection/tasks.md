# Tasks

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Floor control sits beside the picker | Choosing a floor | `test/ui/map_workspace_controls_test.dart` | `map-controls: Choosing a floor` | green |
| Floor control sits beside the picker | Manual-only floors | `test/ui/map_workspace_controls_test.dart` | `map-controls: Choosing a floor` (manual-only fixture has no Auto) | green |
| Floor control sits beside the picker | Map with no floors | `test/ui/map_workspace_controls_test.dart` | `map-controls: Map with no floors` | green |
| Floor control sits beside the picker | Artwork unavailable | `test/ui/map_workspace_controls_test.dart` | `map-controls: Artwork unavailable` | green |
| Auto follows the sampled player position | Position changes at the same height | `test/maps/map_controls_test.dart` | `Auto follows Reserve and Streets independently` | green |
| Auto follows the sampled player position | Height-only extent | `test/maps/map_controls_test.dart` | `Auto follows Reserve and Streets independently` | green |
| Auto follows the sampled player position | Overlapping extents | `test/maps/map_floors_test.dart` | `narrowest extent and stable floor id win in either order` | green |
| Auto follows the sampled player position | Unknown height | `test/maps/map_controls_test.dart` | `Auto follows Reserve and Streets independently` | green |
| Auto follows the sampled player position | Exclusive map | `test/maps/map_floors_test.dart` | `exclusive selection resolves a known gap to base` | green |
| Manual floor selection overrides Auto | Manual choice overrides Auto only on that map | `test/maps/map_controls_test.dart` | `Auto follows Reserve and Streets independently` | green |
| Unassigned markers use the prepared floor extents | Spatial inference for an unassigned marker | `test/maps/map_controller_test.dart` | `spatial marker floors govern paint and hits independently of Auto` | green |
| Unassigned markers use the prepared floor extents | Marker outside a rectangle | `test/maps/map_controller_test.dart` | `spatial marker floors govern paint and hits independently of Auto` | green |
| Unassigned markers use the prepared floor extents | Explicit marker ownership | `test/maps/map_controller_test.dart` | `spatial marker floors govern paint and hits independently of Auto` | green |
| Only the active generation is ever used | Active generation loads | `test/maps/active_pack_loader_test.dart` | `the real loader loads the committed active pack` | green |
| Only the active generation is ever used | Active generation is broken | `test/maps/map_scene_test.dart` | `broken active manifest is a load error and no other generation is read` | green |
| Only the active generation is ever used | Older preparation version | `test/maps/prepared_map_labels_test.dart` | `preparation version 4 is refused by loader and validator` | green |
| The app loads only packs that carry labels | Current pack | `test/maps/active_pack_loader_test.dart` | `the real loader loads the committed active pack` | green |
| The app loads only packs that carry labels | Map without a labels key | `test/maps/prepared_map_labels_test.dart` | `map without labels key fails in loader and validator` | green |
| The app loads only packs that carry labels | Label names an unknown floor | `test/maps/prepared_map_labels_test.dart` | `label with an unknown floor fails naming map and floor` | green |
| Prepared floor extents come from frozen interactive layers | Every shipped multi-floor map carries extents | `test/maps/active_pack_loader_test.dart` | `all bundled multi-floor maps carry the frozen extents` | green |
| Prepared floor extents come from frozen interactive layers | Unlinked or ambiguous extent layer | `test/maps/map_preparation_test.dart` | `extent layers require one named prepared floor` | green |
| Prepared floor extents come from frozen interactive layers | Upstream corners are reversed | `test/maps/map_preparation_test.dart` | `metadata links and normalizes floor extents by rendition identity` | green |
| Malformed source floor extents fail preparation | Malformed source extent | `test/maps/map_preparation_test.dart` | `malformed source extents name the map and layer` | green |
| Validation re-derives floor extents from candidate evidence | Candidate extents differ from evidence | `test/maps/map_preparation_qualification_test.dart` | `candidate rejects divergent extents and legacy floor keys` | green |
| Pack loading rejects malformed floor extents | Invalid extents do not load | `test/maps/prepared_floor_extents_test.dart` | `loader and validator reject malformed floor extents` | green |
| Offline rebuild migrates legacy floor calibration | Offline rebuild upgrades the prior generation | `test/maps/map_preparation_qualification_test.dart` | `verified v4 rebuild migrates only direct floor bands` | green |
| Offline rebuild migrates legacy floor calibration | A v5 candidate retains a legacy floor band | `test/maps/map_preparation_qualification_test.dart` | `candidate rejects divergent extents and legacy floor keys` | green |

## 1. Record the approved contract

- [x] 1.1 Write ADR-0050 and update the architecture contract/index (C1); verify the ADR's only supersession is ADR-0036's preparation version and that the deltas still carry C2–C7 (`openspec validate add-generic-floor-detection --strict`).

## 2. Prepare and apply spatial floor extents

- [x] 2.1 Add the regression tests first: exercise Reserve and Streets player updates/overrides, marker paint/hits, synthetic overlap and exclusive behavior, strict source and prepared formats, v4 migration and tampered candidates; capture failures on the pre-change interfaces where possible. Add the frozen before/after bundled marker comparison as part of the pack regression.
- [x] 2.2 Replace runtime bands with typed `GamePoint` extent classification; wire Auto and marker binding without changing renderer or screenshot admission. Verify the domain/controller and carried UI scenarios.
- [x] 2.3 Derive/validate v5 extents through the shared frozen layer reader and versioned v4 migration; keep labels, marker evidence and artwork admission intact (C4–C7). Rebuild the active pack and declarations with `mise run maps:rebuild` after the gaming guard clears. Validate the narrow map tests, including the full marker transition IDs and explicit ownership and the candidate/migration fixtures.

## 3. Verify the complete offline change

- [ ] 3.1 Run the prescribed gaming guard before heavy work, then prove `mise run analyze`, `mise run test`, `mise run maps:check` and validate release notes (`mise run release-notes -- --check openspec/changes/add-generic-floor-detection/proposal.md`). If heavy qualification is delegated to CI, verify the named hosted checks on the exact PR head.
- [ ] 3.2 [evidence] Record the rebuild, test, reproduction and independently reviewed marker comparison evidence; list owner-only checks as unverified → evidence/verification.md

## Workflow follow-up

- Owner-only checks remain unverified: Reserve bunkers/dome floors, Streets underground and upper floors, Labs and Icebreaker floor following, and affected marker visibility (including Labs Hangar Gate and Parking Gate). These are not offline acceptance scenarios and never run through an agent.
- Pre-ship review; PR with `Closes #131`, requested Codex review as `sh1ny`, hosted checks, and the owner-only status. Archive on the PR branch after checks and reviews settle; do not merge.
