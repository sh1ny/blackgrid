# Review

## Metadata

- **Round:** 2
- **Prior round:** Round 1 returned REVISE for raster stacking and raised seven moderate findings about preservation, focus, presentation, admission, carried constraints, and claims.
- **Reviewer:** fresh-context subagent (omp)
- **Reviewed:** Revised proposal, design, `map-controls`, `map-help` and `prepared-map-packs` deltas, and prior review; corresponding main specs and `map-marker-popups`; all tracked design citation ranges and relevant surrounding code in `lib/ui/{map_workspace,map_screen,marker_popup,shell}.dart`, `lib/ui/ember/`, `lib/domain/map_floors.dart`, `lib/application/map_controller.dart`, `lib/maps/{prepared_map,native_map_scene}.dart`, `tool/maps/{calibration,inventory,pack,prepare,svg}.dart`, `mise.toml`, `test/maps/map_viewport_test.dart`, and the tracked active pack pointer and manifest. ADRs 0005, 0033–0037, 0039 and 0050. All seven named project skills loaded. No referenced stores were reported. Static review only; no app, game, preview, build, formatter, analyzer or test was run.

## Findings

### Critical (blocking)

None.

### Moderate

1. **A held Escape can close the marker just after returning focus to the canvas.** `design.md:53,170` and the `map-controls` delta at `:115–128` preserve selection on Escape from the rail, but do not fence key repeats across the focus handoff. The canvas accepts `KeyRepeatEvent` (`lib/ui/map_workspace.dart:410–414`), and its Escape branch clears both marker and pin selection (`:450–455`). Escape down in the rail followed by a repeat after the canvas takes focus therefore clears the selection without a second press. The unchanged `map-marker-popups` main spec also still requires clearing on Escape “with the map active” (`openspec/specs/map-marker-popups/spec.md:28–41`), which now covers two contexts with opposite outcomes. Define the focus boundary in that spec and test one held press versus a second physical press; the existing canvas test only sends Escape down/up (`test/maps/map_viewport_test.dart:636–643`).
2. **The revised overlap scenario does not state when the popup loses precedence.** D3 puts the rail in front when it owns keyboard focus (`design.md:45`), but the `map-controls` overlap scenario at `:71–74` says the popup remains readable and its Close action remains clickable, without limiting that assertion to the unfocused rail. The card can clamp to the left margin and its Close button is inside the card (`lib/ui/marker_popup.dart:206–223,305–318`). Where the card or Close target lies under the focused rail, ordinary front-to-back hit testing makes that part of the card unavailable. Record the chosen focus-dependent paint **and hit-test** rule in the requirement and in Carried constraints, and assert that the popup regains normal pointer access after focus returns to the canvas. This keeps the user's D3 decision instead of asking implementers to satisfy incompatible expectations in the overlap.
3. **Focus is not specified when the rail replaces a focused compact or expanded control.** The design defines what happens when the whole rail disappears (`design.md:155`), but the expanded/collapsed transition diagram (`:100–109`) has no corresponding handoff. The compact scenario (`map-controls` delta `:130–132`) focuses Expand and activates it without asserting focus after that action exits the tree. The rail is a sibling of the canvas focus subtree (`lib/ui/map_workspace.dart:766–769,909–930`), so losing that focused node does not route the next key through the canvas; it can leave the user having to Tab back in before Up/Down, Page keys or Escape work. Make both directions of the in-rail handoff explicit and exercise them with keyboard events.
4. **The successful promotion scenario also describes a permutation that must be rejected.** In the `prepared-map-packs` delta at `:34–44`, the success WHEN requires only the same IDs in another order. The negative case satisfies that condition too: `[Technical_Level, Second_Level, First_Level]` has the same Labs IDs (`tool/maps/calibration.dart:258–262`) but puts Technical before Second after D2's base-relative rotation, reversing the incumbent overlay order. The design gate at `design.md:37` resolves the implementation; the positive scenario needs the same precondition so the spec does not demand promotion for the intended negative fixture.

### Suggestions

