# Application icon: design record

This is the record of how Blackgrid's application icon was designed: the candidates and where each came from, the comparison sheet, the user's pick and words, and how to rebuild the icon. The rules the icon follows are in [ADR-0027](../../adr/0027-application-icon-pipeline.md). The change that produced it is `add-app-icon`.

## No third-party reference

No source or candidate traces any third-party art, or names it as a style reference. That covers the game's own artwork and logos and other companion apps. The ChatGPT prompt below explicitly asks for nothing copied from any game's artwork. Each candidate's entry in [`candidates/provenance.json`](candidates/provenance.json), and the shipped icon's record in `windows/runner/resources/app_icon/provenance.json`, is the author's attestation of this.

Unlike map marker icons (ADR-0023), the concept images are committed here, as a design record under `docs/`. They are never bundled, and only the SVG redraw or vector design feeds the shipped icon. ADR-0027 records this scope difference. ADR-0028 ([`0028-app-icon-ships-a-compiled-header-logo.md`](../../adr/0028-app-icon-ships-a-compiled-header-logo.md)) adds one bundled file: the compiled `assets/app_icon/app_icon.vec` that the app header draws.

## Candidates

[`candidates/`](candidates/) holds every candidate shown on the sheet, each with an entry in `candidates/provenance.json` (author, method, tools, date, prompt, and for a redraw the concept it redraws). The sheet refuses to run while a file in the folder has no entry.

**Concepts (2026-10-31).** The user generated four concepts with ChatGPT from one prompt, recorded on each concept's entry:

> Design an app icon for Blackgrid, a Windows desktop companion for an extraction shooter. It shows interactive raid maps and scans in-game items to say whether to keep or sell them. The mood is dark, tactical and utilitarian: think a field map grid or a scanner reticle, not a cartoon. Requirements: 1024×1024 square PNG with a transparent background. No text or letters. No game logos, and nothing copied from any game's artwork. One bold shape that is still recognisable at 16×16 px. Keep fine detail to a minimum and use thick strokes. Two or three colours at most, with strong contrast that reads on both light and dark taskbars. Give me 4 distinct concepts.

| Concept | Shape |
|---|---|
| [`01-grid-shield.png`](candidates/concepts/01-grid-shield.png) | Shield split into a 2×2 grid, one amber cell |
| [`02-scanner-aperture.png`](candidates/concepts/02-scanner-aperture.png) | Octagon with four corner brackets around an open centre and an amber corner arc |
| [`03-extraction-waypoint.png`](candidates/concepts/03-extraction-waypoint.png) | Pointed waypoint with an amber chevron |
| [`04-scanned-cargo.png`](candidates/concepts/04-scanned-cargo.png) | Chamfered crate with an amber scan band |

ChatGPT also produced [`concepts-preview.png`](concepts-preview.png), a 1280×760 composite of the four concepts at small sizes on light and dark backgrounds, made in the same session. It is kept beside this record and is not a candidate. A zip of the four PNGs from the same session was not committed, because it duplicates them.

**Vectors (2026-10-31).** Six SVGs in [`candidates/vector/`](candidates/vector/), each a 256-unit `viewBox` of flat filled paths in the concepts' three colours (cream `#F0E8D5`, slate `#172126`, amber `#E6A63D`). All six are `ai-assisted` with Claude Code (claude-opus-5-5): coordinates were measured from the concepts and written as path data.

| Vector | Origin |
|---|---|
| `grid_shield.svg` | Redraw of concept 01 |
| `scanner_aperture.svg` | Redraw of concept 02 |
| `extraction_waypoint.svg` | Redraw of concept 03 |
| `scanned_cargo.svg` | Redraw of concept 04 |
| `grid_reticle.svg` | Original: chamfered tile with a broken crosshair and an amber centre cell |
| `hex_sweep.svg` | Original: hexagon with an amber radar-sweep sector and a cream hub |

## The comparison sheet

```sh
mise run icon:sheet
```

This writes `build/app-icon-preview/index.html` (git-ignored), a self-contained page with no external URL, script or font. Open it in any browser; no app or game is involved. It shows one column per recorded candidate (at most 12) at 16, 20, 24, 32, 40, 48, 64, 96, 128 and 256 px, on a light (`#F3F4F6`) and a dark (`#11161A`) background, close to the Windows light and dark taskbars:
- **Vector columns** show the exact rasters the `.ico` would hold, from the same Flutter renderer as `icon:build`, at 1× and enlarged 4× with no smoothing.
- **Concept columns** show the PNG scaled by the browser, and are labelled as such. A concept can only ship through its vector redraw.

The run validates every candidate first and writes nothing when one is unrecorded or fails to compile, so an earlier sheet stays in place.

## Pick (2026-10-31)

The user picked `vector/hex_sweep.svg`, one of the two original vector designs, with no changes. The user's words: "I like this one: vector/hex_sweep.svg". It has no concept. The user did not ask for a hand-tuned small-size SVG, so all ten sizes are rendered from `app_icon.svg`.

## The shipped icon

`windows/runner/resources/app_icon/` holds the source:
- `app_icon.svg`, a copy of the picked candidate;
- optionally `app_icon_small.svg`, used only for the 16, 20 and 24 px images (not present today);
- `provenance.json`, with the author, method, tools, the picked candidate and pick date, the concept (null here), and the SHA-256 of each source, of `windows/runner/resources/app_icon.ico` and of `assets/app_icon/app_icon.vec`.

`assets/app_icon/app_icon.vec` is `app_icon.svg` compiled with the map marker flags. It is the only icon file that ships as a Flutter asset, for the app header (ADR-0028).

The source folder is not a Flutter asset and is not bundled. `Runner.rc` embeds the `.ico` in `blackgrid.exe`, and the installer takes its setup icon from the same file and its uninstall icon from the installed `blackgrid.exe`.

## Regenerating the icon

After editing `app_icon.svg` (or adding or editing `app_icon_small.svg`), or after a new pick:

```sh
mise run icon:build
```

Then commit `windows/runner/resources/app_icon.ico`, `assets/app_icon/app_icon.vec` and `windows/runner/resources/app_icon/provenance.json` together. The command compiles every source before it renders, then writes the `.ico`, then the `.vec`, then the record's hashes. A failed run changes none of them. `mise run test` fails while a source, the `.ico` or the `.vec` differs from its recorded hash, or while the `.vec` differs from the compiled `app_icon.svg`, and the release bundle check (`app-icon` step) fails while a built `blackgrid.exe` embeds a different icon, so rebuild the bundle too. For a new pick, update `pickedCandidate`, `pickDate` and `concept` in the record by hand first; old candidates stay here as the record.

## Windows icon cache

After installing a build with a new icon over an old one, Explorer, the Start menu or the taskbar may still show the old icon from Windows' icon cache. That is not a defect in the file. Run `ie4uinit -show` (or sign out and back in) to refresh it before judging the icon.
