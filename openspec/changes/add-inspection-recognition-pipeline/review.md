# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Re-check:** Required Changes re-checked in a fresh-context run (Claude Code specwright-reviewer) against the current proposal.md, design.md, specs/*/spec.md, windows/vision/vision.h, lib/data/vision/vision_job.dart, vision_native.dart, vision_failure.dart, vision_runtime.dart, vision_primitives.dart, and pub.dev package metadata for `unorm_dart`. Result: M1-M5 verified; M6 not fully verified (two residual contradictions, see below).
- **Re-check 2:** R6a, R6b and the two non-blocking notes re-checked by the same fresh-context reviewer against the current design.md (D2, D7, class diagram, failure table), proposal.md line 29, specs/item-title-matching/spec.md and specs/inspection-recognition/spec.md, and lib/data/vision/vision_job.dart. Result: M6 verified, so all six Required Changes are applied.
- **Reviewed:** proposal.md; design.md; specs/inspection-recognition/spec.md, specs/item-title-matching/spec.md, specs/vision-runtime/spec.md, specs/release-bundle-integrity/spec.md. Evidence: openspec/architecture.md, openspec/roadmap.md (M2), docs/adr/0004, 0008, 0010, 0011; openspec/specs/vision-worker, vision-runtime, release-bundle-integrity (main); lib/data/vision/vision_job.dart, vision_worker.dart, vision_service.dart, vision_runtime.dart, vision_primitives.dart, vision_failure.dart, vision_image.dart, tesseract_binding.dart; lib/data/capture/capture_frame.dart; lib/domain/catalog.dart; windows/vision/vision.h, vision.cpp, CMakeLists.txt; tool/vision/check_bundle.dart; pubspec.yaml; test/data/vision/ (fake runtime pattern); AGENTS.md. I read the reference companion read-only to check behavioural parity: Services/ScannerItemMatcher.cs, Services/RatEyeCatalogProjection.cs, Services/RatEyeInspectionRecognizer.cs, External/RatEye/RatEye/Processing/Inspection.cs, MultiInspection.cs, Config/Processing/Inspection.cs, Extensions.cs, IconManager.cs, Resources/icon_search.png (dimensions only), MainWindow.xaml.cs 607-803.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. The job has no way to receive the template's `sourceScale`.** The scale requirement scales the marker by "processing scale ÷ template source scale". D4 has `loadMarkerTemplate` return "a `VisionTemplate` plus its `sourceScale`", and the component diagram passes "VisionTemplate + sourceScale" to `VisionService`. None of the three possible routes can carry the value:
- `VisionTemplate` is only `(name, image)` (`lib/data/vision/vision_job.dart:34-42`).
- `VisionService` takes `List<VisionTemplate>` (`vision_service.dart:115-125`).
- The worker builds templates from `_TemplateInit` with name and image only (`vision_worker.dart:183-193`).

`VisionJobFactory` takes no arguments (`vision_job.dart:7`), and D2's `InspectionRequest` is `{kind, clientWidth, clientHeight}`. As designed, the job can only hard-code the source scale or guess it. If it does, a regenerated marker at a different source resolution silently mis-scales every match. ADR-0011 rates the job seam as medium reversal cost, so the route should be decided now. It can be a `templateSourceScale` field in `InspectionRequest`, or a template stored pre-normalised to scale 1.0 so the metadata is not needed at runtime.

**M2. The proposed `BGV_ERR_OVERFLOW` (-4) collides with the existing `BGV_ERR_NO_MEMORY` (-4).** See `windows/vision/vision.h:22`. D3 maps the overflow status to the typed rejection `markerPeaksOverflow`, documented as "the frame is degenerate". With the collision, a `std::bad_alloc` in `matchTemplate` over a 4K frame (the response matrix alone is about 33 MiB, allocated outside the scratch pool) would be reported as a degenerate-frame rejection instead of a native failure. The vision-runtime delta scenario "failure `nativeFailure` with the overflow status" carries the same ambiguity. Use a new code, for example -6, or a positive non-error status, and name it in the vision-runtime delta.

**M3. The title geometry depends on the template's footprint, but nothing constrains the crop rectangle.** The title rules come from the reference and are relative to the scaled marker's top-left corner and width:
- x offset = trunc(1.2 × width);
- title y = marker y;
- the close-button probe row = marker y + scaled height / 2.

