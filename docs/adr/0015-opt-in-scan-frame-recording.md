# 0015 - Opt-in scan frame recording: a session-only mode, a recording-only pixel copy, a post-publish full-client capture, `frames.jsonl` v1

- Status: accepted
- Date: 2026-10-12 (M2 change `add-scan-frame-recording`)
- Supersedes: none
- Source: change `add-scan-frame-recording` (design D1-D8); [ADR-0010](0010-windows-input-and-capture-boundary.md), [ADR-0011](0011-vision-worker-contract.md), [ADR-0012](0012-inspection-recognition-pipeline.md), [ADR-0013](0013-scan-pipeline-coordination.md), [ADR-0014](0014-scan-settle-and-fallback-waits.md)

## Context and problem

The M2 exit criteria need a screenshot corpus labelled independently of the reference, and an offline run that reports marker score, crop, OCR text and candidates per case. Building that corpus by hand means taking and sizing screenshots outside the app. Live scans already see the right frames, but they release them after the vision job, and a targeted frame is only the strip. Nothing keeps pixels, by design: ADR-0010 and ADR-0011 rejected copying frame pixels into a Dart buffer (`TransferableTypedData`) as the scan transport, and screenshots and OCR are not persisted by default (ADR-0013 keeps pixels out of the timing log).

The user needs a deliberate way to save the whole client image and the strip of the scans they make, with hints about what the app saw, without changing what a scan does.

## Decision

- **An opt-in, session-only mode.** The "Record scan frames" switch in the Scanner panel is off at every launch and is never persisted: `AppSettings` is untouched. `ScanCoordinator.setRecording(true)` is accepted only while the live scan state is `ready`, and any transition out of `ready` turns recording off. The recorder's states are `off → starting → on → stopping → off`, with an incrementing session token; a late start is killed and messages from another token are ignored. `stopping` drains the outstanding scans, so a scan queued before leaving `ready` is still written.
- **A recording-only pixel copy.** This is an exception to the copy that ADR-0010 and ADR-0011 rejected for the scan path. On the UI isolate, in `_runPass` just before `submitFrame`, the coordinator calls `CaptureFrame.withPixels` and copies the lent bytes into a `TransferableTypedData`, only while recording. Frame ownership, release and the vision transport are unchanged, so those ADRs stay in force and nothing is superseded: they rejected the copy as the transport, and here the transport is the same.
- **A recorder behind a plain-data port.** `ScanFrameRecorder` (`lib/data/scan_frame_recorder.dart`) takes `RecordedScan` and `RecordedFrame` values and imports nothing from `data/capture/` or `data/vision/`, so both source audits are unchanged.
- **PNG encoding and writes in a writer isolate.** One writer isolate per session builds an RGB image from the BGRX rows, encodes the PNG, writes `<name>.png.tmp` and renames it, then appends the scan's line to `frames.jsonl` after its PNGs. `package:image` moves from `dev_dependencies` to `dependencies`. It is pure Dart and adds no bundle file.
- **A post-publish extra capture.** The fallback pass produces the only full-client frame, and a targeted acceptance does not run it. So after a targeted acceptance, while recording, the scan is published and logged as today, then the coordinator sets the stage to capture and requests one more full-client capture for the same trigger. It copies the pixels, releases the frame at once and hands the scan to the recorder. The extra frame never reaches vision, matching, `ScanReport` or the timing log.
  - **Accepted cost.** A click during this capture takes the pending slot and waits up to the 500 ms capture deadline (ADR-0013, ADR-0014). If the extra capture answers `captureTimeout`, the pending scan ends `ScanFailed(captureBusy)`, exactly as for any capture-stage supersession. It is paid only while recording.
