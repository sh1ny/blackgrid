# Tasks

**Test tiers:**
- **Fast:** `mise run test`. These use no native build: fake files, injected native-open seams and a local loopback HTTP server.
- **Qualification:** `@Tags(['qualification'])`, run with `mise run test:qualification`.
  - Needs `BLACKGRID_RELEASE_BUNDLE`, pointing at `build/windows/x64/runner/Release`. Without it, the tests skip, following the `test/qualification/m5_panel_ocr_test.dart:15-20` pattern.
  - CMake-script tests use `BLACKGRID_CMAKE`, set to a `cmake.exe` path.
  - Tests that start `blackgrid.exe` first confirm that Escape from Tarkov is not running. They check that `Get-Process EscapeFromTarkov -ErrorAction SilentlyContinue` returns nothing, and do nothing else with the game. If this cannot be confirmed, they skip and the result is recorded as unverified (AGENTS.md).

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| release-bundle-integrity → Third-party inputs are pinned | Verified input accepted | test/tool/vision/fetch_runtime_test.dart | `fetch places verified input in content-addressed cache` | green |
| release-bundle-integrity → Third-party inputs are pinned | Altered input refused | test/tool/vision/fetch_runtime_test.dart | `fetch refuses hash mismatch and leaves no cache file` | green |
| release-bundle-integrity → Third-party inputs are pinned | Altered input refused (build) | test/qualification/m2_vision_cmake_test.dart | `verify_inputs.cmake fails on altered cached input naming both hashes` | green |
| release-bundle-integrity → Third-party inputs are pinned | Input missing from the cache | test/qualification/m2_vision_cmake_test.dart | `verify_inputs.cmake fails on missing input naming mise run vision:fetch` | green |
| release-bundle-integrity → Bundle inventory is exact | Complete bundle passes inventory | test/tool/vision/check_bundle_test.dart | `inventory passes on synthetic complete bundle` | green |
| release-bundle-integrity → Bundle inventory is exact | Unexpected DLL | test/tool/vision/check_bundle_test.dart | `inventory fails naming unexpected dll` | green |
| release-bundle-integrity → Bundle inventory is exact | Missing expected file | test/tool/vision/check_bundle_test.dart | `inventory fails naming missing model` | green |
| release-bundle-integrity → Each runtime-verified file matches its binding and pin | Bindings and pins agree | test/tool/vision/check_bundle_test.dart | `hash step passes when manifest, sidecar and lock agree` | green |
| release-bundle-integrity → Each runtime-verified file matches its binding and pin | Binding disagrees with file | test/tool/vision/check_bundle_test.dart | `hash step fails naming file and both hashes` | green |
| release-bundle-integrity → Each runtime-verified file matches its binding and pin | Third-party file differs from pin | test/tool/vision/check_bundle_test.dart | `pin step fails when bound file diverges from lock` | green |
| release-bundle-integrity → Bundle needs no system installation | All imports resolved | test/tool/vision/pe_imports_test.dart | `imports resolve to bundle or allow-list` | green |
| release-bundle-integrity → Bundle needs no system installation | Import needs a system install | test/tool/vision/pe_imports_test.dart | `unresolved vcruntime import fails naming dll and import` | green |
| release-bundle-integrity → Bundle needs no system installation | Unreadable PE file | test/tool/vision/pe_imports_test.dart | `non-PE dll is reported unreadable` | green |
| release-bundle-integrity → App-local VC++ runtime minimum version | Runtime at or above minimum | test/tool/vision/pe_version_test.dart | `runtime version step passes and reports versions` | green |
| release-bundle-integrity → App-local VC++ runtime minimum version | Older toolchain runtime shipped | test/tool/vision/pe_version_test.dart | `runtime below minimum fails with actual and minimum` | green |
| release-bundle-integrity → App-local VC++ runtime minimum version | Version resource missing | test/tool/vision/pe_version_test.dart | `missing version resource fails as unreadable version` | green |
| release-bundle-integrity → Third-party native files are covered by notices | Notices complete | test/tool/vision/check_bundle_test.dart | `notices step passes with version url and sha per lock entry` | green |
| release-bundle-integrity → Third-party native files are covered by notices | Notice missing or stale | test/tool/vision/check_bundle_test.dart | `notices step fails naming component with stale sha` | green |
| release-bundle-integrity → Check is offline and reports results | Passing run | test/qualification/m2_bundle_integrity_test.dart | `real Release bundle passes every integrity step` | green |
| release-bundle-integrity → Check is offline and reports results | Bundle directory absent | test/tool/vision/check_bundle_test.dart | `absent bundle dir exits non-zero without pass report` | green |
| vision-runtime → Runtime files are verified before load | Intact bundle becomes ready | test/qualification/m2_vision_runtime_test.dart | `intact bundle opens ready with file identities` | green |
| vision-runtime → Runtime files are verified before load | Tampered library is refused before load | test/data/vision/vision_runtime_test.dart | `hash mismatch reports hashMismatch and never opens a library` | green |
| vision-runtime → Runtime files are verified before load | Missing model is refused | test/data/vision/vision_runtime_test.dart | `missing model reports missingFile` | green |
| vision-runtime → Runtime files are verified before load | Missing binding is refused | test/data/vision/vision_runtime_test.dart | `missing manifest reports missingFile naming binding` | green |
| vision-runtime → Runtime loads only from the bundle | Bundle path is used | test/qualification/m2_vision_runtime_test.dart | `loaded module paths are inside the bundle` | green |
| vision-runtime → Runtime loads only from the bundle | System installation is ignored | test/qualification/m2_vision_runtime_test.dart | `TESSDATA_PREFIX model is ignored when bundle model missing` | green |
| vision-runtime → Runtime loads only from the bundle | Relative path override is rejected | test/data/vision/vision_runtime_test.dart | `relative runtime directory reports invalidPath` | green |
| vision-runtime → Vision ABI version is checked | Matching ABI | test/qualification/m2_vision_runtime_test.dart | `identity reports vision abi and pinned engine version` | green |
| vision-runtime → Vision ABI version is checked | ABI mismatch | test/data/vision/vision_runtime_test.dart | `abi mismatch reports expected and actual and closes libraries` | green |
| vision-runtime → Vision ABI version is checked | Engine version differs from pin | test/data/vision/vision_runtime_test.dart | `engine version mismatch reports abiMismatch for OCR engine` | green |
| vision-runtime → OCR engine initialises with reference settings | Engine initialises | test/qualification/m2_vision_runtime_test.dart | `engine reports eng, LSTM-only and raw-line` | green |
| vision-runtime → OCR engine initialises with reference settings | Bundle under a non-ASCII path | test/qualification/m2_vision_runtime_test.dart | `bundle copied under Cyrillic path opens ready` | red |
| vision-runtime → OCR engine initialises with reference settings | Corrupt model fails initialisation | test/qualification/m2_vision_runtime_test.dart | `bound truncated model reports engineInitFailed` | green |
| vision-runtime → Image primitives operate on caller-owned buffers | Template found in sample | test/qualification/m2_vision_runtime_test.dart | `template crop matches at its location with score >= 0.99` | green |
| vision-runtime → Image primitives operate on caller-owned buffers | Malformed buffer rejected | test/data/vision/vision_image_test.dart | `short stride or buffer is invalidImage before native call` | green |
| vision-runtime → Image primitives operate on caller-owned buffers | Template larger than image | test/data/vision/vision_image_test.dart | `template larger than image is invalidImage` | green |
| vision-runtime → Image primitives operate on caller-owned buffers | Colour scan with no match | test/qualification/m2_vision_runtime_test.dart | `row scan without match returns none` | green |
| vision-runtime → OCR reads text from a caller-owned image | Sample title recognised | test/qualification/m2_vision_runtime_test.dart | `self-check title OCR equals expected text` | green |
| vision-runtime → OCR reads text from a caller-owned image | Blank image | test/qualification/m2_vision_runtime_test.dart | `white image OCR returns without failure` | green |
| vision-runtime → OCR reads text from a caller-owned image | Recognition after disposal | test/data/vision/vision_runtime_test.dart | `recognise after dispose returns disposed without native call` | green |
| vision-runtime → Disposal releases native resources once | Dispose after ready | test/data/vision/vision_runtime_test.dart | `dispose deletes engine and later calls return disposed` | green |
| vision-runtime → Disposal releases native resources once | Double dispose | test/data/vision/vision_runtime_test.dart | `second dispose is a no-op and delete ran once` | green |
| vision-runtime → Normal app launch does not load the runtime | Normal launch | test/app/launch_mode_test.dart | `no arguments selects UI mode and never constructs runtime` | green |
| vision-runtime → Normal app launch does not load the runtime | Unknown argument | test/app/launch_mode_test.dart | `unknown argument selects UI mode and never constructs runtime` | green |
| vision-runtime → Self-check mode reports readiness | Clean bundle passes | test/qualification/m2_vision_self_check_test.dart | `blackgrid.exe self-check on Release bundle exits 0 with pass report` | red |
| vision-runtime → Self-check mode reports readiness | Broken bundle fails visibly | test/qualification/m2_vision_self_check_test.dart | `self-check on bundle copy without model exits 1 naming model` | red |
| vision-runtime → Self-check mode reports readiness | Native step does not return | test/application/vision_self_check_test.dart | `blocking stub step yields timeout report and code 3` | green |
| vision-runtime → Self-check mode reports readiness | Report path missing or unwritable | test/application/vision_self_check_test.dart | `missing path or directory returns code 2 before loading` | green |
| vision-runtime → Self-check report is complete and authoritative | Report contents | test/application/vision_self_check_test.dart | `report has format identity steps and result mirroring code` | green |
| vision-runtime → Self-check report is complete and authoritative | Report never partially written | test/application/vision_self_check_test.dart | `report is written to tmp then renamed; previous report survives a failed write` | green |

