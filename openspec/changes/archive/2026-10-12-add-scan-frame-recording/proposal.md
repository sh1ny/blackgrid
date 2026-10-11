# Proposal

## Why

M2 cannot close without its screenshot corpus. Two exit criteria in `openspec/roadmap.md` depend on it:
- "The fixed positive/negative screenshot corpus has expected item IDs or rejections labelled independently of the reference" (user).
- "On that corpus, offline recognition reports marker score, title crop, OCR text, candidate scores and the accepted ID or rejection per case" (agent).

The offline corpus runner already exists (`docs/qualification/m2/CORPUS.md`). Each case needs a PNG of the whole client area and the cursor point in client pixels. Ordinary game screenshots do not record where the user clicked, so a targeted case built from them is only approximate.

Blackgrid already captures exactly those pixels on every scan, together with the click point, and then discards them. Recording them gives exact corpus cases from normal play.

It also gives the targeted-pass follow-up its input. In the user's live retest on 2026-10-10 the targeted pass never accepted a scan, and the recorded strip and its full-client frame let that failure be reproduced offline.

## What Changes

- **New opt-in "Record scan frames" switch in the Scanner panel.** It is off at every start and never persisted, so recording cannot stay on unnoticed after a restart.
- **What a recorded scan writes,** into a new session folder under `%LOCALAPPDATA%\Blackgrid\scan-frames\<session start>\`:
  - a PNG of the full-client frame;
  - a PNG of the targeted strip, when the targeted pass captured one;
  - one JSON line in `frames.jsonl` for every published scan, carrying the corpus case fields (`id`, `image`, `client`, `kind`, `cursor` in client pixels) and the `captured` region the image covers. A line has `image: null` when the scan has no full-client frame. A clipped frame is marked and is not a valid corpus case as recorded.
  - The line also carries the scan's outcome as a hint for labelling: accepted ID or rejection reason, OCR text and marker scores. It is never treated as the label.
- **A full-client frame whenever one can be had.** A scan the targeted pass accepts has no fallback frame. While recording is on, it gets one extra full-client capture after the scan is published, outside the scan's own latency path. A click made during that capture waits for it. Scans that fall back reuse their fallback frame. Scans that end without either, such as a catalog rejection or a capture failure, are recorded with `image: null`.
- **Recording is bounded and never blocks scanning:**
  - pixels are copied on the UI isolate before the frame goes to the vision worker;
  - PNG encoding and file writes run on a separate writer isolate with a small, dropping queue;
  - a per-session frame cap stops recording when reached;
  - drops, the cap and write failures are shown in the Scanner panel.
  - The copy's cost lands in that scan's timings, which is acceptable for a diagnostic mode.
- **`package:image` moves from `dev_dependencies` to `dependencies`,** for PNG encoding.
- **`docs/qualification/m2/CORPUS.md` gains a section** on turning a recording into a corpus.

Out of scope:
- labelling: the user decides the expected item or rejection per case;
- the reference baseline;
- the targeted-pass fix itself;
- choosing a folder: the path is shown, not configurable.

## Capabilities

### New Capabilities
- `scan-frame-recording`: opt-in recording of live scan frames and their corpus metadata to disk. Covers when recording is on, what each recorded scan writes, the extra full-client capture, the bounds (queue, cap, non-blocking), the privacy rules (off by default, local only, no credentials) and failure reporting.

### Modified Capabilities
- `scanner-evidence`: the Scanner panel shows the record switch with its count, folder and failure state.
- `scan-pipeline`: while recording, the coordinator hands each pass's pixels to the recorder before vision, and requests the extra full-client capture after a targeted acceptance. The extra capture does not delay publication and never runs while a newer scan is in flight.

## Impact

- **Code:**
  - `lib/application/scan_coordinator.dart`: recording hook and the extra capture.
  - New recorder in `lib/data/` (writer isolate and session folder), wired in `lib/application/app_services.dart`.
  - `lib/ui/live_scan_panel.dart`: the switch and status.
  - The audits in `test/data/capture/capture_source_audit_test.dart` and `test/data/vision/vision_worker_audit_test.dart` keep the coordinator as the only caller of capture and vision.
- **Dependencies:** `image` becomes a runtime dependency. The bundle check and licence notices need to cover it.
- **Game interaction:** none new in kind. The extra capture is a screen BitBlt, the same kind as the fallback capture. It runs only while the user has recording on, and at most once per scan. The game process is never touched (ADR-0010).
- **Privacy:**
  - Frames are screen content, written only while the user turns recording on, and only on this machine.
  - They are never committed: the corpus stays outside the repo (ADR-0012).
  - The timing log stays pixel-free and keeps schema v1.
- **Disk use:**
  - About 2-5 MB per 1080p frame and more at 4K.
  - The session cap bounds it, and the user deletes recordings by hand.
