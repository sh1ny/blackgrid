# Proposal

## Why

The native map still draws every marker category as the same placeholder ring: a dark disc, a 2 px ring and a 3 px dot, told apart by four colours only (`lib/ui/map_workspace.dart:620-681`). `design-map-marker-icons` produced and the user approved (2026-10-28) a Blackgrid-authored set of 19 single-tint glyphs with a role palette and a per-file provenance manifest (`assets/map_markers/`, ADR-0023), but nothing in the app draws them yet and nothing in the release bundle check covers them.

This change serves milestone **M4.5 - player-facing polish, item icons and own map markers** (change 4 of 7, needs `design-map-marker-icons`, which is merged). It closes the exit criterion "Every marker category draws its own Blackgrid-authored icon. Selection, dimming, highlighted exits and saved pins still work. Each icon file has its provenance recorded, and no third-party marker art ships." `redo-marker-preferences` (change 5) reuses the loaded icons for its tiles.

## What Changes

- **The map draws each marker's own icon** in place of the placeholder ring.
  - A marker is drawn as a badge: a dark disc with a ring in the category's role colour, and the category's glyph tinted in the same colour. Size, ring and glyph area come from the manifest's badge geometry (24 px, 30 px when selected, 16 px glyph, 2 px ring).
  - The states keep their meaning: a selected marker draws at the selected size; a highlighted marker (linked or raid highlight) draws its ring and glyph in the highlight cyan and keeps today's selected size, unlike the approved sheet, which drew it at 24 px; a dimmed marker draws the whole badge at 22% opacity. The glyph stays 16 px at every badge size, as on the sheet.
  - Saved pins draw the `CustomPins` icon in the pin colour; a pin that does not match the search is dimmed, as today.
  - Hazard zones keep their red polygon and draw the `HazardZones` icon at the marker point.
  - Hit testing, semantics, the browse list and keyboard behaviour do not change.
- **Safe fallback.** A marker whose filter key has no icon (a future raw pack category passed through `_markerFilterKey`), and every marker while the icons are still loading or after they fail to load, draws the badge with the old centre dot in its role colour, or gold when it has no role. A load failure is logged once; the map keeps working.
- **The release icon set is bundled in compiled form.**
  - A new offline tool compiles each release SVG to `assets/map_markers/compiled/<name>.vec` with exactly the checker's compile flags. The `.vec` files are committed, like the map packs' compiled artwork.
  - `pubspec.yaml` bundles `assets/map_markers/manifest.json` and `assets/map_markers/compiled/` only. The SVG sources and any `prompts/` folder stay out of the app.
  - A fast test fails when a committed `.vec` differs from compiling its SVG, or when a compiled file has no manifest entry.
- **The release bundle check covers map marker icons.** A new step validates the repository's release set with the existing set checker, then confirms that the bundled `assets/map_markers/` holds the same manifest bytes and exactly one compiled file per manifest icon, each equal to compiling its provenance-checked SVG, and nothing else. An unlisted or altered icon file in the bundle fails the check.
- The `openspec/specwright.yaml` edit already on main's working tree (the retired `kintsugimira` reviewer removed) is committed with this change.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `map-marker-icons`: adds how the map draws the set (badge, tint, states, pins, fallback) and how the release set is compiled and kept in step with its sources.
- `release-bundle-integrity`: adds a requirement that every bundled map marker icon matches a provenance-checked manifest entry and that no other file ships in the icon directory.

## Impact

- **App code:** a new marker icon loader and badge style in `lib/maps/` (reads the bundled manifest, decodes each `.vec` once with `vector_graphics`, exposes the glyphs and role colours), wired through `AppServices` like `ItemIconCache`. `_MapPainter` in `lib/ui/map_workspace.dart` draws badges from it. No change to `PreparedMap`, `MapController`'s filtering, settings or persisted data.
- **Assets:** 19 new committed `.vec` files under `assets/map_markers/compiled/` (`-text` already applies to `assets/map_markers/**`); two new `pubspec.yaml` asset entries.
- **Tools:** `tool/markers/compile.dart` (new); `tool/vision/check_bundle.dart` gains a map-marker step that calls `tool/markers/icon_set.dart`. No new dependency: `vector_graphics` is already a runtime dependency and `vector_graphics_compiler` a dev dependency.
- **Tests:** unit tests for the badge style permutations and the loader's fallback paths, a widget test that the map paints icons, compile-sync and bundle-check tests. All offline and fast.
- **ADRs:** constrained by ADR-0005, ADR-0012, ADR-0022 and ADR-0023; no new ADR expected (this change carries out ADR-0023's consequences).
- **User checks:** the in-raid look of the icons on the map, unverified until the user reports it. The exit criterion itself is agent-verified.
