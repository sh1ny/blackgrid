# Proposal

## Why

M8 (map labels and popups) aims for a native map that reads like tarkov.dev's. Today an extract is an unnamed green badge: the player has to click it to learn its name. Every zone outline (extracts, transits, hazard zones, quest objective zones, switches) draws in the same hazard red and always shows. Extract polygons cover the exits and read as danger. The map also never says that the player's position comes from the game's own screenshots, so a player who never presses the screenshot key sees no position and gets no explanation why.

This change serves M8's exit criterion "Extract names show beside their badges in faction colours, and outlines use their category colour and show on hover or selection, proved by widget or painter tests". It also prepares the user check "On real maps the labels, extract names and bubbles read correctly". It is change 2 of M8, after `unpin-map-toolchain`. It needs no new pack version: names, factions and outlines are already in the bundled pack.

## What Changes

- Each visible extract and transit badge gets its name drawn beside it on the map canvas. The name is drawn at a fixed screen size with a dark halo, in its faction's colour: PMC, Scav, shared or transit. The four colours are ours and follow ADR-0023's palette rules: at least 3:1 contrast against `#090F0D` and outside the cyan highlight band. A label fades with its dimmed badge and hides with its category filter.
- Badges are unchanged. Extract badges stay exit green, as ADR-0023 and the `map-marker-icons` spec require; only the name carries the faction colour.
- Zone outlines draw in their category's role colour from the marker icon manifest, instead of red for every category: exit green for extracts and transits, danger red for hazard zones, quest gold for quest objectives and utility violet for switches.
- Extract and transit outlines draw only while their marker is hovered or selected. Other categories' outlines keep showing at all times. A hidden outline is not a click target, and the map's accessibility target for that marker covers only its badge.
- Hovering over a marker on the map is tracked, so the hovered extract shows its outline.
- A `?` help button on the map toolbar opens a short help dialog. It explains that the player's position comes from screenshots taken with the game's own screenshot key and read from the screenshot folder in Settings, and that Blackgrid never captures the screen for it. It also lists the map controls.

## Capabilities

### New Capabilities
- `map-zone-labels`: how the native map draws marker names and zone outlines on the canvas: which markers get a name, in what colour and style, how outlines are coloured, and when an outline is shown and can be hit. `add-location-labels` later adds place labels to this capability.
- `map-help`: the map's help button and what its help tells the player about position tracking and controls.

### Modified Capabilities
<!-- None: badge drawing, badge states and the palette rules in `map-marker-icons` keep their requirements. Its "Hazard zone keeps its outline" scenario (a red polygon for `HazardZones`) stays true, because the danger role is red. -->

## Impact

- `lib/ui/map_workspace.dart`: painter (outline colour and visibility, name labels), hover tracking, `?` button and help dialog.
- `lib/application/map_controller.dart`: `hitTestMarker` stops hitting hidden outlines.
- New pure-Dart rules for label factions, label colours and outline visibility. They live beside `lib/domain/marker_categories.dart`.
- `lib/maps/map_marker_icons.dart`: the outline colour is read through the existing `colourFor`; the manifest and icon files are unchanged.
- Tests: rule tests for the faction and outline policy and the palette, painter or widget tests for labels, outlines, hover and the help dialog.
- No change to the map pack, its tooling or the marker icon set. No new dependency.

## Release Notes

The map now names its extracts and transits beside their badges, coloured by who can use them, and draws each zone outline in its category's colour. Extract outlines appear when you hover over or select an extract. A new help button explains how your position gets onto the map.

### Added
- Extract and transit names on the map, coloured for PMC, Scav, shared and transit exits.
- A `?` help button on the map: your position comes from screenshots taken with the game's own screenshot key.

### Changed
- Zone outlines use their category's colour instead of red. Extract and transit outlines show only while you hover over or select the extract.
