# Tasks

## Test map

`mise run test` runs every row offline, except rows in `test/qualification/`, which are `@Tags(['qualification'])` and need the built Release bundle (`mise run test:qualification`). Exact correlation scores and OCR texts are scripted through a fake `VisionNative`/`VisionEngine` behind `VisionRuntime.open` over a fake runtime directory (design D9a), never crafted pixels.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| inspection-recognition → Marker template is a bound, provenanced asset | Template loads from an intact bundle | test/data/vision/marker_template_test.dart | intact bundle yields a 28x28 template bound by the manifest | green |
| inspection-recognition → Marker template is a bound, provenanced asset | Altered template | test/data/vision/vision_runtime_test.dart | altered marker template reports hashMismatch naming it | green |
| inspection-recognition → Marker template is a bound, provenanced asset | Metadata disagrees with pixels | test/data/vision/marker_template_test.dart | metadata size disagreeing with pixel bytes is invalidTemplate | green |
| inspection-recognition → Marker template is regenerated reproducibly | Reproducible regeneration | test/tool/vision/make_marker_template_test.dart | 1440p screenshot crops a 21px footprint to identical 28x28 output twice | green |
| inspection-recognition → Marker template is regenerated reproducibly | Footprint outside the screenshot | test/tool/vision/make_marker_template_test.dart | footprint past the screenshot edge exits non-zero and writes nothing | green |
| inspection-recognition → Marker template is regenerated reproducibly | Screenshot below 1080p scale | test/tool/vision/make_marker_template_test.dart | screenshot below 1080p scale exits non-zero and writes nothing | green |
| inspection-recognition → Processing scale follows the client size | 4K client | test/data/vision/inspection_geometry_test.dart | 3840x2160 gives scale 2 and a 32x32 template | green |
| inspection-recognition → Processing scale follows the client size | Ultrawide client | test/data/vision/inspection_geometry_test.dart | 3440x1440 scale follows height | green |
| inspection-recognition → Processing scale follows the client size | Scaled template collapses | test/data/vision/inspection_job_test.dart | template under 2px or larger than frame rejects scaleOutOfRange without matching | green |
| inspection-recognition → Targeted recognition finds the best marker | Marker present | test/qualification/inspection_recognition_test.dart | real runtime finds a synthetic marker at its position with score at least 0.99 | red |
| inspection-recognition → Targeted recognition finds the best marker | Score just below the gate | test/data/vision/inspection_job_test.dart | best score 0.8199 yields no evidence and no OCR call | green |
| inspection-recognition → Targeted recognition finds the best marker | Score at the gate | test/data/vision/inspection_job_test.dart | best score exactly 0.82 runs title extraction | green |
| inspection-recognition → Full-client recognition finds every inspection | Two inspection windows | test/data/vision/inspection_job_test.dart | two separated peaks give two evidence entries in score order | green |
| inspection-recognition → Full-client recognition finds every inspection | Overlapping peaks | test/data/vision/inspection_geometry_test.dart | suppression keeps only the higher of two overlapping peaks | green |
| inspection-recognition → Full-client recognition finds every inspection | No inspection on screen | test/data/vision/inspection_job_test.dart | no peak at .82 gives empty evidence with best score | green |
| inspection-recognition → Title region is derived from the marker and clamped | Close button narrows the title | test/data/vision/inspection_geometry_test.dart | close button at x 400 gives title 119,50 217x17 | green |
| inspection-recognition → Title region is derived from the marker and clamped | Region clipped at the frame edge | test/data/vision/inspection_geometry_test.dart | title region is clamped to the frame without padding | green |
| inspection-recognition → Title region is derived from the marker and clamped | Empty region | test/data/vision/inspection_job_test.dart | empty or off-frame title region is emptyTitleRegion with no probe or OCR | green |
| inspection-recognition → Title text is read from a normalised, thresholded crop | Title recognised | test/qualification/inspection_recognition_test.dart | real runtime reads the rendered SALEWA title through the pipeline | red |
| inspection-recognition → Title text is read from a normalised, thresholded crop | OCR fails natively | test/data/vision/inspection_job_test.dart | native OCR failure aborts with the typed failure | green |
| inspection-recognition → Evidence is sendable and bounded | Evidence outlives the frame | test/data/vision/inspection_job_test.dart | evidence crop and text survive frame release and isolate transfer | green |
| inspection-recognition → Evidence is sendable and bounded | Oversized crop | test/data/vision/inspection_job_test.dart | crop above 256 KiB is downscaled and flagged while OCR used full size | green |
| inspection-recognition → Evidence is sendable and bounded | Stage timestamps are ordered | test/data/vision/inspection_job_test.dart | stage timestamps are non-decreasing | green |
| inspection-recognition → Recognition runs only as a vision-worker job | Job runs against a fake runtime | test/data/vision/inspection_job_test.dart | job runs through VisionService over a fake native without loading a library | green |
| inspection-recognition → Recognition runs only as a vision-worker job | Normal launch | test/data/vision/vision_worker_audit_test.dart | no startup path imports or starts the vision service or recognition job | green |
| item-title-matching → Titles and catalog names are normalised the same way | Punctuation and spacing fold | test/domain/title_matching_test.dart | normalise folds punctuation and spacing | green |
| item-title-matching → Titles and catalog names are normalised the same way | Compatibility characters fold | test/domain/title_matching_test.dart | normalise applies NFKC to full-width text | green |
| item-title-matching → Titles and catalog names are normalised the same way | Whitespace-only title | test/domain/title_matching_test.dart | normalise of separators only is empty | green |
| item-title-matching → Match index is built from one immutable catalog snapshot | Index records its source | test/domain/title_matching_test.dart | index results report snapshot mode and revision | green |
| item-title-matching → Match index is built from one immutable catalog snapshot | Kebab-case normalised names | test/domain/title_matching_test.dart | kebab-case normalizedName becomes spaced candidate | green |
| item-title-matching → Match index is built from one immutable catalog snapshot | Empty catalog | test/domain/title_matching_test.dart | empty catalog rejects emptyCatalog | green |
| item-title-matching → Similarity is the better of two edit measures | Spacing difference only | test/domain/title_matching_test.dart | compact similarity ignores spaces | green |
| item-title-matching → Similarity is the better of two edit measures | One substitution | test/domain/title_matching_test.dart | one substitution in six scores 5/6 | green |
| item-title-matching → Titles that are too short or are UI chrome are rejected | Length at the gate | test/domain/title_matching_test.dart | normalised length 3 is matched | green |
| item-title-matching → Titles that are too short or are UI chrome are rejected | Length below the gate | test/domain/title_matching_test.dart | normalised length 2 rejects titleTooShort | green |
| item-title-matching → Titles that are too short or are UI chrome are rejected | Chrome label | test/domain/title_matching_test.dart | localised chrome labels reject uiChrome | green |
| item-title-matching → Best and runner-up are chosen deterministically | Duplicate names | test/domain/title_matching_test.dart | duplicate normalised names keep the smaller id and skip runner-up | green |
| item-title-matching → Best and runner-up are chosen deterministically | Distinct names tie | test/domain/title_matching_test.dart | distinct names at equal score give margin 0 | green |
| item-title-matching → Scores and gates are evaluated in single precision | Margin at the gate | test/domain/title_matching_test.dart | float32 margin of 0.95 vs 0.90 is accepted at the gate | green |
| item-title-matching → Scores and gates are evaluated in single precision | Margin just below the gate in single precision | test/domain/title_matching_test.dart | float32 margin one ulp below .05 goes to the near-tie rule | green |
| item-title-matching → Baseline acceptance gates | Clear accept | test/domain/title_matching_test.dart | similarity .90 over .60 is accepted with margin .30 | green |
| item-title-matching → Baseline acceptance gates | Similarity just below the gate | test/domain/title_matching_test.dart | similarity .5499 rejects belowSimilarity | green |
| item-title-matching → Baseline acceptance gates | Margin just below .05 without confirmation | test/domain/title_matching_test.dart | margin .0499 without confirmation rejects ambiguous | green |
| item-title-matching → Near-ties need confirmation and quantity | Confirmed near-tie | test/domain/title_matching_test.dart | margin .04 with confirmation is accepted | green |
| item-title-matching → Near-ties need confirmation and quantity | Close tie with quantity agreement | test/domain/title_matching_test.dart | margin .01 with confirmation and quantity 20 is accepted | green |
| item-title-matching → Near-ties need confirmation and quantity | Close tie without quantity | test/domain/title_matching_test.dart | margin .01 without quantity rejects ambiguous | green |
| item-title-matching → Confirming matcher compares lower-cased raw names | Confirming pick | test/domain/title_matching_test.dart | confirming matcher picks the exact raw name | green |
| item-title-matching → Confirming matcher compares lower-cased raw names | Near-chrome title | test/domain/title_matching_test.dart | confirming matcher reports none within .85 of chrome | green |
| item-title-matching → Confirming matcher compares lower-cased raw names | Cyrillic look-alike capitals | test/domain/title_matching_test.dart | confirming matcher maps Cyrillic capitals to Latin | green |
| item-title-matching → A title quantity restricts candidates | OCR confusion in quantity | test/domain/title_matching_test.dart | i2@ reads as quantity 120 | green |
| item-title-matching → A title quantity restricts candidates | Quantity selects the variant | test/domain/title_matching_test.dart | quantity 200 restricts to the 200 pcs variant | green |
| item-title-matching → A title quantity restricts candidates | Quantity with no matching candidate | test/domain/title_matching_test.dart | quantity without a matching candidate applies no restriction | green |
| item-title-matching → Targeted and fallback evidence are ranked | Targeted accepted | test/domain/title_matching_test.dart | accepted targeted evidence wins without consulting fallback | green |
| item-title-matching → Targeted and fallback evidence are ranked | Fallback chooses the accepted inspection | test/domain/title_matching_test.dart | ranking prefers accepted over higher marker score | green |
| item-title-matching → Targeted and fallback evidence are ranked | Nothing accepted | test/domain/title_matching_test.dart | nothing accepted is a rejection with top evidence and no accepted id | green |
| item-title-matching → Targeted and fallback evidence are ranked | No marker anywhere | test/domain/title_matching_test.dart | no evidence anywhere rejects noMarker with both best scores | green |
| item-title-matching → Targeted and fallback evidence are ranked | Index from another mode | test/domain/title_matching_test.dart | index from another mode rejects catalogModeMismatch | green |
| vision-runtime → Template match lists every location at or above a threshold | Two template copies | test/qualification/vision_peaks_test.dart | real DLL lists two exact copies in raster order | green |
| vision-runtime → Template match lists every location at or above a threshold | Nothing reaches the threshold | test/qualification/vision_peaks_test.dart | real DLL returns an empty list below threshold | green |
| vision-runtime → Template match lists every location at or above a threshold | More locations than the cap | test/data/vision/vision_runtime_test.dart | peak overflow status -6 surfaces as nativeFailure with no list | green |
| vision-runtime → Template match lists every location at or above a threshold | Template larger than image | test/data/vision/vision_runtime_test.dart | peaks with a template larger than the image is invalidImage without a native call | green |
| release-bundle-integrity → Bundle inventory is exact | Complete bundle passes inventory | test/tool/vision/check_bundle_test.dart | inventory passes on synthetic complete bundle | green |
| release-bundle-integrity → Bundle inventory is exact | Unexpected DLL | test/tool/vision/check_bundle_test.dart | inventory fails naming unexpected dll | green |
| release-bundle-integrity → Bundle inventory is exact | Missing expected file | test/tool/vision/check_bundle_test.dart | inventory fails naming missing model | green |
| release-bundle-integrity → Bundle inventory is exact | Capture library missing | test/tool/vision/check_bundle_test.dart | inventory fails naming missing capture library or binding | green |
| release-bundle-integrity → Bundle inventory is exact | Marker template missing | test/tool/vision/check_bundle_test.dart | inventory fails naming missing marker template or metadata | green |
| release-bundle-integrity → Bundled game artwork is covered by notices | Marker notice complete | test/tool/vision/check_bundle_test.dart | game artwork notices step passes with file, sha and source sha | green |
| release-bundle-integrity → Bundled game artwork is covered by notices | Marker notice stale | test/tool/vision/check_bundle_test.dart | game artwork notices step fails naming a stale marker sha | green |

