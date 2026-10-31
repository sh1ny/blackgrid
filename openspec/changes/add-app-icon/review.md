# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Claude Code)
- **Reviewed:** openspec/changes/add-app-icon/proposal.md, specs/app-icon/spec.md, specs/release-bundle-integrity/spec.md, design.md; openspec/specs/release-bundle-integrity/spec.md; docs/adr/0023, 0024, 0025 (and the docs/adr listing, to confirm 0027 is the next free number); windows/runner/Runner.rc, windows/runner/resource.h, windows/runner/win32_window.cpp, windows/runner/resources/app_icon.ico (parsed its ICONDIR), windows/installer/blackgrid.iss, test/tool/release/installer_script_test.dart, tool/vision/pe.dart, tool/vision/check_bundle.dart, tool/markers/icon_set.dart, lib/maps/map_marker_icons.dart, test/maps/map_scene_test.dart, docs/design/map-marker-icons/, docs/design/icon-concepts/ (listing only), .gitattributes, mise.toml, image-4.8.0 ico_encoder.dart, sky_engine painting.dart (ImageByteFormat). Skills loaded: dart-add-unit-test, dart-write-documentation, dart-run-static-analysis, dart-use-pattern-matching, flutter-add-widget-test. Re-check run: only Required Changes 1-4 were re-verified against design.md, proposal.md and specs/release-bundle-integrity/spec.md as now on disk.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

The two questions the request asked about hold up against the code. First, rasterizing in the Flutter test host works: `test/maps/map_scene_test.dart:1110-1112` already calls `picture.toImage` and `toByteData` under `flutter test`, and `tool/vision/check_bundle.dart` already runs `compileIconSvg` from plain `dart run`. Second, the PE reader can be extended: `pe.dart`'s `_firstEntry`, `_findEntry` and `offsetOf` are the bounds-checked primitives D5 needs. `rc.exe` writes each ICO image's bytes unchanged as an `RT_ICON` resource. Only the `GRPICONDIR` header fields are rebuilt (see S1).

### Critical (blocking)

None.

### Moderate

**M1. Rasterizer byte format is unspecified. The default `rawRgba` is premultiplied, which darkens every anti-aliased edge in the shipped icon.** (Fixed; see Rebuttals.)
D1 said only that `toImage` "yields RGBA bytes". The repo's only readback (`test/maps/map_scene_test.dart:1112`) uses `ui.ImageByteFormat.rawRgba`, and that format returns premultiplied alpha. Both 32-bit ICO DIB images and PNG images store straight alpha. Copying the existing pattern would write every partially transparent edge pixel too dark. At 16 to 24 px that shows as a dark fringe, and the sheet would show the same darkened rasters, so the user's pick would not reveal it.

**M2. The stale-executable scenario rested on a false premise, and the matching rule was undefined.** (Fixed; see Rebuttals.)
The scenario said the Flutter default holds "four images". The committed `app_icon.ico` holds **10** entries: 256 (PNG, 32 bpp), and 48, 32 and 16 px at 4, 8 and 32 bpp each. A count check could not detect the stale case, and the requirement did not say whether images are matched by index or by key, or what happens with duplicate sizes.

**M3. The preview PNG had to become a candidate, which contradicted the ten-column scenario.** (Fixed; see Rebuttals.)
D2 put `concepts-preview.png` into the candidates folder. The "Unrecorded candidate" rule then forced it to have a provenance entry, which made it an 11th, non-square sheet column.

**M4. The change contradicted ADR-0023 without acknowledging it.** (Fixed; see Rebuttals.)
ADR-0023 says a concept image from an image tool "is not committed" and must name a prompt record. The design claimed to reuse ADR-0023's pattern unchanged while committing ChatGPT PNGs with an optional prompt.

### Suggestions

These were not part of the Required Changes and were not re-checked. The coordinator reports that S1, S2 and S4 become tasks and that S3 was not applied.

**S1. Keep the ICO directory fields consistent with the image headers, and normalize the 256 px width.** `rc.exe` (and llvm-rc) rebuild the `GRPICONDIRENTRY` planes and bit count from the image's `BITMAPINFOHEADER` rather than from the `ICONDIRENTRY`. The core's parser and the icon test should require `ICONDIRENTRY` planes and bit count to equal the DIB header's. D5 now maps a stored 0 to 256 for the bundle step, so that part is covered there.

**S2. `readIconGroup()` should stay outside `readPe()`'s single `try`.** `pe.dart:63-70` turns any malformed read into one "unreadable" result for the whole image. If the icon walk is folded into `read()`, a malformed icon resource would also fail the `imports` and `runtimeVersions` steps.

