# Tasks

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| map-controls → A chosen floor fades the base floor | Vector underground floor | test/maps/map_scene_test.dart | reserve: every non-base floor fades the base | red |
| map-controls → A chosen floor fades the base floor | Vector upper floor | test/maps/map_scene_test.dart | streets-of-tarkov: every non-base floor fades the base | red |
| map-controls → A chosen floor fades the base floor | Tile floor over vector artwork | test/maps/map_scene_test.dart | reserve: every non-base floor fades the base | red |
| map-controls → A chosen floor fades the base floor | Raster map | test/maps/map_scene_test.dart | the-lab: every non-base floor fades the base | red |
| map-controls → A chosen floor fades the base floor | Base only | test/maps/map_scene_test.dart | base and its attached layers alone stay at full strength | red |
| map-controls → A chosen floor fades the base floor | Exclusive floors | test/maps/map_scene_test.dart | icebreaker: a chosen floor hides the base instead of fading it | red |

## 1. Fade the base for every non-base floor

- [ ] 1.1 Replace the tile-only test near `test/maps/map_scene_test.dart:494` ("abstract SVG draws tile-only floors over a dimmed base") with tests built from `preparedMapMetadataFixture` and synthetic opaque artwork: for `reserve`, `streets-of-tarkov` and `the-lab`, every non-base floor selected alone draws a base pixel with alpha in (0, 128), and all faded bases have the same alpha whatever the overlay's artwork kind; with only the base selected, a base pixel and an attached-layer pixel (Streets `First_Floor`) keep alpha 255; on `icebreaker` a chosen floor draws no base pixel. Run `mise exec -- flutter test test/maps/map_scene_test.dart` and confirm the vector-overlay (Reserve Bunkers, Streets) and Labs rows fail on alpha 255, the reason the bug exists; rows that already pass are recorded as such.
- [ ] 1.2 Change `_dimBase` in `lib/maps/native_map_scene.dart` to "any non-base floor is selected" (design D1) and draw base tiles with a faded tile paint at the same alpha as `_dimPaint` (design D2). Verify the 1.1 tests pass and flip every Test map row green.
- [ ] 1.3 Carry C1: replace the "Like tarkov.dev, a tile floor…" doc comment on `NativeMapScene._dimBase` with the rule that any selected non-base floor fades the base, whatever its artwork kind, and that the tile-only rule was rejected (#130). Verify by reading the comment.
- [ ] 1.4 Carry C2: document on `NativeMapScene._dimPaint` that faded base pictures and faded base tiles share its opacity, so every floor fades at one strength, and derive the tile paint's alpha from `_dimPaint` rather than repeating the number. Verify by reading the comment and the code.
- [ ] 1.5 Run `mise run analyze`, `mise run test` and `dart format` on the changed files; all pass with no new analyzer findings.

## Workflow follow-up

- Owner check after merge, recorded as unverified until the owner reports: Reserve Bunkers and Streets Underground and Second Floor show the ground level faded under the chosen floor; Labs First Level fades under Second Level. Agents never launch or check against the game (AGENTS.md).
