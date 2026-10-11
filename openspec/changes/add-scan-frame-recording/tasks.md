# Tasks

Implementation notes:

- **Proposal wording leftover (review re-check, non-blocking).** The heading "Recording is bounded and never blocks scanning" predates M3. The specs and D4 are authoritative: a click during the extra capture waits for it.
- **Liveness check for the extra capture (review S7).** A trigger during the extra capture bumps `_scanGeneration`, so `_dead(s)` turns true. The extra-capture code checks instead that the scan was not abandoned (stop, pipeline loss or dispose), for example `identical(_active, s)` together with the activation not being retired. It never uses `_dead(s)`.
- **Test conventions (AGENTS.md):**
  - hand-written fakes; no sleeps;
  - small synthetic frames (for example 8x4 BGRX with stride padding);
  - recorder state tests use a fake writer whose answers complete on `Completer`s;
  - writer tests use a real isolate over a temp dir.
- **Safety:** verification is offline only. Recording against the game is the user's live check.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| scan-frame-recording → Recording is opt-in and lasts one session | Restart | test/application/scan_coordinator_recording_test.dart | recording is off in a new coordinator and is never saved in settings | red |
| scan-frame-recording → Recording is opt-in and lasts one session | Live scan switched off | test/application/scan_coordinator_recording_test.dart | switching live scan off turns recording off and on again leaves it off | red |
| scan-frame-recording → Recording is opt-in and lasts one session | Live scan leaves ready while recording starts | test/data/scan_frame_recorder_test.dart | stop during starting ends off and kills the late writer | red |
| scan-frame-recording → Recording is opt-in and lasts one session | Live scan becomes unavailable | test/application/scan_coordinator_recording_test.dart | worker loss turns recording off and outstanding scans are still written | red |
| scan-frame-recording → Recording is opt-in and lasts one session | Switching on while the last session drains | test/data/scan_frame_recorder_test.dart | start while stopping is refused and creates no folder | red |
| scan-frame-recording → Recording is opt-in and lasts one session | Switching on after the last session drained | test/data/scan_frame_recorder_test.dart | a new session after a drain starts with zero counts | red |
| scan-frame-recording → Each recording session gets its own folder | Switching recording on | test/data/scan_frame_recorder_test.dart | start creates the session folder named by local start time | red |
| scan-frame-recording → Each recording session gets its own folder | Folder name already used | test/data/scan_frame_recorder_test.dart | a second start in the same second uses the -2 suffix | red |
| scan-frame-recording → Each recording session gets its own folder | Folder cannot be created | test/data/scan_frame_recorder_test.dart | folder creation failure leaves recording off with the error | red |
| scan-frame-recording → Every published scan writes one case line and its frames | Scan accepted by the fallback pass | test/application/scan_coordinator_recording_test.dart | fallback acceptance records full and targeted PNGs and one line | red |
| scan-frame-recording → Every published scan writes one case line and its frames | Superseded scan | test/application/scan_coordinator_recording_test.dart | a superseded scan records nothing | red |
| scan-frame-recording → Every published scan writes one case line and its frames | Accepted scan whose extra capture fails | test/application/scan_coordinator_recording_test.dart | failed extra capture records the strip with image null and fullFailure | red |
| scan-frame-recording → Every published scan writes one case line and its frames | Ended on the targeted pass without a fallback | test/application/scan_coordinator_recording_test.dart | catalogUnavailable records the strip with image null | red |
| scan-frame-recording → Every published scan writes one case line and its frames | No frame at all | test/application/scan_coordinator_recording_test.dart | captureBusy records a line with no frames | red |
| scan-frame-recording → Each case line carries the corpus case fields | Click inside the client | test/application/scan_coordinator_recording_test.dart | targeted line carries the client cursor and no expected field | red |
| scan-frame-recording → Each case line carries the corpus case fields | Click outside the client | test/application/scan_coordinator_recording_test.dart | roiOutsideClient records kind fullClient without a cursor | red |
| scan-frame-recording → Each case line carries labelling hints | Accepted scan hints | test/application/scan_coordinator_recording_test.dart | accepted line carries acceptedId, text and null rejectReason | red |
| scan-frame-recording → Each case line carries labelling hints | Window partly off the desktop | test/application/scan_coordinator_recording_test.dart | clipped fallback frame records captured and clipped true | red |
| scan-frame-recording → Each case line carries labelling hints | Full frame taken after the decision | test/application/scan_coordinator_recording_test.dart | extra frame time is later than the strip time | red |
| scan-frame-recording → Recording never changes the recorded scan, and its only effect on later scans is the extra capture | Recording off | test/application/scan_coordinator_recording_test.dart | with recording off no pixels are read and no capture follows | red |
| scan-frame-recording → Recording never changes the recorded scan, and its only effect on later scans is the extra capture | Writer falls behind | test/data/scan_frame_recorder_test.dart | a third outstanding scan is dropped and counted | red |
| scan-frame-recording → Recording never changes the recorded scan, and its only effect on later scans is the extra capture | Later click during the extra capture | test/application/scan_coordinator_recording_test.dart | a trigger during the extra capture starts after its answer and the frame is recorded | red |
| scan-frame-recording → Recording is bounded and stops cleanly on failure | Cap reached | test/data/scan_frame_recorder_test.dart | the 500th hand-off stops intake and its ack turns recording off | red |
| scan-frame-recording → Recording is bounded and stops cleanly on failure | Disk full | test/data/scan_frame_writer_test.dart | a failed PNG write leaves no line and no final PNG | green |
| scan-frame-recording → Recording is bounded and stops cleanly on failure | Disk full | test/data/scan_frame_recorder_test.dart | a writer failure turns recording off with the error | red |
| scan-frame-recording → Recording is bounded and stops cleanly on failure | App closes while writing | test/data/scan_frame_recorder_test.dart | close waits up to the timeout and ignores late acks | red |
| scan-frame-recording → Recordings stay local and carry no credentials | Recording with Tracker connected | test/application/scan_coordinator_recording_test.dart | recorded files never contain the saved Tracker token | red |
| scan-frame-recording → Recordings stay local and carry no credentials | Timing log while recording | test/application/scan_coordinator_recording_test.dart | timing log line keys are the same with recording on | red |
| scan-pipeline → Recording receives each pass's pixels before vision | Recorded fallback scan | test/application/scan_coordinator_recording_test.dart | both passes are copied before submit and each frame is released once | red |
| scan-pipeline → Recording receives each pass's pixels before vision | Superseded before vision | test/application/scan_coordinator_recording_test.dart | superseded after capture releases the frame and records nothing | red |
| scan-pipeline → Targeted acceptance gets one extra full-client capture while recording | Accepted on the targeted pass | test/application/scan_coordinator_recording_test.dart | targeted acceptance publishes before the extra capture | red |
| scan-pipeline → Targeted acceptance gets one extra full-client capture while recording | Recording off | test/application/scan_coordinator_recording_test.dart | with recording off no pixels are read and no capture follows | red |
| scan-pipeline → Targeted acceptance gets one extra full-client capture while recording | Trigger during the extra capture | test/application/scan_coordinator_recording_test.dart | a trigger during the extra capture starts after its answer and the frame is recorded | red |
| scan-pipeline → Targeted acceptance gets one extra full-client capture while recording | Extra capture overruns with a trigger pending | test/application/scan_coordinator_recording_test.dart | extra captureTimeout fails the pending scan captureBusy and records fullFailure | red |
| scan-pipeline → Targeted acceptance gets one extra full-client capture while recording | Extra capture fails | test/application/scan_coordinator_recording_test.dart | failed extra capture records the strip with image null and fullFailure | red |
| scanner-evidence → Scanner shows the record switch and its status | Recording runs | test/ui/live_scan_panel_test.dart | record status shows written, dropped and folder | red |
| scanner-evidence → Scanner shows the record switch and its status | Live scan not ready | test/ui/live_scan_panel_test.dart | record switch is off and disabled unless live scan is ready | red |
| scanner-evidence → Scanner shows the record switch and its status | Write failure | test/ui/live_scan_panel_test.dart | record status shows the write error and folder after a self-stop | red |

