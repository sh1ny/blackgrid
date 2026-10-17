# Spec Delta

## MODIFIED Requirements

### Requirement: Title text is read from a normalised, thresholded crop
The job SHALL resize the title crop by 2 ÷ scale (cubic when enlarging, area when shrinking, unchanged at exactly 1), convert it to grayscale, apply an inverted binary threshold at 120 (above 120 becomes 0, otherwise 255), and OCR the result after bounding its blank right margin. It SHALL preserve every foreground pixel, internal spacing, the left edge and height. It SHALL report the trimmed text; a crop with no foreground SHALL produce empty text without OCR.

#### Scenario: Title recognised
- **WHEN** a frame holds a marker and a light rendered title "SALEWA FIRST AID KIT" in the title region
- **THEN** the evidence's OCR text, trimmed, is "SALEWA FIRST AID KIT"

#### Scenario: OCR fails natively
- **WHEN** the OCR call returns a native failure
- **THEN** the job's answer is that typed failure, not evidence with empty text

#### Scenario: Short title has an excessive blank right margin
- **WHEN** a thresholded title image is 999 pixels wide and its last foreground pixel is at x 586
- **THEN** OCR receives a 595-pixel-wide image containing the original columns 0 through 594, preserving the original height and all title pixels

#### Scenario: Title reaches the existing crop boundary
- **WHEN** the final column of a thresholded title image contains foreground
- **THEN** OCR receives the entire original image without clipping text or adding pixels beyond the existing boundary

#### Scenario: Internal spaces and detached punctuation
- **WHEN** a title contains spaces and a final parenthesis separated from the preceding glyph
- **THEN** the right edge is determined by the last foreground pixel across the entire image, and every space and the final parenthesis remain in the OCR input

#### Scenario: No foreground
- **WHEN** every pixel of a non-empty thresholded title image is white
- **THEN** the evidence has title status `read` and empty text, its preview is the original white crop subject to the byte limit, and OCR is not called

### Requirement: Evidence is sendable and bounded
A recognition result SHALL hold the frame kind (targeted or full client), processing scale, best marker score and its evidence entries. Each entry SHALL hold marker score and position, title region, title status (`read` or `emptyTitleRegion`), OCR text, a thresholded crop copy of at most 256 KiB and QPC stage timestamps. Nothing SHALL reference frame or native memory. The crop SHALL be the image sent to OCR (the blank image when OCR is skipped), or its downscaled preview above the limit.

#### Scenario: Evidence outlives the frame
- **WHEN** a targeted recognition completes and the frame has been released
- **THEN** the evidence's crop bytes and text are still readable and unchanged

#### Scenario: Oversized crop
- **WHEN** the thresholded crop would exceed 256 KiB
- **THEN** the evidence carries a downscaled preview within 256 KiB, flagged `cropDownscaled`, and the OCR still ran on the full-size crop

#### Scenario: Stage timestamps are ordered
- **WHEN** a recognition completes
- **THEN** its stage timestamps are non-decreasing in stage order

#### Scenario: Right margin is bounded before preview generation
- **WHEN** a 999-pixel-wide thresholded title image is narrowed to 595 pixels before OCR and fits the evidence byte limit
- **THEN** the evidence crop is 595 pixels wide with the same pixels as the OCR input, and its title region still identifies the original frame-space extraction rectangle

## ADDED Requirements

### Requirement: OCR title margin is bounded by rendered content
The normalised thresholded title image SHALL end eight pixels after the exclusive right edge of its rightmost foreground pixel, capped at its current width. Black pixels (value 0) are foreground; white pixels (255) are background. The rule SHALL apply equally to targeted and full-client title reads, and SHALL NOT alter recognition acceptance gates.

#### Scenario: Bounded whitespace remains
- **WHEN** the rightmost foreground pixel is at x 19 in a 50-pixel-wide image
- **THEN** the OCR input width is 28 and columns 0 through 27 are preserved

#### Scenario: Limited room at the boundary
- **WHEN** the rightmost foreground pixel is at x 46 in a 50-pixel-wide image
- **THEN** the OCR input width remains 50 without padding outside the image
