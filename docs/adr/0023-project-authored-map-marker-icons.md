# 0023 - Map marker icons are project-authored single-tint SVG glyphs with a provenance manifest

- Status: accepted
- Date: 2026-10-28 (M4.5 change `design-map-marker-icons`)
- Source: change `design-map-marker-icons` (design D1-D7)

## Context and problem

Every marker category on the native map draws the same placeholder ring, told apart by four colours only (`lib/ui/map_workspace.dart:623-681`). The reference companion uses tarkov.dev's marker icons, whose originals came from the Tarkov wiki, so their rights are unclear. Blackgrid needs its own icons, one per marker category, and a record that proves where each file came from. The set is drawn in this change and drawn on the map by `add-map-marker-icons` (change 4).

## Decision

- **One icon per filter key (D1).** 19 keys: the 18 filter keys a prepared map marker can carry plus `CustomPins`. `Labels`, a legacy import key, has no icon. `tool/markers/icon_set.dart` holds the list as one constant, and a test pins it to `markerCategories` minus `Labels`.
- **Single-tint glyph inside a painter-drawn badge (D2).** An icon file is the glyph only, drawn in white (`#FFFFFF`) on a transparent `0 0 24 24` canvas, at most 8 KiB. The renderer draws the badge (dark disc, role-coloured ring) and tints the glyph by alpha (`srcIn`), so selection, dimming, highlight and pins stay painter states and one file serves every state.
  - A closed per-element allow-list: `svg` (root: `xmlns`, `viewBox`, optional `width`/`height` of `24`), `g`, `path`, `circle`, `ellipse`, `rect`, `polygon`, `polyline`, `line`, each with its geometry attributes, `transform` and the paint attributes `fill`, `stroke`, `stroke-width`, `stroke-linecap`, `stroke-linejoin`, `stroke-miterlimit`, `fill-rule`, `clip-rule`, `opacity`. Anything else fails, including `style`, `class`, `id`, `href`, every `on*` attribute, `image`, `text`, `filter`, `use` and foreign namespaces.
  - `fill` and `stroke` take only the tint (`#FFFFFF`, `#fff`, `white`) or `none`. Each shape's effective paint is resolved from the root `svg` through its `g` ancestors and the SVG defaults (`fill` black), so a shape relying on default black fails.
  - Each file compiles with `vector_graphics_compiler`'s `encodeSvg` with `warningsAsErrors: true` and the masking, clipping and overdraw optimizers off, as `tool/maps/pack.dart` does. A warning, an exception or empty output fails. Change 4 compiles with the same flags.
- **Manifest and provenance (D3).** `assets/map_markers/manifest.json`, `schemaVersion` 1, beside the SVGs: `scope` (`release` needs all 19 keys, `candidate` allows a subset for style rounds), `background`, badge geometry, named colour roles, and per icon its key, file, role, `sha256` over the raw bytes and a provenance record (`author`, `origin`, `method`, `tools`, `concept`, `date`). Unknown fields are rejected. File names are lower snake case beside the manifest. `origin` must be `project`; `method` is `hand-authored` or `ai-assisted`, and `ai-assisted` names its tools. A `concept` from an image tool names its prompt record, which must exist inside the manifest's directory tree. `.gitattributes` marks `assets/map_markers/**` and `docs/design/map-marker-icons/candidates/**` as `-text`, so checkouts keep the hashed bytes. No tool rewrites a hash: refreshing one is a deliberate re-attestation.
- **Palette rules (D4, D7).** Each key maps to one role. Every role colour reaches a WCAG contrast of at least 3:1 against `background`. No role uses the highlight hue band [170°, 190°] at HSL saturation 10% or more (below 10% counts as grey). Extract keys use `exit`, `Hazards` and `HazardZones` use `danger`, `CustomPins` uses `pin`. The starting palette keeps today's exit green, danger red and pin light blue; shape, not colour, separates keys that share a role.
- **No third-party marker art.** No author opens, traces or describes to a tool any third-party marker set (tarkov.dev, the Tarkov wiki, the game's UI), and prompts never name one as a style reference. A concept image from an image-generation tool is redrawn as vectors and is not committed. The provenance record is the author's attestation, and the user approves every icon.
- **Offline tools.** `tool/markers/check.dart <manifest>` validates a set; `tool/markers/preview.dart` writes a self-contained HTML preview sheet after validating every set (at most 4).

## Rejected alternatives

- **tarkov.dev's marker set:** its originals came from the Tarkov wiki, so the rights are unclear.
- **An icon font:** a font build pipeline and glyph-coverage tooling for 19 glyphs.
- **Material Symbols or another licensed set:** third-party art, which the milestone's exit criterion excludes.
- **Full-colour icons with baked category colours:** each state would need its own file or a recolour, and a baked colour fights the cyan highlight.
- **Per-file sidecar provenance or `THIRD_PARTY_NOTICES.md`:** the set would need re-assembling, an orphan sidecar would go unnoticed, and prose cannot be checked per file.

## Consequences

- Change 4 bundles the release set, draws it with `CustomPaint`, and calls this library from the bundle check instead of duplicating it.
- **Note for change 4:** `_markerFilterKey`'s fallthrough (`lib/maps/prepared_map.dart:703`) gives a future raw pack category a filter key without adding it to `markerCategories`. Neither key test catches that, so the renderer needs a fallback glyph.
- A new category in `markerCategories` fails the key-list test until it gets an icon.
- **Reversal cost:** medium. Change 4's painter and change 5's preference tiles build on single-tint glyphs and the manifest format; `schemaVersion` lets a later change evolve it.
