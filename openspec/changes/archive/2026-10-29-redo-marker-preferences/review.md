# Review

## Metadata

- **Round:** 1
- **Prior round:** This re-check covers only the round-1 Required Changes 1 and 2, which came from the Moderate unknown-key finding. The round-1 verdict was APPROVE_WITH_CHANGES with CHANGES_APPLIED: no.
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:**
  - Round 1: openspec/changes/redo-marker-preferences/proposal.md, specs/marker-preferences/spec.md and design.md; openspec/architecture.md (the ADR index); docs/adr/0023-project-authored-map-marker-icons.md; docs/adr/0002-sdk-notifiers-and-composition-root.md; openspec/specs/map-rail/spec.md and openspec/specs/map-marker-icons/spec.md; lib/ui/map_screen.dart, lib/ui/map_workspace.dart, lib/ui/theme.dart, lib/maps/map_marker_icons.dart, lib/maps/prepared_map.dart, lib/domain/settings.dart, lib/application/map_controller.dart, lib/application/settings_controller.dart, lib/application/app_services.dart and lib/data/database.dart; test/maps/map_viewport_test.dart, test/ui/map_screen_test.dart and test/ui/map_marker_painting_test.dart; the "Dart and Flutter code" section of AGENTS.md. Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test and flutter-add-widget-test.
  - Re-check: the current proposal.md, spec.md and design.md (D1, D2, D3, the new D5, Failure & Visibility, Flow & State Gaps, Mechanism Ledger and Risks), and the Rebuttals in review.md, checked again against lib/domain/settings.dart:162-165, lib/application/settings_controller.dart:16-20,59-61, lib/application/app_services.dart:204-209,237, lib/application/map_controller.dart:76-79,567-568 and lib/ui/map_screen.dart:307,436-443.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

1. **The unknown-key tile the spec requires saves a key that stops Blackgrid from starting next time, and the design says the opposite.** (Round 1.)
   - The requirement "Category keys have fixed player-facing labels", scenario "Unknown key keeps a tile", required that clicking a `Ziplines` tile hide those markers. The tile calls `setMarker`, which saves through `database.saveSettings` (`lib/application/settings_controller.dart:59-61`, `lib/data/database.dart:187-194`). That writes `markerFilters` with `Ziplines` into the preferences row, even when Save marker filters is off (`lib/domain/settings.dart:148`).
   - On the next start, `AppSettings.fromJson` throws for any key not in `markerCategories` (`lib/domain/settings.dart:162-165`), and `AppServices.open` rethrows (`lib/application/app_services.dart:204-209`), so Blackgrid does not start. Show all and Hide all wrote every applicable key, unknown ones included (`lib/ui/map_screen.dart:436-443`).
   - Unknown keys can really happen (`lib/maps/prepared_map.dart:703`; ADR-0023 Consequences). The design's Failure & Visibility row wrongly said the bundle and pack checks catch them.
   - **Re-check: resolved.** See Required Changes and Rebuttals.

### Suggestions

1. Keep the tile's label from being announced twice: `excludeSemantics: true` or `MergeSemantics`. (Round 1.)
2. Make the order rule ("Saved pins last") agree with the scenario that put unknown keys after Saved pins. (Round 1.)
3. Make the tile painter's `shouldRepaint` compare the key and the shown state. (Round 1.)
4. Build the expected semantics label at `test/maps/map_viewport_test.dart:772` with `markerCategoryLabel`. (Round 1.)
5. New, non-blocking, from the re-check:
   - The scenario "Hide all then Show all" says "no marker or pin is drawn". Since D5, markers with an unsaveable key stay drawn after Hide all, as the scenario "Bulk action with an unsaveable category" requires. The two are consistent only on a map that has no unsaveable key. Changing the THEN to "no marker with a tile, and no pin, is drawn" would remove the ambiguity.
   - proposal.md Impact says existing tests "find tiles by label instead", while design Risks and D3 say `ValueKey('marker-tile-<key>')`. Neither changes behaviour.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **Applied.** In design.md, Failure & Visibility, replace the row "Unknown key in a prepared map" with a row that says what actually happens, and remove the claim about the bundle and pack checks.
   - Verified. The row now says: no tile and no bulk write (D5); the markers stay drawn; the marker list shows the raw key; recovery is to add the key to the D1 table and to `markerCategories`.
   - It also says "No offline check catches an unmapped pack category today (ADR-0023 covers icons, not pack keys)". That matches ADR-0023 Consequences and `lib/maps/prepared_map.dart:703`. The false claim is gone.
   - D5's "Why" bullet describes the launch failure with the correct citations: `settings.dart:162-165` and `app_services.dart:204-209`.