None.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. In the map-controls keyboard requirement and `design.md` flow, specify that a fresh Escape key-down returns focus from the rail without clearing selection, and that Escape repeats cannot clear selection on the canvas following that handoff. Update the `map-marker-popups` “Marker selection is cleared consistently” requirement and its Escape scenario through a delta: canvas or popup Escape clears; rail Escape does not. Extend the widget scenario to send Escape down with rail focus, then a repeat after the canvas receives focus, and assert the selected marker remains. Send key-up and a fresh Escape down and assert normal canvas clearing.
2. In map-controls “The rail exposes floors outside its viewport,” specify that the popup takes paint and pointer precedence where it overlaps an unfocused rail, that the focused rail takes precedence while it owns keyboard focus, and that losing rail focus restores normal popup precedence without changing selection or viewport. Extend the overlap scenario to cover all three phases, including a hit-testable Close target before and after rail focus. Add one carried constraint pointing to that same requirement. Keep both controls mounted and retain the existing Map semantics boundary.
3. In the rail focus flow and map-controls keyboard requirement, specify an in-rail focus destination when a focused control switches presentation: collapse hands focus to the compact Expand action; expanding with rail focus reveals and focuses the current row without selecting a different floor. Add an expanded-to-compact assertion and extend the compact-to-expanded scenario to assert the destination receives focus and can be operated immediately by keyboard.
4. In “A reviewed floor permutation is promoted” in the prepared-map-packs delta, add “and the new order preserves the existing additive raster overlay stack” to the WHEN. Keep the separate rejection scenario unchanged.

CHANGES_APPLIED: yes

## Rebuttals

- Round 1 Critical 1 is resolved by D2 and the negative permutation scenario. The checked-in v5 manifest has the base first on the affected additive maps. Moving Technical before First leaves Labs' non-base order Second/Technical; the proposed moves on the vector maps do not permute their tile-backed floors. The revised contract rejects a relative tile-stack change.
- Round 1 Moderate 1 is resolved by rebinding both frozen calibration and builder context, checking the exact source index except the calibration hash, and adding a drift scenario. Moderate 2's primary-focus gate, no-rail no-op and help distinction are present; round 2 finds the remaining Escape repeat interaction after focus moves. Moderate 3 now has an explicit D3 layering choice and retains the shared semantics boundary; round 2 asks for the matching pointer and spec assertions.
- Round 1 Moderates 4–7 are resolved: compact Auto and step announcements are specified; the artwork admission sequence, distinct operator report and owner's check are retained; collapse lifetime and shortcut ownership have destinations and scenarios; the external citation is removed and the toast expiry is 2.6 seconds. The tracked ranges support the revised design claims.

Independent re-check of round 2's four required changes only:

1. **Fixed; accepted by reviewer.** `design.md:171` makes rail Escape a key-down handoff and prevents canvas repeats from clearing the marker or pin. `specs/map-controls/spec.md:117,127–130` requires the down/hold/release/fresh-press sequence and the corresponding selection outcomes. `specs/map-marker-popups/spec.md:3–4,14–21` separates canvas and popup dismissal from rail Escape and covers repeats through the handoff. `proposal.md:24` records the added capability change.
2. **Fixed; accepted by reviewer.** `specs/map-controls/spec.md:52,71–75` assigns both paint and pointer priority by focus, asserts Close works before and after rail focus, and preserves marker selection and map view through all three phases. `design.md:84` carries the invariant to that requirement; `design.md:45,171` preserves both mounts and the shared semantics boundary and restores popup priority after rail focus.
3. **Fixed; accepted by reviewer.** `design.md:104–105,171` and `specs/map-controls/spec.md:117,132–139` cover both focus destinations: Expand on collapse, and the revealed current row without changing selection on expansion. Both scenarios assert that the next applicable keyboard action works without another Tab.
4. **Fixed; accepted by reviewer.** `specs/prepared-map-packs/spec.md:34–36` now qualifies promotion with raster-stack preservation; the separate rejection scenario at `:42–44` is unchanged.

No unrelated findings or claims were reopened. This was an artifact re-check; no tests were run.
