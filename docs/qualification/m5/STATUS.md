# M5 independent native Map status

**Delivery: functional parity with the reference fork is implemented; all 13 maps are promoted; the user's live check passed (2026-10-07). Ready to commit, push and open the PR.**

Work source: [independent useful Map plan](../../plans/2026-10-07-0050-feat-m5-independent-useful-map-plan.md), on `feat/m5-independent-useful-map`. Historical M3 waivers do not qualify this work.

## Parity decisions (2026-10-07)

The user directed functional parity with their reference fork. This replaces the earlier blocked gates for Streets artwork and OCR backend selection. Both are recorded as amendments to plan B1 and KTD6.

- **Streets artwork.** The publisher's SVG keeps ten `<use>` references to deleted `stairs-85/86/87/90/92` definitions. Headless Chromium renders the original and the reference-free copy byte-identically (`00a96e2d…`). Removing valid stairs changes the render (`d96cb2b9…`). Both reference companions ship the same file through WebView2. `normalizeSvgFloor` drops a `<use>` only when its absent target is on an explicit list of publisher-deleted ids. Restricting it surfaced Customs' two `<use>` references to a deleted `path493`, which a browser also renders as nothing, so it is listed too. Any other missing symbol, unsafe href or missing paint target still fails. Nothing is drawn in their place.
- **Saved-panel OCR.** `Windows.Media.Ocr`, as in both reference companions, replaces the Tesseract candidate. The DLL (`windows/ocr/panel_ocr.cpp`, C++20/C++/WinRT, static CRT) builds with the app and is bound to its installed SHA-256. It holds one process-lifetime MTA usage because C++/WinRT caches activation factories process-wide. Dart ports the reference pipeline: resolution profiles, green-header detection, panel-bottom search, right-anchored crop, upscale, plain plus binarized recognition with merged text, taller-crop retry, tolerant row parsing, and current-map matching by containment, word overlap (≥0.72), similarity (≥0.78) and a raw-text supplement. Microsoft documents package identity as the supported configuration; the user accepts the unpackaged call, as the reference makes it. The Tesseract tooling is archived under ignored `.dart_tool/owned_verification/m5-tesseract-ocr-archive-20261007/` and is not shipped.

## Active pack

Active generation `6a2868b8c4b7c9c8cc53fc2f9b21f77101a4b2d26570d5518b88bdd8fb64b4a5` (preparation version 3, source generation `c194227b…`, calibration evidence SHA-256 `0eb38479d6aeff22890404685fa1e4e0fbe4881f5ffeeef94abf6f608af91818`). Two independent offline rebuilds from frozen `.dart_tool/maps/m5-raw-20261007-abstract` were byte-identical and `validate` passed.

| Map | Artwork | Floors |
| --- | --- | ---: |
| Factory | vector | 4 |
| Customs | vector plus publisher raster overlays | 5 |
| Woods | vector | 1 |
| Shoreline | vector | 4 |
| Interchange | vector | 3 |
| Labs | raster tiles | 3 |
| Reserve | vector plus publisher raster overlays | 6 |
| Lighthouse | vector | 1 |
| Streets of Tarkov | vector | 6 |
| Ground Zero | vector | 4 |
| Terminal | vector | 1 |
| Icebreaker | raster | 16 |
| Labyrinth | raster | 1 |

It supersedes `5320e515…`, differing only in `NOTICE.txt` (the corrected `<use>` wording) and the manifest; all artwork bytes are identical. That generation superseded `710eec41…`, which used complete raster renditions for Customs and Reserve; Customs and Reserve are now built from their publisher SVGs, matching the reference. Original persisted pin bounds remain distinct from artwork geometry. The newer marker snapshot re-keys three Interchange control markers; their fixture IDs and paths were re-pinned (Emercom height 24.18→22.45 upstream). Artwork labels, tolerances and X/Z are unchanged. The three-map M3 generation `0e059640…` stays in the repository, inactive. `5320e515…` and `710eec41…` are moved to ignored `.dart_tool/owned_verification/m5-superseded-map-generations-20261007/`.

## Verification

| Check | Result | Notes |
| --- | --- | --- |
| Full offline suite | **Passed** (2026-10-07, active `6a2868b8…`) | `flutter test`: 688 passed, 0 failed, 4 skipped (native OCR cases needing the built DLL or the private Shoreline image), 1 min 47 s. |
| Native OCR cases | Passed earlier, with `BLACKGRID_PANEL_OCR_RUNTIME` set to the Release folder | Decode errors, tampered-hash refusal and twelve blank jobs. |
| Synthetic panel through the real DLL | Passed | A synthetic 3440×1440 panel resolved all four drawn current-map identities and not a decoy; a blank frame reported `missing`. This is pipeline evidence, not real-panel accuracy. |
| Analysis and formatting | **Clean** (2026-10-07) | `flutter analyze`: no issues. `dart format --set-exit-if-changed .`: 135 files, 0 changed. |
| Release build | **Built clean** (2026-10-07, from an emptied `build/`) | Release, Debug and Profile all bundle only `6a2868b8…`; each OCR DLL matches its `.sha256` binding. Release SHA-256: `blackgrid.exe` `56c7d4c83128f01a…`, `data/app.so` `c7d995effd4680af…`, `blackgrid_panel_ocr.dll` `90752805a7d83481…`. |
| Live map detection and player position | **Passed, tested by the user** (2026-10-07) | The user reports the app detects maps and sets the correct location; the experience is satisfactory. |
| Real Shoreline saved panel | Pending, user | Not available to the agent. Run `dart run tool/ocr/read_saved_panel.dart <image>` or Read Latest. |
| Extract/transit highlights, automatic floors | User-only | Not separately reported. |

