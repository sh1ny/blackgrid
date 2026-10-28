# Review

## Metadata

- **Round:** 2
- **Prior round:** Round 1 gave APPROVE_WITH_CHANGES. M1-M4 were applied and the reviewer re-checked them (changes applied: yes). Commit 79c7372 then amended design.md D6 during apply, which voided that verdict. Round 1 is kept below as history.
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code harness)
- **Reviewed:**
  - Artifacts: proposal.md, specs/map-marker-icons/spec.md, design.md (TIER: FULL), tasks.md (task wording only) and round-1 review.md.
  - History: `git show 79c7372` (the D6 amendment) and `git show 640c3e5 --stat` (the pre-ship fixes).
  - ADRs: openspec/architecture.md (ADR index rows 0005, 0012, 0022, 0023) and docs/adr/0023-project-authored-map-marker-icons.md.
  - Code: tool/markers/icon_set.dart, tool/markers/check.dart and tool/markers/preview.dart; test/tool/markers/ (icon_set_test.dart prompt-record and provenance tests, check_test.dart, preview_test.dart, release_set_test.dart).
  - Assets and docs: assets/map_markers/manifest.json and one SVG, docs/design/map-marker-icons/README.md.
  - Config and rules: `.gitattributes`, `git check-attr text` on the two candidate `prompts/` paths, and AGENTS.md.
  - Recomputed the SHA-256 of all 19 release SVGs against the manifest: all match.
  - Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis.
  - Tests were not run, because this review is read-only.
- **Re-check (Required Changes only):** fresh-context subagent (specwright-reviewer, Claude Code harness). Read the uncommitted `git diff` of design.md, tasks.md and docs/adr/0023-project-authored-map-marker-icons.md, the current design.md D2, D3 `concept`, D4 "Prompt record paths" and D6 "ChatGPT concepts", and tool/markers/icon_set.dart (`_checkRoot`, `_checkElement`, the document-level DOCTYPE and processing-instruction checks, `_promptRecordProblem`). M1 is applied verbatim: D4 now states manifest-tree containment, matching D6, ADR-0023 and `_promptRecordProblem`, and "must stay inside the repository" is gone. The S1-S5 fixes match the code (the root-first paint walk; DOCTYPE, CDATA, non-whitespace text and processing instructions rejected, with the XML declaration parsed by package:xml as a separate declaration node, not a processing instruction) and add no blocking problem. Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. After the amendment, D4 and D6 give different containment rules for `promptRecord`.**
- **The amendment.** Amended D6 (design.md:191) says a prompt is saved "in a `prompts/` folder beside the set's manifest, so `concept.promptRecord` resolves inside the manifest's directory tree (D4, review S8)".
- **D4 was not changed.** D4 "Prompt record paths" (design.md:152-154) still says the path "must stay inside the repository". It also says that this makes the check give the same answer "in tests that use temporary directories". Taken literally, a temp-dir test of a prompt record would fail, which is exactly the S8 problem. So D6 cites D4 for a rule D4 does not state.
- **The code and ADR follow D6.**
  - `_promptRecordProblem` (tool/markers/icon_set.dart:779-796) rejects absolute paths, drive letters and `..`. It resolves symlinks and requires the result to sit under the set directory ("resolves outside the set directory").
  - The test `provenance: prompt record must exist inside the manifest tree` (test/tool/markers/icon_set_test.dart:469-499) pins that behaviour.
  - ADR-0023 says "must exist inside the manifest's directory tree".
- **Consequence.** D4 is the decision that change 4 reads, because it calls this library from the bundle check. D4 now contradicts the code, the ADR and D6. A later implementer or verifier who follows D4 would either loosen the check to repository scope or flag correct code as a deviation.
- **Fix.** Change D4's bullet to state the rule the code enforces (Required Change 1).

### Suggestions

- **S1. Stale prompt path in tasks.md 6.3.**
  - tasks.md:104 still says "A ChatGPT concept's prompt goes in `docs/design/map-marker-icons/prompts/`". The checker cannot accept that location for any set.
  - The task is done and no icon uses a concept (every record has `concept.source: none`), so this changes nothing today.
  - Align the wording so nobody reuses the instruction later. The README already gives the right location (`assets/map_markers/prompts/` for the release set).
- **S2. Prompt records now live under `assets/map_markers/`, which change 4 bundles.**
  - Amended D6 puts the release set's prompt records in `assets/map_markers/prompts/`, which is inside the tree change 4 bundles. They are text the app never reads.
  - A pubspec directory entry `assets/map_markers/` does not include subfolders, so they stay out of the bundle by default. But change 4's bundle check must either inventory that folder or exclude it on purpose.
  - Add a line to ADR-0023's "Note for change 4". A non-bundled record that only passes by accident is the kind of drift the provenance work is meant to prevent.
  - `-text` already covers the folder (`git check-attr` shows `text: unset`), so its bytes stay stable.
