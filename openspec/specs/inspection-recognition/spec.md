# inspection-recognition Specification

## Purpose
Turns a captured inspection frame, either a targeted region near the cursor or the full game client, into typed per-inspection evidence (marker, title crop, OCR text, timings) inside the vision worker, using a marker template whose bytes and provenance are bound in the bundle.

## Requirements

### Requirement: Marker template is a bound, provenanced asset
The bundle SHALL contain one 8-bit grayscale inspection marker template of exactly 28×28 pixels: the marker's footprint at the reference template size, matching the reference's 16×16 footprint at 1080p. It SHALL carry its provenance (source screenshot SHA-256, source client size, footprint origin, recipe). The vision runtime manifest SHALL bind it, and it SHALL load without the UI or the database.

#### Scenario: Template loads from an intact bundle
- **WHEN** the marker template is loaded from an intact Release bundle
- **THEN** it yields a 28×28 1-channel image with non-zero variance, and its SHA-256 equals the manifest entry

#### Scenario: Altered template
- **WHEN** one byte of the bundled marker template is changed
- **THEN** runtime verification fails with failure `hashMismatch` naming the template file, and no recognition runs

#### Scenario: Metadata disagrees with pixels
- **WHEN** the template's metadata declares a width × height different from the pixel byte count
- **THEN** loading fails with a typed `invalidTemplate` failure naming the template

### Requirement: Marker template is regenerated reproducibly from a user-supplied screenshot
A repository tool SHALL produce the marker template from a user-supplied screenshot of the game client area and the marker's top-left pixel. With s = min(W/1920, H/1080) of the screenshot size, it SHALL crop the square footprint of side trunc(16 × s) at that origin and resize it to 28×28. Equal inputs SHALL give byte-identical output. The tool SHALL never capture the screen itself.

#### Scenario: Reproducible regeneration
- **WHEN** the tool runs twice on the same 2560×1440 screenshot and marker origin
- **THEN** both runs crop a 21×21 footprint and write byte-identical 28×28 template and metadata files, and the metadata records the screenshot's SHA-256, its size and the origin

#### Scenario: Footprint outside the screenshot
- **WHEN** the footprint at the given origin extends past the screenshot's bounds
- **THEN** the tool exits non-zero naming the footprint and the image size, and writes no files

#### Scenario: Screenshot below 1080p scale
- **WHEN** the screenshot's scale s is below 1.0, so the footprint would be smaller than 16 pixels
- **THEN** the tool exits non-zero asking for a screenshot at 1080p scale or larger, and writes no files

### Requirement: Processing scale follows the client size
The recognition job SHALL derive the processing scale from the client size given with the request as min(width / 1920, height / 1080), independent of Windows display scaling. It SHALL scale the 28×28 marker template by (16 / 28) × processing scale, truncating each side to whole pixels.

#### Scenario: 4K client
- **WHEN** a frame comes from a 3840×2160 client
- **THEN** the processing scale is 2.0 and the template is matched at 32×32

#### Scenario: Ultrawide client
- **WHEN** a frame comes from a 3440×1440 client
- **THEN** the processing scale is 1440 / 1080 (about 1.333), not 3440 / 1920

#### Scenario: Scaled template collapses
- **WHEN** the scaled template would be smaller than 2 pixels on a side, or larger than the frame
- **THEN** the job returns failure `scaleOutOfRange` with the processing scale, and no template match runs

### Requirement: Targeted recognition finds the best marker
For a targeted frame, the job SHALL convert the frame to grayscale and take the single best normalised cross-correlation location of the scaled template. It SHALL report one evidence entry when the score is at least .82. Below that, the result SHALL hold no evidence and the best score: the `noMarker` case.

#### Scenario: Marker present
- **WHEN** a synthetic targeted frame contains the scaled template at (40, 12)
- **THEN** the evidence reports marker position (40, 12) and a score of at least .99

#### Scenario: Score just below the gate
- **WHEN** the best correlation score is 0.8199
- **THEN** the result holds no evidence and best score 0.8199, and no OCR runs

#### Scenario: Score at the gate
- **WHEN** the best correlation score is exactly 0.82
- **THEN** the marker is accepted and title extraction runs