2. **Applied.** Record an explicit decision: either out of scope with a follow-up issue, or fixed in this change with a scenario showing that settings load again.
   - Verified. The author chose to fix it in this change, as the new D5. Tiles and the Show all and Hide all writes use only `markerPreferenceKeys(...)`, which keeps only keys in the D1 table. A unit test pins the table to `markerCategories` minus `Labels`, so every key that is written passes `AppSettings.fromJson`.
   - Against the code:
     - Today's bulk writes iterate `applicableCategories` (`map_screen.dart:307,441`); D5 replaces that list.
     - An unwritten key stays drawn, because `MapController` hides only on an explicit `false` (`map_controller.dart:567-568`).
     - `setMarker` is the only other writer of `markerFilters`, and the tiles are its only UI caller for categories.
   - The rejected alternatives are recorded with reasons: loosening `fromJson` weakens an integrity check, and an in-memory store would add a second owner. The trade-off, that an unsaveable category cannot be hidden, is stated in D5, in the Mechanism Ledger with the evidence that would reverse it, and in the proposal.
   - The spec drops "Unknown key keeps a tile" and "Unknown keys come last". It adds "Unsaveable category gets no tile", "Every saveable key has a label" and "Bulk action with an unsaveable category", where the settings load on the next start with no `Ziplines` entry. That is the required reload scenario, adapted to the chosen fix.
   - The proposal matches: line 13, and line 16's note on the saveable-key limit.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

Author, after round 1:

- **Moderate (unknown-key tile stops the next launch): fixed.** Accepted by reviewer.
  - Author: Verified against `lib/domain/settings.dart:162-165` and `lib/application/settings_controller.dart:18,59`. For Required change 1, the Failure & Visibility row now says that no offline check catches an unmapped pack key, and the bundle and pack-check claim is gone. For Required change 2, I chose to fix it in this change. Design D5 records the decision: tiles and Show all/Hide all cover only saveable keys (`markerPreferenceKeys`). The spec drops "Unknown key keeps a tile" and "Unknown keys come last" and adds "Unsaveable category gets no tile", "Every saveable key has a label" and "Bulk action with an unsaveable category", where the settings load again on the next launch. The proposal is updated to match.
  - Reviewer: D5, the Failure & Visibility row, the Flow & State Gaps entry, the Mechanism Ledger row, the spec scenarios and the proposal are all present and consistent with the cited code.
- **Suggestion (double announcement): fixed.** Accepted by reviewer.
  - Author: D3 adds `excludeSemantics: true`.
  - Reviewer: D3 now reads `Semantics(toggled: shown, label: label, button: true, excludeSemantics: true)`.
- **Suggestion ("Saved pins last" vs unknown keys after it): fixed by D5.** Accepted by reviewer.
  - Author: Unknown keys get no tile, and the order rule now says Saved pins is last, with a map-order scenario.
  - Reviewer: The order requirement and its scenarios no longer conflict.
- **Suggestion (tile `shouldRepaint`): fixed.** Accepted by reviewer.
  - Author: D2 compares the key, the shown state and the icons instance.
  - Reviewer: D2 says exactly this.
- **Suggestion (`map_viewport_test.dart:772` raw-key label): fixed.** Accepted by reviewer.
  - Author: Risks names it, and the test builds the label with `markerCategoryLabel`.
  - Reviewer: Risks now names the test and the change.