## 1. Decision record

Skills: none (docs only).

- [x] 1.1 Write `docs/adr/0012-inspection-recognition-pipeline.md` (MADR-short: Status accepted, Date, Supersedes none) covering design D1–D9: the split between the vision job and Dart matching, the off-UI matcher adapters, the peak primitive with Dart-side plateau and suppression (ABI 2, status -6), the 28×28 marker asset at the reference footprint and its provenance, same-weight grayscale, and single-precision gates. Include the rejected alternatives and reversal costs. Verify: the file exists, and `docs/adr/README.md` lists it if that README indexes ADRs.
- [x] 1.2 Update `openspec/architecture.md`: add ADR-0012 to "In-force ADRs"; add the recognition job and the title matcher to the component table; replace "the recognition pipeline (M2 change 4)" in "Not built yet" with a note that change 4 is built but unwired until change 5; note vision ABI 2. Verify: `grep -n 0012 openspec/architecture.md` shows the index row.

## 2. Native peak-listing primitive (vision-runtime)

Skills: `dart-add-unit-test`, `dart-write-documentation`, `dart-run-static-analysis`.

- [x] 2.1 Write failing tests in `test/data/vision/vision_runtime_test.dart` for the Dart side over the fake native: "peak overflow status -6 surfaces as nativeFailure with no list", and "peaks with a template larger than the image is invalidImage without a native call" (the fake records zero calls). Verify they fail because `matchTemplatePeaks` does not exist yet.
- [x] 2.2 Add `bgv_match_template_peaks` and `BGV_ERR_OVERFLOW (-6)` to `windows/vision/vision.h`/`vision.cpp` (TM_CCOEFF_NORMED over the shared scratch, raster-order walk, non-NaN ≥ threshold, overflow before writing past `cap`). Bump `BGV_ABI_VERSION` to 2. Add the binding typedef and `matchTemplatePeaks` to `VisionPrimitives`, `VisionRuntime`, the fake native in `test/data/vision/support/` and `VisionJobContext`. Bump `visionExpectedAbi` to 2. Verify: the 2.1 tests pass (flip rows green), and the existing `vision_runtime_test.dart` and `vision_service_test.dart` stay green.
- [x] 2.3 Write `test/qualification/vision_peaks_test.dart` (`@Tags(['qualification'])`) against the built bundle: "real DLL lists two exact copies in raster order" (copies at (10,5) and (60,30), threshold 0.99) and "real DLL returns an empty list below threshold". Run `mise run build:release`, then `mise run test:qualification -- test/qualification/vision_peaks_test.dart`. Also run `--vision-self-check` against the bundle to confirm ABI 2 loads (only after confirming Escape from Tarkov is not running, per AGENTS.md). Verify: both pass (flip green), and the self-check exits 0.

