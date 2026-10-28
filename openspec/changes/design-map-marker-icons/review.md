# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code harness)
- **Reviewed:** proposal.md, specs/map-marker-icons/spec.md, design.md (TIER: FULL); openspec/roadmap.md (M4.5 changes 3-5); openspec/architecture.md (ADR index); docs/adr/0005, 0012 (via the architecture index), 0022 (via the architecture index); AGENTS.md; lib/ui/map_workspace.dart (:93-100, :600-700), lib/ui/theme.dart (GridColors), lib/maps/prepared_map.dart (:640-720), lib/domain/settings.dart (:18-39), lib/application/map_controller.dart (:65-85), tool/maps/pack.dart (:1-110, :1355-1400), tool/maps/quest_markers.dart (filterKey), tool/vision/check_bundle.dart (:460-570), pubspec.yaml, .gitignore, .gitattributes, `git config core.autocrlf`, vector_graphics_compiler 1.3.0 `encodeSvg` defaults (pub cache). Skills loaded: dart-use-pattern-matching, dart-add-unit-test, dart-write-documentation, dart-run-static-analysis.
- **Re-check (Required Changes only):** fresh-context subagent (specwright-reviewer, Claude Code harness). Read the current design.md and specs/map-marker-icons/spec.md, `.gitattributes`, `tool/maps/pack.dart:75-82` and vector_graphics_compiler 1.3.0 `lib/vector_graphics_compiler.dart:41-68` (pub cache). M1-M4 are applied. The S1-S6 fixes add no blocking problem; two non-blocking notes are recorded as S7 and S8. Skills loaded: dart-use-pattern-matching, dart-add-unit-test, dart-write-documentation, dart-run-static-analysis.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. SHA-256 binding breaks on checkout: the new icon paths are not marked `-text`.**
D3 and the provenance requirement bind each record to the exact bytes of its SVG, and the committed-set test runs in `mise run test` before every push (Failure & Visibility). This checkout has `core.autocrlf=true`, and `.gitattributes` exempts only the existing hash-bound trees (`assets/maps/**`, `assets/vision/**`, `test/fixtures/m0/**`, and so on). Its first line says why: "Qualification hashes bind exact payload bytes across Windows/Linux checkouts." `.svg` and `.json` are text to git. An author who writes an LF file and hashes it gets CRLF bytes back on the next checkout or clone. The reverse happens on a Linux or `autocrlf=false` checkout. Either way the "stale record" rule fails on a clean tree, and nobody edited the icon. The design never mentions line endings. Fix: add `assets/map_markers/** -text` and `docs/design/map-marker-icons/candidates/** -text` to `.gitattributes`, following the existing precedent. Add them before the first SVG is committed, and name this in D3 and in the State & Ownership row.

**M2. The "one tint" rule ignores inherited and default paint, so the browser preview can misrepresent the app.**
D2 allows colour values only `#FFFFFF`/`#fff`/`white` or `none` "on the attributes `fill`, `stroke` …". It checks attribute values that are present. In SVG an absent `fill` inherits from the parent and otherwise defaults to black. A `<path d="…"/>` with no `fill` passes the D2 check as written, but it paints black. The spec's form requirement ("paints any colour other than the tint … fails") requires that case to fail. In the app, the `srcIn` tint uses alpha only, so the black glyph tints correctly there. D5 never says how the HTML preview turns the white placeholder into the role colour. If it rewrites the white literal, a default-black glyph renders black on the preview's dark backgrounds. That is the same sheet the user uses to judge 24 px readability and approve the set. Fix:
- **(a)** The form rule resolves each painted shape's effective `fill` and `stroke`, including inheritance through `g` and the SVG default (`fill` black, `stroke` none). It fails any effective colour other than the tint.
- **(b)** D5 states how the preview tints. It should tint by alpha, the `srcIn` equivalent change 4 uses (for example an inline `feFlood` + `feComposite operator="in"` filter in the sheet), so the preview matches the app whatever literal the file carries.

