# Tasks

## Test map

The Flutter-host renderer (`tool/app_icon/render_host_test.dart`) is outside `test/` and is never part of `mise run test` or CI (design D1). Every scenario below is proved by the `dart:ui`-free core or by checks on committed files. Where a scenario needs rasters, the tests use small synthetic RGBA buffers.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| app-icon → The icon source is a project-owned SVG with a provenance record | Source with a concept | test/tool/app_icon/committed_icon_test.dart | the committed source record names the picked candidate, the pick date, author and tools | red |
| app-icon → The icon source is a project-owned SVG with a provenance record | Missing provenance | test/tool/app_icon/provenance_test.dart | a source record without author or pickedCandidate fails naming the field | red |
| app-icon → Concept candidates are committed with provenance | Four concepts recorded | test/tool/app_icon/committed_icon_test.dart | each committed concept PNG has an entry naming the user, ChatGPT and 2026-10-31 | red |
| app-icon → Concept candidates are committed with provenance | Unrecorded candidate | test/tool/app_icon/sheet_test.dart | an unrecorded PNG or SVG in the candidates folder fails naming it and writes no sheet | red |
| app-icon → The comparison sheet shows every candidate at the icon sizes | Sheet with ten candidates | test/tool/app_icon/sheet_test.dart | four concepts and six vectors give ten columns at all ten sizes on both backgrounds, with no external URL | red |
| app-icon → The comparison sheet shows every candidate at the icon sizes | Invalid vector candidate | test/tool/app_icon/sheet_test.dart | a vector that fails to compile exits non-zero naming it and leaves the earlier sheet | red |
| app-icon → The committed icon holds every Windows size | Valid icon | test/tool/app_icon/committed_icon_test.dart | the committed ico holds the ten sizes, 32 bpp, DIB below 256 and PNG at 256, none fully transparent | red |
| app-icon → The committed icon holds every Windows size | Missing size | test/tool/app_icon/ico_test.dart | an ico missing 20 px or with a duplicate 32 px fails naming the size | red |
| app-icon → The committed icon holds every Windows size | Flutter default restored | test/tool/app_icon/ico_test.dart | an ico with the Flutter default SHA-256 fails as the Flutter default | red |
| app-icon → The icon is rebuilt from its source and stays in step | Source edited without rebuild | test/tool/app_icon/provenance_test.dart | a source or ico hash differing from the record fails naming the rebuild command | red |
| app-icon → The icon is rebuilt from its source and stays in step | Render fails | test/tool/app_icon/build_test.dart | a source the compiler rejects exits non-zero naming it and leaves the ico and record unchanged | red |
| app-icon → The executable, the installer and the uninstall entry use the committed icon | Installer script points at the icon | test/tool/release/installer_script_test.dart | SetupIconFile resolves to the committed ico and UninstallDisplayIcon is the installed exe | red |
| app-icon → The executable, the installer and the uninstall entry use the committed icon | Setup icon moved | test/tool/release/installer_script_test.dart | a script naming another setup icon or none fails naming the setting | red |
| release-bundle-integrity → The executable carries the committed application icon | Icon matches | test/tool/vision/check_bundle_test.dart | app-icon step passes listing ten sizes when the exe icon group equals the ico | red |
| release-bundle-integrity → The executable carries the committed application icon | Stale executable icon | test/tool/vision/check_bundle_test.dart | the Flutter default icon group fails naming duplicate 16, 32, 48 and missing 20, 24, 40, 64, 96, 128 | red |
| release-bundle-integrity → The executable carries the committed application icon | No icon resource | test/tool/vision/pe_icon_test.dart | a missing or malformed icon group gives an unreadable result without throwing | red |

## 1. ADR-0027 and the architecture index