## 3. Marker template asset, loader and bundle checks

Skills: `dart-add-unit-test`, `dart-write-documentation`, `dart-run-static-analysis`.

- [x] 3.1 Write failing tests in `test/tool/vision/make_marker_template_test.dart` using small synthetic PNGs written to a temp dir: "1440p screenshot crops a 21px footprint to identical 28x28 output twice", "footprint past the screenshot edge exits non-zero and writes nothing", "screenshot below 1080p scale exits non-zero and writes nothing". Synthetic PNGs carry the real size only where the size is the invariant; use a sparse 2560×1440 image. Verify they fail because the tool is missing.
- [x] 3.2 Implement `tool/vision/make_marker_template.dart <client-screenshot.png> --origin x,y [--out dir]` (design D4): `package:image` decode, BGR luma weights with OpenCV rounding, a trunc(16·s) footprint, a deterministic pure-Dart resize to 28×28, and `.gray` plus `.json` with format, size, stride, source client size, s, origin, screenshot SHA-256 and recipe version. Validation happens before any write. Verify: the 3.1 tests pass (flip green).
- [x] 3.3 Write failing tests in `test/data/vision/marker_template_test.dart`: "intact bundle yields a 28x28 template bound by the manifest" and "metadata size disagreeing with pixel bytes is invalidTemplate", over a temp runtime directory with a manifest. Then implement `loadMarkerTemplate(runtimeDirectory)` in `lib/data/vision/marker_template.dart`, which reads the manifest, checks SHA-256, size 28×28 and non-zero variance, and returns `VisionTemplate('inspectionMarker', …)` or a typed failure. Verify: both pass (flip green).
- [x] 3.4 Add `data/vision/marker/inspection_marker.gray` and `.json` to `visionCoreFiles` (`lib/data/vision/vision_runtime.dart:27`). Write the failing test "altered marker template reports hashMismatch naming it" in `vision_runtime_test.dart`, then make it pass. Update every existing fake runtime directory in `test/data/vision/support/` so the existing runtime and service tests stay green. Verify: `mise run test -- test/data/vision` passes.
- [x] 3.5 Write failing tests in `test/tool/vision/check_bundle_test.dart`: "inventory fails naming missing marker template or metadata", "game artwork notices step passes with file, sha and source sha" and "game artwork notices step fails naming a stale marker sha". Then add the marker files to `tool/vision/bundle_inventory.json` with a game-artwork role, and a game-artwork notices step to `tool/vision/check_bundle.dart` (anchor, file, SHA-256, source screenshot SHA-256, recipe, "game UI artwork captured by the user, not covered by Blackgrid's licence"). Verify: the new tests pass (flip green), and the four existing inventory rows re-run green.
- [x] 3.6 Install the marker files in `windows/vision/CMakeLists.txt` into `data/vision/marker/` and append them to `BGV_MANIFEST_FILES`, following the self-check block at lines 228-233. Verify: after 3.7, `mise run build:release` writes both paths into `data/vision/runtime.manifest.json`.
- [ ] 3.7 **User step.** Ask the user for one saved screenshot of the game client area (fullscreen or borderless, client pixels only, 4K preferred) with an item inspection window open, and the marker's top-left pixel, or let the agent locate it in the supplied file. Agents never capture or interact with the game (AGENTS.md); read only the file the user supplies. **Supplied 2026-10-09:** `C:\Users\bgshi\OneDrive\Documents\Escape from Tarkov\Screenshots\2026-10-09[18-10] (0).png`. It is a 3440×1440 8-bit RGB PNG, SHA-256 `4c46ea322d14fb28285a79c4fe74b46c37f28f5cd2138858ff6a8a5dcc0d3eb3`, showing the AK-74 6L31 60-round magazine inspect window. The magnifier glyph spans x 1201–1216, y 280–295. With the reference icon's 4/28 margin, the footprint origin is **(1198, 277)** and its side is trunc(16 × 4/3) = 21. Check that the title start (1198 + 25 = 1223) lands just before the title text at about x 1224, and that the probe row (287) crosses the text. Run the tool with `--origin 1198,277` and commit `assets/vision/marker/*`, never the screenshot. Add the `THIRD_PARTY_NOTICES.md` entry (game UI artwork, user-captured, file SHA-256, source screenshot SHA-256, recipe). Verify: `mise run build:release` passes `bundle:check`, and `test/qualification/m2_bundle_integrity_test.dart` passes.