The reference marker is `icon_search.png`, 28×28 scaled by 16/28 (`Config/Processing/Inspection.cs:42`), so it is a 16×16 footprint at 1080p (`Inspection.cs:235-247,410-450`). Blackgrid's template is whatever rectangle the user crops (`--rect x,y,w,h`). A crop that is a few pixels looser or tighter than the reference footprint shifts:
- the title start (by 1.2× the width difference);
- the title's top edge (17 px high, so a 2-3 px shift clips glyphs);
- the probe row, which can then miss the close button so the width is never narrowed.

Every scan's OCR degrades, and nothing reports it until the user's corpus runs. Either require the crop to reproduce the reference footprint (square, side trunc(16 × sourceScale), same anchor), with a tool check and a spec scenario, or decouple the geometry from the template's size: base the offsets on a reference marker width of trunc(16 × scale) and record any anchor offset in the metadata.

**M4. Gate arithmetic in Dart doubles diverges from the reference's float32 arithmetic at exact boundaries.** The reference computes similarity and margin in `float` and compares with `0.55f`/`0.05f`/`0.03f` (`ScannerItemMatcher.cs:37-41,121-127,194-205`). I checked by emulation. Best = 1 − 1/20 and runner-up = 1 − 2/20 (one extra edit on a 20-character name, typical title length) give:
- a float32 margin of 0.0500000119, which is not below 0.05f, so the reference accepts without confirmation;
- a double margin of 0.04999999999999993, which is below 0.05, so a plain Dart port routes the case to the near-tie rule and can return `ambiguous`.

The same flip happens for lengths 40, 60 and 100. The proposal promises boundary vectors "just below, at, and above" each gate, so the "at" vectors will encode one behaviour or the other by accident. Since parity is the stated goal, the spec should say how a gate is evaluated: float32 emulation (`Float32List` round-trips) matching the reference, or exact rational comparison with an explicit note that this deviates. Add one at-gate scenario for the .05 margin.

**M5. Dart has no NFKC normalisation, and the design names no source for it.** The normalisation requirement and its scenario "ＡＫ－７４" → "ak 74" need NFKC. The Dart SDK has no `String` normalisation, and `pubspec.yaml` has no package for it (dependencies: drift, http, crypto, ffi, vector_graphics). Unicode general categories are available through `RegExp(..., unicode: true)` `\p{L}`/`\p{Nd}`/`\p{Nl}`, but NFKC is not. Implementation will hit an unplanned decision: either a new third-party package, with notices and dependency-policy implications, or a hand-written subset that must be stated as a deviation (for example full-width ASCII and compatibility digits only). D7 or D1 should decide it and the spec should match.

**M6. The typed outcome vocabulary is inconsistent across specs and design, and change 5 codes against it (D2: medium reversal cost).**
- The specs name outcomes `noMarker` (targeted recognition, outcome ranking) and `emptyTitleRegion` (title region), and the failure table names a rejection `matcherFailed`.
- D2's `InspectionRecognition` has no `noMarker` case; it is implied by `InspectionRecognised` with 0 entries. `InspectionEvidence` has no outcome field, so `emptyTitleRegion` has nowhere to live.
- D7's `TitleRejected` reasons omit `noMarker`, `emptyTitleRegion` and `matcherFailed`.
- The proposal lists "no marker" among the typed matcher outcomes.
- The evidence requirement puts frame kind and processing scale on each evidence entry; D2 puts them on `InspectionRecognised`.

Settle one sealed vocabulary for each of the job result, the evidence and the match, and make the specs, D2, D7 and the class diagram agree.

### Suggestions

- **S1. Probe and crop edge cases against the existing primitives.**
  - `findInRangeRow` rejects `startX >= width` as `invalidImage` (`vision_runtime.dart:302-313`). The reference loop simply finds nothing (`Extensions.cs:141`). A marker within 0.2 × width of the right edge would turn into a `VisionFailed`. If that is thrown as `VisionJobAbort`, it aborts the whole full-client request instead of giving `emptyTitleRegion`. State that the probe is skipped when the title start is outside the frame.
  - The spec gives the colour bounds as R/G/B, but the scan uses buffer order (BGRX) (`vision.h:65-72`). State that the bounds are passed as B, G, R.
  - State that the probe starts at the title-region x, as in `Inspection.cs:242-247`, and that the mid row is y + trunc(scaled height / 2).