## 1. Decision records, notices and pins (before any binary enters a build)

- [x] 1.1 Write `docs/adr/0008-item-vision-runtime.md` in MADR-short form (Status Accepted, Date, Supersedes none). It records design D1, D2, D3, D6 and D7: owned `blackgrid_vision.dll`, the charlesw package 5.2.0 with engine 5.0.0 and Leptonica 1.82.0, the lock and install-manifest binding, bundle-only load order, app-local Visual C++ runtime, and the UTF-8 active code page with its process-wide effect. Update `openspec/architecture.md`: component table, the "Not built yet" line (`:60`), resource bounds (image caps; no per-call timeout until change 3), the packaging row and the ADR index. Verify: the ADR file exists and the index row links it.
- [x] 1.2 Download, outside the repo and into a scratch directory, the OpenCV 4.13.0 tag archive (from both `github.com/opencv/opencv/archive/refs/tags/4.13.0.zip` and `codeload.github.com`), the `Tesseract` 5.2.0 nupkg, and tessdata_fast 4.1.0 `eng.traineddata`. Record each SHA-256 and size. Cross-check the extracted `x64/tesseract50.dll` and `x64/leptonica-1.82.0.dll` hashes against the fork's `Assets/Scanner/rat-eye-integrity.json`, and the traineddata against `7d4322bd…70b2`. Confirm the engine version string, which is expected to be `tesseract 5.0.0`. Verify: both archive downloads hash identically, and the extracted hashes equal the fork manifest. Record the hashes in the PR.
- [x] 1.3 Write `windows/vision/third_party.lock.json` (format 1) from task 1.2: `id`, `version`, `packageVersion`/`engineVersion` for Tesseract, `url`(s), `sha256`, `size`, `license`, `noticeAnchor`, and `extractFrom`/`path` for nupkg members. Verify: the file parses and every value matches task 1.2's record.
- [x] 1.4 Add the `THIRD_PARTY_NOTICES.md` section "M2 item vision runtime":
  - OpenCV 4.13.0 (Apache-2.0);
  - the Tesseract 5.0.0 engine as built in charlesw `Tesseract` 5.2.0 (Apache-2.0);
  - Leptonica 1.82.0 (its BSD-style license);
  - tessdata_fast 4.1.0 `eng.traineddata` (Apache-2.0);
  - the Microsoft Visual C++ runtime (redistributable version and Distributable Code terms, no SHA-256);
  - `package:archive` (pinned dev dependency).

  Each entry carries its anchor, version, URL, SHA-256 and verbatim terms. Verify: for every lock entry, the notices text contains its version, URL and SHA-256 (the same check task 6.3 automates).

