# 0040 - Found-in-raid evidence belongs to the accepted inspection

- Status: accepted
- Date: 2026-11-11 (change `detect-found-in-raid`)
- Supersedes: 0016 ([ADR-0016](0016-centred-targeted-region.md)), the targeted band's lower-edge formula only (`60` becomes `400`). Its remaining decisions, and the physical-pixel, full-client fallback and clip-not-pad boundaries of ADR-0010, stay in force.
- Source: change `detect-found-in-raid` (design D1-D5, State & Ownership, Resource Bounds); [ADR-0012](0012-inspection-recognition-pipeline.md), [ADR-0017](0017-accepted-scans-feed-the-decision-engine.md)

## Context and problem

A title identifies an item, but its found-in-raid (FIR) state is a separate fact pictured in the inspection window. A false No can hide a FIR-only quest need. Multiple inspections may be present in a single frame, and a mastery medal can appear beside the FIR check. A missing or obscured corner is not evidence that the check is absent. Detection must stay associated with the inspection that wins title matching, and manual choices must not rewrite that evidence.

The owner supplied twelve private saved pictures with frozen labels, hashes and client geometry. A planning-only image experiment motivated the recipe below; it is not a production/native accuracy result. Production offline qualification and the owner-only live check remain separate acceptance work. No agent may interact with the game to obtain or verify evidence.

## Decision

### Targeted capture

Keep ADR-0016's centred band, changing only its below-centre reference constant from 60 to 400. For physical client size `w×h`, `cx = w div 2`, `cy = h div 2`, exact rational `s = min(w/1920, h/1080)` and `f(k) = floor(k*s)`, the requested rectangle is `(cx - f(440), 0, f(440) + f(700), cy + f(400))`. DPI is metadata, not a scaling input; the trigger remains an in-client identity guard. Intersect with the client and virtual desktop, report requested and captured rectangles, and clip rather than pad. Empty intersections and existing size limits remain failures. The width, top edge, full-client fallback, marker ranking, waits and capture safety/ownership rules are unchanged. At 3840×2160 the requested band is 2280×1880.

No new capture or retry is made for FIR: Unknown does not reject an accepted title or trigger a fallback. This does not remove ADR-0015's independently opted-in recording capture.

### Guarded template and reproducible binding

The existing recognition job uses the captured frame's grayscale for NCC and its BGRX pixels for guards; X is ignored. Marker offsets below are in reference pixels and each coordinate is scaled with `floor(offset*s)`, including negative offsets, using the physical client size rather than the captured image size.

