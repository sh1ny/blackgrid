# Tasks

Skills for every Dart group (AGENTS.md "Dart and Flutter code"): `dart-use-pattern-matching`, `dart-add-unit-test`, `dart-write-documentation` and `dart-run-static-analysis`. Groups 3 and 4 also use `flutter-add-widget-test`.

Rules for every group:
- The game is never launched or touched. Painter and widget tests go through `test/support/map_widget_harness.dart` with small synthetic maps and an injected icon manifest, as `test/ui/map_marker_painting_test.dart` does.
- Hover is driven with `tester.createGesture(kind: PointerDeviceKind.mouse)` and `moveTo`, never with sleeps.
- Rule permutations (factions, outline visibility, palette) are proved in the domain test, not in widget tests (AGENTS.md: cheapest layer).

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| map-zone-labels → Extracts and transits show their names beside their badges | Visible extract shows its name | test/ui/map_zone_labels_test.dart | a PmcExtracts marker paints its name right of its badge | red |
| map-zone-labels → Extracts and transits show their names beside their badges | Other categories stay unnamed | test/domain/map_zone_style_test.dart | only the four exit keys have a label faction | red |
| map-zone-labels → Extracts and transits show their names beside their badges | Hidden category draws no name | test/ui/map_zone_labels_test.dart | hiding ScavExtracts removes its badge and name only | red |
| map-zone-labels → Extracts and transits show their names beside their badges | Extract with an empty name | test/ui/map_zone_labels_test.dart | a blank extract name paints its badge and no label | red |
| map-zone-labels → Name labels are coloured by faction | Each faction draws its own colour | test/ui/map_zone_labels_test.dart | four factions paint four label colours over exit-green badges | red |
| map-zone-labels → Name labels are coloured by faction | Palette rule rejects a bad label colour | test/domain/map_zone_style_test.dart | label palette meets contrast, hue band and distinctness rules | red |
| map-zone-labels → Name labels are coloured by faction | Highlighted extract keeps its faction name colour | test/ui/map_zone_labels_test.dart | a raid-highlighted Scav extract keeps its Scav label colour | red |
| map-zone-labels → Name labels stay readable at every zoom | Zooming keeps the text size | test/ui/map_zone_labels_test.dart | zooming moves the label but keeps its font size | red |
| map-zone-labels → Name labels stay readable at every zoom | Dimmed extract fades its name | test/ui/map_zone_labels_test.dart | a dimmed extract paints its name at 0.22 alpha | red |
| map-zone-labels → Name labels stay readable at every zoom | Overlapping badge stays on top | test/ui/map_zone_labels_test.dart | names paint after outlines and before every badge | red |
| map-zone-labels → Zone outlines use their category colour | Categories draw their own outline colours | test/ui/map_zone_labels_test.dart | hazard, quest and switch outlines paint in their role colours | red |
| map-zone-labels → Zone outlines use their category colour | Icons not loaded yet | test/ui/map_zone_labels_test.dart | before icons load a quest outline paints gold | red |
| map-zone-labels → Extract and transit outlines show on hover or selection | Extract outline is hidden at rest | test/ui/map_zone_labels_test.dart | an extract at rest paints no outline | red |
| map-zone-labels → Extract and transit outlines show on hover or selection | Hover reveals the outline | test/ui/map_zone_labels_test.dart | hovering an extract badge paints its outline until the pointer leaves | red |
| map-zone-labels → Extract and transit outlines show on hover or selection | Moving into the revealed outline keeps it | test/ui/map_zone_labels_test.dart | moving from the badge into the revealed area keeps the outline | red |
| map-zone-labels → Extract and transit outlines show on hover or selection | Selection keeps the outline | test/ui/map_zone_labels_test.dart | a selected extract keeps its outline after the pointer leaves | red |
| map-zone-labels → Extract and transit outlines show on hover or selection | Hazard zone outline always shows | test/domain/map_zone_style_test.dart | outlineDrawn is true for non-exit keys at rest | red |
| map-zone-labels → Extract and transit outlines show on hover or selection | Pointer leaves the map | test/ui/map_zone_labels_test.dart | leaving the viewport clears the hovered outline | red |
| map-zone-labels → A hidden outline is not a click target | Click inside a hidden extract area | test/maps/map_controller_test.dart | a hidden extract outline is not hit | red |
| map-zone-labels → A hidden outline is not a click target | Click inside a drawn hazard zone | test/maps/map_controller_test.dart | a hazard outline is still hit | red |
| map-zone-labels → A hidden outline is not a click target | Accessibility target of an extract | test/ui/map_zone_labels_test.dart | a hidden extract's semantics rect is its badge circle | red |
| map-help → The map toolbar has a help button | Open and close the help | test/ui/map_help_test.dart | the help button opens and Close closes the help, keeping the selection | red |
| map-help → The map toolbar has a help button | Help without artwork | test/ui/map_help_test.dart | the help button works with no artwork loaded | red |
| map-help → The map toolbar has a help button | Escape closes only the dialog | test/ui/map_help_test.dart | Escape closes the help and keeps the selected marker | red |
| map-help → Help explains how the player's position reaches the map | Position section content | test/ui/map_help_test.dart | the help explains the screenshot key, folder and no-position case | red |
| map-help → Help explains how the player's position reaches the map | No promise of live capture | test/ui/map_help_test.dart | the help text makes no screen-capture claim | red |
| map-help → Help lists the map controls | Controls section content | test/ui/map_help_test.dart | the help lists every map control | red |
| map-help → Help lists the map controls | Help text has no developer wording | test/ui/map_help_test.dart | the help text has no filter keys or raw identifiers | red |