- **S2. Map each spec scenario to a test layer (AGENTS.md "cheapest test layer").**
  - "Marker present … score ≥ .99" and "Title recognised" need real `matchTemplate` and Tesseract. They are qualification-tier tests unless the fake primitives implement NCC.
  - `VisionJobContext` is a `final class` over a real `VisionRuntime` (`vision_job.dart:45-55`). The available seam is `VisionRuntime.open` over a fake runtime directory with `FakeNative`/`FakePrimitives`, as in `test/data/vision/vision_runtime_test.dart:67-153`, or a job core written against a small ops interface.
  - Say which scenarios are scripted-fake tests and which are qualification-tier.
- **S3. Corpus targeted cases need a cursor point.** User corpus images will be full screenshots, but the reference's flow is a targeted ROI from the cursor, then the fallback (`MainWindow.xaml.cs:737-801`). Add a trigger point to each `corpus.json` case and derive the ROI with the existing pure-Dart capture planner, so per-case outcomes are comparable with the reference baseline.
- **S4. How `check_bundle` finds "files derived from game artwork".** It needs an inventory role, for example `game-artwork` in `tool/vision/bundle_inventory.json`. The current inventory check only flags unexpected `.dll`/`.traineddata` (`check_bundle.dart:152-155`), so the marker files must be listed explicitly to be reported missing. The proposal's Impact list omits `bundle_inventory.json`.
- **S5. The `vision-runtime` main requirement "Runtime files are verified before any library is loaded" lists the vision files in a parenthesis.** Adding the marker to `visionCoreFiles` makes a missing marker turn the whole runtime `unavailable`, including `--vision-self-check`. Consider a MODIFIED delta that names the marker files, so the archived spec states this.
- **S6. Wording in "A title quantity restricts candidates".** "whose raw name ends in the same last number" reads like a suffix test: "Ammo pack (200 pcs)" ends in "pcs)". Use "whose raw name's last number equals it", as the near-tie requirement already does. The OCR-confusion rule for a leading `i`/`l` also applies before `@`, is case-insensitive, and needs a non-alphanumeric character before it (`ScannerItemMatcher.cs:257-265`). Add a scenario or the exact rule.
- **S7. Building the index.** Say which isolate builds `TitleMatchIndex`: NFKC over about 5k names twice. D1's "one `Isolate.run` per outcome" also disagrees with the sequence diagram, which shows two (targeted match, then `rankOutcome`). Building the index inside the same `Isolate.run`, or caching it per snapshot off the UI, removes both questions.
- **S8. Record full-client job time per resolution family in the corpus report.** OpenCV is single-threaded (ADR-0011), and up to 8 OCR calls must fit the 1.5 s deadline. Record the job time so that change 5's tuning has data.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (M1) In design.md D2/D4 and the class diagram, define how the job receives the template's source scale: an `InspectionRequest` field such as `templateSourceScale`, or a template normalised to source scale 1.0 at load time. Update the inspection-recognition "Processing scale follows the client size" requirement so the source of the source scale is unambiguous. **Re-check: verified.** D2 drops any scale field: the template is fixed at 28×28 at the reference footprint and the job scales it by (16/28) × processing scale (D2, D5, class diagram; spec "Processing scale follows the client size"). I checked the arithmetic in doubles: trunc(28 × 16/28 × s) gives 16, 21, 24 and 32 for s = 1, 4/3, 1.5 and 2, matching the spec scenarios.
2. (M2) In design.md D3 and specs/vision-runtime/spec.md, give the overflow status a code distinct from every existing `BGV_*` code (`BGV_ERR_NO_MEMORY` is -4), and name it in the "More locations than the cap" scenario. **Re-check: verified.** `BGV_ERR_OVERFLOW` is -6, distinct from -1…-5 (`windows/vision/vision.h:21-25`). D3 maps only -6 to `markerPeaksOverflow`, and the vision-runtime scenario names -6. The Dart binding keeps the status (`vision_primitives.dart:230`, `vision_runtime.dart:371`), so the job can tell -6 apart from -4.
3. (M3) In specs/inspection-recognition/spec.md and design.md D4, constrain the marker crop so the title geometry matches the reference footprint (16×16 at 1080p, the same anchor as the reference marker). Make the crop tool reject a non-conforming rectangle, and add a scenario. Alternatively, base the title offsets on trunc(16 × scale) independently of the template size and record any anchor offset in the metadata. **Re-check: verified.** The tool takes only `--origin` and derives the square footprint trunc(16·s), then normalises it to 28×28 (D4). The spec adds scenarios for reproducibility (2560×1440 → 21×21), an out-of-bounds footprint and s < 1. The title-geometry scenario (x 119, width 217) is consistent with a 16 px scaled marker.
4. (M4) In specs/item-title-matching/spec.md, state how similarity, margin and gate comparisons are evaluated (float32 emulation to match the reference, or an exact method stated as a deviation). Add an at-gate margin scenario, for example best 0.95 and runner-up 0.90 over 20-character names, with its required outcome. **Re-check: verified.** The new requirement "Scores and gates are evaluated in single precision" and D7's `Float32List` rule are in place. I emulated the at-gate scenario: float32(0.95) − float32(0.90) = 0.0500000119, which is not below float32(0.05), so the scenario's expected outcome (accepted) is correct. The existing .80/.7501 scenario still gives a margin below .05 in float32.
5. (M5) In design.md (D7 or a new decision), choose the NFKC implementation (a named package with notices handling, or a stated subset). If a subset is chosen, align the normalisation requirement. **Re-check: verified.** D7 chooses `unorm_dart` 0.3.3, pinned exactly; the proposal Impact lists it. pub.dev reports 0.3.3 as the latest version, with an MIT licence. The licence-page path and the scope of the native-file notices check are stated.
6. (M6) Make one consistent sealed vocabulary across the specs, D2, D7, the failure table and the class diagram: where `noMarker`, `emptyTitleRegion` and `matcherFailed` live, and whether kind and scale are per evidence entry or per result. **Re-check: not fully verified (first re-check); verified on re-check 2, see R6a and R6b.** The vocabulary now agrees across the specs, D2, D7, the failure table and the class diagram for `noMarker`, `emptyTitleRegion` (`titleStatus`), `matcherFailed`, and kind and scale on the result. The edit introduced two contradictions in the touched area; see Remaining below.