- **S3. Carry the round-1 S7 wording into D2.**
  - D2 "Effective paint" (design.md:86) still resolves paint "through its `g` ancestors". The code starts the walk at the root `svg` (`_checkElement(root, null, null, …)`, icon_set.dart:586), and ADR-0023 says "from the root `svg`".
  - Every release SVG sets `fill="#FFFFFF"` on the root only (for example pmc_extracts.svg), so the literal design text would reject the whole shipped set.
  - Say "through its ancestors, the root `svg` included".
- **S4. Record the non-element rejections in D2.**
  - The pre-ship fix (640c3e5) rejects processing instructions at document level and inside elements. The checker also rejects DOCTYPE, CDATA and non-whitespace text (icon_set.dart:546-551, 641-646).
  - The shared format now depends on these rules (for example `<?xml-stylesheet href=…?>`), but D2 and ADR-0023 describe only the element and attribute allow-list.
  - Add one bullet, so change 4 and change 5 know what the format excludes.
- **S5. Stale task-group reference in Failure & Visibility.**
  - The "Set checker" row says the committed-set test runs "through the committed-set test (task group 4)". That test is `test/tool/markers/release_set_test.dart`, added in task 7.2 (group 7).
  - Flow & State Gaps correctly says it is added "in the same task group that completes the set". Change "(task group 4)" to "(task group 7)".

The amendment holds up otherwise.
- The README, ADR-0023 and the checker agree on manifest-tree containment.
- Both new `prompts/` locations are `-text`.
- Moving the folder does not change any committed byte or recorded hash.
- The rest of the design still matches the code. That covers:
  - the closed allow-list, effective paint and the compile flags;
  - the palette maths, including the 10% grey cut-off;
  - provenance and origin;
  - the preview's alpha tint, its atomic `.tmp` rename and the 4-set refusal before validation;
  - the refusal to write on an invalid set, leaving the previous sheet in place.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **M1.** In design.md D4, replace the "Prompt record paths" bullet's sub-points with:
   - "A `promptRecord` path resolves relative to the manifest's directory and must stay inside that directory tree. Absolute paths, drive letters and `..` segments fail, and the resolved path (symlinks followed) must lie under the manifest's directory."
   - "The check therefore gives the same answer from any working directory, including in tests that use temporary directories, and a set's prompt records travel with the set (D6)."

   Remove the phrase "must stay inside the repository".

CHANGES_APPLIED: yes

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. A Critical/Moderate rebuttal counts only once marked "accepted by reviewer". -->

- **M1** fixed: design.md D4 "Prompt record paths" now carries the two required sub-points verbatim, and "must stay inside the repository" is gone. Accepted by reviewer.
- **S1** fixed: tasks.md 6.3 now points to a `prompts/` folder beside the set's manifest (design D6, as amended). Accepted by reviewer.
- **S2** fixed: ADR-0023 gains a second note for change 4. A concept-based icon's prompt record sits in `assets/map_markers/prompts/`; change 4 decides whether the bundle includes or excludes that folder, and the bundle check must not treat it as an icon. Accepted by reviewer.
- **S3** fixed: D2 "Effective paint" resolves paint "through its ancestors, from the root `svg` through each `g`". Accepted by reviewer.
- **S4** fixed: D2 "Closed allow-list" adds that a DOCTYPE, processing instructions other than the XML declaration, CDATA and non-whitespace text fail. ADR-0023's allow-list bullet says the same. Accepted by reviewer.
- **S5** fixed: Failure & Visibility now cites task group 7 for the committed-set test. Accepted by reviewer.

---

## Round 1 (history)

This is the round-1 record, kept for history. Its machine-readable verdict and changes-applied lines have been removed. Its outcome was APPROVE_WITH_CHANGES, with the changes applied and re-checked by the reviewer. Commit 79c7372 voided that verdict.

### Round 1 metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code harness)
- **Reviewed:** proposal.md, specs/map-marker-icons/spec.md, design.md (TIER: FULL); openspec/roadmap.md (M4.5 changes 3-5); openspec/architecture.md (ADR index); docs/adr/0005, 0012 (via the architecture index), 0022 (via the architecture index); AGENTS.md; lib/ui/map_workspace.dart (:93-100, :600-700), lib/ui/theme.dart (GridColors), lib/maps/prepared_map.dart (:640-720), lib/domain/settings.dart (:18-39), lib/application/map_controller.dart (:65-85), tool/maps/pack.dart (:1-110, :1355-1400), tool/maps/quest_markers.dart (filterKey), tool/vision/check_bundle.dart (:460-570), pubspec.yaml, .gitignore, .gitattributes, `git config core.autocrlf`, vector_graphics_compiler 1.3.0 `encodeSvg` defaults (pub cache). Skills loaded: dart-use-pattern-matching, dart-add-unit-test, dart-write-documentation, dart-run-static-analysis.
- **Re-check (Required Changes only):** fresh-context subagent (specwright-reviewer, Claude Code harness). Read the current design.md and specs/map-marker-icons/spec.md, `.gitattributes`, `tool/maps/pack.dart:75-82` and vector_graphics_compiler 1.3.0 `lib/vector_graphics_compiler.dart:41-68` (pub cache). M1-M4 are applied. The S1-S6 fixes add no blocking problem; two non-blocking notes are recorded as S7 and S8. Skills loaded: dart-use-pattern-matching, dart-add-unit-test, dart-write-documentation, dart-run-static-analysis.

