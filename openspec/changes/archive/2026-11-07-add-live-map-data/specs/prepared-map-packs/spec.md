# Spec Delta

## MODIFIED Requirements

### Requirement: Refreshed marker metadata is a complete frozen source generation
A metadata refresh SHALL derive supported artwork maps' markers from a fresh regular-mode REST map, task and trader snapshot with its English dictionaries. It SHALL carry the exact acquired bytes, source URLs and hashes in a new generation. Required parser roots, keys and needed record shapes SHALL be validated; malformed required records and ambiguous source identities SHALL fail without changing the active generation. A supported artwork map absent from a structurally valid source SHALL have an empty marker inventory; new unsupported source maps SHALL NOT become selectable or block metadata renewal. Existing marker categories and label rules SHALL remain in force. Historical content, counts, identities, placements and hashes SHALL NOT be admission gates for new source content.

#### Scenario: Refresh covers the supported inventory
- **WHEN** a refreshed snapshot contains supported map identities and the required marker, task, trader and English dictionaries
- **THEN** the candidate retains the complete supported artwork map set and its prepared marker inventory is derived from those recorded sources, including non-boss markers

#### Scenario: Source identity is missing or ambiguous
- **WHEN** a supported source map is absent or appears twice under the same source identity in the refreshed snapshot
- **THEN** absence yields an empty inventory for that prepared map, while ambiguity fails validation naming that identity and leaves the active generation unchanged

#### Scenario: Required metadata is malformed
- **WHEN** a required source dictionary or a position-bearing record has an invalid structure
- **THEN** preparation or validation fails with the offending source identified rather than silently dropping that record, and the active generation is unchanged

#### Scenario: Acquired evidence is altered
- **WHEN** carried metadata bytes no longer match their recorded source hash
- **THEN** validation fails naming the source and the candidate cannot be promoted

#### Scenario: Renewal tolerates unused uncarried indexed sources
- **WHEN** a verified baseline generation indexes an unused source whose bytes it does not carry, and a metadata renewal replaces the six permitted metadata inputs
- **THEN** renewal can rebuild and validate from the generation-backed build-read closure without acquiring that unused source, while retaining the exact source index inventory and unchanged non-metadata records; a missing input needed by the build or replacement bytes changed after staging still fails validation and prevents promotion

#### Scenario: Upstream content evolves
- **WHEN** valid new metadata removes quests or markers, adds markers, changes names, positions or boss chances, or supplies empty collections
- **THEN** renewal derives those facts from the new frozen sources without requiring equality with the baseline

#### Scenario: Optional references and translations disappear
- **WHEN** a structurally valid source has empty map or task collections or a dictionary no longer includes a previously referenced quest, trader, item or translation ID
- **THEN** renewal accepts that content without requiring historical referential completeness, derives available facts without invention, and applies existing unavailable-name or omission behavior

### Requirement: Boss position coverage is preserved per source map
Each source boss location position SHALL produce exactly one boss marker in its supported source map, preserving mob identity, resolved name, location, coordinates and boss-wide spawn chance under the existing label rules. Validation SHALL reject missing, extra, misassigned or altered records relative to the candidate's own frozen source, not relative to historical source content. Multiplicity SHALL be preserved. Explicitly empty location or position lists SHALL produce no invented position markers.

#### Scenario: Boss records retain their source facts
- **WHEN** a frozen boss record has positions on a supported map and its boss-wide chance differs from its location chance
- **THEN** every position appears in that map with the source mob, resolved name, location and coordinates, and uses the boss-wide chance rather than the location chance

#### Scenario: Same-count corruption is rejected
- **WHEN** a candidate loses a boss position, adds one, moves one to another map, or changes its mob, name, location, coordinates or spawn chance relative to its own frozen source, including changes that preserve the total marker count
- **THEN** validation fails identifying the affected map or record and the candidate cannot be promoted

#### Scenario: Repeated boss positions retain multiplicity
- **WHEN** source records repeat a mob and position, including records with different spawn chances
- **THEN** the prepared map retains every occurrence with its own associated facts instead of deduplicating them

#### Scenario: Source supplies no boss coordinates
- **WHEN** a boss has an explicitly empty location list or a location has an explicitly empty position list
- **THEN** no position marker is invented for it, validation accepts that empty coverage, and the refresh evidence identifies the empty source coverage rather than claiming it as a mapped location

### Requirement: Metadata-only refresh preserves prepared artwork and calibration
A metadata-only refresh SHALL preserve the baseline's artwork bytes, notices, calibration, map geometry, artwork frames, display crops, floor inventory and rendering metadata. Historical marker floor overrides SHALL be applied only while their marker identity and placement assumptions match; otherwise the existing floor policy SHALL apply without blocking renewal or inventing a removed marker. A non-metadata preservation failure SHALL prevent promotion. Metadata changes SHALL retain the existing per-map report and owner-check requirement.

#### Scenario: Metadata changes without artwork changes
- **WHEN** refreshed marker data changes map records but every preserved artwork and calibration property matches the active baseline
- **THEN** the new generation carries those unchanged properties, the report names the changed maps, and the owner check remains required before merge