**M3. The attribute rule is neither a complete allow-list nor a usable deny-list, and the preview inlines the SVGs into HTML.**
D2 lists allowed paint attributes, then says "Anything else fails the check: `style`, `class`, `href`, …". Read as an allow-list, it rejects every valid glyph, because `d`, `cx`, `cy`, `r`, `x`, `y`, `width`, `height`, `points`, `x1`…`y2`, `rx`, `ry`, `viewBox`, `xmlns` and `transform` are not listed. Read as the enumerated deny-list, it admits event-handler attributes (`onload`, `onclick`), `id` with `url(#…)` references, `xml:base` and similar. D5 inlines every glyph into an HTML file that the user opens in a browser, so an `onload` on an admitted `<svg>` or `<path>` would run script there. The mechanism ledger calls this an "element and attribute allow-list", and the manifest format is shared with changes 4 and 5. The allowed attribute set has to be exact. Fix: replace the D2 attribute sentence with a closed allow-list per element:
- the geometry attributes of each allowed element;
- the paint attributes already listed;
- `transform`, if wanted;
- `viewBox`, `xmlns` and optionally `width`/`height` on the root.

Everything else fails, naming the attribute. Add a spec scenario that an `on*` attribute (for example `onload`) fails.

**M4. As specified, the compile check cannot catch the silent drops that justify it.**
The mechanism ledger keeps the `encodeSvg` check because "the compiler silently drops unsupported features". D4 says only "compiles each SVG with `vector_graphics_compiler`'s `encodeSvg`, as `pack.dart:75` does". In vector_graphics_compiler 1.3.0, `encodeSvg` defaults to `warningsAsErrors: false`, and the parser then logs unsupported content and drops it without throwing (`lib/vector_graphics_compiler.dart:129-144`). The optimizers default to on and run only when `path_ops` is initialised (`parser.dart:821-837`), so output can differ between environments. `pack.dart:75-81` passes `warningsAsErrors: true` with all three optimizers off. Fix: state in D4 that the checker calls `encodeSvg` with exactly those flags (`warningsAsErrors: true`, masking, clipping and overdraw optimizers disabled), so a warning counts as a compile failure. Change 4 should then compile with the same flags.

### Suggestions

- **S1. Pin the HSL hue of achromatic colours.** HSL hue is undefined for greys. D7's `spawn` role `#C9CDBF` is near-grey; it computes to about 77° and passes, but a retuned grey depends on the implementation's undefined-hue convention. State that saturation 0 counts as outside the band, or require a minimum saturation for the band test.
- **S2. Define the base path for `promptRecord`.** D3 makes `promptRecord` "repo-relative", but the checker receives only a manifest path, and candidate manifests sit in `docs/`. Resolve it relative to the manifest, or pass the repo root explicitly, so the check gives the same answer from any working directory and in tests that use temporary directories.
- **S3. Add a spec scenario for the four-set bound.** D6 bounds a preview at 4 candidate sets and the CLI refuses more, but no spec scenario covers it. Add "WHEN given five sets THEN it exits non-zero and writes no sheet".
- **S4. Correct the `HazardZones` context.** D1 says the map draws hazard zones "as polygons" and change 4 "may draw it at the zone's label point". Today `_MapPainter` already draws the polygon and then the ring glyph at the marker point (`map_workspace.dart:600-635`). The icon decision is unaffected, but change 4 should not read this as new behaviour.
- **S5. Make the `stationaryWeapons` colour move a user-facing choice.** D7 moves `stationaryWeapons` from gold to the `danger` red, which today means hazards only (`map_workspace.dart:627`). The spec allows it, but the proposal says the palette "keeps today's meanings". List it as an explicit round-2 decision in the design record, so the user sees the change.
- **S6. Note a key-list gap for change 4.** The key-list test ties the tool constant to `markerCategories`. `_markerFilterKey`'s `_ => category` fallthrough (`prepared_map.dart:703`) means a future raw pack category gets a filter key without entering `markerCategories`, so neither test catches it. That is change 4's problem (a fallback glyph), but worth a line in the ADR-0023 draft.

