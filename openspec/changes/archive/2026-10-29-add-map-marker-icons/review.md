# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed:** proposal.md; design.md (TIER: FULL); specs/map-marker-icons/spec.md; specs/release-bundle-integrity/spec.md; openspec/roadmap.md (M4.5); openspec/architecture.md; docs/adr/0005, 0012 (index row), 0022 (index row), 0023; openspec/specs/map-marker-icons/spec.md; openspec/specs/release-bundle-integrity/spec.md; docs/design/map-marker-icons/README.md; lib/ui/map_workspace.dart (painter, `_glyph`, semantics); lib/maps/native_map_scene.dart (`loadPicture`, `BytesLoader`); lib/maps/prepared_map.dart (`_markerFilterKey`); lib/application/app_services.dart (constructor, `open`, `initialize`, `reloadAfterImport`, `dispose`); lib/ui/app.dart (service disposal); lib/ui/theme.dart; lib/domain/settings.dart (`markerCategories`); tool/markers/icon_set.dart; tool/markers/preview.dart (`_cell`); tool/vision/check_bundle.dart (`checkBundle`, `runCli`); test/tool/vision/check_bundle_test.dart (fixture, `run`); pubspec.yaml; .gitattributes; assets/map_markers/ (manifest and 19 SVGs); the active map pack manifest (per-map marker counts). Project rules: AGENTS.md "Dart and Flutter code" and the game-safety and testing boundary. Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis, flutter-add-widget-test.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. The fallback colour after a manifest failure contradicts itself across spec and design.**
- The spec says gold. The requirement "Missing or failed icons never block the map" says the fallback ring is "in the category's role colour (gold when none is known)". Its scenario "Manifest unreadable" requires "every marker draws a gold fallback badge".
- The design says something else. D2: `icon(key)` returns `null` for every key when the manifest fails. D4 then resolves the role from "a small table keyed by filter key": extracts green, hazards red, pins `Colors.lightBlueAccent`. Under D4, a manifest failure draws `PmcExtracts` green and pins light blue, not gold.
- The Failure & Visibility row for a missing or invalid manifest says "Every key on the gold fallback, or the known fallback colours (D4)", so it allows both readings.
- Consequence: the implementer has to choose. Whichever they pick, either the spec scenario's test or D4's "keep today's meanings" fails. The spec's "when none is known" does not say whether the fallback table counts as "known".

**M2. The glyph size on selected and highlighted badges departs from the approved preview and from the spec, while the artifacts say it matches.**
- The approved sheet draws the glyph at a fixed `badge.glyph` (16 px), at both the 24 px and the 30 px badge size (`tool/markers/preview.dart` `_cell`, `width="${badge.glyph}"` for every state).
- The sheet also draws the highlighted state at `diameter` (24 px). Only `selected` uses `selectedDiameter` (`final size = state == 'selected' ? ...`).
- D3 scales the glyph to `g = glyph × d / diameter`, which is 20 px on a 30 px badge. It also sizes the raster from that 20 px (80 × 80).
- The proposal says the states "match the approved preview". The new spec requirement says "glyph area SHALL come from the release set's badge geometry", and the manifest's `glyph` is 16.
- The Risks bullet "A highlighted marker now changes … to a 30 px badge → That is the selected size the preview showed" misstates the sheet: highlighted was shown at 24 px. Keeping today's enlarged highlight is a defensible choice, but it is not what the user approved on the sheet, and the artifacts should say so.
- Consequence: the shipped look differs from what the user approved (docs/design/map-marker-icons/README.md, "Approval"). A test written from the spec (16 px glyph area) would disagree with D3's 20 px.

### Suggestions

**S1. Compile each icon once per bundle check.**
- `checkIconSet` already compiles every SVG in `_checkForm`. D5 step 3 compiles them all again.
- Every existing `check_bundle_test.dart` case calls `fx.run()` → `runCli` → `checkBundle`, so each of the 29 cases would compile at least 38 times against the real set.
- Pass a memoising `IconCompiler` to `checkIconSet(markerManifestPath, compile: ...)` and reuse its bytes in step 3. Or let tests point `--marker-icons` at a small synthetic set where the case is not about markers. This keeps `mise run test` fast (AGENTS.md).

**S2. Protect the new input from `--report`.**
- `runCli` refuses report paths that would overwrite its committed inputs (`protectedFiles: [inventory, lock, notices, allow]`, check_bundle.dart:660-664).
- D5 adds `markerManifestPath` as a committed input but does not add it to that list. `--report assets/map_markers/manifest.json` would then overwrite the release manifest.
- Add the marker manifest, or its directory, to the protected paths.

