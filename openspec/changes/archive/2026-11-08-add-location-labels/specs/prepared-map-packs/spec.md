# Spec Delta

## ADDED Requirements

### Requirement: A pack carries each map's place labels
Every map in a prepared pack SHALL carry a list of place labels, empty when its interactive metadata has none. Each label SHALL record its text, its source position projected like a marker position, its rotation in degrees, its relative size and the Blackgrid floors it belongs to. Labels SHALL keep their source order. The build SHALL read them only from the frozen interactive metadata (`metadata/maps.json`).

#### Scenario: Map with labels
- **WHEN** the pack is built from the frozen sources
- **THEN** Interchange carries 77 place labels, Customs 24 and Labs 31, in source order, with 303 labels across the 10 maps that have them

#### Scenario: Map without labels
- **WHEN** a supported map's interactive metadata has no labels, as Terminal, Icebreaker and Labyrinth do
- **THEN** that map carries an empty label list

#### Scenario: Missing optional fields
- **WHEN** a source label has no rotation or no size
- **THEN** it carries rotation 0 and size 80

#### Scenario: Numeric text field
- **WHEN** a source label gives its rotation as a numeric string such as `"-9"`
- **THEN** it carries rotation −9

### Requirement: A label's floors come from its height band
The builder SHALL hold a reviewed table that gives floors of maps with banded labels a height band, each matching one height in the interactive metadata; a floor left out gets no banded labels. A banded label SHALL belong to every floor whose band overlaps its band (missing bottom or top: unbounded); an unbanded label SHALL belong to the base floor. A label overlapping no floor band SHALL fail the build naming the map and label.

#### Scenario: Upper-floor label
- **WHEN** Interchange's "IDEA" has band 25–33 and the 2nd Floor overlay has band 25–34
- **THEN** "IDEA" belongs to that overlay only

#### Scenario: Label spanning floors
- **WHEN** Factory's "Office Building" has bottom −1 and top 10000
- **THEN** it belongs to the base floor and both upper floors

#### Scenario: Unbanded label
- **WHEN** a Customs label has no bottom and no top
- **THEN** it belongs to Customs' base floor only

#### Scenario: Label outside every floor
- **WHEN** a label's band overlaps no floor band of its map
- **THEN** the build fails naming the map and label text, and nothing is promoted

#### Scenario: Band edge
- **WHEN** Interchange's base band is −1000 to 25, its 2nd Floor overlay band is 25 to 34, and a label's band is 25–33
- **THEN** the label belongs to the overlay only, because a floor band includes its bottom and excludes its top

#### Scenario: Banded label without floor bands
- **WHEN** a map's labels carry bands and the table gives none of its floors a band
- **THEN** the build fails naming the map and the first such label

#### Scenario: Table drifts from the metadata
- **WHEN** a band in the table differs from the frozen metadata's height for the layer it is reviewed against
- **THEN** the fast test suite fails naming the map, floor and both bands

### Requirement: Malformed labels fail the build
A source label SHALL have non-empty text and a finite two-number position; rotation, size, bottom and top SHALL be finite numbers or numeric strings when present, and size SHALL be positive. A malformed label SHALL fail the build naming the map and label index; it SHALL NOT be skipped.

#### Scenario: Bad position
- **WHEN** a label's position has one number or a non-numeric entry
- **THEN** the build fails naming the map and label index

#### Scenario: Empty text
- **WHEN** a label's text is empty or only whitespace
- **THEN** the build fails naming the map and label index

### Requirement: The app loads only packs that carry labels
The app and the validator SHALL require a `labels` key on every map of a pack and SHALL validate every label before the map is used: non-empty text, finite position, rotation and size, a positive size, and floors that exist on that map. A map without the key, or with an invalid label, SHALL make the pack fail to load with a message naming the map and the problem.

#### Scenario: Current pack
- **WHEN** the app loads the active generation built by this change
- **THEN** every map loads with its labels

#### Scenario: Map without a labels key
- **WHEN** a version 4 manifest has a map entry without a `labels` key
- **THEN** validation and app loading both fail naming the map

