# Spec Delta

## MODIFIED Requirements

### Requirement: Evidence is sendable and bounded
A recognition result SHALL hold frame kind, processing scale, best marker score and evidence entries. Each entry SHALL hold marker score/position, title region/status, OCR text, a crop of at most 256 KiB, QPC stage timestamps and typed FIR evidence (Yes, No or Unknown, with its reason and searched region). No value SHALL reference frame or native memory. The title crop SHALL remain the bounded OCR preview, or empty for `emptyTitleRegion`.

#### Scenario: Evidence outlives the frame
- **WHEN** a targeted recognition completes and the frame has been released
- **THEN** the evidence's crop bytes, text and FIR value/reason remain readable and unchanged

#### Scenario: Oversized crop
- **WHEN** the thresholded crop would exceed 256 KiB
- **THEN** the evidence carries a downscaled preview within 256 KiB, flagged `cropDownscaled`, and the OCR still ran on the full-size crop

#### Scenario: Stage timestamps are ordered
- **WHEN** a recognition completes
- **THEN** its stage timestamps are non-decreasing in stage order

#### Scenario: Right margin is bounded before preview generation
- **WHEN** a 999-pixel-wide thresholded title image is narrowed to 595 pixels before OCR and fits the evidence byte limit
- **THEN** the evidence crop is 595 pixels wide with the same pixels as the OCR input, and its title region still identifies the original frame-space extraction rectangle

#### Scenario: Crop-free report keeps FIR
- **WHEN** a recognition report discards its title-preview bytes for recent-report retention
- **THEN** each inspection retains its FIR value, reason and searched-region metadata without retaining picture pixels

## ADDED Requirements

### Requirement: Found-in-raid evidence belongs to the inspection picture
For each inspection the system SHALL analyse the bottom-left picture corner from that inspection's existing frame. A recognised check icon SHALL yield Yes. A completely captured, readable corner without it SHALL yield No. An incomplete or unreadable corner SHALL yield Unknown with a reason. A mastery medal SHALL NOT count as the check. The system SHALL NOT acquire another frame solely to determine FIR.

#### Scenario: Check without a medal
- **WHEN** an inspection's readable picture corner contains the check icon without a mastery medal
- **THEN** that inspection's FIR evidence is Yes with reason icon found

#### Scenario: Check beside a medal
- **WHEN** the check icon is to the right of the mastery medal in the inspected picture
- **THEN** that inspection's FIR evidence is Yes

#### Scenario: Fully captured negative corners
- **WHEN** a readable corner contains either only a mastery medal or neither icon
- **THEN** that inspection's FIR evidence is No with reason icon absent

#### Scenario: Cut-off corner
- **WHEN** the title and marker are readable but any required corner or readability-check pixels lie outside the captured frame
- **THEN** FIR is Unknown with reason corner cut off; the absent pixels are not padded and no extra capture is requested

#### Scenario: Unreadable corner
- **WHEN** corner pixels are present but the picture/action boundary cannot be validated, or the icon match is ambiguous, including unexplained check-coloured fragments
- **THEN** FIR is Unknown with reason corner unreadable, never No

#### Scenario: Partially obscured check
- **WHEN** part of a check is hidden, its residual pixels remain visible and its match score is below the positive threshold
- **THEN** the inspection reports FIR Unknown with reason corner unreadable, never No

#### Scenario: Multiple windows have different FIR
- **WHEN** a frame contains one inspection with a check and another readable inspection without one
- **THEN** the entries carry Yes and No respectively, without borrowing the other inspection's icon

#### Scenario: Frame kind and origin do not change the result
- **WHEN** the same complete inspection is present in targeted and full-client frames, including a frame with a clipped client origin but an intact corner
- **THEN** both entries yield the same FIR value using the actual frame coordinates and the physical client scale

### Requirement: The check template is bound and reproducible
The bundle SHALL bind a small grayscale check-icon template and its metadata by hash. Metadata SHALL identify the source screenshot hash, physical client size, source crop and recipe. The source screenshot SHALL remain private. Equal source bytes and recipe SHALL reproduce identical assets. A missing, altered or invalid template SHALL report a scan-start failure, not manufacture negative FIR evidence.

#### Scenario: Intact reproducible template
- **WHEN** the template tool runs twice on the annotated owner screenshot and the resulting intact bundle starts live scan
- **THEN** both generated assets are byte-identical and the worker receives a validated template

#### Scenario: Invalid template bundle
- **WHEN** either check-template file is missing, its hash differs, or its metadata disagrees with its pixels
- **THEN** live scan reports an explicit template-unavailable or invalid-template failure before recognition starts

### Requirement: FIR detection is qualified offline on supplied pictures
Offline qualification SHALL compare detected FIR with frozen owner-picture labels at 1920×1080 and 3440×1440, covering positive/negative flags, medals/no medal and direct/container-opened inspections. Client size and captured bounds SHALL be annotated separately from image dimensions. The runner SHALL read only supplied files and SHALL report missing inputs as unverified, never passed.

#### Scenario: Owner-picture matrix
- **WHEN** the twelve supplied images and their frozen annotations are replayed with the production detector
- **THEN** each annotated inspection yields its labelled Yes or No, with no Unknown substituted for a readable negative

#### Scenario: Misleading file dimensions
- **WHEN** a supplied 3440×1392 image is annotated as a bottom-cropped 3440×1440 client, or a bordered image contains a 1920×1080 client
- **THEN** recognition uses the annotated client scale and captured origin, not an inferred scale from the JPEG dimensions

#### Scenario: Missing private input
- **WHEN** a required screenshot or its expected hash is unavailable to the qualification run
- **THEN** the matrix is reported unverified with the missing input identified, not as a successful qualification