- [ ] 1.1 Write `docs/adr/0027-application-icon-pipeline.md` (MADR-short, `Status: accepted`, today's date) from design D1 to D5 and the ADRs section: the project-owned SVG source, rasterizing in the Flutter host with straight alpha, the DIB/PNG ICO layout, hash binding, the bundle `app-icon` step, and the scope difference from ADR-0023 (committed concepts, optional prompt). Include rejected alternatives and reversal cost. Add its row to the in-force index in `openspec/architecture.md`. Verify: the file exists, and `grep 0027 openspec/architecture.md` finds the row.

## 2. ICO core: encoder, parser and checks

Load `dart-add-unit-test`, `dart-write-documentation` and `dart-use-pattern-matching` first.

- [ ] 2.1 Write failing tests in `test/tool/app_icon/ico_test.dart` for the rows "Missing size" and "Flutter default restored". Add extra tests:
  - a half-transparent pixel (for example RGBA `200,100,50,128`) round-trips with straight alpha through the 16 px DIB and the 256 px PNG;
  - a stored width or height of 0 reads as 256;
  - directory planes and bit count must equal the DIB header's (review S1);
  - a PNG-encoded 32 px entry fails, and a 24 bpp entry fails.

  Use synthetic buffers only. Verify they fail for the missing implementation.
- [ ] 2.2 Implement `tool/app_icon/ico.dart`: `encodeIco` (D4 layout, ascending sizes, DIB below 256, PNG at 256) and `parseIco`, both bounds-checked; the result is a sealed parse result, never an exception. Implement `checkIco(bytes)`, which returns failures naming the size or format, the required size list, and the Flutter default SHA-256 (taken from the current `windows/runner/resources/app_icon.ico` before it is replaced). Verify that the 2.1 tests pass, and flip both rows green.

## 3. Candidates and their provenance

- [ ] 3.1 Move the four concept PNGs from `docs/design/icon-concepts/` to `docs/design/app-icon/candidates/concepts/`, keeping their names. Move `concepts-preview.png` to `docs/design/app-icon/concepts-preview.png`. Do not commit the zip. Remove the `/docs/design/icon-concepts/` line from `.git/info/exclude`: it is local and not committed. Add `docs/design/app-icon/candidates/** -text` and `windows/runner/resources/app_icon/** -text` to `.gitattributes`. Ask the user for the ChatGPT prompts. Record each one they supply, and record the prompt as null otherwise. Verify: `git status` shows the four PNGs and the preview as new files, and `git check-ignore` reports nothing for them.
- [ ] 3.2 Draw the six vector candidates in `docs/design/app-icon/candidates/vector/`: `grid_shield.svg`, `scanner_aperture.svg`, `extraction_waypoint.svg` and `scanned_cargo.svg` (redraws of the concepts, same three colours), plus two original designs. They must not trace, or take as a style reference, any third-party art. Each is a 256-unit `viewBox`, at most 64 KiB, and compiles with `compileIconSvg`. Write `docs/design/app-icon/candidates/provenance.json`, with one entry per file: author, tool, date, prompt, and `concept` for a redraw. Verify: `compileIconSvg` succeeds on all six through a one-off `dart run` of the core loader.
- [ ] 3.3 Write a failing test, then implement `tool/app_icon/provenance.dart`. It parses and validates the candidates record and the source record (D2 fields; unknown fields rejected) and the hash binding. Cover the rows "Missing provenance" and "Source edited without rebuild", plus a candidate record entry that points at a missing file. Verify that `test/tool/app_icon/provenance_test.dart` passes, and flip both rows green.

## 4. Renderer host, comparison sheet and build command

- [ ] 4.1 Write failing tests in `test/tool/app_icon/sheet_test.dart` for the rows "Unrecorded candidate" (both PNG and SVG), "Sheet with ten candidates" (with a fake raster provider that returns synthetic RGBA buffers) and "Invalid vector candidate". Add an extra test that more than 12 candidates exit before rendering. In `test/tool/app_icon/build_test.dart`, write a failing test for the row "Render fails", using injected temporary paths. Verify they fail.
- [ ] 4.2 Implement `tool/app_icon/sheet.dart`, which builds the HTML and writes it through `.tmp` and a rename (D3), and `tool/app_icon/build.dart`. The build command compiles every source before it renders, renders through an injected raster provider, then writes the `.ico` through `.tmp` and a rename and the record after it (Failure & Visibility). Verify that the 4.1 tests pass, and flip three rows green.
- [ ] 4.3 Implement `tool/app_icon/render_host_test.dart`, the D1 Flutter host. It uses `compileIconSvg`, decodes the picture, renders each size with `toImage` under `tester.runAsync`, reads it with `ImageByteFormat.rawStraightRgba`, and uses `app_icon_small.svg` for 16, 20 and 24 px when that file exists. With no `APP_ICON_MODE` set (review S4), it fails with the mise commands and writes nothing. Add mise tasks `icon:build` and `icon:sheet`, which run it with the define. Verify:
  - `mise run icon:sheet` writes `build/app-icon-preview/index.html` with ten columns;
  - running the host with no define fails and writes nothing.

## 5. The user's pick and the committed icon

- [ ] 5.1 Show the user the sheet (`build/app-icon-preview/index.html`) and ask them to pick a candidate. Apply any tweaks they ask for, regenerating the sheet each time. Never pick for them. Record their words. Verify: the user names one candidate.
- [ ] 5.2 Copy the picked SVG to `windows/runner/resources/app_icon/app_icon.svg`, adding `app_icon_small.svg` only if the user found 16 to 24 px illegible. Write `provenance.json`, with `pickedCandidate`, `pickDate` and `concept` set. Run `mise run icon:build`, which replaces `windows/runner/resources/app_icon.ico` and writes the hashes. Verify: `git diff --stat` shows the `.ico` replaced, and `provenance.json` holds three or four hashes.
- [ ] 5.3 Write `test/tool/app_icon/committed_icon_test.dart`, covering the rows "Source with a concept", "Four concepts recorded" and "Valid icon". It runs `checkIco` and the provenance checks on the committed files. Verify that it passes, and flip the three rows green.
- [ ] 5.4 Write `docs/design/app-icon/README.md`, the design record in the marker README's pattern. It covers the candidates and their provenance, the preview composite's provenance, the sheet command, the user's pick with their words, the regeneration command (`mise run icon:build`, then commit the `.ico` and `provenance.json`), and a note that Windows may cache the old icon (`ie4uinit -show`). Verify: the file exists and every command it names is a mise task.

## 6. Installer script wiring

- [ ] 6.1 Add tests to `test/tool/release/installer_script_test.dart` for the rows "Installer script points at the icon" and "Setup icon moved": `SetupIconFile` resolved relative to the `.iss` equals `windows/runner/resources/app_icon.ico`, and `UninstallDisplayIcon={app}\blackgrid.exe`. The first may pass immediately, because the wiring already exists. Make the second fail on a mutated script string. Verify that both pass on the real script, and flip both rows green.

## 7. Bundle check `app-icon` step

- [ ] 7.1 Write failing tests in `test/tool/vision/pe_icon_test.dart` for the row "No icon resource":
  - no `.rsrc`;
  - no `RT_GROUP_ICON`;
  - a group count above 32;
  - an entry whose `nID` has no `RT_ICON`;
  - data running past the end of the file.

  Build the PE images synthetically, in the existing PE test fixtures' style. Add a test that a malformed icon group leaves `readPe`'s imports and version readable (review S2). Verify they fail.
- [ ] 7.2 Implement `readIconGroup(bytes)` in `tool/vision/pe.dart`, separate from `readPe`'s single try (S2), with bounds checks like `_version()`. Verify that the 7.1 tests pass, and flip the row green.
- [ ] 7.3 Write failing tests in `test/tool/vision/check_bundle_test.dart` for the rows "Icon matches" and "Stale executable icon". The stale case uses an icon group built from the current Flutter default `.ico`'s ten images. Then add the `app-icon` step after `map-marker-icons` in `tool/vision/check_bundle.dart` (D5 key matching), and update `release-bundle-integrity` references in its doc comment. Verify that the tests pass, and flip both rows green.

## 8. Integration

- [ ] 8.1 Run `dart format` on the changed Dart files, then `mise run analyze` and `mise run test`. Verify: both exit 0.
- [ ] 8.2 Confirm that Escape from Tarkov is not running (`tasklist`, checking for `EscapeFromTarkov.exe`; if that can't be confirmed, skip and record this check as unverified). Then run `mise run build:release`, which runs `bundle:check`. Verify: the report's `app-icon` step passes, listing the ten sizes. The app is not launched.
- [ ] 8.3 Run `openspec validate add-app-icon --strict`. Verify: it passes.

## Workflow follow-up

- User check (M6 exit criteria): install the published beta from the installer and from the zip. Confirm the new icon on the exe, the Start menu entry, the setup wizard and the Apps & features uninstall entry.