## 4. Recognition geometry (pure Dart)

Skills: `dart-add-unit-test`, `dart-use-pattern-matching`, `dart-write-documentation`.

- [x] 4.1 Write failing tests in `test/data/vision/inspection_geometry_test.dart`: "3840x2160 gives scale 2 and a 32x32 template", "3440x1440 scale follows height", "close button at x 400 gives title 119,50 217x17", "title region is clamped to the frame without padding" and "suppression keeps only the higher of two overlapping peaks". Add plateau-rule vectors (equal neighbours, earliest raster wins) and the order score desc / y asc / x asc. Verify they fail for missing functions.
- [x] 4.2 Implement `lib/data/vision/inspection_geometry.dart`: `processingScale`, `scaledTemplateSize`, `titleRegion` (including the start-beyond-edge and empty cases), the probe row and its BGRX bounds, `suppressPeaks(candidates, templateW, templateH, maxPeaks: 8)`. Verify: the 4.1 tests pass (flip green).

## 5. Inspection recognition job

Skills: `dart-add-unit-test`, `dart-use-pattern-matching`, `dart-write-documentation`, `dart-run-static-analysis`.

- [x] 5.1 Write failing tests in `test/data/vision/inspection_job_test.dart`, running the real job through `VisionService` over the scriptable fake native (scripted best and peak scores, OCR texts, and per-call failure injection): every `inspection_job_test.dart` row in the test map. Use a small synthetic frame; the oversized-crop row uses a scripted large crop size, not a large frame. Verify they fail because the job is missing.
- [x] 5.2 Implement `lib/data/vision/inspection_recognition.dart`: `InspectionRequest`, sealed `InspectionRecognition` (`InspectionRecognised`/`InspectionRejected`), `InspectionEvidence` with `titleStatus`, and `InspectionRecognitionJob` with its top-level factory (design D2, D5, D6). The job has a ≤4-entry scaled-template cache, the .82 gate, `maxPeaks` 8, `VisionJobAbort` on native failure, `StateError` for a missing template, the 256 KiB crop cap and QPC stage stamps. Verify: the 5.1 tests pass (flip green).
- [x] 5.3 Extend `test/data/vision/vision_worker_audit_test.dart` so startup paths also must not import `inspection_recognition.dart` or name `InspectionRecognitionJob`, with matcher vectors. Verify: "no startup path imports or starts the vision service or recognition job" passes (flip green).
- [ ] 5.4 Write `test/qualification/inspection_recognition_test.dart` (`@Tags(['qualification'])`): with the built bundle, a synthetic frame rendered with the self-check font tooling holds the committed marker at a known position and "SALEWA FIRST AID KIT" in the title region. Rows: "real runtime finds a synthetic marker at its position with score at least 0.99" and "real runtime reads the rendered SALEWA title through the pipeline". Verify: `mise run test:qualification -- test/qualification/inspection_recognition_test.dart` passes (flip green).