## 2. Pinned fetch tool

- [x] 2.1 Write failing tests in `test/tool/vision/fetch_runtime_test.dart` against a loopback `HttpServer` serving fixture bytes: `fetch places verified input in content-addressed cache` and `fetch refuses hash mismatch and leaves no cache file`. Also add an extra test for the size cap and timeout abort, and one for nupkg member extraction with per-member pin checks. Verify: they fail because the tool does not exist.
- [x] 2.2 Implement `tool/vision/fetch_runtime.dart`: read the lock, download over HTTPS with a 120 s timeout and the size cap, check the SHA-256, write a temp file and rename it into `.dart_tool/blackgrid_vision_inputs/<sha256>/<name>`, and extract nupkg members with `package:archive` (add it as a pinned dev dependency). Add the mise task `vision:fetch`. Verify: the task 2.1 tests pass and their test-map rows go green; `mise run vision:fetch` populates the cache with every lock entry.

## 3. Native build: inputs, OpenCV, vision DLL, install, runtime libraries

- [x] 3.1 Write `windows/vision/verify_inputs.cmake`, a script usable by `include()` and by `cmake -P`, which reads the lock with `string(JSON)` and `file(SHA256)`-checks each cached input. Write failing tests in `test/qualification/m2_vision_cmake_test.dart` (gated on `BLACKGRID_CMAKE`): `verify_inputs.cmake fails on altered cached input naming both hashes` and `verify_inputs.cmake fails on missing input naming mise run vision:fetch`, plus a passing-case test. Verify: they fail first, then pass after the script is completed; the rows go green.
- [x] 3.2 Set `cmake_policy(SET CMP0091 NEW)` before `project()` in `windows/CMakeLists.txt`. Verify: after a Release build, the PE imports of `blackgrid_panel_ocr.dll` no longer include `MSVCP140`, `VCRUNTIME140` or `VCRUNTIME140_1`, and the M5 qualification test `test/qualification/m5_panel_ocr_test.dart` still passes with `BLACKGRID_PANEL_OCR_RUNTIME` set.
- [x] 3.3 Add `windows/vision/CMakeLists.txt` with the OpenCV 4.13.0 `ExternalProject_Add`:
  - source: the verified cached archive, re-checked against the lock SHA-256 whenever the download step extracts it, and extracted once into a content-addressed directory shared by every configuration; build and install directories are keyed by the same hash (design D1);
  - modules and options: `BUILD_LIST=core,imgproc`, static libraries, `BUILD_WITH_STATIC_CRT=ON`, and IPP, OpenCL, ADE, Eigen, ITT, protobuf, image codecs, tests, apps and bindings all off;
  - configurations: separate Release (`/MT`, used by Release and Profile) and Debug (`/MTd`) install prefixes.

  Verify: `flutter build windows --release` and `flutter build windows --debug` both complete, the OpenCV configure log shows no download, and the build times are recorded for the PR.
