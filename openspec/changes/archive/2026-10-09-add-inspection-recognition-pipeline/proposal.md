# Proposal

## Why

M2 (capture/recognition proof) needs a recognition step between the warm vision worker (change 3) and the Scanner wiring (change 5). Nothing yet turns a captured inspection frame into an accepted item identity, or into a typed rejection. This is M2 change 4. It serves these exit criteria:

- Offline recognition reports, per case, the marker score, title crop, OCR text, candidate scores, and the accepted ID or the rejection, with coverage and false positives compared against the reference (agent-verified, once the user-labelled corpus and the baseline exist).
- The pipeline's half of "blocked or slow native calls cannot freeze the UI isolate or publish late": the pipeline runs only as a vision-worker job, under ADR-0011.

Constrained by ADR-0008 (item vision runtime: English, LSTM-only, raw-line OCR; bundle-only, manifest-bound files), ADR-0010 (physical-pixel ROI, frames cross isolates as tickets) and ADR-0011 (job seam fixed at spawn, sendable params and results, templates owned by the worker). The behaviour target is the user's private reference companion, following its working approach (functional parity) rather than stricter gates it never had. Blackgrid copies no code from it.

## What Changes

- **Inspection marker template asset.** The user captures a game screenshot of an open inspection window and supplies it. A repeatable tool crops the magnifier marker's footprint from it and normalises it to a 28×28 8-bit grayscale asset at the reference template size, with provenance (screenshot hash, source size, footprint origin, recipe). The asset is installed under `data/vision/` and bound by the existing vision runtime manifest, so a changed or missing marker fails verification like any other vision file. `THIRD_PARTY_NOTICES.md` records it as game UI artwork captured by the user. The reference's RatEye `icon_search.png` is not used: its ELv2 terms forbid redistribution, and rights gate G11 is open.
- **Inspection recognition job.** A `VisionJob` that runs in the vision worker over a targeted ROI frame or a full-client frame:
  - Scales the marker to the client resolution (28×28 × 16/28 × `min(w/1920, h/1080)`, as the reference scales its marker).
  - Finds the marker with normalised cross-correlation.
  - Derives the marker-relative title region (1.2× marker-width offset, 17×scale high, 500×scale wide, trimmed at the close-button colour probe minus 64×scale), clamped and never padded.
  - Resizes the title to 4K-equivalent size (2/scale), applies an inverted binary threshold at 120, and runs OCR.
  - In full-client mode, finds every marker peak at or above .82, with plateau and overlap suppression, and reads each one's title.
  - Returns sendable evidence per inspection: marker score and position, title rectangle, a bounded copy of the thresholded title crop, OCR text, and per-stage QPC timings, or a typed failure.
- **Title normalisation and identity matching, pure Dart.**
  - Normalisation: NFKC, lower case, keep letters and digits, collapse every other run to one space.
  - Similarity: the better of normalised Levenshtein and a space-insensitive compact similarity.
  - Gates: marker .82, similarity .55, minimum normalised title length 3, runner-up margin .05.
  - Confirming raw-name matcher: lower-cased raw names, first candidate wins ties, gate .55, its own UI-chrome check at .85 similarity. Below the .05 margin, a near-tie is accepted only when this matcher picks the same item; below .03, it also needs a matching quantity token of 10 or more.
  - Numeric-quantity constraint, OCR digit confusions (`@`→0, leading `i`/`l`→1), and exact localised UI-chrome rejection.
  - Duplicate normalised names resolve deterministically to the smaller ID.
  - Every outcome is typed: accepted, no marker, title too short, UI chrome, below similarity, ambiguous, empty catalog, catalog mode mismatch, or matcher failed. Each carries the best and runner-up candidates and their scores. Matching runs against an immutable, mode-scoped match index built from a `CatalogSnapshot`.
- **Recognition outcome over targeted and fallback evidence.** Targeted evidence is matched first. If it is not accepted, the caller can submit a full-client fallback; its evidence is ranked accepted first, then by similarity, then by marker score, then by peak order. Unaccepted evidence stays a rejection with its evidence attached and is never an identity. Scheduling the fallback (when to capture, deadlines) and the UI belong to change 5.
- **Offline corpus harness.** A qualification-tagged runner executes the job and matcher over a labelled screenshot corpus. Per case it reports marker score, title crop, OCR text, candidate scores and accepted ID or rejection, and compares coverage and false positives with a recorded reference baseline when one is present. The corpus and its labels are user-supplied. Until they exist, the harness runs over synthetic fixtures only and reports the corpus comparison as unverified.
- Not in this change: wiring into app startup or Scanner, hotkeys, decisions, history, the Map snapshot, and multilingual OCR. The vision service stays unwired, as ADR-0011 requires.

## Capabilities

### New Capabilities
- `inspection-recognition`: turns a captured inspection frame (targeted ROI or full client) into typed per-inspection evidence inside the vision worker. Covers the marker template asset and its provenance, scale derivation, marker search and multi-peak suppression, the title region, OCR preprocessing, and evidence and timing output.
- `item-title-matching`: turns OCR title text into an accepted catalog identity or a typed rejection. Covers normalisation, similarity, the baseline gates, the confirming matcher, quantity and UI-chrome safeguards, deterministic ties, the mode-scoped match index, and targeted/fallback evidence ranking.

### Modified Capabilities
- `vision-runtime`: adds one primitive that lists every template-match location at or above a threshold (capped, with overflow reported). Full-client recognition needs every peak, and the existing primitive returns only the best. The vision ABI version goes from 1 to 2.
- `release-bundle-integrity`: the bundle inventory and the third-party notices requirement now include the inspection marker template, which is bound by the vision runtime manifest and recorded as user-captured game artwork.

## Impact

- New Dart under `lib/data/vision/` (recognition job, evidence types) and `lib/domain/` (normaliser, matcher, match index). Both are pure and testable without the native runtime through a fake `VisionJobContext` backend.
- New asset under `assets/vision/marker/`, a crop tool under `tool/vision/`, a CMake install entry in `windows/vision/CMakeLists.txt` (bound into `runtime.manifest.json`), the marker files in `tool/vision/bundle_inventory.json`, a game-artwork notices step in `tool/vision/check_bundle.dart`, and a notices entry.
- New Dart dependency `unorm_dart` 0.3.3 (MIT, pure Dart) for NFKC normalisation, which the Dart SDK lacks.
- New offline tests: geometry, threshold and peak-suppression vectors, matcher boundary vectors at each gate (just below, at, and above), quantity, chrome and Unicode cases. Qualification-tagged corpus and real-runtime tests are excluded from `mise run test`.
- A user step: supply one in-game screenshot with an open inspection window (from a saved screenshot file; agents never capture the game). Labelling the corpus and recording the reference baseline remain user-verified M2 criteria.
- No new third-party native libraries. One new owned primitive in `windows/vision/vision.cpp` (`bgv_match_template_peaks`) bumps `BGV_ABI_VERSION` to 2; the Dart binding and `visionExpectedAbi` move with it. The existing one-row colour scan covers the close-button probe.
