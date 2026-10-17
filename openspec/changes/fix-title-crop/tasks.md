# Tasks

## Test map

Paths are relative to the code repo. `job` below means `test/data/vision/inspection_job_test.dart`; `crop` means the new `test/data/vision/inspection_title_crop_test.dart`. Green rows are existing tests for unchanged behavior and must be rerun. Red rows require new regression coverage before implementation. All job tests use the real job and service with the repository's hand-written fake runtime, not native DLLs.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Title text is read from a normalised, thresholded crop | Title recognised | job | best score exactly 0.82 runs title extraction | green |
| Title text is read from a normalised, thresholded crop | OCR fails natively | job | native OCR failure aborts with the typed failure | green |
| Title text is read from a normalised, thresholded crop | Short title has an excessive blank right margin | crop; job | bounds the recorded 999-to-595 extent; OCR receives the bounded title image | red |
| Title text is read from a normalised, thresholded crop | Title reaches the existing crop boundary | crop; job | foreground at the last column retains full width; OCR receives a boundary title unchanged | red |
| Title text is read from a normalised, thresholded crop | Internal spaces and detached punctuation | crop | preserves internal spaces and detached final punctuation | green |
| Title text is read from a normalised, thresholded crop | No foreground | job | blank title skips OCR and retains white preview | red |
| Evidence is sendable and bounded | Evidence outlives the frame | job | evidence crop and text survive frame release and isolate transfer | green |
| Evidence is sendable and bounded | Oversized crop | job | crop above 256 KiB is downscaled and flagged while OCR used full size | green |
| Evidence is sendable and bounded | Stage timestamps are ordered | job | stage timestamps are non-decreasing | green |
| Evidence is sendable and bounded | Right margin is bounded before preview generation | job | preview equals bounded OCR input and titleRect retains source geometry | red |
| OCR title margin is bounded by rendered content | Bounded whitespace remains | crop | rightmost foreground at 19 yields width 28 | green |
| OCR title margin is bounded by rendered content | Limited room at the boundary | crop | rightmost foreground at 46 retains width 50 | green |

## 1. Pure title-crop policy

- [x] 1.1 Add failing tests in `inspection_title_crop_test.dart` for the test-map crop scenarios, plus padded stride with black padding ignored, all-white input, foreground in different rows, one-pixel images, and source-byte preservation. Use very short heights even for the recorded numeric extent. Verify with `mise exec -- flutter test test/data/vision/inspection_title_crop_test.dart` and record the expected missing-helper/red failure before implementation.
- [x] 1.2 Implement the pure helper/result in `lib/data/vision/inspection_title_crop.dart` following design D1/D2 and the spec's single margin rule. Respect validated logical image dimensions, avoid counting row padding, and produce a tightly packed owned copy only on narrowing; expose blank content without a zero-width image. Add `///` documentation to public declarations. Run the new crop tests to green, format with pinned `dart format`, and update the corresponding test-map states.

## 2. Worker job integration and evidence

- [x] 2.1 Extend the existing hand-written runtime fake only as needed to supply deterministic binary title pixels and record the logical pixels OCR receives. Add the red job tests named in the test map, covering both targeted and full-client paths, blank title followed by a readable second peak, and detached preview bytes after narrowed-image frame release. Use top-level factories/shared native control memory for cross-isolate fake control as required by AGENTS.md; use no sleeps. Run the focused job tests and confirm failures are caused by the current whole-width/blank-OCR behavior.
- [ ] 2.2 Wire the helper between thresholding and the preprocessing timestamp in `InspectionRecognitionJob`, send its image to OCR and preview, and implement D2's blank-text path. Preserve the frame-space title rectangle, typed native failures, later-peak processing and existing publication fences. Clarify the public evidence crop/status documentation for a blank or narrowed image without adding fields or statuses. Run all crop and job tests to green and update their test-map states.
- [ ] 2.3 Rerun the existing green map rows plus geometry, template-cache, whole-request native-failure, worker ownership and preview-cap checks. Update only fake fixtures/expected preprocessing dimensions that legitimately changed; preserve full-size-OCR versus capped-preview assertions and every integrity/ownership check. Verify with `mise exec -- flutter test test/data/vision/inspection_title_crop_test.dart test/data/vision/inspection_geometry_test.dart test/data/vision/inspection_job_test.dart`, and format every changed Dart file with pinned `dart format`.

## 3. Integration qualification

- [ ] 3.1 Run `mise run analyze` and `mise run test`, fix relevant failures without relaxing matching or safety gates, and record both results. These are the required pinned offline gates; native/bundle checks remain qualification-tagged.
- [ ] 3.2 Confirm both Tarkov process names are absent immediately before loading native libraries. Keep the existing corpus, catalog, labels and `out/before-fix-title-crop.json` unchanged. Run the exact tagged corpus command in `evidence.md` against all 50 cases, then save a separate `out/after-fix-title-crop.json`. No app, companion or game launch is needed. If the game is running or its absence cannot be established, leave this task unfinished and report why.
- [ ] 3.3 Mechanically compare the before/after reports by case ID and expected label, requiring identical case sets and labels, more than 26 correct item cases, retention of each of the 26 previously correct items, rejection of all 15 negatives, no new false-positive case, and no changed wrong ID on an already wrong case. Save the per-case comparison beside the reports, report the five original ambiguous cases individually, and document remaining MDR/Weapon case outcomes. A passing report-only corpus test or aggregate improvement is insufficient. Verify every assertion succeeds before marking this task done; otherwise stop completion and investigate rather than weaken the criteria.
- [ ] 3.4 Add a concise qualification result to this change's evidence, linking local reports and identifying the code/bundle revision used. Record the reference comparison, other-resolution accuracy, clean-machine check and live-game retest as unverified. Keep PNGs, catalog data, raw OCR probe and full reports outside Git. Verify with `git diff --check`, inspection of the changed-file list, and `openspec validate fix-title-crop --strict`.

## Workflow follow-up

- Implementation follows a separate apply request. Use `specwright-commit` to commit completed tasks, then the required pre-ship review and the configured PR workflow. Archive only after implementation and qualification pass; this task list does not mark M2 closed or any user-only check passed.