- [x] 3.4 Implement `windows/vision/vision.cpp`, the `bgv_*` C ABI from design D4. It uses caller-owned buffers only, wraps them in `cv::Mat` headers without copying, checks the size, channel and stride caps natively, catches every C++ exception at the boundary, maps errors to negative status codes, and provides `bgv_abi()`. Build it as `blackgrid_vision.dll` (x64, C++20, static CRT, `/W4 /EHsc /permissive-`). Verify: the Release build produces the DLL, and its PE exports list exactly the `bgv_*` functions.
- [x] 3.5 Install into the bundle:
  - into the exe directory: `blackgrid_vision.dll`, plus `tesseract50.dll` and `leptonica-1.82.0.dll` from the verified cache;
  - into `data/vision/tessdata/`: `eng.traineddata`;
  - into `data/vision/self_check/`: the sample from task 5.1;
  - the app-local Visual C++ runtime, through `InstallRequiredSystemLibraries` with `CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP` and filtered to the committed name list;
  - finally an `install(CODE)` step that writes `data/vision/runtime.manifest.json` (format, abi, engineVersion, files with SHA-256 and size).

  Verify: after a Release build, the manifest lists every vision file and each hash equals `Get-FileHash` of the installed file.
- [x] 3.6 Add `<activeCodePage>UTF-8</activeCodePage>` to `windows/runner/runner.exe.manifest`. Verify: the Release exe's embedded manifest contains it (`mt.exe -inputresource` or a PE resource read), and `mise run test` still passes. Runtime coverage is task 4.4's non-ASCII row.

## 4. Dart vision runtime and bindings

- [x] 4.1 Write failing fast tests in `test/data/vision/vision_image_test.dart` (`short stride or buffer is invalidImage before native call`, `template larger than image is invalidImage`, plus the 8192 px and 24 MPix caps). Then implement `lib/data/vision/vision_image.dart` (a caller-owned image descriptor with validation). Verify: the tests pass and the rows go green.
- [x] 4.2 Write failing fast tests in `test/data/vision/vision_runtime_test.dart` against a temp runtime directory with fake files and an injected native-open seam that records calls:
  - `hash mismatch reports hashMismatch and never opens a library`;
  - `missing model reports missingFile`;
  - `missing manifest reports missingFile naming binding`;
  - `relative runtime directory reports invalidPath`;
  - `abi mismatch reports expected and actual and closes libraries`;
  - `engine version mismatch reports abiMismatch for OCR engine`;
  - `recognise after dispose returns disposed without native call`;
  - `dispose deletes engine and later calls return disposed`;
  - `second dispose is a no-op and delete ran once`.

  Verify: they fail because the runtime does not exist.