## 6. Title normalisation and matching (pure Dart)

Skills: `dart-add-unit-test`, `dart-use-pattern-matching`, `dart-write-documentation`, `dart-run-static-analysis`.

- [x] 6.1 Add `unorm_dart: 0.3.3` (exact pin) to `pubspec.yaml` dependencies and run `flutter pub get` through mise. Verify: `pubspec.lock` pins 0.3.3, and `mise run analyze` is clean.
- [x] 6.2 Write failing tests in `test/domain/title_matching_test.dart` for every `title_matching_test.dart` row in the test map, except ranking. Use small synthetic `CatalogSnapshot`s; similarity scenarios that name scores use crafted strings whose exact float32 scores are asserted. Verify they fail for missing code.
- [x] 6.3 Implement `lib/domain/title_matching.dart` (design D7): `normaliseTitle`, `RecognitionGates` (float32 constants), similarity with `Float32List` rounding, `TitleMatchIndex.build`, the quantity token with OCR confusions, the confirming matcher with Cyrillic-capital mapping and its .85 chrome check, the primary matcher with duplicate handling, and the near-tie rule. The result is sealed `TitleMatch` (`TitleAccepted`/`TitleRejected`). Verify: the 6.2 tests pass (flip green).
- [x] 6.4 Add a qualification-tagged benchmark `test/qualification/title_matching_benchmark_test.dart`: 10k synthetic items; p95 per-title match ≤ 20 ms; index build and isolate copy time recorded. Verify: it passes, with timings printed.

