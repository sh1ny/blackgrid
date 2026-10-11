# Spec Delta

## ADDED Requirements

### Requirement: Recording receives each pass's pixels before vision
While frame recording is on, the pipeline SHALL copy each pass's captured pixels and metadata for the recorder before handing the frame to the vision worker. The frame itself SHALL stay owned and released exactly as without recording. While recording is off, the pipeline SHALL make no copy.

#### Scenario: Recorded fallback scan
- **WHEN** recording is on and a scan runs a targeted and a fallback pass
- **THEN** the recorder receives a copy of both frames with the trigger's client point, and each frame is released once by the vision worker

#### Scenario: Superseded before vision
- **WHEN** a recorded scan is superseded after its capture answer and before its frame reaches the vision worker
- **THEN** the frame is released, and the recorder writes nothing for that scan

### Requirement: Targeted acceptance gets one extra full-client capture while recording
While recording is on, a scan accepted by its targeted pass SHALL, after it is published and logged, request one full-client capture for the same trigger target. That frame SHALL be used only for recording: it is never recognised, never changes the published scan and never adds keys to its timing log line. A trigger arriving during this capture SHALL take the pending slot and wait for its answer, as during a capture stage, including the `captureTimeout` → `captureBusy` outcome.

#### Scenario: Accepted on the targeted pass
- **WHEN** recording is on and a scan is accepted by its targeted pass
- **THEN** the accepted evidence is published first, then one full-client capture is requested and its frame goes to the recorder

#### Scenario: Recording off
- **WHEN** recording is off and a scan is accepted by its targeted pass
- **THEN** no capture is requested after the scan ends

#### Scenario: Trigger during the extra capture
- **WHEN** a new trigger arrives while the extra capture is in flight
- **THEN** the new scan starts once that capture answers, and the extra frame is still recorded

#### Scenario: Extra capture overruns with a trigger pending
- **WHEN** a trigger is pending and the extra capture answers `captureTimeout`
- **THEN** the pending trigger's scan ends `failed` with `captureBusy` and is logged, and the recorded scan's line has `image: null` and `fullFailure: "captureTimeout"`

#### Scenario: Extra capture fails
- **WHEN** the extra capture fails with `targetChanged`
- **THEN** the published scan is unchanged, and the recorder writes the scan's strip with `image: null` and `fullFailure: "targetChanged"`