**Remaining after the first re-check (resolved on re-check 2):**

- **R6a.** D2 says a missing marker template throws `VisionJobAbort(VisionInvalidTemplate)`. That type cannot be built. `VisionJobAbort` takes a `VisionFailure` (`lib/data/vision/vision_job.dart:24-27`), but `VisionInvalidTemplate<R>` is a `VisionNotDelivered<R>` answer (`vision_job.dart:220`), not a `VisionFailure` (the `VisionFailure` subtypes are in `vision_failure.dart`). As written, the implementer must improvise. A plain throw gives `VisionJobFailed`, and an unrelated failure type such as `VisionInvalidImage` mislabels the cause. Either way, change 5 cannot rely on the documented case. Fix: name an existing route. One option is a thrown `StateError`, so the result is `jobFailed`, and the failure table should say so. Another is a new `VisionFailure` subtype, stated in D2. **Re-check 2: verified.** D2 line 44 now throws `StateError`, and the worker answers `jobFailed`, as its contract says (`vision_job.dart:12-14`: "a job that throws … is answered [VisionJobFailed]"). The failure-table row "Job throws (bug, or a missing marker template)" matches. No reference to `VisionJobAbort(VisionInvalidTemplate)` remains in design.md.
- **R6b.** The new scenario "No marker anywhere" requires the `noMarker` outcome to carry "the best marker scores of both results". D7's `OutcomeRejected(reason, evidence?, match?)` and the class diagram have no field for these scores. With no evidence there is no `InspectionEvidence.markerScore` either, so the THEN cannot be asserted against the designed type. Fix: add `targetedBestMarkerScore?`/`fullClientBestMarkerScore?` (or the two `InspectionRecognition` values) to `OutcomeRejected` in D7 and the class diagram, or drop the clause from the scenario. **Re-check 2: verified.** D7 and the class diagram now give `OutcomeRejected` the fields `targetedBestMarkerScore?` and `fallbackBestMarkerScore?`, copied from the two results. Both `InspectionRecognised.bestMarkerScore` and `InspectionRejected.bestMarkerScore?` can supply them, so the "No marker anywhere" THEN is assertable.