### PR #7 follow-up verification (2026-10-07)

Code changed for canonical bulk-filter persistence and screenshot-disagreement admission, so the integration owner reran offline checks before publishing the fixes. No app, reference companion or game was launched.

| Check | Follow-up result |
| --- | --- |
| Full offline suite, including qualification | 688 passed, 0 failed, 4 native/private-image skips, 0 errors; durable JSON reporter ended with `success: true` at 115.912 s. The MCP receive timed out after 30 s; the terminal reporter, not the timeout, establishes the result. An earlier timed-out attempt had no durable reporter and remains outcome-unknown. |
| Whole-project analysis | Dart MCP `analyze_files`: no errors. |
| Changed Dart files | Dart MCP formatter processed four files and formatted the disagreement test. |
| Release rebuild | `mise exec -- flutter build windows --release` succeeded. The only bundled pack is `6a2868b8…`; all 1,322 packaged pack files match the source bytes, and the OCR DLL matches its SHA-256 binding. |
| Updated Release payload hashes | `blackgrid.exe`: `56c7d4c83128f01ab2a6176c7823206b37a555cc62fb6df93b470c351bc12bad`; `data/app.so`: `969339685fe758f5666dbee767ddf64ad3fa0d8549b4712389a6f7501de0b155`; `blackgrid_panel_ocr.dll`: `90752805a7d83481f23479318e0ccacd8ecc4e750f3a295f4473580cfe68b1c8`. |

Debug/Profile clean builds and the user live check above predate these follow-up changes; they were not rerun.

**Unverified offline/native gates:** independent numeric placement controls for the ten new families and Icebreaker (also absent in the reference fork); complete all-map pointer/keyboard/semantic checks at resize and DPI contexts; fixed rendering/resource budgets; outside-checkout Release startup and restart; durable pin and import outcomes in the packaged app.

## Review fixes (2026-10-07)

Applied from a read-only review of the full diff.

- Screenshot watcher emits a status only when it changes. The 1 Hz poll no longer erases the session's reading/assumed-association message. A superseded screenshot job now restores `watching` itself instead of relying on the poll.
- Log reader: a rejected record (over-limit or malformed UTF-8) stays visible until newer bytes read cleanly, then returns to `watching`. A transient read error (for example a sharing violation) no longer clears the detected map and mode; a vanished log still reaches `missing`. Previously any error status was permanent until the next scene line.
- A failed log/screenshot bind is reported as that input's error instead of breaking every later bind and shutdown. `MapSessionController.close` always disposes, and `AppServices.dispose` closes the database even if Map session shutdown throws.
- Matched panel evidence keeps its merged OCR `rawText`.
- Quest name/trader fields restore their text after rebuilds, so hidden quests are never unexplained. Pin search matches pin labels only, not frame names.
- PR #7 marker-filter follow-up: Show all and Hide all write only canonical filter keys, not raw marker-category aliases rejected by saved-settings validation. The existing widget regression now reads the database and reloads settings after both actions with filter persistence enabled. Verified by the follow-up offline suite above.
- PR #7 screenshot-association follow-up: a known detected/manual map disagreement blocks watched screenshot admission, so it cannot publish position, automatic floors or raid highlights onto the manual map. Explicit Read Latest remains visibly assumed, and missing log context retains assumed watched samples. The disagreement regression now follows plan KTD5/U7 rather than the former reference-parity comment. Verified by the follow-up offline suite above.
- The missing-target `<use>` drop is limited to known publisher-deleted ids (see above); `prepare` usage text and the pack's `NOTICE.txt` describe it.

**Left as is:** the raw-text matcher checks the whole panel text as well as the extract/transit section, matching the reference fork.

## Earlier evidence still applicable

- **Saved-file runtime smoke.** A throwaway program drove the production `SessionLogReader`, `ScreenshotDirectoryWatcher` and filename parser over real temporary files: incomplete log records are withheld until newline, replay resolves map and mode, truncation starts a new incarnation, Read Latest preserves the finalized timestamp, renamed identical content does not publish twice, and a rewrite to an unsupported scene clears the map.
- **Bounded app-only shell smoke** (three-map pack, before promotion): floor selection, zoom, fit, marker browser, marker details, pin add and remove, the passive latest-scan card and honest missing-input status. In-memory pins do not prove restart durability.
- **Log replay race.** The consumed-prefix race is fixed by hashing the prefix actually read from the replay handle, with a real-file rewrite regression.

## Safety boundary

Agents never launch, focus, capture, attach to or drive a game, never inspect its memory, and never launch or drive Blackgrid or the reference while EFT is running. EFT absence was confirmed by a minimal process-name check before each earlier app or native smoke. Live-game results are attributed to the user; checks the user has not reported remain unverified.

## History

Before the parity decisions, M5 was recorded as blocked: Streets normalization failed on `Missing SVG dependency #stairs-86`, and all four Tesseract 5.5.3 candidates (`tessdata_fast`/`best` × single-block/sparse-text) read the Shoreline positive's header as unreadable and produced no names. Each saved-file run took 0.56–2.48 s. Neither block applies to the current implementation. The Tesseract build, model and candidate receipts are kept in the ignored archive above.