#### Scenario: Label names an unknown floor
- **WHEN** a pack label lists a floor that its map does not have
- **THEN** the pack fails to load, naming the map and the floor

### Requirement: Validation re-derives labels from the candidate's own metadata
Pack validation SHALL extract and assign each map's labels again from the candidate's own `evidence/metadata/maps.json` with the builder's floor band table and SHALL require them to equal the manifest's labels. A mismatch SHALL fail validation naming the map, and nothing SHALL be promoted or published.

#### Scenario: Labels match their evidence
- **WHEN** a freshly built candidate is validated
- **THEN** every map's labels equal those derived from its own frozen metadata, and validation passes

#### Scenario: Labels differ from their evidence
- **WHEN** a candidate's labels differ from those derived from its own frozen metadata
- **THEN** validation fails naming the map, and nothing is promoted

### Requirement: The third-party notices credit the place labels
`THIRD_PARTY_NOTICES.md` SHALL credit the place labels: their source repository and file (`the-hideout/tarkov-dev`, `src/data/maps.json`), its MIT licence and copyright line, the pack path of that licence text (`evidence/terms/tarkov-dev-software-LICENSE.txt`), that the frozen URL and hash are in the pack's `evidence/sources.json`, and that Blackgrid claims no ownership of the place names. The pack's `NOTICE.txt` SHALL stay unchanged.

#### Scenario: Credit present
- **WHEN** the fast test suite runs
- **THEN** it finds the place label entry in `THIRD_PARTY_NOTICES.md` with the repository, file, licence and licence path

#### Scenario: Licence text missing from the pack
- **WHEN** the active pack lacks `evidence/terms/tarkov-dev-software-LICENSE.txt`
- **THEN** the same test fails naming that path

## MODIFIED Requirements

### Requirement: Only the active generation is ever used

The app SHALL load only the generation that `assets/maps/active.json` names. It SHALL NOT fall back to any other generation. A pack that fails to load SHALL show its error in the map area. Packs SHALL use preparation version 4, with the complete supported map set, and the app and the validator SHALL refuse any other preparation version. A rollback is a commit that restores an earlier generation from git history.

#### Scenario: Active generation loads
- **WHEN** `assets/maps/active.json` names a valid preparation version 4 generation
- **THEN** the app loads that generation, and no other generation is read

#### Scenario: Active generation is broken
- **WHEN** the active generation's manifest cannot be loaded
- **THEN** the map area shows the load error, and the app reads no other generation

#### Scenario: Older preparation version
- **WHEN** a manifest declares preparation version 3
- **THEN** the app refuses it with an error naming preparation version 3, and validation refuses it as an unsupported preparation version

### Requirement: Metadata-only refresh preserves prepared artwork and calibration
A metadata-only refresh SHALL preserve the baseline's artwork bytes, notices, calibration, map geometry, artwork frames, display crops, floor inventory, place labels and rendering metadata. Historical marker floor overrides SHALL be applied only while their marker identity and placement assumptions match; otherwise the existing floor policy SHALL apply without blocking renewal or inventing a removed marker. A non-metadata preservation failure SHALL prevent promotion. Metadata changes SHALL retain the existing per-map report and owner-check requirement.

#### Scenario: Metadata changes without artwork changes
- **WHEN** refreshed marker data changes map records but every preserved artwork and calibration property matches the active baseline
- **THEN** the new generation carries those unchanged properties, the report names the changed maps, and the owner check remains required before merge

#### Scenario: Artwork or calibration drifts
- **WHEN** a candidate changes any preserved artwork byte, notice, frame, crop, geometry, floor inventory, place label or rendering metadata
- **THEN** metadata-only validation fails naming the changed property and the active generation, pointer and asset declarations remain unchanged

#### Scenario: Reviewed floor ownership no longer matches
- **WHEN** a refreshed source removes a reviewed floor-assigned marker or changes its identity or reviewed placement assumptions
- **THEN** renewal does not restore the marker or force the stale assignment, and uses the existing floor policy for any remaining marker without changing calibration or rejecting valid content
