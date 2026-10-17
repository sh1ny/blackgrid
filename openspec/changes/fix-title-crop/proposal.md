# Proposal

## Why

M2 change 8 advances the labelled-corpus recognition criterion: five readable inspection titles are rejected as ambiguous because the raw-line OCR engine hallucinates characters in the crop's blank right margin. The 2026-10-17 offline run reproduces the failures, and a controlled comparison using the same bundled engine removes the trailing junk by trimming only that margin (see [evidence.md](evidence.md)).

## What Changes

- Trim the thresholded title image to its rightmost foreground pixel plus a small bounded margin before OCR, preserving all rendered text and internal spaces.
- Store the image actually sent to OCR in evidence, subject to the existing preview byte limit.
- Prove the crop rule with small synthetic images and fake-runtime job tests, then compare the complete 50-case local corpus against the saved pre-change report: coverage must improve, existing correct items must remain correct, and no new false-positive case may appear.
- Keep marker, title similarity, ambiguity and quantity gates unchanged. Targeted capture placement/timing remains M4 work. Catalog duplicate/preset identity policy is outside this change; the four existing wrong accepts remain visible in qualification.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `inspection-recognition`: bound the blank right margin of the normalised title image before OCR and expose that same image as evidence.

## Impact

- Recognition preprocessing in `lib/data/vision/inspection_recognition.dart` and a pure crop helper alongside the vision image/geometry code.
- Synthetic unit tests and fake-runtime job integration tests under `test/data/vision/`; an offline qualification comparison over the user's local corpus.
- No new dependencies, native API changes, persisted data changes or user controls. Screenshots, catalogue snapshot and full reports stay outside Git.
