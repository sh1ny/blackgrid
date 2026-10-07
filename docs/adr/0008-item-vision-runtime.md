# 0008 - Item vision runtime: owned primitives DLL, pinned third-party OCR binaries, app-local Visual C++ runtime, UTF-8 code page

- Status: accepted
- Date: 2026-10-08 (M2 change `add-native-vision-runtime`)
- Supersedes: none
- Source: [design](../../openspec/changes/add-native-vision-runtime/design.md) D1, D2, D3, D6, D7; [implementation strategy §6](../IMPLEMENTATION_STRATEGY.md#6-scanner-strategy)

## Context and problem

Item recognition (M2/M4) needs OpenCV template matching and image operations, plus Tesseract OCR with an English model, packaged inside the Release bundle. The reference fork uses OpenCvSharp 4.13.0, the charlesw `Tesseract` 5.2.0 NuGet package (Tesseract engine 5.0.0, Leptonica 1.82.0) and tessdata_fast 4.1.0 `eng.traineddata`. The bundle must load these with no machine-wide installation, and every third-party binary must be pinned and covered by notices before it enters a build. The existing Release bundle already depended on a system-installed Visual C++ runtime without declaring it: CMake policy CMP0091 was OLD, so the panel OCR DLL's static-CRT setting was ignored.

## Decision

- **Owned `blackgrid_vision.dll`** (`windows/vision/`). It statically links OpenCV 4.13.0 `core` and `imgproc`, built through `ExternalProject_Add` from a SHA-256-pinned source archive with every downloading or unneeded component off. It exports a small, versioned `bgv_*` C ABI over caller-owned buffers only (`bgv_abi()` carries the version). Release and Profile link a Release (`/MT`) OpenCV build; Debug links a separate Debug (`/MTd`) build. It contains no recognition policy.
- **Pinned third-party OCR binaries.** `tesseract50.dll` (engine 5.0.0) and `leptonica-1.82.0.dll` (Leptonica 1.82.0) are extracted from the charlesw `Tesseract` 5.2.0 nupkg; the model is tessdata_fast 4.1.0 `eng.traineddata`. The package and engine versions differ, and both are recorded. An owned minimal Tesseract C-API `dart:ffi` binding uses LSTM-only mode and raw-line segmentation, matching the fork.
- **Lock and install-manifest binding.** `windows/vision/third_party.lock.json` is the sole committed authority for third-party inputs (URL, version, size, SHA-256, license, notice anchor). A fetch tool caches only verified files, and CMake refuses unverified inputs. At install, CMake writes one `data/vision/runtime.manifest.json` (ABI, engine version, SHA-256 and size of every vision file). The Dart loader verifies every file against it before opening any library. Like the panel OCR binding, this proves the bundle matches its build; it is not tamper-proof.
- **Bundle-only load order.** The loader opens `leptonica-1.82.0.dll`, then `tesseract50.dll`, then `blackgrid_vision.dll`, each by absolute path inside the executable's directory, and passes the model directory explicitly. It does not change the process DLL search policy (`SetDefaultDllDirectories`/`AddDllDirectory`), and it ignores `PATH`, the working directory and `TESSDATA_PREFIX`.
- **App-local Visual C++ runtime as a bundle-wide rule.** `windows/CMakeLists.txt` sets `cmake_policy(SET CMP0091 NEW)` before `project()`, so per-target static CRT takes effect. `msvcp140.dll`, `vcruntime140.dll` and `vcruntime140_1.dll` (the import check extends the list if needed) are installed app-locally from the build toolchain through `InstallRequiredSystemLibraries`. They are not pinned by hash; the offline integrity check enforces a committed minimum file version instead.
- **UTF-8 active code page.** `tesseract50.dll` opens its model only through narrow `char*` paths. `windows/runner/runner.exe.manifest` declares `<activeCodePage>UTF-8</activeCodePage>`, and the binding passes the datapath as UTF-8. This is process-wide: every `-A` API and narrow CRT call in `blackgrid.exe` interprets strings as UTF-8. Flutter, Dart and the runner use wide APIs or explicit conversion, so nothing relied on the legacy ANSI code page.

## Rejected alternative

- **`dartcv4` native-assets package.** It brings a large Dart API for five calls and fetches OpenCV outside our pins (ADR-0007).
- **Prebuilt `opencv_world` DLL.** Tens of MB of unused modules, plus its CRT and ABI coupling.
- **Building Tesseract 5.5 and Leptonica from source.** A heavy build dependency, and it moves recognition away from the reference baseline.
- **Per-file `.sha256` sidecars.** Five independent bindings can be partially present or stale.
- **Process-wide DLL directories** (as the fork does). They also change resolution for Flutter, panel OCR and sqlite.
- **Requiring the Visual C++ redistributable on user machines.** It breaks "no system installation".

## Consequences

- **First builds compile OpenCV**, once per configuration family. `flutter clean` wipes both the build tree and the input cache, so `mise run vision:fetch` must run again.
- **Third-party bytes are reviewable.** Changing a binary is a lock edit plus a notices edit in the same commit, checked by the offline bundle integrity tool.
- **The panel OCR DLL now really uses static CRT**, so its hash changes once.
- **Native calls have no duration bound in this change.** The warm worker isolate with admission and duration bounds comes in change 3 (ADR-0004). Until then, only the self-check (under a watchdog) and tests load the runtime.
- **Reversal cost: medium** for the `bgv_*` ABI (changes 3 and 4 code against it); low for the binaries, the binding format and the code page.
