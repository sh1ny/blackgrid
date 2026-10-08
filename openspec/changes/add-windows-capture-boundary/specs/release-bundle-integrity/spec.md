# Spec Delta

## MODIFIED Requirements

### Requirement: Bundle inventory is exact
The integrity check SHALL compare the bundle's native libraries and models against the expected inventory. The inventory is: the vision files, the panel OCR library, the capture library and its hash binding, the Flutter engine, the native-asset libraries, and the app-local Visual C++ runtime libraries. The check SHALL fail on any missing expected file and on any unexpected `.dll` or `.traineddata`.

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
