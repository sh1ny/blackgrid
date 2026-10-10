# vision-runtime Specification

## Purpose

Provides the app-local native item vision runtime (image primitives, OCR engine and model) that item recognition builds on, verified against its bindings and loaded only from the application bundle.

## Requirements

### Requirement: Runtime files are verified before any library is loaded
Before opening any vision library, the runtime SHALL confirm that every vision file (the vision primitives library, the OCR engine library, its image library and the OCR model) exists in the application directory and matches its SHA-256 binding. Any missing file or mismatch makes the runtime unavailable, and no vision library is opened.

#### Scenario: Intact bundle becomes ready
- **WHEN** every vision file is present in the application directory and matches its binding
- **THEN** runtime status is `ready` and the reported runtime identity lists each file with its SHA-256

#### Scenario: Tampered library is refused before load
- **WHEN** the OCR engine library's bytes differ from its binding
- **THEN** runtime status is `unavailable` with failure `hashMismatch` naming that file, and no vision library has been opened in the process

#### Scenario: Missing model is refused
- **WHEN** the OCR model file is absent from the bundle
- **THEN** runtime status is `unavailable` with failure `missingFile` naming the model

#### Scenario: Missing binding is refused
- **WHEN** a vision library is present but its binding is absent
- **THEN** runtime status is `unavailable` with failure `missingFile` naming the binding

### Requirement: Runtime loads only from the application bundle
The runtime SHALL load each vision library by absolute path inside the directory of the running executable, and SHALL read the OCR model only from the bundle's model directory. It MUST NOT resolve vision libraries or models from `PATH`, the working directory, `TESSDATA_PREFIX` or any machine-wide installation.

#### Scenario: Bundle path is used
- **WHEN** the runtime starts from a Release bundle
- **THEN** the reported loaded paths of all vision libraries and the model are inside the executable's directory

#### Scenario: System installation is ignored
- **WHEN** `TESSDATA_PREFIX` names a directory holding a different `eng.traineddata`, and the bundle's model is missing
- **THEN** runtime status is `unavailable` with failure `missingFile`, and the external model is not used

#### Scenario: Relative path override is rejected
- **WHEN** the runtime is constructed with a relative runtime directory
- **THEN** runtime status is `unavailable` with failure `invalidPath`, and no file is opened

### Requirement: Vision ABI version is checked
After a hash-verified open, the runtime SHALL check that the vision primitives library reports the ABI version this build expects, and SHALL check that the OCR engine reports the engine version pinned for the bundled engine library (Tesseract 5.0.0 inside the charlesw 5.2.0 package). On a mismatch it SHALL release every library it opened.

#### Scenario: Matching ABI
- **WHEN** the vision library reports the expected ABI and the OCR engine reports its pinned engine version
- **THEN** runtime status is `ready` and the identity includes both versions

#### Scenario: ABI mismatch
- **WHEN** the vision library reports a different ABI version
- **THEN** runtime status is `unavailable` with failure `abiMismatch`, stating the expected and actual versions

#### Scenario: Engine version differs from pin
- **WHEN** the OCR engine reports a version other than its pinned engine version
- **THEN** runtime status is `unavailable` with failure `abiMismatch` naming the OCR engine, and every opened library is closed

### Requirement: OCR engine initialises with the reference settings
The runtime SHALL initialise the OCR engine with the bundled English model, LSTM-only engine mode and raw-line page segmentation, with no character whitelist. If the engine cannot initialise, the runtime SHALL report failure `engineInitFailed` and release the engine.

#### Scenario: Engine initialises
- **WHEN** the runtime is ready
- **THEN** the OCR engine reports language `eng`, LSTM-only mode and raw-line segmentation

#### Scenario: Bundle under a non-ASCII path
- **WHEN** the application directory's path contains non-ASCII characters (for example Cyrillic)
- **THEN** the OCR engine initialises with the bundled model, and runtime status is `ready`

#### Scenario: Corrupt model fails initialisation
- **WHEN** the model's binding matches but the engine rejects the model during initialisation (simulated in a test by binding a truncated model)
- **THEN** runtime status is `unavailable` with failure `engineInitFailed`, and the engine handle is released

### Requirement: Image primitives operate on caller-owned buffers
The runtime SHALL expose these operations on caller-owned 8-bit images (width, height, stride, channels): grayscale conversion, cubic or area resize, binary-inverse threshold, normalized cross-correlation template match (best score and location), and a one-row colour-range scan. It SHALL reject a malformed image before any native call.

#### Scenario: Template found in sample
- **WHEN** a template is matched against an image containing an exact copy of it at (x, y)
- **THEN** the result location is (x, y) and the score is at least 0.99

#### Scenario: Malformed buffer rejected
- **WHEN** the stride is smaller than width × channels, or the buffer is shorter than stride × height
- **THEN** the operation returns failure `invalidImage`, and no native call is made

#### Scenario: Template larger than image
- **WHEN** the template is wider or taller than the image
- **THEN** the operation returns failure `invalidImage`

#### Scenario: Uniform template rejected
- **WHEN** a template with zero variance (every pixel equal) is matched
- **THEN** the operation returns failure `nativeFailure` with status -2 (`BGV_ERR_IMAGE`), not a match location

#### Scenario: Colour scan with no match
- **WHEN** no pixel in the scanned row falls within the colour range
- **THEN** the scan returns none

