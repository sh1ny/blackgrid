# 0012 - Inspection recognition pipeline: vision job plus pure Dart matching, off-UI adapters, native peak primitive, manifest-bound marker asset, same-weight grayscale

- Status: accepted
- Date: 2026-10-09 (M2 change `add-inspection-recognition-pipeline`)
- Supersedes: none
- Source: change `add-inspection-recognition-pipeline` (design D1-D9); [implementation strategy §6](../IMPLEMENTATION_STRATEGY.md#6-scanner-strategy)

## Context and problem

Change 3 left a warm vision worker with a job seam (ADR-0011) and no job. Change 4 must turn a capture frame into an item identity: find the inspection marker, read the title next to it, and match the text against the catalog. The behaviour follows the user's private reference companion, read as a behavioural oracle; no code is copied. Three constraints shape the design. The worker serialises every native call and has a 1.5 s deadline, so only stages that need native primitives belong in it. Full-client fallback frames can hold several inspection windows, but the native API can only return the single best match. The marker template must be a rights-recorded, hash-bound asset, and the reference's grayscale conversion for the marker has swapped R/B weights that make sense only for its own template. Change 5 (Scanner wiring) and M4 (hotkeys) code against whatever this change fixes.

## Decision

- **The job and the matcher are separate.** `InspectionRecognitionJob` runs in the vision worker: marker search, title rectangle, close-button probe, crop, resize, grayscale, inverted threshold and OCR. It returns sendable `InspectionEvidence`, wrapped in a sealed `InspectionRecognition`. Normalisation, the index, both matchers and outcome ranking are pure, synchronous Dart in `lib/domain/title_matching.dart`, free of `dart:ffi`. The index is built once per catalog snapshot.
- **Matching runs off the UI isolate through two adapters,** following ADR-0004's bulk-CPU pattern. One builds the index in a single `Isolate.run` per snapshot. The other matches and ranks all evidence of one outcome (targeted plus fallback) in one `Isolate.run`. An isolate error becomes a typed `matcherFailed` rejection.
- **Typed values, not exceptions.** The job takes a small sealed request (kind and client size) and returns recognised or rejected results. A native failure inside a stage aborts the request with the typed `VisionFailure`; partial evidence is never returned.
- **A native peak-listing primitive with policy in Dart.** `bgv_match_template_peaks` runs the same normalised-correlation match as the best-match primitive, emits every non-NaN response at or above a threshold up to a cap, and returns a new status, `BGV_ERR_OVERFLOW` (-6), past the cap. Only -6 maps to `markerPeaksOverflow`. The vision ABI becomes 2. The plateau rule, ordering and suppression are Dart functions, so they are testable without the DLL (ADR-0010: native facts, Dart policy).
- **The marker is a committed raw grayscale asset.** `assets/vision/marker/inspection_marker.gray` is 28×28, cut at the reference footprint (the same square the reference marker covers once scaled) from a user-supplied client screenshot by `tool/vision/make_marker_template.dart`. A JSON file beside it records the format, size, source client size, source scale, origin, the screenshot's SHA-256 and the recipe version. The screenshot is never committed; its hash is the provenance. CMake installs both files into the vision bundle and binds them in the runtime manifest, and both are core files, so a missing or altered marker makes the runtime unavailable. A notices entry records the rights status of the game artwork, and `check_bundle` enforces it. `loadMarkerTemplate` validates the files and returns the template that change 5 passes to the service.
- **Same-weight grayscale.** Frame and template are both converted with the correct BGR luma weights. The job scales the template once per target size (reference factor 16/28 times the processing scale) and caches at most 4 scaled copies for the worker's lifetime.
- **Single-precision gates.** Similarities, the margin and the gate constants are evaluated as 32-bit floats, to reproduce the reference's boundary behaviour. The gate constants live in the specs and in one const object, not in this ADR.
- **Layered tests.** Boundary vectors are pure-function unit tests. Job sequencing runs the real job over the existing fake `VisionNative` seam. Real NCC and OCR on rendered frames, the corpus runner and the matcher benchmark are `qualification`-tagged. The user's screenshot corpus is never committed.
- **Not wired.** Change 4 is built and unwired; change 5 constructs the service, loads the marker and calls the adapters.

## Rejected alternatives

- **Matching inside the worker job,** with the catalog index sent to the worker: the worker serialises native calls, so matching would delay the next OCR, and the index would have to stay in step with mode changes and refreshes, coupling the catalog lifecycle to the vision service generation.
- **Matching on the UI isolate:** each title is scored against every candidate twice, an estimated 5-20 ms per title, multiplied by the full-client peak count. It would drop frames.
- **Returning the full float response map to Dart:** about 32 MiB per 4K frame, copied across FFI for each fallback.
- **Iterative best-match with masking:** it needs N full-frame matches, and painting over pixels alters neighbouring correlations, so it cannot reproduce the plateau and suppression rule.
- **Native-side suppression:** it puts policy in native code and makes the rule untestable without the DLL.
- **A PNG marker asset decoded in the worker:** it adds a codec to the runtime path, and the decoder's output would become part of the template's identity. Raw `.gray` plus `.json` is already the pattern of the self-check asset.
- **Loading the template inside the job from the runtime directory:** the job context exposes no path, and ADR-0011 fixes templates as service-construction input.
- **Reproducing the reference's swapped-weight marker conversion:** it only made sense for its own template composited on a fixed background. With a template cut from a real screenshot, consistent weights maximise correlation.
- **Reusing the existing substring catalog search index:** it has no edit distance and mixes IDs into the haystack.
- **OCR only on the best full-client peak:** the reference reads every peak, and ranking needs each one's match.
- **Committing the corpus:** the images are user game screenshots with unresolved redistribution status, and they are large.
- **No ADR:** change 5 and M4 depend on the job seam and the evidence contract.

## Consequences

- **The marker is redistributed game artwork.** The user chose this explicitly. The notices entry states the status and `check_bundle` enforces that the entry exists.
- **Whether one crop reaches the gate at other resolutions is unproven** until the user's corpus runs. If scores fall short, a per-family template set is a follow-up change. Synthetic tests prove geometry and gate arithmetic only, so coverage and false-positive claims stay unverified until then.
- **Correct-weight grayscale shifts marker scores** compared with the reference. The corpus baseline comparison makes the shift visible.
- **A stale bundle fails loudly.** The ABI bump makes an old bundle report `abiMismatch`, a typed failure.
- **Bounded by construction:** 4096 native peak candidates, 8 kept inspections per full-client frame (each costs an OCR call against the 1.5 s deadline), 256 KiB crop per evidence entry, 4 cached scaled templates, one matcher isolate per outcome.
- **The index is copied into the matcher isolate once per outcome.** If measured as material, change 5 can switch to a long-lived matcher isolate.
- **Mid-request OCR failure aborts the whole request,** so a failing engine is not trusted for the remaining peaks.
- **The confirming matcher maps only Cyrillic capitals to Latin.** Lower-case mapping in the reference is unverified, so it is not built.
- **Future recognition work binds here:** M4 hotkeys and other languages reuse the evidence contract and the job seam.
- **Reversal cost:** low for the matcher adapters, the peak primitive (additive; the ABI bump is a manifest and constant change), grayscale weights and the test layering. Medium for the job and evidence types, which change 5 codes against, and for the marker asset format, which is committed data used by one file.
