# Prepared map packs delta

## MODIFIED Requirements

### Requirement: Only the active generation is ever used
The app SHALL load only the generation that `assets/maps/active.json` names. It SHALL NOT fall back to any other generation. A pack that fails to load SHALL show its error in the map area. Packs SHALL use preparation version 5, with the complete supported map set, and the app and candidate validator SHALL refuse any other preparation version. A rollback is a commit that restores an earlier generation and its matching code from git history.

#### Scenario: Active generation loads
- **WHEN** `assets/maps/active.json` names a valid preparation version 5 generation
- **THEN** the app loads that generation, and no other generation is read

#### Scenario: Active generation is broken
- **WHEN** the active generation's manifest cannot be loaded
- **THEN** the map area shows the load error, and the app reads no other generation

#### Scenario: Older preparation version
- **WHEN** a manifest declares preparation version 4
- **THEN** the app refuses it with an error naming preparation version 4, and candidate validation refuses it as an unsupported preparation version

### Requirement: The app loads only packs that carry labels
The app and the validator SHALL require a `labels` key on every map of a pack and SHALL validate every label before the map is used: non-empty text, finite position, rotation and size, a positive size, and floors that exist on that map. A map without the key, or with an invalid label, SHALL make the pack fail to load with a message naming the map and the problem.

#### Scenario: Current pack
- **WHEN** the app loads the active generation built by this change
- **THEN** every map loads with its labels

#### Scenario: Map without a labels key
- **WHEN** a version 5 manifest has a map entry without a `labels` key
- **THEN** validation and app loading both fail naming the map

#### Scenario: Label names an unknown floor
- **WHEN** a pack label lists a floor that its map does not have
- **THEN** the pack fails to load, naming the map and the floor

## ADDED Requirements

### Requirement: Prepared floor extents come from frozen interactive layers
The builder SHALL read each supported map's frozen interactive layer extents (`evidence/metadata/maps.json`), not root height ranges. Every layer with extents SHALL link to exactly one floor by a nonempty `svgLayer` and floor `id`, otherwise by a nonempty `tilePath` and `sourceTileUrl`. Each floor SHALL carry its extents, or an empty list. The builder SHALL normalize rectangle corners on both game axes and name the map and layer when linking fails.

#### Scenario: Every shipped multi-floor map carries extents
- **WHEN** the bundled generation is prepared from its frozen data
- **THEN** every map with multiple floors has at least one extent; Reserve includes bounded Bunkers extents and Streets has height-only extents

#### Scenario: Unlinked or ambiguous extent layer
- **WHEN** a layer with extents matches zero floors or more than one floor
- **THEN** the build fails naming the map and layer and no generation is promoted

#### Scenario: Upstream corners are reversed
- **WHEN** a source rectangle's first corner is greater than its second on either axis
- **THEN** the prepared rectangle stores the minimum and maximum on that axis and preserves the covered game coordinates

### Requirement: Malformed source floor extents fail preparation
Omitted or empty source `bounds` SHALL mean height-only. Present non-list bounds, malformed or degenerate rectangles, and nonfinite or nonpositive height spans SHALL fail preparation with the map and layer named.

#### Scenario: Malformed source extent
- **WHEN** an extent-bearing layer has a malformed height range or a `bounds` value that is present but null or invalid
- **THEN** preparation rejects that source naming the map and layer, without promoting a generation

### Requirement: Validation re-derives floor extents from candidate evidence
The validator SHALL derive the expected floor extents from the candidate's own frozen interactive metadata and reject a difference. Place-label floor assignment SHALL remain independent.

#### Scenario: Candidate extents differ from evidence
- **WHEN** a candidate's floor extents differ from those derived from its own frozen interactive source
- **THEN** validation fails naming the map and nothing is promoted

### Requirement: Pack loading rejects malformed floor extents
Each extent SHALL have finite height endpoints with a finite positive span and a `bounds` list containing zero or more rectangles with finite coordinates and finite positive spans on both axes. The app and validator SHALL reject missing `extents` or `bounds` lists and malformed extents, naming the map and floor. Only an empty bounds list means height-only in the prepared representation.

#### Scenario: Invalid extents do not load
- **WHEN** a floor has no `extents` list, an extent has no `bounds` list, or a height range or rectangle is malformed or degenerate
- **THEN** pack loading and candidate validation reject the pack and identify the map and floor

### Requirement: Offline rebuild migrates legacy floor calibration
Only rebuilding the verified v4 active generation SHALL translate legacy floor calibration to v5. The migration SHALL remove direct floor `heightBand` keys, preserve marker bands and ownership evidence and all non-calibration source bytes, and rebind the calibration source and output hashes and `sourceGeneration`. Candidate validation SHALL refuse legacy direct floor keys in v5 calibration or floor records without weakening reviewed artwork admission.

#### Scenario: Offline rebuild upgrades the prior generation
- **WHEN** the offline rebuild uses a verified version 4 incumbent
- **THEN** it writes valid v5 evidence with only legacy floor bands removed from calibration, retains nested marker evidence and all other source bytes, passes exact default artwork calibration admission, and the v5 generation reproduces byte-identically

#### Scenario: A v5 candidate retains a legacy floor band
- **WHEN** a candidate's v5 floor record or calibration holds a legacy direct `heightBand`, even with internally consistent hashes
- **THEN** validation rejects it naming the affected map and floor, without changing the active generation
