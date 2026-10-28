# Spec Delta

## ADDED Requirements

### Requirement: Bundled map marker icons are project-authored and recorded
The integrity check SHALL validate the repository's release map marker set with the set check, including provenance and hashes. It SHALL then confirm that the bundle's map marker directory holds the same manifest bytes and exactly one compiled file per manifest icon, each equal to compiling that icon's checked SVG, and no other file or folder. Any failure SHALL fail this step and name the file.

#### Scenario: Bundled icons match the recorded set
- **WHEN** the release set passes the set check and the bundle holds its manifest and the 19 compiled icons, each equal to compiling its SVG
- **THEN** the map marker step passes and the report lists it with no failures

#### Scenario: Unlisted icon file in the bundle
- **WHEN** the bundle's map marker directory also holds `compiled/skull_alt.vec`, or holds an `.svg` or `.png` file
- **THEN** the map marker step fails and names that file as unexpected

#### Scenario: Altered bundled icon
- **WHEN** a bundled compiled icon differs from compiling its SVG, or the bundled manifest differs from the repository's
- **THEN** the map marker step fails and names the file

#### Scenario: Release set fails its own check
- **WHEN** an icon's recorded SHA-256 is stale or its provenance is incomplete
- **THEN** the map marker step fails and reports the set check's failures, and the bundle check exits non-zero

#### Scenario: Icons missing from the bundle
- **WHEN** the bundle has no map marker directory, or lacks one manifest icon's compiled file
- **THEN** the map marker step fails and names the missing path
