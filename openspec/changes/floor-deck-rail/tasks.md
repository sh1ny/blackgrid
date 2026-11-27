# Tasks

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| The floor rail sits under the picker | Choosing a floor | `test/ui/map_workspace_controls_test.dart` | map-controls: Choosing a floor | green |
| The floor rail sits under the picker | An exclusive deck is chosen | `test/ui/map_floor_rail_test.dart` | a manual deck choice checks exactly one floor | green |
| The floor rail sits under the picker | Multiple additive floors | `test/ui/map_floor_rail_test.dart` | checked overlays retain the base and show the ground divider | green |
| The floor rail sits under the picker | Reset to the base | `test/maps/map_floors_test.dart` | selecting the additive base resets overlays | green |
| The floor rail sits under the picker | Manual-only floors | `test/ui/map_floor_rail_test.dart` | multiple manual floors have no Auto switch | green |
| The floor rail sits under the picker | One floor with Auto | `test/ui/map_floor_rail_test.dart` | a single Auto floor has no adjacent step | green |
| The floor rail sits under the picker | Map with no floors | `test/ui/map_workspace_controls_test.dart` | map-controls: Map with no floors | green |
| The floor rail sits under the picker | One floor without Auto | `test/ui/map_floor_rail_test.dart` | a single manual floor has no rail | green |
| The floor rail sits under the picker | Artwork unavailable | `test/ui/map_workspace_controls_test.dart` | map-controls: Artwork unavailable | green |
| The rail exposes floors outside its viewport | More floors than fit | `test/ui/map_floor_rail_test.dart` | a scrolled rail counts both clipped edges | green |
| The rail exposes floors outside its viewport | All floors fit | `test/ui/map_floor_rail_test.dart` | growing the viewport clears both overflow cues | green |
| The rail exposes floors outside its viewport | Collapse and expand | `test/ui/map_floor_rail_test.dart` | the compact line retains current floor and Auto | green |
| The rail exposes floors outside its viewport | The rail disappears and returns | `test/ui/map_workspace_controls_test.dart` | collapse survives a hidden rail but not a remounted workspace | green |
| The rail exposes floors outside its viewport | A marker popup overlaps the rail | `test/maps/map_viewport_test.dart` | overlapping rail and popup exchange priority without changing the map | green |
| The rail reports the player floor separately from Auto | Manual selection away from the sampled floor | `test/ui/map_floor_rail_test.dart` | You remains on the sampled floor when Auto is off | green |
| The rail reports the player floor separately from Auto | Unresolved position | `test/ui/map_floor_rail_test.dart` | unresolved position keeps selection and shows waiting | green |
| The rail reports the player floor separately from Auto | Auto resumes | `test/ui/map_floor_rail_test.dart` | enabling Auto immediately shows the known floor | green |
| The rail reports the player floor separately from Auto | Auto is toggled while collapsed | `test/ui/map_floor_rail_test.dart` | A updates the Auto tag without expanding the rail | green |
| Map shortcuts step floors and reach the rail | Step with multiple overlays active | `test/ui/map_floor_rail_test.dart` | a step replaces overlays and announces the destination | green |
| Map shortcuts step floors and reach the rail | At the end of the floor stack | `test/ui/map_floor_rail_test.dart` | a boundary step keeps selection and Auto | green |
| Map shortcuts step floors and reach the rail | Shortcuts outside the map | `test/maps/map_viewport_test.dart` | focused popup and text inputs do not run floor shortcuts | green |
| Map shortcuts step floors and reach the rail | No rail accepts floor shortcuts | `test/ui/map_workspace_controls_test.dart` | a map without a rail ignores floor shortcuts | green |
| The rail supports keyboard and screen reader navigation | Exclusive keyboard navigation | `test/ui/map_floor_rail_test.dart` | exclusive keyboard traversal selects and reveals the deck | green |
| The rail supports keyboard and screen reader navigation | Additive keyboard navigation | `test/ui/map_floor_rail_test.dart` | additive keyboard traversal moves focus before changing visibility | green |
| The rail supports keyboard and screen reader navigation | Escape with a map marker selected | `test/maps/map_viewport_test.dart` | Escape repeats after leaving the rail do not dismiss a marker | green |
| The rail supports keyboard and screen reader navigation | Focus on a collapsed rail | `test/ui/map_floor_rail_test.dart` | expanding from the keyboard focuses the current row | green |
| The rail supports keyboard and screen reader navigation | Collapse keeps focus in the rail | `test/ui/map_floor_rail_test.dart` | collapsing from the keyboard moves focus to Expand | green |
| Help lists the map controls | Controls section content | `test/ui/map_help_test.dart` | the help lists every map control | green |
| Help lists the map controls | Help text has no developer wording | `test/ui/map_help_test.dart` | the help text has no filter keys or raw identifiers | green |
| Marker selection is cleared consistently | Close marker bubble | `test/maps/marker_popup_test.dart` | close clears selection bubble and linked highlights | green |
| Marker selection is cleared consistently | Pin selection | `test/maps/marker_popup_test.dart` | selecting a pin clears marker and retains pin details | green |
| Marker selection is cleared consistently | Empty map and Escape | `test/maps/marker_popup_test.dart` | empty canvas and Escape clear marker selection | green |
| Marker selection is cleared consistently | Escape leaves the floor rail without clearing selection | `test/maps/map_viewport_test.dart` | Escape repeats after leaving the rail do not dismiss a marker | green |
| Existing offline and metadata-only workflows remain independent | Pending source and calibration changes | `test/maps/map_preparation_qualification_test.dart` | default rebuild ignores the pending reviewed floor order | red |
| Existing offline and metadata-only workflows remain independent | Metadata-only preservation fails | `test/maps/map_generation_inputs_test.dart` | metadata preservation rejects forbidden artifact differences | green |
| Floor arrays preserve the reviewed bottom-to-top order | Base in the middle of a deck stack | `test/maps/map_scene_test.dart` | prepared array keeps a middle base without changing initial visibility | green |
| Floor arrays preserve the reviewed bottom-to-top order | Floor order is changed after preparation | `test/maps/map_preparation_qualification_test.dart` | validator rejects a floor array reordered outside its calibration | red |
| Floor arrays preserve the reviewed bottom-to-top order | Reordering does not change artwork or classification | `test/maps/map_preparation_qualification_test.dart`, `test/maps/map_scene_test.dart` | explicit floor-order rebuild preserves frozen facts; reordered Labs tiles keep the incumbent paint stack | red |
| An explicit offline rebuild may update only floor order | A reviewed floor permutation is promoted | `test/maps/map_preparation_qualification_test.dart` | explicit floor-order rebuild preserves frozen facts | red |
| An explicit offline rebuild may update only floor order | The reviewed order is not a permutation | `test/maps/map_generation_inputs_test.dart` | order-only rebuild rejects missing additional and duplicate floors | red |
| An explicit offline rebuild may update only floor order | The permutation would change raster stacking | `test/maps/map_generation_inputs_test.dart` | order-only rebuild rejects reversed overlapping raster overlays | red |
| An explicit offline rebuild may update only floor order | The candidate drifts beyond the reorder | `test/maps/map_generation_inputs_test.dart` | order-only admission rejects source-index and candidate drift | red |

