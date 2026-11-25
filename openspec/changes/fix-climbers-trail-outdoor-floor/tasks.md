# Tasks

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| map-controls → Unassigned markers use the prepared floor extents | Spatial inference for an unassigned marker | `test/maps/map_controller_test.dart` | spatial marker floors govern paint and hits independently of Auto | green |
| map-controls → Unassigned markers use the prepared floor extents | Marker outside a rectangle | `test/maps/map_controller_test.dart` | spatial marker floors govern paint and hits independently of Auto | green |
| map-controls → Unassigned markers use the prepared floor extents | Explicit marker ownership | `test/maps/map_controller_test.dart` | spatial marker floors govern paint and hits independently of Auto | green |
| map-controls → Unassigned markers use the prepared floor extents | Outdoor Climber’s Trail on bundled Shoreline | `test/maps/map_controller_test.dart` | bundled Shoreline keeps Climber’s Trail on ground and indoor exits underground | red |

## 1. Correct Shoreline marker ownership

- [ ] 1.1 Add the bundled Shoreline regression at the `MapController` seam using the committed pack and synthetic sample/match data, without opening the app or running the game. Start on Auto with only ground visible; assert map and matched-exit eligibility for Climber’s Trail but not Admin Basement or Transit to Labyrinth, then show Underground and assert the latter two become eligible. Run the targeted file and observe the Climber’s Trail assertion fail before changing calibration. Preserve the existing synthetic marker-floor test that proves C1 for paint and hit eligibility.
- [ ] 1.2 Add red-first shared normalizer coverage for the exact frozen extract identity and volume and for drift of ID or placement. Add the Shoreline `Ground_Level` entry to the reviewed calibration and reuse the existing Interchange volume guard. Verify matching sources receive the assignment, a drifted identity or volume uses normal inference (C2, already documented by ADR-0035), and existing Interchange/Icebreaker behavior stays green.
- [ ] 1.3 Rebuild a staged candidate offline as in D2, check the narrow manifest/evidence delta before publishing, and update `active.json`, generated pubspec declarations, and the generation together. Move only Climber’s Trail from the inferred Second_Floor entries to explicit ownership in `test/fixtures/map_floor_marker_delta.json`, keeping the provenance guards active. Run the controller and active-pack loader tests and turn the bundled scenario green. Run `mise run maps:check` for C3 (already documented by ADR-0033).
- [ ] 1.4 Format changed Dart files; verify release notes and the project’s offline analyze and fast test tasks, or record the matching hosted CI result when local heavy work is unavailable.

## Workflow follow-up

- Keep the PR on this branch; check reviews and CI and archive on the PR branch before reporting ready. Do not merge.
- Hand off the Shoreline-only owner check on the regenerated pack. A live raid check is unverified until the owner reports it or explicitly approves skipping that confirmation; no agent launches or drives either app against the game.
