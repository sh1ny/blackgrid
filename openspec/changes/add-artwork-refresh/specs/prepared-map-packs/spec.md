# Spec Delta

## ADDED Requirements

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

Fresh observations SHALL require admission by existing reviewed source configuration; downloading SHALL NOT approve them. Required supported identities SHALL be unique and complete. Newly unsupported identities relative to baseline discovery SHALL receive separate-integration guidance; pre-existing unsupported entries SHALL NOT alone block staging. Discovery SHALL NOT make unsupported maps selectable.

#### Scenario: Changed locked source
- **WHEN** a locked source's observed identity or bytes differ from reviewed configuration
- **THEN** staging identifies the source and approved and observed hashes where available and refuses admission until the exact identity, revision, URL and hash are updated through the existing reviewed source configuration

#### Scenario: Reviewed source matches
- **WHEN** the reviewed source identity, revision, URL and hash match acquired bytes and other checks pass
- **THEN** the candidate may use those bytes with their recorded provenance

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
