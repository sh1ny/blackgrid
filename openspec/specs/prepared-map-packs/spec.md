# prepared-map-packs Specification

## Purpose
Defines how Blackgrid's offline-prepared map packs are built, proven and accepted. Each pack records the toolchain that built it and binds every compiled vector to its source by reproduction, not by pinned versions. The committed pack can be checked and rebuilt with one command whenever the preparation libraries change, and the app accepts any pack whose vector format it can decode.

## Requirements

### Requirement: A pack records the toolchain that built it

A pack build SHALL record in its manifest the resolved versions of `xml`, `image`, `vector_graphics_compiler`, `vector_graphics` and `vector_graphics_codec`, as resolved for the project when the build runs. A recorded version SHALL NOT be written from a fixed value in the tool. No validation or load SHALL require a recorded version to equal any particular value.

#### Scenario: Build records the installed versions
- **WHEN** a pack is built while the project resolves `vector_graphics_compiler` 1.3.4 and `image` 4.12.0
- **THEN** the manifest's toolchain record lists `vector_graphics_compiler` 1.3.4 and `image` 4.12.0, plus the resolved versions of the other three packages

#### Scenario: A package is not resolved
- **WHEN** a pack build starts and the project's resolved packages do not include `vector_graphics_codec`
- **THEN** the build fails before writing a candidate, with an error that names `vector_graphics_codec`

#### Scenario: An older recorded version still validates
- **WHEN** a pack whose `toolchain` record lists `vector_graphics_compiler` 1.3.0 and which records vector format 1 is validated with compiler 1.3.4 installed, and every vector recompiles to the committed bytes
- **THEN** validation passes

#### Scenario: Separate compile step records the compiling toolchain
- **WHEN** a candidate is normalized while the project resolves compiler 1.3.0, the project is then resolved to compiler 1.3.4, and the separate compile step runs
- **THEN** the compiled candidate's `toolchain` record lists compiler 1.3.4

### Requirement: Compiled vectors are deterministic

A pack build SHALL compile each vector component twice from the same compiler input. It SHALL fail if the two outputs differ in any byte, naming the component. A failed build SHALL leave no promotable candidate.

#### Scenario: Stable compiler
- **WHEN** a build compiles a component and both compilations give the same bytes
- **THEN** that payload is written and the build continues

#### Scenario: Unstable compiler output
- **WHEN** the two compilations of `artwork/customs/Ground_Level.vec` differ
- **THEN** the build fails with an error naming `artwork/customs/Ground_Level.vec`, and the candidate has no manifest, so it cannot be validated or promoted

### Requirement: Every compiled vector is bound to its source by recompilation

Validation SHALL recompile each vector component's compiler input, which is derived from the source SVG the pack carries as evidence, with the installed compiler. It SHALL reject the pack unless the committed payload is byte-identical to that output. No hash table of expected payloads SHALL be kept in the tool.

#### Scenario: Unmodified pack
- **WHEN** a pack built with the installed compiler is validated
- **THEN** validation passes

#### Scenario: Substituted payload
- **WHEN** another component's valid `.vec` is copied over `artwork/interchange/Ground_Level.vec` and the manifest's output hashes are updated to match
- **THEN** validation fails with an error naming `artwork/interchange/Ground_Level.vec`

### Requirement: A pack records and is checked against its vector format

Whichever step compiles the vectors SHALL record in the manifest the vector codec format number written in the header of the compiled payloads. Validation of a compiled pack SHALL reject a missing record, and any payload whose header does not carry the vector magic number and the recorded format. It SHALL check headers before comparing payload bytes. An uncompiled candidate carries no format record.

#### Scenario: Consistent format
- **WHEN** every compiled payload's header carries format 1 and the manifest records format 1
- **THEN** validation passes this check

#### Scenario: Mismatched payload header
- **WHEN** the manifest records format 1, one payload's header carries format 2, and the manifest's output hash for that payload is updated to match
- **THEN** validation fails with an error naming that payload and both formats

#### Scenario: Missing format record
- **WHEN** a compiled pack's manifest has no vector format record
- **THEN** validation fails with an error saying the vector format is not recorded