- **Latency is judged with recording off.** Timings from a recording session include the pixel copy and the extra-capture waits. The timing log schema stays v1.
- **Bounds.** At most 2 outstanding scans (handed to the writer and not acked, counting the one being written); a scan ending while 2 are outstanding is dropped and counted. A cap of 500 hand-offs per session, after which recording turns off with reason `capReached`. `close()` waits at most 2 s for acks, then kills the writer. A write failure or a dead writer stops recording and shows the error.
- **Session folder and names.** `%LOCALAPPDATA%\Blackgrid\scan-frames\<yyyyMMdd-HHmmss>[-N]\`, where `-N` separates two sessions started in the same second. A case id is `<session folder name>-NNNN`, with `NNNN` the zero-padded `ScanReport.id`, so ids stay unique when sessions are merged into one corpus. Files are `<id>-full.png`, `<id>-targeted.png` and `frames.jsonl`.
- **`frames.jsonl` v1.** One JSON object per published scan, appended after its PNGs exist:
  - the corpus case fields: `id`, `image`, `client {width,height}`, `kind`, and `cursor {x,y}` (omitted for `fullClient`);
  - `captured {left,top,width,height}` in client pixels, the rectangle the full PNG covers;
  - hint fields: `clipped`, `strip`, `outcome` (`accepted|rejected|failed`), `acceptedId`, `rejectReason`, `failure`, `fullFailure`, `text`, `targetedMarkerScore`, `fallbackMarkerScore`, `stripCapturedAtUtc`, `fullCapturedAtUtc`;
  - `v: 1`.

  `image` and `strip` are null when that frame does not exist, and `captured` is null with `image`. `kind` is `fullClient` when the targeted pass failed `roiOutsideClient`, and `targeted` otherwise. There is no `expected` field: labelling is the user's. A line with `clipped: true` is not a valid corpus case as recorded, because the corpus runner requires the image size to equal the client size and ADR-0010 is clip-not-pad. Readers skip an unparseable final line, which a crash during the append can leave.

## Rejected alternatives

- **Copying inside the vision job and returning the copy with the answer (D1):** the worker is serial, so copying and sending 8-33 MB delays the reply and the next request inside the 1.5 s deadline, and recording would enter the vision request contract that other scans share.
- **Zero-copy, holding the frame slot until the writer has encoded it (D1):** it holds 1 of 4 native slots for seconds per frame, so captures would fail `frameBudgetExceeded`.
- **The recorder adopting `CaptureFrame`s or tickets (D2):** a second frame owner breaks single frame ownership and needs both audits relaxed.
- **A PNG encoder in the vision DLL, `Isolate.run` per scan, or `dart:ui` encoding (D3):** the first grows the native ABI and puts file I/O beside recognition, the second spawns an isolate per click, the third runs on the UI and raster threads.
- **Forcing the fallback pass while recording (D4):** it changes recognition and publication, against "recording never blocks or changes scanning".
- **Capturing the full client in parallel with the targeted pass (D4):** capture admits one request at a time, and ADR-0013 rejected parallel captures per trigger.
- **Strip-only records for targeted acceptances (D4):** the corpus runner needs the whole client, so those records would be useless.
- **A persisted setting (D5):** it could leave recording on after a restart and fill the disk with screen content.
- **A byte budget instead of a count (D6), and writing `corpus.json` directly (D7):** frame size varies by resolution, a count is easier to show; the recorder cannot know a label, and rewriting one JSON document per scan is not append-safe.

## Consequences

- **Screen content reaches disk only on an explicit switch-on,** in a local folder whose path the panel shows. Nothing is uploaded and old sessions are never deleted automatically.
- **Recording skews timings** by the pixel copy (a few ms at 1080p) and the extra-capture waits; `docs/qualification/m2/CORPUS.md` says to judge latency with recording off.
- **Disk use is bounded per session, not overall:** about 2-5 MB per 1080p full PNG, up to roughly 20 GB for 500 scans at 4K, shown growing in the panel. A byte budget is the next step if this proves a problem.
- **`v: 1` binds later corpus tooling.** Changing a field needs a new version and a new ADR.
- **Reversal cost:** low for the copy, the extra capture and the bounds (one branch each, constants in one file); medium for the line format once corpora exist.
