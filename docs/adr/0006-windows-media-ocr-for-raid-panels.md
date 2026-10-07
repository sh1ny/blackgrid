# 0006 - Windows.Media.Ocr for Map-owned raid-panel OCR

- Status: accepted
- Date: 2026-10-07 (M5, PR #7)
- Source: [implementation strategy §5](../IMPLEMENTATION_STRATEGY.md#session-evidence-and-saved-pins), [§11](../IMPLEMENTATION_STRATEGY.md#11-migration-plan); [M5 status](../qualification/m5/STATUS.md#parity-decisions-2026-10-07)

## Context and problem

Map highlights raid exits read from the extract panel in saved game screenshots. The reference companions use Windows.Media.Ocr for this. Item recognition is a separate, later pipeline (OpenCV + Tesseract, M2). The strategy had left the panel backend open.

## Decision

The user decided this on 2026-10-07, for functional parity with their reference fork.

- **Panel OCR uses Windows.Media.Ocr**, called unpackaged as the reference does. It lives in `blackgrid_panel_ocr.dll` (`windows/ocr/panel_ocr.cpp`: C++/WinRT, static CRT, x64).
- **Binding.** Dart loads the DLL through `dart:ffi`. Before `DynamicLibrary.open` it checks the install-time `.sha256` binding and an ABI version (`lib/data/raid_panel_ocr.dart:188-206`; `windows/CMakeLists.txt:90-98`).
- **Pipeline (Dart).** Resolution profiles, panel location and crop, retry, parse, and current-map matching run in Dart. A name matches by normalised equality or containment, directional word overlap ≥0.72, or similarity ≥0.78. Strongest-match selection rejects ties, and a raw-text supplement applies additional rules (`lib/domain/raid_panel_text_parser.dart`; `lib/domain/raid_exfil_matcher.dart:106-114,145-176,190-275`).
- **Ownership.** The feature belongs to Map and has no Scanner dependency.

## Rejected alternative

- **Tesseract for panels as well,** sharing the future item-OCR engine. It was prototyped and archived unshipped. It added packaging and model risk ahead of Scanner and diverged from the reference.

## Consequences

- **Two OCR engines will coexist** once item recognition lands.
- **Unsupported configuration.** Microsoft documents package identity as the supported setup; the user accepts the unpackaged call.
- **No timeout.** The OCR call has no duration bound (ADR-0004).
- **Unverified on real panels.** Accuracy on real saved panels is a user check, still pending.
- **Reversal cost: low-medium.** The engine sits behind one FFI module and one Dart adapter; the parser and matcher are engine-independent.
