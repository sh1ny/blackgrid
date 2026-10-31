# release-bundle-integrity Specification

## Purpose

An offline check that a built Windows Release bundle contains every native library and model it needs. Each file must be bound to its expected bytes, depend on nothing outside the bundle and Windows, and be covered by third-party notices.

## Requirements

### Requirement: Third-party inputs are pinned before they enter a build
Every third-party native input (OpenCV source archive, OCR engine library, its image library, OCR model) SHALL be recorded in a committed lock file with source URL, version, byte size, SHA-256 and license. The build SHALL refuse any input whose bytes do not match that record.

#### Scenario: Verified input accepted
- **WHEN** a fetched input matches its lock record's size and SHA-256
- **THEN** the input is placed in the build cache and the build proceeds

#### Scenario: Altered input refused
- **WHEN** a fetched or cached input's SHA-256 differs from its lock record
- **THEN** the fetch or build fails with an error naming the input and both hashes, and the input is not installed into the bundle

#### Scenario: Input missing from the cache
- **WHEN** the build starts and a locked input has not been fetched
- **THEN** the build fails with an error naming the input and the fetch command to run

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

### Requirement: Each runtime-verified file matches its binding and pin
For each file the app verifies at runtime (vision files, panel OCR library and capture library), the check SHALL confirm that the file matches its build binding. For each third-party file, it SHALL also confirm that the file's SHA-256 equals the lock file's pinned value. The check SHALL record the SHA-256 of build-bound files that are not verified at runtime (Flutter engine, native-asset libraries, Visual C++ runtime) in its report.

#### Scenario: Bindings and pins agree
- **WHEN** every runtime-verified file matches its binding, and every third-party file matches its pin
- **THEN** the hash step passes

#### Scenario: Binding disagrees with file
- **WHEN** a vision file's binding does not match the file's bytes
- **THEN** the check fails, naming the file and both hashes

#### Scenario: Third-party file differs from pin
- **WHEN** the bundled OCR engine library has a valid binding, but its SHA-256 differs from the lock file
- **THEN** the check fails, naming the file as diverging from its pinned source

#### Scenario: Capture binding disagrees with file
- **WHEN** `blackgrid_capture.dll.sha256` does not match the bytes of `blackgrid_capture.dll`
- **THEN** the check fails, naming the capture library and both hashes

### Requirement: Bundle needs no system installation
For the executable and every DLL in the bundle, the check SHALL read the import table and confirm that each imported DLL is either present in the bundle or is a Windows system library on the check's allow-list. Anything else is a failure. The allow-list SHALL be committed and SHALL NOT contain any Visual C++ redistributable or third-party library.

#### Scenario: All imports resolved
- **WHEN** every import of every bundled DLL is in the bundle or on the system allow-list
- **THEN** the import step passes

#### Scenario: Import needs a system install
- **WHEN** a bundled DLL imports a library that is neither in the bundle nor on the allow-list (for example a Visual C++ runtime DLL that is not shipped)
- **THEN** the check fails, naming the DLL and the unresolved import

#### Scenario: Unreadable PE file
- **WHEN** a bundled `.dll` is not a valid x64 PE image
- **THEN** the check fails, naming the file as unreadable

### Requirement: App-local Visual C++ runtime meets a committed minimum version
For each app-local Visual C++ runtime DLL in the bundle, the check SHALL read its PE file version and SHALL fail if it is older than the committed minimum version for that DLL. The check SHALL record each DLL's version in its report.

#### Scenario: Runtime at or above minimum
- **WHEN** every shipped Visual C++ runtime DLL's file version is at or above its committed minimum
- **THEN** the runtime-version step passes and the report lists each DLL's version

#### Scenario: Older toolchain runtime shipped
- **WHEN** a shipped `vcruntime140.dll` has a file version below the committed minimum
- **THEN** the check fails, naming the DLL with its actual and minimum versions

#### Scenario: Version resource missing
- **WHEN** a shipped Visual C++ runtime DLL has no readable version resource
- **THEN** the check fails, naming the DLL as having an unreadable version