**S3. Keep `lib/maps` free of `lib/ui`.**
- D2 and D4 put `GridColors.inset` and `GridColors.gold` defaults into `lib/maps/map_marker_icons.dart`. No file under `lib/maps/` imports `lib/ui/` today.
- Either define the two fallback colours as constants in the loader file, or place `markerBadgeStyle`'s colour fallback in the UI layer.

**S4. State that `open()` never completes with an error.**
- `initialize()` starts `open()` without awaiting it. Any exception that escapes, for example a `FlutterError` from `rootBundle.load` or a `TypeError` in the parser, becomes an unhandled async error, and in tests a failed test.
- D6 says "catches per file". Make it explicit that the manifest step and each icon step catch every error (`catch (error)`, not only `FormatException`), and that a unit test covers a throwing `load`.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **Fallback colour (M1).** Make spec and design name one behaviour. Recommended: keep D4's fallback table.
   - In specs/map-marker-icons/spec.md, requirement "Missing or failed icons never block the map": replace "the ring in the category's role colour (gold when none is known)" with "the ring in the category's role colour once the manifest is loaded; otherwise in the key's fallback colour (exit green for the extract keys, danger red for `Hazards` and `HazardZones`, light blue for pins, gold for every other key)".
   - In the same requirement, rewrite the "Manifest unreadable" THEN to "every marker draws a fallback badge in its key's fallback colour (for example `lootLoose` gold, `PmcExtracts` green, a saved pin light blue), a log entry names the manifest, and selecting and hit testing markers still work".
   - In design.md, Failure & Visibility, change the first row's outcome to "Every key draws the fallback badge in its D4 fallback colour".
   - In D4, list the fallback table's exact keys and colours: `PmcExtracts`, `ScavExtracts`, `SharedExtracts` → `GridColors.green`; `Hazards`, `HazardZones` → `Colors.redAccent`; `CustomPins` → `Colors.lightBlueAccent`.
   - If gold-only is preferred instead, change D4 and the Failure row to match the current spec text.
2. **Glyph size and the preview claim (M2).** Recommended: match the approved sheet.
   - In design.md D3, draw the glyph at `glyph` px (16) at every badge size. Rasterize at 4 × 16 = 64 px, and update Resource Bounds (19 × 64 × 64 × 4 B ≈ 311 KB) and the DPR note.
   - In the Risks bullet on highlighted markers, replace "That is the selected size the preview showed" with a statement that highlighted markers keep today's enlarged size, which the preview drew at 24 px, and that the user judges this in the user check.
   - In proposal.md, change "match the approved preview" to say that highlighted markers keep today's selected size, unlike the sheet.
   - If a scaled 20 px glyph is preferred instead, state it in the spec requirement "The map draws each marker as its category's icon badge" (glyph area scales with the badge diameter), note in proposal.md and design.md that this departs from the approved sheet, and fix the same Risks bullet.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

- **M1:** fixed. Took the recommended option: the spec requirement "Missing or failed icons never block the map" and its "Manifest unreadable" THEN now name the key's fallback colour; design D4 lists the fallback table's keys and colours; the Failure & Visibility manifest row names the D4 fallback colour.
- **M1, note:** to keep the requirement description within 500 characters, the fallback colour list sits in a new scenario, "Fallback colours without a manifest", in the same requirement; the description says "otherwise in the key's fallback colour".
- **M2:** fixed. Took the recommended option: design D3 draws the glyph at a fixed 16 px at every badge size and rasterizes at 64 px; Resource Bounds (≈311 KB), the DPR note, the sequence diagram and the Risks bullets are updated; proposal.md says highlighted markers keep today's selected size, unlike the sheet.
- **S1-S4:** taken into tasks.md (memoised compile in the bundle step, marker manifest added to the report guard, no `lib/ui` import in `lib/maps`, `open()` catches every error with a throwing-load test). No artifact under review was edited for them.

- **Reviewer re-check (round 1):** M1 accepted by reviewer. The spec description, the new scenario "Fallback colours without a manifest", the "Manifest unreadable" THEN, the D4 table and the Failure row now agree. Non-blocking: proposal.md's "Safe fallback" bullet still says "in its role colour, or gold when it has no role"; a later edit could name the key's fallback colour. M2 accepted by reviewer. D3 draws a fixed 16 px glyph from a 64 px raster, Resource Bounds (≈311 KB), the DPR note and the sequence diagram are updated, the Risks bullet and proposal.md state that the highlighted size departs from the sheet, and the spec's "glyph area from badge geometry" now holds.