## 7. Outcome ranking and off-UI adapters

Skills: `dart-add-unit-test`, `dart-use-pattern-matching`, `dart-write-documentation`.

- [x] 7.1 Write failing ranking tests in `test/domain/title_matching_test.dart`: "accepted targeted evidence wins without consulting fallback", "ranking prefers accepted over higher marker score", "nothing accepted is a rejection with top evidence and no accepted id", "no evidence anywhere rejects noMarker with both best scores", "index from another mode rejects catalogModeMismatch". Verify they fail.
- [x] 7.2 Implement `rankOutcome` and sealed `RecognitionOutcome` (`OutcomeAccepted`/`OutcomeRejected` with both best marker scores), treating `emptyTitleRegion` evidence as an empty title. Verify: the 7.1 tests pass (flip green).
- [x] 7.3 Implement `lib/application/recognition_matcher.dart` with `buildTitleMatchIndexOffUi` and `matchRecognitionOffUi` (one `Isolate.run` each; an isolate error gives `OutcomeRejected(matcherFailed)`). Test both in `test/application/recognition_matcher_test.dart`, including the error path through an injected runner. Verify: the tests pass, and the vision worker audit stays green (the adapter imports neither the service nor the job).

## 8. Offline corpus runner

Skills: `dart-add-unit-test`, `dart-write-documentation`.

