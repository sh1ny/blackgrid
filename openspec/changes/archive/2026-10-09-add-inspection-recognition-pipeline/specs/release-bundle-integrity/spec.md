# Spec Delta

## MODIFIED Requirements

### Requirement: Bundle inventory is exact
The integrity check SHALL compare the bundle's native libraries and models against the expected inventory. The inventory is: the vision files, the panel OCR library, the capture library and its hash binding, the Flutter engine, the native-asset libraries, and the app-local Visual C++ runtime libraries. The vision files SHALL include the inspection marker template and its metadata. The check SHALL fail on any missing expected file and on any unexpected `.dll` or `.traineddata`.

#### Scenario: Complete bundle passes inventory
- **WHEN** the check runs on a Release bundle produced by this build
- **THEN** the inventory step passes and the report lists every expected file with its SHA-256

#### Scenario: Unexpected DLL
- **WHEN** an extra `.dll` is present in the bundle directory
- **THEN** the check fails, naming that file as unexpected

#### Scenario: Missing expected file
- **WHEN** the OCR model has been removed from the bundle
- **THEN** the check fails, naming the model as missing

#### Scenario: Capture library missing
- **WHEN** `blackgrid_capture.dll` or its `.sha256` binding has been removed from the bundle
- **THEN** the check fails, naming the removed file as missing

#### Scenario: Marker template missing
- **WHEN** the inspection marker template or its metadata has been removed from the bundle
- **THEN** the check fails, naming the removed file as missing

## ADDED Requirements

### Requirement: Bundled game artwork is covered by notices
For each bundled file derived from game artwork, the check SHALL confirm that `THIRD_PARTY_NOTICES.md` has an entry naming the file, its SHA-256, the SHA-256 of the user-supplied source screenshot, and its recipe, and stating that it is game UI artwork captured by the user and not covered by Blackgrid's licence.

#### Scenario: Marker notice complete
- **WHEN** the notices entry for the marker template names its file, its SHA-256 and the source screenshot's SHA-256
- **THEN** the notices step passes for the template

#### Scenario: Marker notice stale
- **WHEN** the marker template is regenerated and the notices entry still names the old SHA-256
- **THEN** the check fails, naming the marker template