#### Scenario: Artwork or calibration drifts
- **WHEN** a candidate changes any preserved artwork byte, notice, frame, crop, geometry, floor inventory or rendering metadata
- **THEN** metadata-only validation fails naming the changed property and the active generation, pointer and asset declarations remain unchanged

#### Scenario: Reviewed floor ownership no longer matches
- **WHEN** a refreshed source removes a reviewed floor-assigned marker or changes its identity or reviewed placement assumptions
- **THEN** renewal does not restore the marker or force the stale assignment, and uses the existing floor policy for any remaining marker without changing calibration or rejecting valid content

### Requirement: Fresh sources and identities require reviewed admission
Fresh artwork sources SHALL follow reviewed admission: locked primary sources and required terms need identity, URL, revision where available, expected hash and provenance; raster tiles need reviewed calibration, exact URLs and frozen hash integrity, not prior byte approval. Supported artwork source identities SHALL be unique and complete. New unsupported artwork identities SHALL receive integration guidance, never become selectable; existing unsupported entries SHALL NOT alone block staging. Marker metadata source-map absence or new unsupported metadata maps SHALL NOT be treated as missing or unreviewed artwork identities.

#### Scenario: Changed locked source
- **WHEN** a locked source's observed identity or bytes differ from reviewed configuration
- **THEN** staging identifies the source and approved and observed hashes where available and refuses admission until the exact identity, revision where available, URL and hash are updated through reviewed source configuration

#### Scenario: Reviewed source matches
- **WHEN** a locked primary source or required terms document matches reviewed identity, revision where available, URL and expected hash, or raster tiles match reviewed calibration and exact configured URLs with verified acquired hashes
- **THEN** the candidate may use those bytes with recorded provenance; raster hashes prove frozen integrity without claiming pre-reviewed tile bytes, and URL drift or frozen-byte corruption is rejected

#### Scenario: Supported identity is invalid or a new unsupported identity appears
- **WHEN** a required supported artwork identity is missing, duplicate, ambiguous or malformed, or artwork discovery identifies an unsupported map absent from baseline metadata
- **THEN** the operation names the identity and problem; invalid supported artwork identities block staging, while a newly unsupported artwork identity is diagnosed as requiring separately authored integration and is not added to the candidate

#### Scenario: Metadata changes do not block artwork staging
- **WHEN** retained structurally valid metadata omits a supported map or includes a new unsupported map
- **THEN** artwork staging still applies its independent artwork admission checks without requiring the metadata map inventory to match historical content

### Requirement: Frozen evidence and calibration remain valid
The candidate SHALL carry verified build-read inputs, identities and hashes for offline reproduction; unread historical indexed inputs MAY remain absent. Existing artwork source, geometry, floor, frame and raster dependency checks SHALL remain effective. Artwork discrepancies SHALL name required review, not silently recalibrate or discard artwork ownership. Marker overrides are conditional on matching identity and placement assumptions and do not impose historical content equality. Same-source agreement SHALL NOT count as independent placement proof.

#### Scenario: Reproduction from frozen candidate
- **WHEN** a valid candidate is built and its temporary acquired inputs are removed
- **THEN** its carried build-read closure can reproduce it offline for the existing canonical supported artwork inventory, even if an unread historical indexed source was not carried

#### Scenario: Evidence is missing or corrupted
- **WHEN** a needed source, evidence or candidate output is missing or does not match its recorded hash
- **THEN** validation names the affected input and refuses publication

#### Scenario: Calibration or reviewed ownership no longer matches
- **WHEN** source artwork geometry, frame, floor or dependency conflicts with reviewed calibration
- **THEN** the operation identifies the affected map and property and blocks the invalid candidate until the applicable authored configuration is reviewed and updated

#### Scenario: Marker ownership no longer matches
- **WHEN** a reviewed marker identity, placement or assignment assumption changes or disappears in valid source metadata
- **THEN** the stale marker override is omitted and neither frozen reproduction nor artwork staging rejects the candidate for that historical difference

### Requirement: Existing offline and metadata-only workflows remain independent
Offline check and rebuild and metadata-only renewal SHALL use the verified active generation's own calibration, source lock and notices, not pending reviewed configuration for a different artwork candidate. They SHALL retain source-index integrity, reproducibility, six-source replacement and non-metadata preservation checks, while conditional marker overrides do not freeze historical metadata content.

#### Scenario: Pending source and calibration changes
- **WHEN** reviewed source locks, notices or calibration differ for a pending artwork candidate while the old generation remains active
- **THEN** offline check and rebuild use the old verified generation without network acquisition, and metadata-only renewal retains its baseline context and six-source and non-metadata preservation gates

#### Scenario: Metadata-only preservation fails
- **WHEN** metadata-only renewal changes preserved artwork, calibration, notices or non-six source records
- **THEN** its existing validation rejects the candidate and active assets, pointer and declarations remain unchanged