Also add (no row): "stop during the extra capture releases the frame and records nothing" (S7), and "coordinator still the only capture and vision caller" (both audits re-run green).

## 1. ADR, roadmap and dependency

- [x] 1.1 Write `docs/adr/0015-opt-in-scan-frame-recording.md` (MADR-short, D8). It covers:
  - the opt-in, session-only mode;
  - the recording-only pixel copy (an exception to the copies ADR-0010 and ADR-0011 rejected for the scan path; it supersedes nothing);
  - the post-publish extra capture and its cost to a click made during it;
  - latency judged with recording off;
  - `frames.jsonl` v1;
  - `image` as a runtime dependency.

  Add it to `docs/adr/README.md` and the `openspec/architecture.md` ADR index, and update the ScanCoordinator row. Verify: the files exist and both indexes link 0015.
- [x] 1.2 Add change 7 `add-scan-frame-recording` to the M2 list in `openspec/roadmap.md`, naming the corpus exit criteria it serves. Verify: `openspec validate --all` shows no new error.
- [x] 1.3 Move `image: 4.8.0` from `dev_dependencies` to `dependencies` in `pubspec.yaml`, then run `mise exec -- flutter pub get`. Check the D3 API (`Image.fromBytes` with `rowStride`, `numChannels: 4`, `order: ChannelOrder.bgra`; 3-channel convert; `encodePng(level:)`) with `ctx7` or the package source (`mcp__dart__read_package_uris`), and note the confirmed calls in the 2.x writer's doc comment. Verify: `mise run analyze` is clean.

## 2. Writer isolate

- [x] 2.1 Add `test/data/scan_frame_writer_test.dart`, with a real writer isolate over a temp dir and an 8x4 BGRX frame with stride padding. It covers:
  - the PNG decodes to the expected RGB pixels, opaque;
  - the line is appended after both PNGs, with the D7 fields;
  - "a failed PNG write leaves no line and no final PNG", using an injected failing file-ops factory (a top-level function sent to the isolate);
  - messages and answers carry the session token.

  Verify: the tests fail (no writer).
