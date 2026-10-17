# scan-frame-recording Specification

## Purpose
Saves live scan frames and their corpus metadata to disk while the user turns recording on, so that real scans become exact, labellable cases for the offline inspection corpus. Recording never changes what the recorded scan recognises or publishes.

## Requirements

### Requirement: Recording is opt-in and lasts one session
Frame recording SHALL be off at every launch and SHALL NOT be persisted. It SHALL be possible to turn it on only while live scan is `ready`, and while no earlier recording session is still stopping. Live scan leaving `ready` (switched off, stopping or unavailable) SHALL turn recording off, including while recording is still starting.

#### Scenario: Restart
- **WHEN** the user quits Blackgrid with recording on and starts it again
- **THEN** recording is off and no scan writes a frame until the user turns it on

#### Scenario: Live scan switched off
- **WHEN** live scan is turned off while recording is on
- **THEN** recording is off, and turning live scan back on leaves it off

#### Scenario: Live scan leaves ready while recording starts
- **WHEN** the vision worker dies after the user turned recording on and before the session folder and writer are ready
- **THEN** recording is off and stays off, and no scan is written to that session

#### Scenario: Live scan becomes unavailable
- **WHEN** the vision worker dies while recording is on
- **THEN** recording is off and the scans already handed to the writer are still written

#### Scenario: Switching on while the last session drains
- **WHEN** the user turns recording on while the previous session is still writing its queued scans
- **THEN** the switch-on is refused: the switch stays off and no new session folder is created

#### Scenario: Switching on after the last session drained
- **WHEN** the previous session wrote 12 scans and the user turns recording on after its drain ended
- **THEN** a new session starts with 0 written and 0 dropped