- [x] 8.1 Write `test/qualification/inspection_corpus_test.dart` (`@Tags(['qualification'])`, design D8). It reads `BLACKGRID_CORPUS_DIR` (absent → skip with the reason printed) and loads `corpus.json`. Each case has an image, client size, kind, cursor point and expected ID or `reject`; targeted cases are cropped with the capture ROI rule from the cursor point. It runs the job and matcher, and writes `report.json` with per-case marker score, crop path, OCR text, top candidates and outcome, plus coverage, false positives and per-family full-client job time. With `baseline.json` present it compares, and fails on lower coverage or more false positives. Document the corpus layout in `docs/qualification/m2/CORPUS.md`. Verify: running with a two-case synthetic corpus in a temp dir produces the report, and without the variable it skips with its reason.

## 9. Integration checks

- [x] 9.1 Run `dart format` on changed files, then `mise run analyze` and `mise run test`. Verify: both pass, and every non-qualification test-map row is green.
- [ ] 9.2 Run `mise run build:release` and then `mise run test:qualification`, after confirming Escape from Tarkov is not running. If it is running or this cannot be confirmed, stop and ask the user. Verify: the qualification tier passes, including `m2_bundle_integrity_test.dart`, `vision_peaks_test.dart` and `inspection_recognition_test.dart`, and every test-map row is green.
- [x] 9.3 Run `openspec validate add-inspection-recognition-pipeline --strict`. Verify: it passes.

## Workflow follow-up

- User-verified M2 criteria remain open after this change: labelling the screenshot corpus, recording the reference baseline, and running the corpus comparison (`BLACKGRID_CORPUS_DIR`). They are recorded as unverified until the user reports results.
- Change 5 (`add-scanner-evidence-slice`) wires `loadMarkerTemplate`, `VisionService` with `InspectionRecognitionJob`, and the matcher adapters into the Scanner, and owns fallback scheduling and timing display.