### Requirement: OCR reads text from a caller-owned image
The runtime SHALL recognise text from a caller-owned 8-bit image. It SHALL return the text as a Dart string, release the engine's text buffer, and clear the engine's image before returning, whether recognition succeeded or failed.

#### Scenario: Sample title recognised
- **WHEN** the bundled self-check title image is recognised
- **THEN** the returned text, trimmed, equals the sample's expected title

#### Scenario: Blank image
- **WHEN** a uniformly white image is recognised
- **THEN** recognition returns text without failure or truncation. The text is not required to be empty: in raw-line mode the pinned engine, like the reference, can emit short noise for a blank line (amended 2026-10-08 to match the reference)

#### Scenario: Recognition after disposal
- **WHEN** recognition is requested after the runtime has been disposed
- **THEN** the call returns failure `disposed`, and no native call is made

### Requirement: Runtime disposal releases native resources once
Disposing the runtime SHALL end and delete the OCR engine and release opened libraries exactly once. Repeated disposal SHALL be a no-op.

#### Scenario: Dispose after ready
- **WHEN** a ready runtime is disposed
- **THEN** the OCR engine is deleted, status becomes `disposed`, and subsequent operations return failure `disposed`

#### Scenario: Double dispose
- **WHEN** dispose is called twice
- **THEN** the second call returns without error, and the native delete function was called exactly once

### Requirement: Normal app launch does not load the vision runtime
Starting the application with live scanning off SHALL NOT open any vision library or read the OCR model. The runtime SHALL be loaded only by the vision self-check mode, by tests, and by the scan pipeline's vision worker while live scanning is on.

#### Scenario: Normal launch
- **WHEN** the application starts without the self-check argument and with live scanning off
- **THEN** the UI starts, and no vision library is loaded in the process

#### Scenario: Unknown argument
- **WHEN** the application starts with an unrecognised argument and with live scanning off
- **THEN** the UI starts normally, and no vision library is loaded

#### Scenario: Live scanning on at launch
- **WHEN** the application starts with live scanning saved on
- **THEN** the vision runtime is loaded only inside the scan pipeline's vision worker, never on the UI isolate

### Requirement: Vision self-check mode reports bundle readiness
Running the executable with `--vision-self-check <report-path>` SHALL, without showing a window or loading the database, verify and load the runtime, run a template match and OCR on the bundled self-check sample, write a JSON report to the given path, and exit with code 0 only if every step passed.

#### Scenario: Clean bundle passes
- **WHEN** the self-check runs from an intact Release bundle
- **THEN** the report shows the runtime `ready`, a template-match score of at least 0.99 at the expected location, and the expected OCR text, and the process exits with code 0

#### Scenario: Broken bundle fails visibly
- **WHEN** the self-check runs with the OCR model removed from the bundle
- **THEN** the report shows failure `missingFile` naming the model, and the process exits with a non-zero code

#### Scenario: Native step does not return
- **WHEN** a self-check native step has not finished 60 seconds after the self-check started (simulated in a test with a blocking stub)
- **THEN** the report records failure `timeout` naming that step, and the process exits with a non-zero code without waiting for the native call

#### Scenario: Report path missing or unwritable
- **WHEN** the self-check is given no report path, or a path whose directory does not exist
- **THEN** no window is shown, and the process exits with a distinct non-zero code reserved for usage errors

### Requirement: Self-check report is complete and authoritative
The self-check report's `result` field SHALL be the authoritative outcome, and the exit code SHALL mirror it. The report SHALL be replaced in one step, so that it is either absent or whole. It SHALL include a format version, the application version, the runtime identity (file names, SHA-256 and versions), each step's result and duration, and any typed failure.

#### Scenario: Report contents
- **WHEN** a self-check run finishes
- **THEN** the report holds `format`, `appVersion`, `runtimeIdentity` with each vision file's SHA-256 and the engine and ABI versions, one entry per step with its result and duration, and `result` equal to `pass` exactly when the exit code is 0

#### Scenario: Report names the build
- **WHEN** the self-check runs from a bundle built with app version `0.2.0-beta.1+120`
- **THEN** the report's `appVersion` is `0.2.0-beta.1+120`

#### Scenario: Development build
- **WHEN** the self-check runs from a build made without an app version
- **THEN** the report's `appVersion` is `dev`

#### Scenario: Report never partially written
- **WHEN** the self-check is interrupted while writing its report
- **THEN** the report path holds either no file or a previous complete report, never a truncated one

### Requirement: Template match lists every location at or above a threshold
The runtime SHALL list every template-match location whose normalised cross-correlation score is at or above a caller-given threshold, in raster order, with its score, up to a caller-given cap. It SHALL report overflow, not a truncated list, when more locations qualify than the cap allows. NaN scores SHALL never qualify. Malformed images SHALL be rejected as for the other primitives.

#### Scenario: Two template copies
- **WHEN** a template is listed at threshold 0.99 against an image holding exact copies of it at (10, 5) and (60, 30)
- **THEN** the list holds (10, 5) and (60, 30) in that order, each with score at least 0.99

#### Scenario: Nothing reaches the threshold
- **WHEN** no location reaches the threshold
- **THEN** the list is empty and no failure is reported

#### Scenario: More locations than the cap
- **WHEN** more locations qualify than the cap allows
- **THEN** the operation returns failure `nativeFailure` with status -6 (`BGV_ERR_OVERFLOW`, distinct from every other status), and no partial list

#### Scenario: Template larger than image
- **WHEN** the template is wider or taller than the image
- **THEN** the operation returns failure `invalidImage`, and no native call is made