Non-blocking notes (not Required Changes):
- proposal.md line 29 lists the typed outcomes without `matcherFailed` and `catalogModeMismatch`. The proposal is not normative, but aligning it avoids confusion. **Re-check 2: fixed.** Line 29 now lists both.
- The spec scenario "Scaled template collapses" says the job returns `scaleOutOfRange` "with the processing scale", but `InspectionRejected(kind, reason, bestMarkerScore?)` has no scale field. Add `scale` to `InspectionRejected` or drop the clause. **Re-check 2: fixed.** `InspectionRejected(kind, scale, reason, bestMarkerScore?)` is used in D2 and the class diagram.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. A Critical/Moderate rebuttal counts only once marked "accepted by reviewer". -->

- **M1 fixed:** the template is always 28×28 at the reference footprint, so no source scale crosses into the job. Job scale k = (16/28) × processing scale. See design D2/D4/D5 and the class diagram; spec "Marker template is a bound, provenanced asset" and "Processing scale follows the client size".
- **M2 fixed:** `BGV_ERR_OVERFLOW` is -6, and only -6 maps to `markerPeaksOverflow` (design D3; vision-runtime spec scenario "More locations than the cap").
- **M3 fixed:** the crop tool takes only the marker origin and derives the square footprint trunc(16·s), the same as the reference's 16×16-at-1080p footprint, then normalises it to 28×28. It rejects footprints out of bounds and s < 1 (spec "Marker template is regenerated reproducibly…", new scenarios; design D4).
- **M4 fixed:** new requirement "Scores and gates are evaluated in single precision" with an at-gate scenario (0.95 vs 0.90 over 20 characters → accepted); design D7 (`Float32List` rounding).
- **M5 fixed:** `unorm_dart` 0.3.3 (MIT) provides NFKC, and `RegExp` `\p{L}\p{Nd}\p{Nl}` with `unicode: true` gives the character classes (design D7; proposal Impact).
- **M6 fixed:** one vocabulary. The result holds kind, scale, best score and evidence. Each evidence entry has `titleStatus` (`read`/`emptyTitleRegion`). `noMarker` is an empty evidence list at the job level and an `OutcomeRejected(noMarker)` at the outcome level; `matcherFailed` is an outcome reason set by the adapter. `templateMissing` was dropped in favour of `VisionJobAbort(VisionInvalidTemplate)`. See design D2/D7, the class diagram and the failure table; specs "Evidence is sendable and bounded", "Targeted recognition…" and "Targeted and fallback evidence are ranked…" (new `noMarker` scenario).
- **Suggestions applied:** S1 (out-of-range start → `emptyTitleRegion` without a probe; BGRX bound order; probe start; design D6, spec title-region scenario), S2 (new D9a test layers), S3 (corpus cursor point, D8), S4 (`bundle_inventory.json` and the check_bundle notices step in the proposal Impact), S6 (quantity wording and the exact i/l rule), S7 (index built in one `Isolate.run` per snapshot; one match isolate per outcome, D1), S8 (per-family full-client time, D8). S5 was not applied as a MODIFIED vision-runtime requirement: the marker joins `visionCoreFiles`, which the existing "Runtime files are verified before any library is loaded" requirement already covers generically, and the inspection-recognition "Altered template" scenario asserts it.
- **Reviewer re-check:** M1-M5 fixes verified against the cited files. M6 is partly fixed: R6a (`VisionJobAbort(VisionInvalidTemplate)` is ill-typed) and R6b (the `noMarker` outcome has no field for the best marker scores) remain. `CHANGES_APPLIED` stays `no` until both are resolved and re-checked.
- **R6a fixed (author):** a missing marker template now throws `StateError` → `jobFailed` (design D2; failure table "Job throws" row).
- **R6b fixed (author):** `OutcomeRejected` gains `targetedBestMarkerScore?` and `fallbackBestMarkerScore?`, copied from the two results (design D7 and the class diagram), so the "No marker anywhere" scenario is testable.
- **Notes fixed (author):** the proposal's outcome list now includes catalog mode mismatch and matcher failed; `InspectionRejected` carries `scale` (D2 and the class diagram).
- **Reviewer re-check 2:** R6a and R6b are verified, and both notes are fixed. No new contradiction appears between the specs and the design in the touched areas. All six Required Changes are verified. `CHANGES_APPLIED: yes`.