## 1. Floor policy and paint order

- [x] 1.1 Record ADR-0052 and index it in `openspec/architecture.md` (C1). Document navigation array authority, the explicit rebuild guard, separate base and classification rules, and the unchanged default rebuild. Verify the index links to an accepted ADR with the scoped decision.
- [x] 1.2 Write loader and scene regressions for the middle base and overlapping coloured Labs tiles. Compare incumbent and reordered records at the actual paint boundary. Write lowest-layer selection tests for additive reset and exclusive or single-destination selection, including the controller's per-map Auto override and one final visibility state. Confirm the changed-behavior tests are red before code.
- [x] 1.3 Preserve the manifest sequence in `MapFloorPolicy` and the loader. Keep the base flag, layer ownership, extent tie-break and visibility. Add a single controller command for exclusive activation and stepping. Preserve the faded base and tile stacking under D2; expose the shared relative-order rule to the pack tool. Update existing policy and loader assertions to the intended output for the incumbent manifest. Verify `test/maps/map_floors_test.dart`, `test/maps/map_controller_test.dart` and `test/maps/map_scene_test.dart`.

## 2. Floor rail and focus

- [x] 2.1 Write the rail and Map widget regressions in the Test map. Use a small in-memory floor fixture for narrow, long and exclusive cases, and the actual Map workspace for shortcut, map-view and popup priority. Use explicit signals for async work and fake widget time for the toast; do not add real-time correctness assertions or sleeps. Confirm the changed behavior is red before code.
- [x] 2.2 Replace the segmented control with the separate rail. Bind it to the controller, keep viewport and picker geometry, and implement collapse, vertical cues, the two selection models, Auto status and independent You tag (C3, C4). Add a small fixture-only Flutter widget preview for the chosen surface. Verify the corresponding rail and workspace tests.
- [x] 2.3 Implement floor keys, toast, focus transfers and focus-aware pointer priority (C5–C7). Keep the popup mounted and its existing semantics region. Update map help, `DESIGN.md` X13 and the README player description. Remove old segmented assertions and migrate callers in `test/maps/map_viewport_test.dart`, `test/maps/marker_popup_test.dart`, `test/ui/map_screen_test.dart` and `test/ui/map_workspace_controls_test.dart`. Verify those files, `test/ui/map_floor_rail_test.dart` and `test/ui/map_help_test.dart`, including the held-Escape and overlap regressions.