1. For each retained inspection, use the marker in actual frame coordinates and the half-open rectangle from marker + `(floor(-8*s), floor(275*s))` to marker + `(floor(80*s), floor(330*s))`. Require the complete rectangle and every guard pixel inside the real frame; never clamp and call it complete. Clipping elsewhere does not invalidate an intact corner.
2. Validate the picture/action boundary: at reference x offsets 60, 65, 70 and 75, all BGR channels at y offsets 318, 319 and 320 must be ≤12, and all channels at y offsets 323, 324 and 325 must be in [18,45]. A failed cue is unreadable, not absent.
3. Use a 28×28 raw grayscale check template cropped without resampling from image rectangle `(1199, 732, 28, 28)` of the private `afak_fir_yes_no_medal_3440x1440.jpg`. Its source image and physical client are both 3440×1440, image client origin (0,0), SHA-256 `0d5fbdccd97c07c5b9a82c97633059325c9142cbab27953c024c868c93e2169b`. Convert with the same correct BGR luma as the marker and frame (the marker tool's fixed-point `(R*4899 + G*9617 + B*1868 + 8192) >> 14`). The stored crop includes a dark margin. Its reference footprint is 21 pixels; scale to `trunc(21*s)` using the existing cubic/area rule. A side below 2 or too large for the search rectangle is unreadable.
4. Match within the bounded rectangle with the existing native NCC primitive. A finite score ≥0.82 yields `iconFound` (Yes). A score in (0.60,0.82), a non-finite score or an invalid candidate is unreadable. Do not pass a constant template or mask a native failure. These gates do not change title or marker acceptance.
5. A score ≤0.60 yields `iconAbsent` (No) only after the boundary passes and no unexplained gold remains in the expected check slot. A gold pixel has `R>110`, `G>90`, `B<0.8*G` and `R>1.4*B`. A medal witness is at least `max(1,floor(2*s*s))` gold pixels in marker-relative x `[-4,0)`, y `[280,318)`. With a witness, inspect residual gold in x `[32,75)`, y `[280,318)`; without one inspect x `[-4,75)`, y `[280,318)`. Scale rectangle edges with the same floor rule. Any residual gold makes a low score unreadable. The witness never yields Yes; only the template match does. Treat a uniformly dark search image as zero score only after the separate boundary and residual-gold guards pass.
6. Return typed `iconFound`, `iconAbsent`, `cornerCutOff` or `cornerUnreadable`, with the searched rectangle and a finite best score when one exists. Cut-off and unreadable both project to Unknown, with distinct reasons. A missing template is a startup failure, not per-frame Unknown; native operation failures follow the existing typed worker failure path.

The deterministic offline recipe records source SHA-256, source image size, physical client size, crop rectangle, grayscale conversion and recipe version in metadata; equal source bytes and recipe reproduce identical raw pixels and metadata. Keep the source screenshot private. Install both `.gray` and `.json` under `data/vision/fir/`, bind both in the runtime manifest and required core files, inventory them and record artwork rights, source hash and recipe in the notice. Load and validate the complete marker/check asset set before scan activation; missing, altered or invalid files fail explicitly before recognition. The existing marker bytes, format and recipe remain unchanged. This artwork binding follows ADR-0012; it is not a new native ABI.

### Per-inspection evidence and ownership

`InspectionRecognitionJob` computes one required typed reading for each retained inspection while it owns the frame. It returns sendable, immutable metadata, including reason, searched rectangle and finite score when available, with no reference to frame or native memory. Title crop stripping keeps this metadata without a FIR image preview. The existing title matcher ranks entries as before; after its existing report-id, epoch, mode and item fences, `ScanDecisionFeed` passes only the winning outcome's reading into selection. A different entry's icon must never supply the winner's FIR.

Selection constructs an immutable `AcceptedScan` with the winning detection and the decision at acceptance. It first clears any old override and projects the detected value through the shared decision engine, then freezes the acceptance decision and records its existing history verdict before later refreshes or overrides can change the snapshot. Session state retains the latest accepted record under the existing higher-report-id rule; duplicates and stale reports cannot reapply detection or erase an override.

`SelectionController` alone owns the current detected source and nullable manual override. Effective FIR is the override if present, otherwise the current scan detection, otherwise Unknown. A manual Unknown is a real override, not the absence sentinel. New accepted scans, even of the same item, clear the override and use their own detection. Manual, history and correction selections clear old scan evidence and override and start Unknown; mode/session retirement clears all FIR context. Same-selection catalog/progress refresh and age changes recompute advice without resetting either source. A missing selected item supplies no advice or FIR to another item.

Returning to the latest accepted scan restores its immutable detected reading and original age, clears any override, closes history and records no activity. A stale epoch/mode or missing item refuses the return without changing selection, FIR or history. Neither a refresh nor a later override alters the accepted detection, acceptance verdict or recorded verdict.

### Shared control and provenance

Map and Scanner use the existing shared Unknown/Yes/No control and inline caption, with source and cut-off/unreadable reason available as text and semantics. Manual/history/correction Unknown does not claim automatic detection. Any activation, including the already selected automatic value, establishes a manual override. Keep the displayed controlled selection a singleton: enable `emptySelectionAllowed` solely to receive selected-segment activation, map an empty callback to the value captured for that render and a non-empty callback to its single value, and call `setFir` in both cases. Never publish an empty selection or add an Auto segment. Existing Ember tokens and wrapping remain in use.

### Bounds, failures and persistence

Retain the existing capture limits (four slots, side ≤8192, ≤25,165,824 pixels, one active and zero queued, 500 ms deadline and 2 s drain) and vision limits (4096 native peaks, eight retained inspections, 1.5 s submission deadline and 2 s drain). Corner work is one bounded scaled rectangle per retained inspection; there is no additional full-frame copy. Marker and check templates have separate four-size worker-owned caches. Evidence adds only fixed scalar/rectangle FIR metadata to the existing ≤256 KiB title preview per entry. The existing recent-report bound remains; qualification reads the frozen twelve pictures one at a time.

Readings and overrides are session-only; restart restores neither. No FIR value or additional image is added to Drift, history, settings or Tracker, and there is no data migration. ADR-0015's independently opted-in frame recording is unchanged. The existing activity record continues to store its source and acceptance verdict. No new queue, isolate, native export or ABI, detector service, observation channel or FIR-specific capture is introduced. Scan-start template failures and typed worker failures stay visible rather than manufacturing No. Missing private qualification inputs are unverified, not passed.

## Rejected alternatives

- **Capture the full height or make a second FIR capture:** the former spends more pixels; the latter can pair the title with a different screen and adds work and ordering risk.
- **Infer No from a low NCC score or search gold alone:** clipping and partial checks can lower scores, and a mastery medal can look gold. Readability and residual-gold admission protect the negative; only a template match produces Yes.
- **Send picture pixels to the UI or take the first inspection's FIR:** this extends frame ownership and can associate an unrelated window with the accepted item.
- **Mutate the accepted record or use Unknown as the no-override sentinel:** source evidence and user input become indistinguishable, and explicit manual Unknown cannot override detected Yes.
- **Persist FIR or add a new service, isolate, queue, native API or setting:** existing bounded in-memory ownership and worker primitives suffice for the chosen behavior.

## Consequences

- The deeper band costs more capture and recognition work; existing clipping, admission and deadlines still apply. Saved targeted replay must measure conflicts and timing; absent inputs remain unverified.
- A complete but unreadable corner produces conservative Unknown without invalidating item identity. A missing or corrupt required template prevents scan activation.
- Detection and acceptance are immutable snapshots while the visible decision may change with manual override or refreshed authorities. Latest-scan return restores detection, not the old override.
- The template is redistributed game artwork with recorded provenance and notice; source screenshots remain private. The measured recipe covers the supplied layout, not a universal accuracy claim. All twelve frozen labels need production offline qualification; live verification belongs to the owner alone.
- Reversal cost is low for the band constant, calibrated numeric gates and transient override; it is medium for the bound template and shared per-inspection evidence contracts. No stored user data migration is needed.