#### Scenario: Uncompiled candidate
- **WHEN** a normalized, uncompiled candidate with no format record is validated as uncompiled
- **THEN** validation passes, and promoting it fails because its vectors are not compiled

### Requirement: The app accepts packs in the vector format it decodes

The app SHALL load a pack whose manifest says its vectors are compiled and records the vector format that the app's bundled vector runtime decodes, whatever toolchain versions the manifest records. It SHALL refuse any other pack with an error that names the recorded format and the supported format. The map area SHALL show that error as a load failure.

#### Scenario: Supported format with other recorded versions
- **WHEN** the active manifest records format 1, the app decodes format 1, and the toolchain record lists compiler 9.9.9
- **THEN** the pack loads

#### Scenario: Unsupported format
- **WHEN** the active manifest records format 2 and the app decodes format 1
- **THEN** loading fails with a message naming format 2 and format 1, and the map area shows the load failure

#### Scenario: No format record
- **WHEN** the active manifest has no vector format record
- **THEN** loading fails with a message saying the vector format is not recorded

### Requirement: The app's supported vector format matches its vector runtime

The project SHALL keep the app's supported vector format equal to the format that the resolved `vector_graphics_codec` writes and decodes. A dependency update that changes the codec's format SHALL fail the fast test suite until the supported format and the pack are updated together.

#### Scenario: Codec unchanged
- **WHEN** the fast test suite encodes a small SVG with the resolved compiler and reads the header format
- **THEN** it equals the app's supported format, and the resolved runtime decodes the payload without error

#### Scenario: Codec format changes
- **WHEN** a dependency update resolves a codec that writes format 2 while the app supports format 1
- **THEN** the fast test suite fails with a message naming both formats and `mise run maps:rebuild`

### Requirement: The committed pack is checked for reproducibility

A check SHALL first verify that the active generation's id is the hash of its manifest and that its files are exactly the manifest's outputs. It SHALL then rebuild the generation offline from its own files with the installed toolchain and compare, ignoring only the toolchain record. It SHALL pass only when everything else is byte-identical. It SHALL run in CI and SHALL NOT modify the repository.

#### Scenario: Toolchain update with identical output
- **WHEN** the compiler moves to a new version that compiles every component to the committed bytes, and the check runs
- **THEN** the check passes and prints `Map pack <generation id> reproduced byte-identically with` followed by the five resolved package versions it used, and the repository is unchanged

#### Scenario: Toolchain update that changes output
- **WHEN** a new compiler version changes the bytes of `artwork/woods/Ground_Level.vec` and the check runs
- **THEN** the check fails, prints the per-map change summary as `woods Ground_Level: 1 changed file(s)`, lists `artwork/woods/Ground_Level.vec`, names `mise run maps:rebuild`, and leaves the repository and `assets/maps/active.json` unchanged

#### Scenario: A needed input is not carried
- **WHEN** the rebuild needs a source file that the committed generation does not carry
- **THEN** the check fails with an error naming that source path, without network access

#### Scenario: Committed evidence was edited
- **WHEN** a committed evidence file no longer matches the hash in the generation's source index
- **THEN** the check fails with an error naming that file

#### Scenario: Committed output was edited
- **WHEN** `artwork/customs/Ground_Level.svg` in the active generation is edited in place, or an extra file is added to the generation's folder
- **THEN** the check fails before rebuilding, with an error naming that file

#### Scenario: Manifest no longer matches its generation id
- **WHEN** the active generation's `manifest.json` is rewritten in place, so its hash differs from the generation id in `assets/maps/active.json`
- **THEN** the check fails before rebuilding, with an error naming the generation id

### Requirement: One command rebuilds and promotes the committed pack

A rebuild command SHALL refuse interrupted-promotion leftovers, verify the committed generation and asset markers, and rebuild offline. Only a validated result SHALL be promoted, after which it SHALL update the asset declarations and delete every other generation. It SHALL report changed files and manifest values per map and floor, and SHALL require the owner's check when anything but the toolchain record changed.

#### Scenario: Only provenance changes
- **WHEN** the rebuilt manifest is identical to the active generation's apart from the toolchain record
- **THEN** a new generation is promoted, `assets/maps/active.json` names it, the map asset declarations list its directories, the previous generation folder is deleted, and the report says nothing but provenance changed and does not ask for the owner's check

