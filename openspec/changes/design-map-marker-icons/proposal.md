# Proposal

## Why

All 19 marker categories on the native map are drawn as the same placeholder ring: a dark disc, a 2 px ring and a centre dot. Only four colours tell them apart. Exits are green, hazards red, saved pins light blue, and everything else is gold (`lib/ui/map_workspace.dart:623-681`). In a raid, a player cannot tell a transit from a stash, a boss spawn from a lock, or a quest item from loose loot without opening each marker.

The reference companion uses tarkov.dev's marker icons. That set is MIT in name, but its originals came from the Tarkov wiki (`the-hideout/tarkov-dev` commit `bb40b16`), so their rights are unclear. Blackgrid must draw its own.

This change serves milestone **M4.5 - player-facing polish, item icons and own map markers** (change 3 of 7, independent). It produces the icon set for the exit criterion "Every marker category draws its own Blackgrid-authored icon … Each icon file has its provenance recorded, and no third-party marker art ships." Drawing the icons on the map and adding the bundle-time provenance check is `add-map-marker-icons` (change 4). The Marker preferences grid that reuses them is `redo-marker-preferences` (change 5).

## What Changes

- **A Blackgrid-authored icon set: one icon per marker category,** keyed by the filter keys the map already uses. That is 18 marker keys plus `CustomPins` (19 in all). `Labels` is a legacy import key that no marker has, so it gets no icon.
- **Icons are small vector glyphs in one consistent style.**
  - Each glyph is drawn in a single tint, readable at 24 px on the dark map.
  - No raster images, text, fonts or external references.
  - The glyphs compile with the build-time vector compiler the map already uses (ADR-0005).
- **A category palette that keeps today's meanings.**
  - Exits stay green, hazards red and saved pins light blue.
  - Cyan stays reserved for highlighted markers.
  - Every colour reaches a minimum contrast against the marker background.
  - Shape, not colour alone, tells similar categories apart, such as PMC, Scav and shared extracts.
- **A provenance record for every icon file.**
  - Each record holds the file's hash, the author, the method (hand-authored, or AI-assisted with the tool named), any concept source, and the date.
  - Third-party marker art is never used, traced or imitated, and the records cannot claim a third-party origin.
- **An offline check** that validates the set: every category has exactly one icon, each file follows the restricted vector form and compiles, each record is complete and matches its file, and the palette rules hold.
- **An offline preview generator.**
  - It writes a self-contained preview sheet that a browser opens.
  - The sheet shows every category at 24 px and enlarged, on dark, mid and light map tones.
  - Each icon appears in the normal, selected, dimmed and highlighted states, with a colour-vision-deficiency row.
  - Style directions can be compared side by side.
  - The user picks the style and approves the final set from these previews. Nobody needs to launch the app or the game.
- **A design record** of the style rounds, the user's picks and the palette.
- Nothing is bundled into the app yet. The app's look and behaviour do not change in this change.

## Capabilities

### New Capabilities
- `map-marker-icons`: the project-authored icon set for map marker categories. It covers category coverage, the icon file form, the category palette, provenance, the validation check and the preview sheet. `add-map-marker-icons` later extends it with how the map draws the icons.

### Modified Capabilities
None. `release-bundle-integrity` covers bundled native files and game artwork. These icons are not bundled until change 4, which decides how the bundle check covers them.

## Impact

- **New source files:** an icon directory holding one SVG per category and a manifest (category → file, colour role, provenance). There is also a design record under `docs/`. Neither is listed in `pubspec.yaml` assets in this change.
- **New offline tools** under `tool/`, with tests under `test/tool/`: the set checker and the preview generator. They reuse `vector_graphics_compiler` (already a dev dependency) and add no new dependency.
- **A new ADR:** map marker icons are project-authored, restricted-form SVG glyphs with a per-file provenance manifest, tinted by category role, and no third-party marker art. Change 4 builds on it.
- **User checks:**
  - picking the style direction;
  - approving the final set from the rendered previews;
  - judging glyph distinctness and 24 px readability.

  Agents never launch the app or the game for these checks (AGENTS.md).
- No runtime code, data, settings, schema or network change. `mise run test` gains only fast offline tool tests.