## 1. Label and outline rules

- [ ] 1.1 Write `test/domain/map_zone_style_test.dart` (rows "Other categories stay unnamed", "Palette rule rejects a bad label colour", "Hazard zone outline always shows"). Cover every key in `markerCategoryLabels`, plus an unknown key, for `labelFactionFor` and `outlineDrawn` with all four hover/selected combinations. Check the four label colours against `#090F0D` contrast ≥ 3:1, the 170°–190° hue band at ≥ 10% saturation, and pairwise distinctness, with a failure message that names the faction, colour and rule. Verify it fails because `lib/domain/map_zone_style.dart` does not exist yet.
- [ ] 1.2 Implement `lib/domain/map_zone_style.dart` per design D1 and D3: `LabelFaction`, `labelFactionFor`, `labelColourFor` with the four colours, and `outlineDrawn`, with `///` docs. Verify that 1.1 passes and flip its three rows green.

## 2. Hit testing respects hidden outlines

- [ ] 2.1 Add failing tests to `test/maps/map_controller_test.dart` (rows "Click inside a hidden extract area", "Click inside a drawn hazard zone"). Use a synthetic map with an extract and a hazard zone, each with an outline. A point inside the extract polygon away from its badge returns null at rest, and returns the extract when `hoveredMarkerId` is the extract or it is selected. A point inside the hazard polygon returns the hazard. Verify the extract-at-rest case fails against the current `hitTestMarker`.
- [ ] 2.2 Add the optional `hoveredMarkerId` to `MapController.hitTestMarker`, and filter its outline pass with `outlineDrawn` using the hover id and `_selectedMarkerId` (design D3). Verify that 2.1 and the existing `map_controller_test.dart` hit tests pass, and flip both rows green.

## 3. Painter: outline colours, hover, names and semantics

- [ ] 3.1 Write failing painter and widget tests in `test/ui/map_zone_labels_test.dart` for every `map-zone-labels` row mapped to that file. Use a synthetic map with one PMC, one Scav, one shared extract, one transit, a hazard zone, a quest objective zone, a switch with an outline and a `locks` marker. Hover goes through a mouse `TestGesture`, and names are asserted through the recorded canvas (`paints..paragraph`, or by intercepting text on a recording canvas, whichever the harness supports). Update the existing `map_marker_painting_test.dart` hazard test from `Colors.red`/`redAccent` to the danger role colour `#FF5252` (the `map-marker-icons` "red zone polygon" scenario still holds). Verify that the new tests fail for the right reason: red outlines, no names, extract outlines always drawn.
- [ ] 3.2 Implement design D2, D4 and D5 in `lib/ui/map_workspace.dart`:
  - outline colour from `markerIcons.colourFor`;
  - `_hoveredMarker` with a generation guard, set through a `MouseRegion` (`onHover`/`onExit`) and passed to `hitTestMarker` and the painter;
  - the three paint passes (outlines, names, badges), with the name `TextPainter` and halo;
  - the semantics rect limited to the badge circle when `outlineDrawn` is false;
  - clicks via `_select` passing the hover id.

  Verify that 3.1 and the whole `test/ui/` map suite pass, then flip the rows green.

## 4. Map help

- [ ] 4.1 Write failing widget tests in `test/ui/map_help_test.dart` for every `map-help` row. Cover the tooltip "Map help", open and close with Close and with Escape (the selected marker stays selected), with and without artwork, the position text (screenshot key, Settings screenshot folder, no screenshot means no position, never captures the screen), every control from the spec, and no `PmcExtracts`-style keys or `camelCase` identifiers in the dialog text. Verify that they fail because there is no button yet.
- [ ] 4.2 Implement design D6: the `?` `IconButton` at the end of the toolbar, the "Map help" `AlertDialog` with "Your position" and "Controls" sections, and focus returned to the map on close. Verify that 4.1 passes, then flip the rows green.

## 5. Integration checks

- [ ] 5.1 Run `mise run analyze` and `mise run test`, and format with `dart format`. Both must pass with no new analyzer issues.
- [ ] 5.2 Re-check the proposal's `## Release Notes` against what shipped and run `mise run release-notes -- --check openspec/changes/add-extract-labels/proposal.md` (exit 0).

## Workflow follow-up

- User check (unverified until the user reports it; agents do not launch the app while the game runs): on real maps, extract and transit names read correctly in their faction colours, extract outlines appear on hover or selection, other outlines use their category colours, and the help dialog reads clearly. This feeds M8's user-verified exit criterion.