#### Scenario: Manifest values change without a file change
- **WHEN** the rebuild changes the display crop of `thelab` and no output file
- **THEN** the new generation is promoted, the report prints `thelab: manifest values changed`, and it says the owner must check the maps listed in the app before merge

#### Scenario: Artwork bytes change
- **WHEN** the rebuild changes `artwork/woods/Ground_Level.vec` and two tiles of `thelab` `First_Level`
- **THEN** the new generation is promoted, and the report prints `woods Ground_Level: 1 changed file(s)` and `thelab First_Level: 2 changed file(s)`, lists those paths, and says the owner must check those maps in the app before merge

#### Scenario: Validation fails
- **WHEN** the rebuilt candidate fails validation
- **THEN** nothing is promoted or deleted, the active generation and `assets/maps/active.json` and the map asset declarations are unchanged, the command exits non-zero with the validation error, and the candidate folder is kept and named for inspection

#### Scenario: Asset declaration markers missing
- **WHEN** `pubspec.yaml` lacks the begin or end marker of the generated map asset block, or has either twice
- **THEN** the command fails before rebuilding, with an error naming the marker, and nothing under `assets/maps/` changes

#### Scenario: Interrupted earlier promotion
- **WHEN** `assets/maps/active.next.json` or a `versions/.<id>.staging` folder for any id is left from an interrupted promotion
- **THEN** the command fails before rebuilding, names the leftover path, and nothing under `assets/maps/` changes, the leftover included

### Requirement: Only the active generation is ever used

The app SHALL load only the generation that `assets/maps/active.json` names. It SHALL NOT fall back to any other generation. A pack that fails to load SHALL show its error in the map area. Packs SHALL use preparation version 3, with the complete supported map set, and the app and the validator SHALL refuse any other preparation version. A rollback is a commit that restores an earlier generation from git history.

#### Scenario: Active generation loads
- **WHEN** `assets/maps/active.json` names a valid preparation version 3 generation
- **THEN** the app loads that generation, and no other generation is read

#### Scenario: Active generation is broken
- **WHEN** the active generation's manifest cannot be loaded
- **THEN** the map area shows the load error, and the app reads no other generation

#### Scenario: Older preparation version
- **WHEN** a manifest declares preparation version 2
- **THEN** the app refuses it with an error naming preparation version 2, and validation refuses it as an unsupported preparation version

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

### Requirement: Fresh artwork is staged independently of publication

An explicit refresh operation SHALL acquire fresh artwork, required interactive source metadata and terms for the supported inventory, construct a frozen candidate, validate it and report changes by map and floor. It SHALL retain byte-for-byte the verified baseline's six regular-mode marker, task and trader sources and their English dictionaries, and retain its calibration by default. It SHALL leave the active generation, pointer and asset declarations unchanged.

#### Scenario: Changed artwork stages without publication
- **WHEN** admitted artwork differs and the complete candidate validates
- **THEN** the operation stages the candidate, reports changed maps, floors, files and manifest values, and leaves active assets, pointer and declarations unchanged

#### Scenario: No artwork change or evidence-only change
- **WHEN** all checks pass and the candidate has no changes or only source evidence changes
- **THEN** staging succeeds and the report states the actual differences without inventing a visual change or requiring an image gate

#### Scenario: Baseline inputs and reviewed calibration
- **WHEN** staging uses a verified baseline
- **THEN** it retains all six exact metadata snapshots and baseline calibration; an explicit selection of reviewed updated calibration instead freezes and reconciles that configuration before a candidate can validate

#### Scenario: Fetch or candidate failure
- **WHEN** a required fetch, source integrity check, build or validation fails
- **THEN** the operation identifies the failing source or check, produces no validated candidate for publication, and leaves the active generation, pointer and declarations unchanged

### Requirement: Fresh sources and identities require reviewed admission

Fresh sources SHALL follow reviewed admission: locked primary sources and required terms need identity, URL, revision where available, expected hash and provenance; raster tiles need reviewed calibration, exact URLs and frozen hash integrity, not prior byte approval. Supported identities SHALL be unique and complete. New unsupported identities SHALL receive integration guidance, never become selectable; existing unsupported entries SHALL NOT alone block staging.