- [x] 4.3 Implement `lib/data/vision/`:
  - `vision_runtime.dart`: sealed `VisionRuntimeStatus` and `VisionFailure`, and the load order from design D5/D6 (manifest, hashes, leptonica → tesseract → vision by absolute path, ABI and engine version from the manifest, engine init with an explicit UTF-8 datapath, LSTM-only and raw line, close in reverse order on failure and on dispose);
  - `tesseract_binding.dart`: the function set from design D2, with `TessDeleteText` and `Clear` always run, and the 64 KiB text cap;
  - `vision_primitives.dart`: `bgv_*` lookups with Dart-allocated output buffers.

  Verify: the task 4.2 tests pass and their rows go green, and `mise run analyze` is clean.
- [x] 4.4 Write `test/qualification/m2_vision_runtime_test.dart` (gated on `BLACKGRID_RELEASE_BUNDLE`, loading in the test process; no app launch) with:
  - `intact bundle opens ready with file identities`;
  - `loaded module paths are inside the bundle` (through `GetModuleFileNameW`);
  - `TESSDATA_PREFIX model is ignored when bundle model missing` (on a temp bundle copy);
  - `identity reports vision abi and pinned engine version`;
  - `engine reports eng, LSTM-only and raw-line`;
  - `bundle copied under Cyrillic path opens ready`;
  - `bound truncated model reports engineInitFailed` (a temp copy with a regenerated manifest);
  - `template crop matches at its location with score >= 0.99`;
  - `row scan without match returns none`;
  - `self-check title OCR equals expected text`;
  - `white image OCR returns without failure`.

  The test process is not `blackgrid.exe` and has no UTF-8 manifest. The Cyrillic case therefore runs through the self-check exe in task 5.5 when the test runner cannot show it; record which path covered it. Verify: with the Release bundle from group 3, all tests pass and the rows go green.

## 5. Self-check sample, runner and entry dispatch

- [x] 5.1 Write `tool/vision/make_self_check_sample.dart`. It renders a fixed title string with a font whose license permits redistributing rendered output, writes `assets/vision/self_check/title.gray` (raw 8-bit, no codec) and `title.json` (w, h, stride, expected text, template rect), and adds the font's notice to `THIRD_PARTY_NOTICES.md`. Verify: running the tool twice produces byte-identical files (`Get-FileHash`), and the notice entry exists.
- [x] 5.2 Write failing fast tests in `test/application/vision_self_check_test.dart` that use an injected runtime factory and a stub that blocks:
  - `blocking stub step yields timeout report and code 3` (with an injectable watchdog duration);
  - `missing path or directory returns code 2 before loading`;
  - `report has format identity steps and result mirroring code`;
  - `report is written to tmp then renamed; previous report survives a failed write`.

  Verify: they fail first.
- [x] 5.3 Implement `lib/application/vision_self_check.dart` with `runVisionSelfCheck(args)` returning the exit code. It validates usage, then runs verify, load, match, OCR and dispose in `Isolate.spawn` with progress messages, a 60 s watchdog, report format 1 written to tmp and renamed, and the datapath named on `engineInitFailed`. Its help text documents the `Start-Process -Wait -PassThru` and `start /wait` invocations. Verify: the task 5.2 tests pass and the rows go green.
- [x] 5.4 Write failing tests in `test/app/launch_mode_test.dart` (`no arguments selects UI mode and never constructs runtime`, `unknown argument selects UI mode and never constructs runtime`, plus a self-check selection test). Then change `lib/main.dart` to `main(List<String> args)`, which resolves the launch mode before `WidgetsFlutterBinding.ensureInitialized()`. In self-check mode it calls `exit(await runVisionSelfCheck(...))`; otherwise the existing `runApp` path stays unchanged. Verify: the tests pass, the rows go green, and `mise run test` passes.
- [ ] 5.5 Write `test/qualification/m2_vision_self_check_test.dart`, gated on `BLACKGRID_RELEASE_BUNDLE` and on the game-not-running confirmation above. It starts `blackgrid.exe --vision-self-check <tmp>` with a wait and covers:
  - `blackgrid.exe self-check on Release bundle exits 0 with pass report`;
  - `self-check on bundle copy without model exits 1 naming model`;
  - the same run from a bundle copied under a Cyrillic directory name, as an extra test.

  Verify: confirm Escape from Tarkov is not running, then run; the tests pass and the rows go green. If that cannot be confirmed, record them as unverified.

