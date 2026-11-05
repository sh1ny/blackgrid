# Spec Delta

## ADDED Requirements

### Requirement: Refreshed marker metadata is a complete frozen source generation

A metadata refresh SHALL derive every supported map's markers from a fresh regular-mode REST map, task and trader snapshot with its English dictionaries. It SHALL carry the exact acquired bytes, source URLs and hashes in a new generation. Missing or ambiguous supported-map identities and malformed required records SHALL fail validation without changing the active generation. Existing marker categories and label rules SHALL remain in force.

#### Scenario: Refresh covers the supported inventory
- **WHEN** a refreshed snapshot contains all supported map identities and the required marker, task, trader and English dictionaries
- **THEN** the candidate contains the complete supported map set and its prepared marker inventory is derived from those recorded sources, including non-boss markers

#### Scenario: Source identity is missing or ambiguous
- **WHEN** a required supported map is absent or appears twice under the same source identity in the refreshed snapshot
- **THEN** validation fails naming that map, and the active generation is unchanged

#### Scenario: Required metadata is malformed
- **WHEN** a required source dictionary or a position-bearing record has an invalid structure
- **THEN** preparation or validation fails with the offending source identified rather than silently dropping that record, and the active generation is unchanged

#### Scenario: Acquired evidence is altered
- **WHEN** carried metadata bytes no longer match their recorded source hash
- **THEN** validation fails naming the source and the candidate cannot be promoted

#### Scenario: Renewal tolerates unused uncarried indexed sources
- **WHEN** a verified baseline generation indexes an unused source whose bytes it does not carry, and a metadata renewal replaces the six permitted metadata inputs
- **THEN** renewal can rebuild and validate from the generation-backed build-read closure without acquiring that unused source, while retaining the exact source index inventory and unchanged non-metadata records; a missing input needed by the build or replacement bytes changed after staging still fails validation and prevents promotion

### Requirement: Boss position coverage is preserved per source map

Each source boss location position SHALL produce exactly one boss marker in its supported source map, preserving mob identity, resolved name, location, coordinates and boss-wide spawn chance under the existing label rules. Validation SHALL reject missing, extra, misassigned or altered records. Multiplicity SHALL be preserved. Explicitly empty location or position lists SHALL produce no invented position markers.

#### Scenario: Boss records retain their source facts
- **WHEN** a frozen boss record has positions on a supported map and its boss-wide chance differs from its location chance
- **THEN** every position appears in that map with the source mob, resolved name, location and coordinates, and uses the boss-wide chance rather than the location chance

#### Scenario: Same-count corruption is rejected
- **WHEN** a candidate loses a boss position, adds one, moves one to another map, or changes its mob, name, location, coordinates or spawn chance, including changes that preserve the total marker count
- **THEN** validation fails identifying the affected map or record and the candidate cannot be promoted

#### Scenario: Repeated boss positions retain multiplicity
- **WHEN** source records repeat a mob and position, including records with different spawn chances
- **THEN** the prepared map retains every occurrence with its own associated facts instead of deduplicating them

#### Scenario: Source supplies no boss coordinates
- **WHEN** a boss has an explicitly empty location list or a location has an explicitly empty position list
- **THEN** no position marker is invented for it, validation accepts that empty coverage, and the refresh evidence identifies the empty source coverage rather than claiming it as a mapped location

### Requirement: Metadata-only refresh preserves prepared artwork and calibration

A metadata-only refresh SHALL preserve the baseline's artwork bytes, notices, calibration, map geometry, artwork frames, display crops, floor inventory and rendering metadata. Reviewed marker floor assignments SHALL remain attached to their unchanged reviewed marker volumes. A preservation failure SHALL prevent promotion. Metadata changes SHALL retain the existing per-map report and owner-check requirement.

#### Scenario: Metadata changes without artwork changes
- **WHEN** refreshed marker data changes map records but every preserved artwork and calibration property matches the active baseline
- **THEN** the new generation carries those unchanged properties, the report names the changed maps, and the owner check remains required before merge

#### Scenario: Artwork or calibration drifts
- **WHEN** a candidate changes any preserved artwork byte, notice, frame, crop, geometry, floor inventory or rendering metadata
- **THEN** metadata-only validation fails naming the changed property and the active generation, pointer and asset declarations remain unchanged

#### Scenario: Reviewed floor ownership no longer matches
- **WHEN** a refreshed source removes a reviewed floor-assigned marker, changes its reviewed volume or causes its floor assignment to be lost
- **THEN** metadata-only validation fails naming that marker instead of discarding the assignment or changing calibration silently