#### Scenario: Changed locked source
- **WHEN** a locked source's observed identity or bytes differ from reviewed configuration
- **THEN** staging identifies the source and approved and observed hashes where available and refuses admission until the exact identity, revision where available, URL and hash are updated through reviewed source configuration

#### Scenario: Reviewed source matches
- **WHEN** a locked primary source or required terms document matches reviewed identity, revision where available, URL and expected hash, or raster tiles match reviewed calibration and exact configured URLs with verified acquired hashes
- **THEN** the candidate may use those bytes with recorded provenance; raster hashes prove frozen integrity without claiming pre-reviewed tile bytes, and URL drift or frozen-byte corruption is rejected

#### Scenario: Supported identity is invalid or a new unsupported identity appears
- **WHEN** a required supported identity is missing, duplicate, ambiguous or malformed, or discovery identifies an unsupported map absent from baseline metadata
- **THEN** the operation names the identity and problem; invalid supported identities block staging, while a newly unsupported identity is diagnosed as requiring separately authored integration and is not added to the candidate

### Requirement: Frozen evidence and calibration remain valid

The candidate SHALL carry verified build-read inputs, identities and hashes for offline reproduction; unread historical indexed inputs MAY remain absent. Existing source, geometry, floor, frame, raster dependency and reviewed ownership checks SHALL remain effective. Discrepancies SHALL name required review, not silently recalibrate, reassign or discard ownership. Same-source agreement SHALL NOT count as independent placement proof.

#### Scenario: Reproduction from frozen candidate
- **WHEN** a valid candidate is built and its temporary acquired inputs are removed
- **THEN** its carried build-read closure can reproduce it offline for the existing canonical supported inventory, even if an unread historical indexed source was not carried

#### Scenario: Evidence is missing or corrupted
- **WHEN** a needed source, evidence or candidate output is missing or does not match its recorded hash
- **THEN** validation names the affected input and refuses publication

#### Scenario: Calibration or reviewed ownership no longer matches
- **WHEN** source geometry, frame, floor or dependency conflicts with reviewed calibration, or a reviewed marker identity, volume or assignment changes or disappears
- **THEN** the operation identifies the affected map and property and blocks the invalid candidate until the applicable authored configuration is reviewed and updated

### Requirement: Explicit publication uses the staged candidate

A separate explicit publication operation SHALL verify the current active baseline and the named staged candidate, rehash and validate its closure before active writes, print the existing baseline-to-candidate report, and publish that same candidate through the existing promotion, asset-declaration, pruning and recovery behavior. It SHALL NOT rebuild after staging or claim that a person reviewed the candidate. An operator SHALL serialize all writers to a pack root.

#### Scenario: Candidate is explicitly published
- **WHEN** the operator invokes publication with a valid staged candidate and current verified baseline
- **THEN** the report compares those generations and the exact candidate is promoted, asset declarations are updated and superseded generations are pruned

#### Scenario: Corrupt candidate or invalid baseline
- **WHEN** the staged candidate or its evidence is altered, or the current baseline fails verification
- **THEN** publication fails before active writes, identifies the failure and leaves pointer, active generation and declarations unchanged

#### Scenario: Publication is interrupted
- **WHEN** the existing transaction fails during promotion, asset replacement or pruning
- **THEN** it reports the actual completed phase and recovery state without claiming success

### Requirement: Existing offline and metadata-only workflows remain independent

Offline check and rebuild and metadata-only renewal SHALL use the verified active generation's own calibration, source lock and notices, not pending reviewed configuration for a different artwork candidate. They SHALL retain existing source-index, reproducibility, six-source replacement, preservation and ownership checks.

#### Scenario: Pending source and calibration changes
- **WHEN** reviewed source locks, notices or calibration differ for a pending artwork candidate while the old generation remains active
- **THEN** offline check and rebuild use the old verified generation without network acquisition, and metadata-only renewal retains its baseline context and existing six-source preservation gates

#### Scenario: Metadata-only preservation fails
- **WHEN** metadata-only renewal changes preserved artwork, calibration, notices, non-six source records or reviewed ownership
- **THEN** its existing validation rejects the candidate and active assets, pointer and declarations remain unchanged
