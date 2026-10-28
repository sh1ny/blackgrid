# Map marker icons: design record

This is the record of how Blackgrid's own map marker icons were designed: each style round, the directions shown, the user's pick and words, and the final palette. The rules the icons follow are in [ADR-0023](../../adr/0023-project-authored-map-marker-icons.md). The change that produced them is `design-map-marker-icons`.

## No third-party reference

No author opens, traces or describes to a tool any third-party marker set. That covers tarkov.dev, the Tarkov wiki and the game's own UI. Prompts for image-generation tools must not name them as a style reference. Each icon's provenance record in its manifest is the author's attestation of this.

A concept image from an image-generation tool (for example ChatGPT) is redrawn as vectors. Its prompt is saved under `docs/design/map-marker-icons/prompts/`, and the concept image itself is not committed.

## Regenerating the preview sheet

The preview is a self-contained HTML file. Open it in any browser; no app or game is involved.

```sh
# Round 1: the candidate directions side by side
mise exec -- dart run tool/markers/preview.dart docs/design/map-marker-icons/candidates/*/manifest.json

# Round 2: the release set
mise exec -- dart run tool/markers/preview.dart assets/map_markers/manifest.json
```

Both write `build/marker-previews/index.html` (git-ignored); pass `--out <path>` to write elsewhere. The generator validates every set first and writes nothing when a set fails. To check a set on its own, run `mise exec -- dart run tool/markers/check.dart <manifest>`.

Each icon is shown on the dark Blackgrid background `#070D0B`, a mid olive-grey map tone `#5A6150` and a light sand map tone `#C9C2A8`. It appears at 24 px and ×3 in these states:
- normal;
- selected (30 px badge);
- dimmed (opacity 0.22);
- highlighted (cyan `#18FFFF`);
- a deuteranopia simulation (Machado 2009, full severity).

## Round 1: style directions (2026-10-28)

Three candidate directions cover the same six representative keys: `PmcExtracts`, `Transits`, `Hazards`, `BossSpawns`, `lootContainers` and `QuestItems`. Each direction is a `scope: candidate` set in [`candidates/`](candidates/), using the starting role colours (exit green, danger red, boss magenta, quest gold, loot amber).

| Direction | Style | Glyphs |
|---|---|---|
| [`solid`](candidates/solid/) | Filled silhouettes; details are cut out of the shape | Door frame with an arrow out; two opposed arrows; warning triangle with a cut-out `!`; crown on a bar, later a skull (see the pick below); crate with a lid and a latch; four-point star |
| [`outline`](candidates/outline/) | 2 px round-joined strokes | The same subjects drawn as line art, with a filled dot on the `!` |
| [`outline-accent`](candidates/outline-accent/) | A 2 px outline frame plus one solid accent | Door frame with a solid arrow; ring with a solid arrow through it; triangle with a solid `!`; crown outline on a solid bar; crate with a solid lid; ring with a solid star |

All 18 files are hand-coded SVG path data, `ai-assisted` with Claude Code (claude-opus-5-5), with no concept source.

**What to judge:**
- which direction reads best at 24 px on all three tones;
- whether the glyphs stay distinct from each other;
- whether the style suits the rest of the UI.

The user can also ask for changes, or bring their own drawings or ChatGPT concepts.

**Pick (2026-10-28):** `solid`, with a skull instead of the crown for `BossSpawns`. The user's words: "I like the solid version, but can we do some sort of skulls for the bosses?"

The `solid` crown was redrawn as a solid skull: a rounded cranium over a narrower jaw, with the eyes, nose and two tooth gaps cut out. Its provenance is unchanged: `ai-assisted` with Claude Code (claude-opus-5-5), no concept source, and the hash was refreshed after re-attesting it. Shown on the sheet, the user approved it: "As my egyptian friends would say....Berfect!"

Round 2 draws all 19 keys in the `solid` style. `CultistSpawns` shares the boss colour with `BossSpawns`, so it gets a distinct shape (a hooded figure) instead of a second skull.