### Requirement: Third-party native files are covered by notices
For each third-party file in the lock file, the check SHALL confirm that `THIRD_PARTY_NOTICES.md` contains an entry naming its component, version, source URL and SHA-256. It SHALL also confirm that a Visual C++ runtime entry exists that names the redistributable terms.

#### Scenario: Notices complete
- **WHEN** every locked component has a notices entry with matching version and SHA-256
- **THEN** the notices step passes

#### Scenario: Notice missing or stale
- **WHEN** the lock file pins a SHA-256 that does not appear in that component's notices entry
- **THEN** the check fails, naming the component

### Requirement: Check is offline and reports results
The integrity check SHALL run without network access, the app or the game. It SHALL take a bundle directory as input and SHALL produce a machine-readable report with one result per step, exiting non-zero if any step failed.

#### Scenario: Passing run
- **WHEN** the check runs on an intact Release bundle with network disabled
- **THEN** it exits 0, and its report shows every step passed

#### Scenario: Bundle directory absent
- **WHEN** the given bundle directory does not exist
- **THEN** the check exits non-zero with an error naming the path, and writes no report claiming a pass

### Requirement: Bundled game artwork is covered by notices
For each bundled file derived from game artwork, the check SHALL confirm that `THIRD_PARTY_NOTICES.md` has an entry naming the file, its SHA-256, the SHA-256 of the user-supplied source screenshot, and its recipe, and stating that it is game UI artwork captured by the user and not covered by Blackgrid's licence.

#### Scenario: Marker notice complete
- **WHEN** the notices entry for the marker template names its file, its SHA-256 and the source screenshot's SHA-256
- **THEN** the notices step passes for the template

#### Scenario: Marker notice stale
- **WHEN** the marker template is regenerated and the notices entry still names the old SHA-256
- **THEN** the check fails, naming the marker template

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

### Requirement: The executable carries the committed application icon
The integrity check SHALL compare the icon group of the bundle's `blackgrid.exe` with `windows/runner/resources/app_icon.ico`, matching images by (width, height, bit depth), a stored 0 read as 256. Each size SHALL appear once per side, whatever its bit depth, and each embedded image SHALL equal the `.ico` image with the same key, byte for byte. A size repeated on one side, a key on one side only, unequal bytes or no readable icon group SHALL fail the step, naming the size, key or reason.

#### Scenario: Icon matches
- **WHEN** the bundle was built from a checkout whose `.ico` holds the ten required sizes
- **THEN** the `app-icon` step passes, listing the ten sizes

#### Scenario: Stale executable icon
- **WHEN** the executable still embeds the Flutter default icon: ten images, 256 px plus 16, 32 and 48 px at 4, 8 and 32 bpp each
- **THEN** the `app-icon` step fails, naming the duplicate sizes 16, 32 and 48 and the sizes missing from the executable (20, 24, 40, 64, 96, 128), and the check exits non-zero

#### Scenario: No icon resource
- **WHEN** the executable has no icon group resource, or its resource directory is malformed
- **THEN** the `app-icon` step fails with an unreadable result, and the check neither throws nor reads out of range

### Requirement: The bundle carries the committed in-app logo
The integrity check's `app-icon` step SHALL also compare the bundle's `data/flutter_assets/assets/app_icon/app_icon.vec` with the committed `assets/app_icon/app_icon.vec`, byte for byte. A missing bundled file, an unreadable committed file or unequal bytes SHALL fail the step, naming the file and the reason. The comparison reads both files only; it neither compiles nor renders them.

#### Scenario: Logo matches
- **WHEN** the bundle was built from a checkout whose committed `.vec` is in step
- **THEN** the `app-icon` step passes and its details name `app_icon.vec` beside the ten icon sizes

#### Scenario: Logo missing from the bundle
- **WHEN** the bundle has no `data/flutter_assets/assets/app_icon/app_icon.vec`, for example because the asset entry was dropped from `pubspec.yaml`
- **THEN** the `app-icon` step fails, naming the bundled path as missing, and the check exits non-zero

#### Scenario: Stale bundled logo
- **WHEN** the bundled `.vec` differs from the committed one, for example because the bundle was built before a rebuild of the icon
- **THEN** the `app-icon` step fails, saying `app_icon.vec` differs between the bundle and the checkout, and the check exits non-zero