## 6. Offline bundle integrity check

- [x] 6.1 Write failing tests in `test/tool/vision/pe_imports_test.dart` and `test/tool/vision/pe_version_test.dart`. They use minimal PE32+ images generated by a test helper (`test/support/pe_builder.dart`) with import, delay-import and version resources:
  - `imports resolve to bundle or allow-list`;
  - `unresolved vcruntime import fails naming dll and import`;
  - `non-PE dll is reported unreadable`;
  - `runtime version step passes and reports versions`;
  - `runtime below minimum fails with actual and minimum`;
  - `missing version resource fails as unreadable version`.

  Verify: they fail first.
- [x] 6.2 Implement `tool/vision/pe.dart`, a PE32+ reader for headers, sections, import and delay-import directories, and `VS_FIXEDFILEINFO`. Add `tool/vision/system_allowlist.json` (Windows system DLLs including `KERNEL32`, `USER32`, `GDI32`, `WS2_32`; `api-ms-win-*` and `ext-ms-*` by prefix; no Visual C++ runtime names). Verify: the task 6.1 tests pass and the rows go green.
- [x] 6.3 Write failing tests in `test/tool/vision/check_bundle_test.dart` over synthetic bundle directories:
  - `inventory passes on synthetic complete bundle`;
  - `inventory fails naming unexpected dll`;
  - `inventory fails naming missing model`;
  - `hash step passes when manifest, sidecar and lock agree`;
  - `hash step fails naming file and both hashes`;
  - `pin step fails when bound file diverges from lock`;
  - `notices step passes with version url and sha per lock entry`;
  - `notices step fails naming component with stale sha`;
  - `absent bundle dir exits non-zero without pass report`.

  Then implement `tool/vision/check_bundle.dart` and `tool/vision/bundle_inventory.json` (the expected files, plus the Visual C++ runtime names with committed minimum versions), with steps inventory, bindings, pins, imports, runtime versions and notices, a JSON report, and no network. Add the mise task `bundle:check`. Verify: the tests pass and the rows go green.
- [x] 6.4 Write `test/qualification/m2_bundle_integrity_test.dart` (gated on `BLACKGRID_RELEASE_BUNDLE`): `real Release bundle passes every integrity step`. Verify: after a fresh `flutter build windows --release`, the test and `mise run bundle:check -- build/windows/x64/runner/Release` both pass with network disabled or unused, and the row goes green. If imports reveal another needed runtime DLL, extend the D7 name list and the inventory, then re-run.

## 7. Integration and exit-criteria evidence

- [ ] 7.1 From a clean tree, run `mise run vision:fetch`, `flutter build windows --release`, `mise run bundle:check -- build/windows/x64/runner/Release`, `mise run analyze`, `mise run test`, and `mise run test:qualification` with `BLACKGRID_RELEASE_BUNDLE`, `BLACKGRID_CMAKE` and `BLACKGRID_PANEL_OCR_RUNTIME` set. The app-launching tests run only after the game-not-running confirmation. Verify: every command exits 0 and every test-map row is green; record the outputs and the bundle size delta in the PR.
- [ ] 7.2 Record the M2 exit-criteria evidence in the PR description:
  - notices recorded before binaries enter the build (agent, tasks 1.4 and 6.3);
  - the bundle integrity check passes (agent, task 7.1).

  Hand the user the clean-machine self-check procedure: copy `build/windows/x64/runner/Release` to a clean Windows x64 machine and run `$p = Start-Process -Wait -PassThru .\blackgrid.exe -ArgumentList '--vision-self-check','C:\temp\vision.json'; $p.ExitCode`. Record that criterion as unverified until the user reports the result. Verify: the PR description lists each criterion with its evidence or its unverified status.

## Workflow follow-up

- After merge, `specwright-finish` handles archive; then `specwright-roadmap next` starts `add-windows-capture-boundary` (change 2) or `add-vision-worker` (change 3).
- The M2 clean-machine criterion stays open until the user runs the self-check and reports the result.