- [x] 2.2 Implement in `lib/data/scan_frame_recorder.dart`:
  - the plain-data types `RecordedFrame` and `RecordedScan`, and the line serialiser (D7, `v: 1`, nulls for absent values);
  - the writer isolate entry: materialise, BGRX→RGB, `encodePng`, then `.png.tmp` → rename, then append the line in one write, then ack or a typed failure with its token.

  No import from `data/capture/` or `data/vision/`. Verify: the 2.1 tests pass, then flip the writer row green.

## 3. Recorder lifecycle and bounds

- [x] 3.1 Add `test/data/scan_frame_recorder_test.dart`, with a fake writer (completer-driven) and an injected clock and folder root. It covers the recorder rows:
  - start, the folder name and the `-2` suffix, folder failure;
  - stop during starting, refusal while stopping, zero counts after a drain;
  - a third outstanding scan dropped, the cap of 500 hand-offs, a writer failure;
  - close with timeout and stale-token acks ignored.

  Verify: they fail.
- [ ] 3.2 Implement `ScanFrameRecorder`:
  - the state machine `off/starting/on/stopping` with a session token (D5);
  - folder naming (D6);
  - the outstanding bound of 2, the cap of 500 hand-offs and the counters;
  - `ValueListenable<ScanRecordingStatus>` (state, written, dropped, folder, stop reason);
  - `close({Duration timeout = 2 s})`;
  - an injectable writer factory, whose default is the 2.2 isolate.

  Verify: the 3.1 tests pass, then flip their rows green.

## 4. Coordinator

- [ ] 4.1 Add `test/application/scan_coordinator_recording_test.dart` over the existing fake capture and vision ports (`test/application/support/fake_scan_ports.dart`), extended so a fake frame can lend pixels and counts `withPixels` calls. Add a fake recorder that records `RecordedScan`s. It covers every coordinator row of the test map, plus "stop during the extra capture releases the frame and records nothing". Verify: they fail.
- [ ] 4.2 In `lib/application/scan_coordinator.dart`:
  - take an injected `ScanFrameRecorder`;
  - `setRecording(bool)` and `recordingStatus`;
  - `recorder.stop()` on every `_set` that leaves `ready`;
  - the D1 copy in `_runPass` (recording only), stored on `_Scan` with each frame's metadata, the client cursor and `captured`;
  - the record hand-off on every `_finish` path except a targeted acceptance while recording;
  - for that acceptance, the D4 extra capture after `_finish`, with `s.stage = _Stage.capture` and the liveness check from the implementation notes, then the hand-off with `fullFailure` on failure;
  - superseded scans never hand off.

  Wire the recorder in `lib/application/app_services.dart` (root `<LocalPaths root>\scan-frames`; in tests a temp dir), and call its `close()` in `dispose` after `scanner.dispose()`. Verify: the 4.1 tests, the whole `scan_coordinator_*` suite, `app_services_*` tests, and both audit tests pass, then flip the rows green.

## 5. Scanner panel

- [ ] 5.1 Add the three panel tests to `test/ui/live_scan_panel_test.dart` (switch key `record-frames-switch`, status key `record-frames-status`). Verify: they fail.
- [ ] 5.2 Add the "Record scan frames" switch and status lines to `lib/ui/live_scan_panel.dart`, listening to `scanner.recordingStatus`. Raise `leftHeight` in `lib/ui/scanner_screen.dart` if the controls need it. Verify: the 5.1 tests and the existing panel and `shell_test.dart` layout tests pass (re-run them), then flip the rows green.

## 6. Corpus documentation

- [x] 6.1 Add a "Recording a corpus from live scans" section to `docs/qualification/m2/CORPUS.md`. It covers:
  - the switch and the session folder;
  - mapping `frames.jsonl` to `corpus.json`: keep lines with an `image` and `clipped: false`, copy `id`, `image`, `client`, `kind`, `cursor`, and add `expected` from the user's label;
  - the hint fields are never labels;
  - clipped lines are not valid cases;
  - ids carry the session, so sessions can be merged;
  - timings from recording sessions include the copy and the extra-capture waits, so latency is judged with recording off.

  Verify: the doc names every D7 field.

## 7. Integration

- [ ] 7.1 Run `mise run analyze` and `mise run test`, and `dart format` the changed files. Verify: both are green and every test-map row is green.
- [ ] 7.2 Run `mise run build:release`, only after confirming Escape from Tarkov is not running; if that cannot be confirmed, record the build as skipped and unverified. Verify: the build and bundle check pass (the `image` package adds no bundle file), or the skip is recorded.

## Workflow follow-up

- The user records a session in-game (inspect windows of varied items, plus negatives such as the right-click menu) and labels the cases. The agent then builds `corpus.json` and runs the corpus test (`docs/qualification/m2/CORPUS.md`).
- The targeted-pass follow-up change uses the recorded strips and full frames to reproduce the targeted misses offline.
