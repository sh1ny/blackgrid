# Proposal

## Why

Milestone **M2 - capture/recognition proof** needs item recognition primitives (OpenCV template matching and image operations, Tesseract OCR with a traineddata model) packaged inside the Release bundle before any recognition pipeline can be built on them. This is change 1 of 5. It advances these M2 exit criteria:

- *Binaries and traineddata have source, version and terms in `THIRD_PARTY_NOTICES.md` before they enter a build* (agent).
- *The Release bundle contains every native DLL and model it needs, each hash-bound and loaded from the bundle, with no system installation; an offline bundle integrity check passes* (agent).
- It also gives the user a way to run the check *the same bundle launches and recognises on a clean Windows machine* (user), before the Scanner slice exists.

Today Blackgrid has no OpenCV or Tesseract code, no item OCR model, and no bundle integrity check (`openspec/architecture.md:60`). The only hash-bound native file is the panel OCR DLL.

## What Changes

- **Owned vision primitives DLL.** Add `blackgrid_vision.dll`, built by the Windows CMake project.
  - It statically links OpenCV 4.13 `core` and `imgproc`, built from a source archive pinned by SHA-256. The version matches the reference fork's OpenCvSharp 4.13.0.
  - It exports only a small, versioned C ABI with the primitives the reference pipeline uses: grayscale conversion, resize (cubic/area), binary-inverse threshold, normalized cross-correlation template match with best location and score, and a bounded colour-range row scan.
  - It contains no matching, scheduling or recognition policy.
- **Tesseract runtime, matching the fork.**
  - Ship `tesseract50.dll` (Tesseract engine 5.0.0) and `leptonica-1.82.0.dll` (Leptonica 1.82.0), extracted from the pinned charlesw `Tesseract` 5.2.0 NuGet package. The package version and the engine version differ; the lock records both, and the runtime checks the engine version.
  - Ship tessdata_fast 4.1.0 `eng.traineddata` (SHA-256 `7d4322bd…70b2`).
  - Add an owned minimal Tesseract C-API `dart:ffi` binding (create, init LSTM-only, set page segmentation mode to raw line, set image from an owned buffer, recognise, read text, free text, end and delete).
- **Pinned acquisition.**
  - A committed lock file records the URL, version, size, SHA-256 and license of every third-party input.
  - A fetch tool downloads each input into a gitignored cache and refuses any file whose hash does not match.
  - The CMake configure step refuses unverified inputs.
- **Hash-bound loading from the bundle.**
  - Each installed vision file gets a build-bound SHA-256 binding, following the panel OCR pattern.
  - The Dart loader checks every binding and the vision ABI version before it opens any library, and loads only by absolute path from the application directory.
  - Failures are typed (missing file, hash mismatch, ABI mismatch, load failure, model missing, engine init failure); they are never thrown into callers.
- **App-local Visual C++ runtime.** Today's Release bundle already depends on a system install:
  - `blackgrid.exe` and `blackgrid_panel_ocr.dll` import `MSVCP140`, `VCRUNTIME140` and `VCRUNTIME140_1`;
  - the panel DLL's static-CRT setting is silently ignored, because the root CMake project predates policy CMP0091;
  - the charlesw Tesseract build also needs the Visual C++ runtime.

  The fix is to install the Visual C++ runtime DLLs app-locally from the build toolchain's redistributable directory, and to set CMP0091 so per-target CRT settings take effect.
- **UTF-8 active code page.** `tesseract50.dll` opens its model through narrow-character file APIs only. The runner manifest gains `<activeCodePage>UTF-8</activeCodePage>`, so a bundle under a non-ASCII path (for example a Cyrillic Windows profile name) still loads the model.
- **Offline bundle integrity check.** A tool and a qualification test inspect a Release bundle:
  - every expected DLL and model is present and matches its binding and pinned hash;
  - no unexpected DLL is present;
  - every DLL's imports resolve to the bundle or to Windows system libraries;
  - every third-party file has a matching `THIRD_PARTY_NOTICES.md` entry.
- **Vision self-check mode.** `blackgrid.exe --vision-self-check <report-path>` performs these steps without showing a window:
  - verifies and loads the runtime;
  - runs template matching and OCR on a sample bundled with the app;
  - writes a JSON report and exits with a status code.
  The user runs it on a clean machine. The normal app launch does not load the vision runtime.
- **Notices.** Add `THIRD_PARTY_NOTICES.md` entries for OpenCV 4.13 (Apache-2.0), the Tesseract 5.0.0 engine as built in the charlesw `Tesseract` 5.2.0 package (Apache-2.0), Leptonica 1.82.0 (BSD-2-Clause style) and tessdata_fast 4.1.0 `eng.traineddata` (Apache-2.0), each with source, version, SHA-256 and verbatim terms.
  - The Microsoft Visual C++ runtime notice records the redistributable version and the terms (Distributable Code under the Visual Studio license), without a SHA-256. These DLLs come from the build toolchain, and the integrity check enforces a committed minimum file version instead.
  - These entries go in before the binaries enter a build.

Out of scope:
- The warm vision worker isolate, request admission and duration bounds (change 3).
- Marker templates, title ROI geometry, OCR normalisation and catalog matching (change 4).
- Capture (change 2) and Scanner UI (change 5).
- Panel OCR, which stays on Windows.Media.Ocr (ADR-0006).

## Capabilities

### New Capabilities
- `vision-runtime`: the app-local item vision runtime. Covers which native libraries and model it consists of, how they are verified and loaded from the bundle, the primitive operations it exposes, typed availability and failures, and the self-check mode.
- `release-bundle-integrity`: the offline check over a built Release bundle. Covers inventory, hash bindings, pinned third-party hashes, import resolution without system installs, and notice coverage for third-party native files.

### Modified Capabilities
None. No main specs exist yet.

## Impact

- **Native build:**
  - new `windows/vision/` CMake subproject and C++ source;
  - `windows/CMakeLists.txt` install and hash-binding steps, next to the panel OCR at `windows/CMakeLists.txt:90-99`;
  - first builds compile OpenCV `core` and `imgproc` from source, which takes minutes, after which the build cache is reused;
  - the build needs network once, to fetch inputs; the app never does.
- **Dart:**
  - new vision runtime loader and bindings under `lib/data/`;
  - `lib/main.dart` gains a self-check entry path before `runApp`;
  - no UI change.
- **Tooling:**
  - a third-party lock file and fetch tool;
  - a bundle integrity tool;
  - `mise` tasks to fetch and check;
  - `.gitignore` entry for the input cache.
- **Tests:**
  - fast-tier tests for the loader's verification order and typed failures, using fake files;
  - qualification-tier tests against a built Release bundle, using the existing `BLACKGRID_*` env-var pattern.
- **Bundle size:** about +7 MB for Tesseract and Leptonica, +4 MB for the model, and a few MB for the vision DLL.
- **Docs:**
  - `THIRD_PARTY_NOTICES.md`;
  - an ADR recording the owned vision DLL and pinned third-party runtime decision;
  - the `openspec/architecture.md` component table, ADR index and resource bounds.
- **ADRs constraining this change:**
  - 0004: blocking native work belongs to a worker isolate. This change adds no UI-isolate native call path; the worker comes in change 3.
  - 0006: panel OCR is separate from item OCR.
  - 0007: standalone hash-bound FFI DLLs built by the Windows CMake; no plugin packages.
