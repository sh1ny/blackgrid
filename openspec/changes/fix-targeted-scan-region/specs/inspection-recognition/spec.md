# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: Targeted recognition finds the best marker`
- TO: `### Requirement: Targeted recognition finds every inspection in its region`

## MODIFIED Requirements

### Requirement: Targeted recognition finds every inspection in its region
For a targeted frame, the job SHALL search for marker peaks exactly as for a full-client frame: every peak scoring at least .82, with the same plateau rule, visit order, suppression and cap of 8 kept peaks, each kept peak getting its own title read. With no peak at or above .82, the result SHALL hold no evidence and the best score observed: the `noMarker` case.

#### Scenario: Marker present
- **WHEN** a synthetic targeted frame contains the scaled template at (40, 12)
- **THEN** the evidence holds one entry reporting marker position (40, 12) and a score of at least .99

#### Scenario: Cascaded inspection windows
- **WHEN** a synthetic targeted frame contains two non-overlapping marker copies with different titles
- **THEN** the job returns two evidence entries in score order, each with its own title text

#### Scenario: Score just below the gate
- **WHEN** the best correlation score in a targeted frame is 0.8199
- **THEN** the result holds no evidence and best score 0.8199, and no OCR runs

#### Scenario: Score at the gate
- **WHEN** the best correlation score in a targeted frame is exactly 0.82
- **THEN** the marker is accepted and title extraction runs

#### Scenario: Too many peaks
- **WHEN** the native peak listing for a targeted frame reports more peaks than its cap
- **THEN** the job returns rejection `markerPeaksOverflow`, as for a full-client frame
