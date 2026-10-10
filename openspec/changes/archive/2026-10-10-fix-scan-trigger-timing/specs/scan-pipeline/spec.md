# Spec Delta

## MODIFIED Requirements

### Requirement: One scan in flight, latest trigger wins
At most one scan SHALL be in flight, and at most one trigger SHALL wait. A trigger arriving during a scan SHALL supersede that scan. While the scan is in its capture stage, the new trigger SHALL take the pending slot, and a trigger it replaces there is dropped and counted. During a wait, the vision stage or matching, the new scan SHALL start at once. A superseded scan SHALL publish no evidence. The pending trigger SHALL start once the superseded scan's native stage returns or its vision request is invalidated.

#### Scenario: Burst during capture
- **WHEN** triggers 2 and 3 arrive while scan 1 waits for its targeted capture
- **THEN** scan 1 is superseded and publishes nothing, its frame is released, trigger 2 is dropped, and trigger 3's scan starts once that capture returns, reporting 1 superseded trigger

#### Scenario: Pending trigger meets an overrun capture
- **WHEN** a trigger is pending and the in-flight capture answers `captureTimeout`
- **THEN** the superseded scan is logged, and the pending trigger's scan ends `failed` with `captureBusy` while the capture worker stays overrun, and is logged

#### Scenario: Trigger during the vision stage
- **WHEN** a new trigger arrives while scan 1 waits for its vision answer
- **THEN** scan 1's vision request is invalidated at once, the new scan's settle wait starts without waiting for the old job, and the old job's late result is never published

#### Scenario: Trigger during matching
- **WHEN** a new trigger arrives while scan 1's matching runs off the UI isolate
- **THEN** the new scan starts at once, and scan 1's match result is discarded when it arrives

#### Scenario: Triggers dropped by the native queue
- **WHEN** a trigger arrives reporting 4 events dropped by the native queue before it
- **THEN** the scan it starts records 4 dropped native triggers


## ADDED Requirements

### Requirement: Targeted capture waits for the inspect window to settle
A scan SHALL NOT request its targeted capture earlier than 50 ms after its trigger's timestamp, measured on the trigger and capture clock. A scan whose trigger is already at least 50 ms old SHALL request the capture without waiting. The wait SHALL hold no frame and make no native call.

#### Scenario: Fresh trigger
- **WHEN** a trigger is handled 1 ms after its timestamp
- **THEN** the scan waits 49 ms, the remaining time to 50 ms after the trigger, and then requests the targeted capture

#### Scenario: Trigger already old
- **WHEN** a pending trigger starts its scan 120 ms after its timestamp
- **THEN** the targeted capture is requested at once, with no further wait

#### Scenario: Switched off while waiting
- **WHEN** live scan is switched off while a scan waits to settle
- **THEN** no capture is requested for that scan and it publishes nothing

### Requirement: Fallback capture waits until 200 ms after the trigger
A scan's fallback capture SHALL NOT be requested earlier than 200 ms after its trigger's timestamp. The `fallback` phase SHALL be published before this wait. A fallback whose deadline has already passed SHALL be requested without waiting.

#### Scenario: Quick targeted rejection
- **WHEN** a scan's targeted pass is rejected `noMarker` 80 ms after its trigger
- **THEN** the `fallback` phase is published at once, and the fallback capture is requested no earlier than 200 ms after the trigger

#### Scenario: Slow targeted rejection
- **WHEN** a scan's targeted pass is rejected `belowSimilarity` 260 ms after its trigger
- **THEN** the fallback capture is requested at once

### Requirement: A trigger during a wait supersedes the scan at once
A trigger arriving while a scan waits before a capture request SHALL supersede that scan at once. The new scan SHALL start right away, without the pending slot, and run its own settle wait. The superseded scan SHALL request no further capture and publish no evidence.

#### Scenario: Second click during the settle wait
- **WHEN** trigger 2 arrives 20 ms after trigger 1, while scan 1 waits to settle
- **THEN** scan 1 requests no capture and publishes nothing, and scan 2's targeted capture is requested no earlier than 50 ms after trigger 2

#### Scenario: Click during the fallback wait
- **WHEN** a new trigger arrives while scan 1 waits for its fallback deadline
- **THEN** scan 1 requests no fallback capture and publishes no evidence, and the new scan shows the `targeted` phase