## 3. Rebuild the prepared pack

- [ ] 3.1 Write the pack rule, report and command regressions using the existing small verified-generation fixtures. Cover wrong floor IDs, raster stack order, tampered floor or source-index facts, manifest order versus calibration, audited order-only publication and default rebuild insulation. Tag cases requiring the complete pack fixture as qualification. Confirm the changed behavior is red before code.
- [ ] 3.2 Implement `--reviewed-floor-order` on offline refresh only. Reuse verified inputs, replace only the frozen calibration array order and its source hash, fully validate, enforce before/after preservation and reuse the publication transaction (C2). Report each reordered map and the owner check without labelling unchanged artwork as changed. Document usage and artwork staging order in the CLI help and README. Verify targeted map generation, qualification and change-report cases from 3.1.
- [ ] 3.3 Move the seven underground/technical entries to the front of their authored lists. Keep Icebreaker, Interchange and the single-floor maps in existing order. Run `mise run maps:rebuild -- --reviewed-floor-order` after the machine-load gate permits it. Include the new generation, active pointer, generated pubspec assets and removal of the superseded generation in the same commit. Update assertions on active map order. Verify `mise run maps:check` reproduces the new generation and only calibration evidence and its source index differ among output hashes.
- [ ] 3.4 [evidence] Record the regenerated generation ID, the per-map floor-order report, and the reproduction line after the offline check passes → evidence/map-pack.md
- [ ] 3.5 [user] Check the seven maps named in the order-only report in Blackgrid before merge. Confirm the floor rail lists the expected order and artwork still draws normally. Also check Icebreaker's Infirmary placement and the overflow cues on a short window. No game needs to be running for this check.

## 4. Integration

- [ ] 4.1 Verify `openspec validate floor-deck-rail --strict`, the release-notes check and the focused Dart checks. Run `mise run analyze` and `mise run test` after the gaming check permits heavy work. If the owner is gaming and the identical gates run on the PR commit, record verified CI results instead of claiming local passes.

## Workflow follow-up

- Run Specwright pre-ship review, open the PR as KintsugiBot, watch CI and review, and resolve findings. Run Itsaplan sync at each Specwright step.
- After agent checks, keep the user map check visibly pending until the owner reports it and records the task tick. Ask to archive on the PR branch; sync specs and archive there before merge. The owner merges.