### Requirement: Each recording session gets its own folder
Each switch-on SHALL start a new session folder under `%LOCALAPPDATA%\Blackgrid\scan-frames\`, named by its local start time (`yyyyMMdd-HHmmss`), with a `-2`, `-3`, … suffix when that name exists.

#### Scenario: Switching recording on
- **WHEN** live scan is `ready` and the user turns recording on at 2026-10-10 14:03:07
- **THEN** recording is on and the folder `scan-frames\20261010-140307\` exists

#### Scenario: Folder name already used
- **WHEN** recording is switched on twice within the same second
- **THEN** the second session writes to the folder with the `-2` suffix and the first folder is unchanged

#### Scenario: Folder cannot be created
- **WHEN** the session folder cannot be created
- **THEN** recording is off, the error is shown, and live scan keeps scanning

### Requirement: Every published scan writes one case line and its frames
While recording is on, each scan that ends accepted, rejected or failed SHALL get exactly one line in the session's `frames.jsonl`. Superseded scans SHALL get none. The recorder SHALL write the scan's full-client frame, when it has one, as an opaque RGB PNG `<id>-full.png` at its captured size. It SHALL write the scan's targeted strip, when it has one, as `<id>-targeted.png`. The line SHALL name these files, with `image: null` or `strip: null` for a missing frame.

#### Scenario: Scan accepted by the fallback pass
- **WHEN** Scanner's scan #7 of session `20261010-140307` is accepted by its fallback pass on a 1920x1080 client
- **THEN** the folder holds `20261010-140307-0007-full.png` (1920x1080) and `20261010-140307-0007-targeted.png` (1140x600), and `frames.jsonl` has one line with id `20261010-140307-0007`

#### Scenario: Superseded scan
- **WHEN** a scan is superseded before it ends
- **THEN** nothing is written for it

#### Scenario: Accepted scan whose extra capture fails
- **WHEN** a scan is accepted by its targeted pass and its extra full-client capture fails with `targetChanged`
- **THEN** its strip PNG is written, and its line has `outcome: "accepted"`, `image: null` and `fullFailure: "targetChanged"`

#### Scenario: Ended on the targeted pass without a fallback
- **WHEN** a scan is rejected `catalogUnavailable` after its targeted pass
- **THEN** its strip PNG is written and its line has `image: null`, `outcome: "rejected"` and `rejectReason: "catalogUnavailable"`

#### Scenario: No frame at all
- **WHEN** a scan fails because its targeted capture answers `captureBusy`
- **THEN** no PNG is written and its line has `image: null`, `strip: null`, `outcome: "failed"` and `failure: "captureBusy"`

### Requirement: Each case line carries the corpus case fields
Each `frames.jsonl` line SHALL be a JSON object with `v: 1`, the corpus case fields of `docs/qualification/m2/CORPUS.md` and `captured`:
- `id`: `<session folder name>-NNNN`, with NNNN the Scanner's scan number zero-padded to at least 4 digits;
- `image`, `client` (`width`, `height`), `kind`, and `cursor` in client pixels;
- `captured` (`left`, `top`, `width`, `height` in client pixels), the region the full PNG covers.

The line SHALL NOT carry an `expected` field.

#### Scenario: Click inside the client
- **WHEN** the trigger was at client point (812, 403) and the scan was rejected `belowSimilarity`
- **THEN** the line has `kind: "targeted"`, `cursor: {"x": 812, "y": 403}`, `outcome: "rejected"`, `rejectReason: "belowSimilarity"` and no `expected` field

#### Scenario: Click outside the client
- **WHEN** the trigger point was outside the client, so the scan ran only the fallback pass
- **THEN** the line has `kind: "fullClient"` and no `cursor`

### Requirement: Each case line carries labelling hints
Each line SHALL also carry these hint fields, for labelling only: `clipped`, `strip`, `outcome`, `acceptedId`, `rejectReason`, `failure`, `fullFailure`, `text`, `targetedMarkerScore`, `fallbackMarkerScore`, `stripCapturedAtUtc` and `fullCapturedAtUtc`. A field whose value does not exist for the scan SHALL be null.

#### Scenario: Accepted scan hints
- **WHEN** a scan is accepted as item `5755356824597772cb798962` by its fallback pass with OCR text `AK-74`
- **THEN** its line has `outcome: "accepted"`, `acceptedId: "5755356824597772cb798962"`, `text: "AK-74"`, `rejectReason: null` and no `expected` field

#### Scenario: Window partly off the desktop
- **WHEN** a 1920x1080 client's left 200 pixels lay off the virtual desktop
- **THEN** the line has `clipped: true`, `client` 1920x1080, and `captured` `{left: 200, top: 0, width: 1720, height: 1080}`, matching the PNG's size

#### Scenario: Full frame taken after the decision
- **WHEN** a targeted acceptance's extra capture answers 180 ms after its strip was captured
- **THEN** `fullCapturedAtUtc` is 180 ms after `stripCapturedAtUtc`

### Requirement: Recording never changes the recorded scan, and its only effect on later scans is the extra capture
Recording SHALL NOT change the recorded scan's passes, recognition result or publication. Recording work on the scan path SHALL be limited to copying pixels and the extra capture. PNG encoding and file writes SHALL run off the UI isolate. At most 2 scans SHALL be handed to the writer and not yet written, counting the one being written. A scan ending while 2 are outstanding SHALL be dropped from recording and counted.

#### Scenario: Recording off
- **WHEN** recording is off
- **THEN** no pixels are copied and no file is written for any scan

#### Scenario: Writer falls behind
- **WHEN** a scan ends while 2 recorded scans are handed to the writer and not yet written
- **THEN** that scan is published as usual, it is not written, and the dropped count rises by one

#### Scenario: Later click during the extra capture
- **WHEN** the user clicks again while a recorded scan's extra capture is in flight
- **THEN** the new scan starts once that capture answers, within the 500 ms capture deadline, and its timings include that wait

### Requirement: Recording is bounded and stops cleanly on failure
A session SHALL hand at most 500 scans to the writer. The 500th hand-off SHALL stop the session taking new scans, and recording SHALL turn off once that scan is written. A write failure SHALL turn recording off, keep the error and leave scanning running. Each line SHALL be appended only after its PNG files are complete. An interrupted write SHALL leave no partial PNG under its final name, and late results from an earlier session SHALL NOT change the current session's counts or state.

#### Scenario: Cap reached
- **WHEN** the 500th scan of a session is handed to the writer
- **THEN** no later scan is handed over, recording turns off once it is written, and Scanner shows that the cap was reached with 500 written

#### Scenario: Disk full
- **WHEN** writing a PNG fails because the disk is full
- **THEN** recording turns off with the error shown, that scan has no line in `frames.jsonl`, and live scan stays `ready`

#### Scenario: App closes while writing
- **WHEN** Blackgrid closes with recorded scans still queued
- **THEN** it waits up to 2 seconds for them, and every line in `frames.jsonl` names files that exist

### Requirement: Recordings stay local and carry no credentials
Recorded files SHALL be written only to the session folder on this machine, and SHALL NOT be uploaded or sent anywhere. Case lines SHALL hold no credentials or Tracker data. The scan timing log SHALL stay pixel-free and keep schema v1.

#### Scenario: Recording with Tracker connected
- **WHEN** a scan is recorded while a Tracker token is saved
- **THEN** no file in the session folder contains the token

#### Scenario: Timing log while recording
- **WHEN** a recorded scan is logged
- **THEN** its `scan-timings.jsonl` line has the same keys as an unrecorded scan's line and holds no pixel bytes