### Requirement: Full-client recognition finds every inspection
For a full-client frame, the job SHALL report every correlation peak with a score of at least .82. A peak SHALL win its plateau: of 8-neighbours with an equal score, the earliest in raster order wins. Peaks SHALL be visited by score descending, then y ascending, then x ascending, and each accepted peak SHALL suppress any later peak whose top-left is less than one template width and height from it. Each kept peak SHALL get its own title read.

#### Scenario: Two inspection windows
- **WHEN** a synthetic full-client frame contains two non-overlapping marker copies
- **THEN** the job returns two evidence entries in score order, each with its own title text

#### Scenario: Overlapping peaks
- **WHEN** two peaks at or above .82 lie within one template width and height of each other
- **THEN** only the higher-scoring peak is reported

#### Scenario: No inspection on screen
- **WHEN** no correlation score in the full-client frame reaches .82
- **THEN** the job returns an empty evidence list with the best score observed, not a failure

### Requirement: Title region is derived from the marker and clamped
The title region SHALL start at marker x + trunc(scaled marker width × 1.2) and at marker y. Its height SHALL be trunc(17 × scale) and its width trunc(500 × scale), both clamped to the frame. When a close-button pixel (R 50–80, G 10–15, B 10–15) is found on row marker y + scaled marker height div 2, scanning right from the region's start x, the width SHALL end trunc(64 × scale) before it. The region SHALL never be padded.

#### Scenario: Close button narrows the title
- **WHEN** a 1080p frame has a marker at (100, 50) with a 16 px scaled width and a close-button pixel at x 400 on row 58
- **THEN** the title region is x 119, y 50, width 217, height 17

#### Scenario: Region clipped at the frame edge
- **WHEN** the marker sits so near the right edge that fewer than trunc(500 × scale) pixels remain
- **THEN** the region width equals the remaining pixels, and no padding pixels appear in the crop

#### Scenario: Empty region
- **WHEN** the clamped or close-button-narrowed width or height is 0 or less, or the region's start x lies at or beyond the frame's right edge
- **THEN** the evidence entry has title status `emptyTitleRegion` and empty text, no probe or OCR runs for it, and the request does not fail

### Requirement: Title text is read from a normalised, thresholded crop
The job SHALL resize the title crop by 2 ÷ scale (cubic when enlarging, area when shrinking, unchanged at exactly 1), convert it to grayscale, apply an inverted binary threshold at 120 (above 120 becomes 0, otherwise 255), and OCR the result. It SHALL report the trimmed text.

#### Scenario: Title recognised
- **WHEN** a frame holds a marker and a light rendered title "SALEWA FIRST AID KIT" in the title region
- **THEN** the evidence's OCR text, trimmed, is "SALEWA FIRST AID KIT"

#### Scenario: OCR fails natively
- **WHEN** the OCR call returns a native failure
- **THEN** the job's answer is that typed failure, not evidence with empty text

### Requirement: Evidence is sendable and bounded
A recognition result SHALL hold the frame kind (targeted or full client), processing scale, best marker score and its evidence entries. Each entry SHALL hold marker score and position, title region, title status (`read` or `emptyTitleRegion`), OCR text, a thresholded crop copy of at most 256 KiB and QPC stage timestamps. Nothing SHALL reference frame or native memory.

#### Scenario: Evidence outlives the frame
- **WHEN** a targeted recognition completes and the frame has been released
- **THEN** the evidence's crop bytes and text are still readable and unchanged

#### Scenario: Oversized crop
- **WHEN** the thresholded crop would exceed 256 KiB
- **THEN** the evidence carries a downscaled preview within 256 KiB, flagged `cropDownscaled`, and the OCR still ran on the full-size crop

#### Scenario: Stage timestamps are ordered
- **WHEN** a recognition completes
- **THEN** its stage timestamps are non-decreasing in stage order

### Requirement: Recognition runs only as a vision-worker job
Recognition SHALL run only inside the vision worker as a job: no native recognition step SHALL run on the UI isolate. The application SHALL start recognition only through the scan pipeline while live scanning is on; with live scanning off, normal launch SHALL NOT start recognition.

#### Scenario: Job runs against a fake runtime
- **WHEN** the recognition job runs in a test against a fake job context
- **THEN** it completes without loading any native library

#### Scenario: Normal launch
- **WHEN** the application starts normally with live scanning off
- **THEN** no recognition job is constructed, and the offline source audit finds the job referenced only by the scan pipeline's source