**S3. Make the remaining spec clauses checkable** (in `specs/app-icon/spec.md`; not applied).
- "No image is fully transparent" appears only in a THEN. Move it into the requirement text.
- "Uncompressed bitmaps below 256 px, PNG at 256" and "32-bit with alpha" have no failure scenario.
- "No source or candidate SHALL trace … third-party art" cannot be asserted by a test. Phrase it as the record's attestation field.
- "The icon check fails" should say "the icon test".
- Vector candidates need a provenance-entry scenario as well.

**S4. Define what `render_host_test.dart` does with no `APP_ICON_MODE`.** It should fail with the mise command to use, or do nothing, and never write a partial `.ico`.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (M1) In design.md D1, state that the rasters are read with `ui.ImageByteFormat.rawStraightRgba` (straight alpha) and passed to both the ICO encoder and the sheet. Add a core unit test that a half-transparent pixel round-trips through the DIB and PNG encoders with straight alpha.
2. (M2) In specs/release-bundle-integrity/spec.md:
   - Correct the "Stale executable icon" scenario to the real default: ten images, sizes 16, 32, 48 and 256, with 16, 32 and 48 at 4, 8 and 32 bpp. Its THEN names the sizes missing from the executable (20, 24, 40, 64, 96, 128) and the duplicate sizes.
   - In the requirement text, state that images are matched by (width, height, bit depth), and that a duplicate key on either side fails the step.
   - Mirror the matching rule in design.md D5.
3. (M3) Resolve the preview PNG in design.md D2 and the app-icon spec. Either:
   - keep `concepts-preview.png` outside `candidates/`, for example in `docs/design/app-icon/` beside the design record, with its provenance in the record; or
   - give provenance entries a `kind` (`candidate` or `reference`) that the sheet excludes, and add a scenario for it.

   With either option, the ten-column scenario then holds.
4. (M4) In design.md, add a statement that ADR-0023's rules "concept images are not committed" and "concepts name a prompt record" are scoped to map marker icons and deliberately not applied here, with the reason: these are the user's own generations, kept in `docs/` and never bundled. Then either record a short ADR during apply, or update the Mechanism Ledger's ADR row and the ADRs section to say why none is needed despite this second asset family.

CHANGES_APPLIED: yes

## Rebuttals

- **RC1 (M1): fixed, accepted by reviewer.** design.md D1 now reads each raster with `ui.ImageByteFormat.rawStraightRgba`. It names the premultiplied `rawRgba` at `map_scene_test.dart:1112` as the trap, and says the same straight-alpha bytes go to the ICO encoder and the sheet. The format exists in the pinned engine (`painting.dart:1861`). The round-trip unit test is an implementation item, deferred by the coordinator to tasks.md. That is acceptable for a design gate, provided tasks.md lists the test; the pre-ship review should confirm it exists.
- **RC2 (M2): fixed, accepted by reviewer.**
  - The release-bundle-integrity requirement now keys images by (width, height, bit depth), reads a stored 0 as 256, and requires each key once per side. A duplicate key, a key on one side only, unequal bytes, or no readable group fails the step and names it.
  - The stale scenario now matches the parsed default: ten images, 256 plus 16, 32 and 48 at 4, 8 and 32 bpp. It names the duplicate sizes 16, 32 and 48 and the missing sizes 20, 24, 40, 64, 96 and 128. The default's 256 PNG and its 32 bpp entries share keys with the new icon. Under the stated rule they also fail on unequal bytes, which is consistent with the scenario.
  - design.md D5 states the same rule.
- **RC3 (M3): fixed, accepted by reviewer.** design.md D2 moves the composite to `docs/design/app-icon/concepts-preview.png`, beside the design record, with its provenance stated in the record. `candidates/concepts/` now holds only the four square PNGs, and the proposal bullet matches. The app-icon spec's "Unrecorded candidate" and ten-column scenarios are now consistent with each other.
- **RC4 (M4): fixed, accepted by reviewer.**
  - The design.md ADRs section names the two ADR-0023 rules that are deliberately not applied, and gives the reason: the user's own generations, kept under `docs/`, never bundled, with only the redrawn SVG shipped.
  - The Mechanism Ledger's ADR row is now "yes (ADR-0027)". ADR-0027 is listed to record during apply, indexed in architecture.md, and named in the proposal.
  - docs/adr ends at 0026, so 0027 is the next free number.