- **S7 (re-check, non-blocking). Name the root `svg` in the effective-paint walk.** D2 lets every element carry paint attributes, the root `svg` included. But "Effective paint" resolves a shape's `fill` and `stroke` only "through its `g` ancestors". Read literally, a valid glyph with `fill="#fff"` on the root and none on its paths would fail as default black. Say "through its ancestors, the root `svg` included" when the checker is written.
- **S8 (re-check, non-blocking). Define "the repository" for the `promptRecord` containment rule.** D4 resolves `promptRecord` relative to the manifest's directory and requires the result to "stay inside the repository". It also says the check gives the same answer "in tests that use temporary directories". A temporary-directory manifest is outside the repository, so a test of a concept with a prompt record would fail containment unless the root is an explicit input. Pass the root to the library (the CLI defaults it to the repo; tests pass the temporary directory), or contain the path to the manifest's directory tree.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **M1.** Make design.md D3 and the State & Ownership row require `.gitattributes` entries `assets/map_markers/** -text` and `docs/design/map-marker-icons/candidates/** -text`, added before any icon file is committed. The reason: the SHA-256 binds exact bytes, and the checkout uses `core.autocrlf=true`.
2. **M2.**
   - In design.md D2, specify that the form rule checks each shape's effective `fill`/`stroke`, after inheritance and the SVG defaults (`fill` black, `stroke` none), and fails any effective colour other than the tint.
   - In D5, specify that the preview tints glyphs by alpha (an `srcIn` equivalent), not by rewriting the white literal.
   - Add a spec scenario under "Icon files use the restricted single-tint vector form": a shape with no `fill` (default black) fails and names the file.
3. **M3.**
   - Replace the D2 attribute sentence with a closed per-element attribute allow-list: the geometry attributes, the listed paint attributes, `transform` if allowed, and `viewBox`/`xmlns` (and optionally `width`/`height`) on the root. Every other attribute fails, naming it.
   - Add a spec scenario: an icon with an `on*` event attribute (for example `onload`) fails and names the file and attribute.
4. **M4.** In design.md D4, state that the checker calls `encodeSvg` with `warningsAsErrors: true` and the masking, clipping and overdraw optimizers disabled, matching `tool/maps/pack.dart:75-81`, and that a compiler warning counts as a compile failure.

CHANGES_APPLIED: yes

## Rebuttals

- **M1** fixed: design D3 "Line endings" bullet and the State & Ownership row; `.gitattributes` `-text` entries for `assets/map_markers/**` and `docs/design/map-marker-icons/candidates/**` before the first icon is committed. Accepted by reviewer.
- **M2** fixed: D2 "Effective paint" bullet (inheritance and SVG defaults; default black fails); D5 "Tinting" bullet (alpha tint via `feFlood` + `feComposite operator="in"`); spec scenario "Default or inherited paint fails". Accepted by reviewer.
- **M3** fixed: D2 "Closed allow-list" with per-element geometry attributes, `transform` and paint attributes, everything else failing; spec scenario "Unlisted attribute fails" (`onload`). Accepted by reviewer.
- **M4** fixed: D4 "Compile check" bullet (`warningsAsErrors: true`, masking/clipping/overdraw optimizers off, as `pack.dart:75-81`; change 4 uses the same flags); spec scenario "File that does not compile fails" now includes a compiler warning. Accepted by reviewer.
- **S1** fixed: D4 "Palette rule" (saturation below 10% counts as grey, outside the band). Accepted by reviewer.
- **S2** fixed: D3 `concept` and D4 "Prompt record paths" (relative to the manifest's directory, inside the repository). Accepted by reviewer.
- **S3** fixed: spec scenario "Too many candidate sets writes no sheet". Accepted by reviewer.
- **S4** fixed: D1 `HazardZones` bullet. Accepted by reviewer.
- **S5** fixed: D7 `stationaryWeapons` bullet (explicit round-2 decision in the design record). Accepted by reviewer.
- **S6** fixed: ADRs section, note for change 4 in ADR-0023. Accepted by reviewer.