### Round 1 findings

#### Critical (blocking)

None.

#### Moderate

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

#### Suggestions

- **S1. Pin the HSL hue of achromatic colours.** HSL hue is undefined for greys. D7's `spawn` role `#C9CDBF` is near-grey; it computes to about 77° and passes, but a retuned grey depends on the implementation's undefined-hue convention. State that saturation 0 counts as outside the band, or require a minimum saturation for the band test.
- **S2. Define the base path for `promptRecord`.** D3 makes `promptRecord` "repo-relative", but the checker receives only a manifest path, and candidate manifests sit in `docs/`. Resolve it relative to the manifest, or pass the repo root explicitly, so the check gives the same answer from any working directory and in tests that use temporary directories.
- **S3. Add a spec scenario for the four-set bound.** D6 bounds a preview at 4 candidate sets and the CLI refuses more, but no spec scenario covers it. Add "WHEN given five sets THEN it exits non-zero and writes no sheet".
- **S4. Correct the `HazardZones` context.** D1 says the map draws hazard zones "as polygons" and change 4 "may draw it at the zone's label point". Today `_MapPainter` already draws the polygon and then the ring glyph at the marker point (`map_workspace.dart:600-635`). The icon decision is unaffected, but change 4 should not read this as new behaviour.
- **S5. Make the `stationaryWeapons` colour move a user-facing choice.** D7 moves `stationaryWeapons` from gold to the `danger` red, which today means hazards only (`map_workspace.dart:627`). The spec allows it, but the proposal says the palette "keeps today's meanings". List it as an explicit round-2 decision in the design record, so the user sees the change.
- **S6. Note a key-list gap for change 4.** The key-list test ties the tool constant to `markerCategories`. `_markerFilterKey`'s `_ => category` fallthrough (`prepared_map.dart:703`) means a future raw pack category gets a filter key without entering `markerCategories`, so neither test catches it. That is change 4's problem (a fallback glyph), but worth a line in the ADR-0023 draft.
- **S7 (re-check, non-blocking). Name the root `svg` in the effective-paint walk.** D2 lets every element carry paint attributes, the root `svg` included. But "Effective paint" resolves a shape's `fill` and `stroke` only "through its `g` ancestors". Read literally, a valid glyph with `fill="#fff"` on the root and none on its paths would fail as default black. Say "through its ancestors, the root `svg` included" when the checker is written.
- **S8 (re-check, non-blocking). Define "the repository" for the `promptRecord` containment rule.** D4 resolves `promptRecord` relative to the manifest's directory and requires the result to "stay inside the repository". It also says the check gives the same answer "in tests that use temporary directories". A temporary-directory manifest is outside the repository, so a test of a concept with a prompt record would fail containment unless the root is an explicit input. Pass the root to the library (the CLI defaults it to the repo; tests pass the temporary directory), or contain the path to the manifest's directory tree.

### Round 1 required changes

1. **M1.** Make design.md D3 and the State & Ownership row require `.gitattributes` entries `assets/map_markers/** -text` and `docs/design/map-marker-icons/candidates/** -text`, added before any icon file is committed. The reason: the SHA-256 binds exact bytes, and the checkout uses `core.autocrlf=true`.
2. **M2.**
   - In design.md D2, specify that the form rule checks each shape's effective `fill`/`stroke`, after inheritance and the SVG defaults (`fill` black, `stroke` none), and fails any effective colour other than the tint.
   - In D5, specify that the preview tints glyphs by alpha (an `srcIn` equivalent), not by rewriting the white literal.
   - Add a spec scenario under "Icon files use the restricted single-tint vector form": a shape with no `fill` (default black) fails and names the file.
3. **M3.**
   - Replace the D2 attribute sentence with a closed per-element attribute allow-list: the geometry attributes, the listed paint attributes, `transform` if allowed, and `viewBox`/`xmlns` (and optionally `width`/`height`) on the root. Every other attribute fails, naming it.
   - Add a spec scenario: an icon with an `on*` event attribute (for example `onload`) fails and names the file and attribute.
4. **M4.** In design.md D4, state that the checker calls `encodeSvg` with `warningsAsErrors: true` and the masking, clipping and overdraw optimizers disabled, matching `tool/maps/pack.dart:75-81`, and that a compiler warning counts as a compile failure.

### Round 1 rebuttals

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
