# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Claude Code, specwright reviewer role)
- **Reviewed:** `proposal.md`, `specs/vision-runtime/spec.md`, `specs/release-bundle-integrity/spec.md`, `design.md` (TIER: FULL); `openspec/architecture.md`, `openspec/roadmap.md` (M2); ADRs 0004, 0006, 0007; `windows/CMakeLists.txt`, `windows/ocr/CMakeLists.txt`, `windows/runner/main.cpp`, `windows/runner/flutter_window.cpp`, `windows/runner/win32_window.cpp`, `windows/runner/utils.cpp`, `windows/runner/CMakeLists.txt`, `windows/runner/runner.exe.manifest`, `lib/main.dart`, `lib/data/raid_panel_ocr.dart`, `test/qualification/m5_panel_ocr_test.dart`, `THIRD_PARTY_NOTICES.md` (headings), `docs/IMPLEMENTATION_STRATEGY.md` §6, `docs/qualification/m0/u2-rights-decision-packet.md`, `mise.toml`, `.gitignore`. Reference fork (read-only): `Assets/Scanner/rat-eye-integrity.json`, `External/RatEye/RatEye/Processing/Inspection.cs:380-403`, `Services/Scanner/RatEyeRuntime.cs` (DLL directory calls), and the fork's built `x64/tesseract50.dll` / `x64/leptonica-1.82.0.dll` (SHA-256, PE imports and exports via `llvm-objdump -p`, embedded strings).
- **Re-check (Required Changes only):** a separate fresh-context reviewer subagent read the current `proposal.md`, `design.md`, `specs/vision-runtime/spec.md`, `specs/release-bundle-integrity/spec.md`, ADRs 0004, 0006 and 0007, `windows/runner/runner.exe.manifest` and `windows/runner/utils.cpp`. It did not rely on the Rebuttals notes. `openspec validate add-native-vision-runtime --strict` passes ("Change 'add-native-vision-runtime' is valid"). All 5 Required Changes are satisfied:
  - **C1 satisfied.** The spec "Vision ABI version is checked" names the pinned engine version (Tesseract 5.0.0 inside the charlesw 5.2.0 package). The "Matching ABI" scenario checks the pinned engine version, and a new failure scenario, "Engine version differs from pin", was added. D2 and D3 carry `packageVersion`/`engineVersion` in the lock and the manifest. D5 step 6 compares `TessVersion()` against the manifest's `engineVersion` without hard-coding it. The proposal Tesseract runtime and Notices bullets, the D2 title and the ADR-0008 title distinguish package 5.2.0 from engine 5.0.0 and Leptonica 1.82.0.
  - **M1 satisfied.** A new requirement, "Self-check report is complete and authoritative", makes `result` authoritative, has the exit code mirror it, and requires a whole-or-absent report ("Report never partially written" scenario). D9 adds the tmp-then-rename write, the `Start-Process -Wait -PassThru` and `start /wait` invocations, and a `runVisionSelfCheck` that returns the code with only `main` calling `exit`. The sequence diagram matches.
  - **M2 satisfied.** The D1 "Configuration mapping" says `Release` and `Profile` use the Release `/MT` prefix, `Debug` uses a separate Debug `/MTd` prefix, and each prefix is built once and reused. The Risks build-time entry states this behaviour.
  - **M3 satisfied, option (a).** The proposal Notices bullet records the redistributable version and terms without a SHA-256. D7 commits a minimum PE file version per runtime DLL in `bundle_inventory.json`, and D10 step 5 enforces it. The `release-bundle-integrity` spec adds "App-local Visual C++ runtime meets a committed minimum version" with pass, below-minimum and unreadable-version scenarios, and its notices requirement also requires a Visual C++ runtime entry.
  - **M4 satisfied, option (a).** The spec has the scenario "Bundle under a non-ASCII path". D6 adds `<activeCodePage>UTF-8</activeCodePage>` to the runner manifest, states the process-wide effect, and names the datapath on `engineInitFailed`. Flow & State Gaps has the matching entry with a Cyrillic-path qualification test, and ADR-0008 is set to record it. The current manifest has no `activeCodePage`, so this is a planned edit. D6's claim that the runner converts arguments with wide APIs holds (`windows/runner/utils.cpp:54-63` `WideCharToMultiByte(CP_UTF8, …)`).
  - **Consistency.** No contradiction was found with the other artifacts or with ADRs 0004, 0006 and 0007:
    - The self-check helper isolate adds no UI-isolate native call path, and the warm worker stays in change 3 (ADR-0004).
    - Panel OCR stays separate, and CMP0091 makes its static-CRT setting take effect as ADR-0006 describes.
    - The vision code remains a standalone hash-bound CMake-built FFI DLL with no plugin package (ADR-0007).

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

**C1. The charlesw `Tesseract` 5.2.0 package ships a Tesseract 5.0.0 engine, so the required `TessVersion() == "5.2.0"` check fails on every intact bundle.**
- Evidence: the fork's `x64/tesseract50.dll` has SHA-256 `de4d04ec…cb2b`, which matches `rat-eye-integrity.json` (the pin D2 cross-checks against). Its only embedded engine version string is the compile-time `TESSERACT_VERSION_STR` inside the hOCR renderer meta tag: `<meta name='ocr-system' content='tesseract 5.0.0' />`. The string `5.2.0` does not occur anywhere in the binary. `5.2.0` is the NuGet wrapper's version, not the native engine's.
- Affected text: spec `vision-runtime` "Vision ABI version is checked" ("SHALL check that the OCR engine reports version 5.2.0", and the "Matching ABI" scenario); design D5 step 6; the proposal "Notices" bullet and design D2/ADR-0008 wording "Tesseract 5.2.0".
- Consequence: as written, `VisionRuntime.open` returns `abiMismatch` on a correct bundle. The self-check then always exits 1, and the M2 clean-machine criterion cannot pass. Recording "Tesseract 5.2.0" in `THIRD_PARTY_NOTICES.md` would also misstate the engine version, which breaks the M2 exit criterion that source, version and terms are recorded correctly.

### Moderate

**M1. The self-check's exit-code contract cannot be observed the way a user normally runs it.**
- Evidence: `blackgrid.exe` is a GUI-subsystem executable (`windows/runner/CMakeLists.txt:9` `add_executable(... WIN32`, `wWinMain` in `main.cpp:8`). When a GUI executable is started directly from `cmd.exe` or PowerShell, the shell does not wait for it, and `%ERRORLEVEL%` / `$LASTEXITCODE` do not show its exit code. `AttachConsole(ATTACH_PARENT_PROCESS)` (`main.cpp:12`) then prints stderr after the prompt has already returned.
- Affected text: spec "Vision self-check mode reports bundle readiness" ("exit with code 0 only if every step passed") and D9 exit codes 0-3. These are presented as the user's pass/fail signal on the clean machine.
- Consequence: a user who types the documented command sees a return with no error, whatever happened. They can read a failed or still-running self-check as a pass, or read the report before it has been written. This is the one user-only M2 check this change enables.

**M2. The OpenCV `ExternalProject` build has no mapping for Flutter's multi-config build types.**
- Evidence: the root project defines `Debug;Profile;Release` (`windows/CMakeLists.txt:14-17`). OpenCV only knows Debug/Release, and D1 specifies only `BUILD_WITH_STATIC_CRT=ON`.
- Consequences:
  - The vision DLL in Debug (`/MTd`, `_ITERATOR_DEBUG_LEVEL=2`) cannot link against Release-built OpenCV static libraries. MSVC reports LNK2038 mismatch errors.
  - A `Profile` build passes a configuration OpenCV does not define.
  - Without an explicit mapping, either `flutter run` (Debug) and `flutter build windows --profile` break, or each configuration rebuilds OpenCV for minutes, which goes beyond the "first build only" cost the proposal states.
- The design states neither the mapping nor whether Debug builds the vision DLL at all.

**M3. The Visual C++ runtime is the one shipped third-party native file with no pin, no notice check and an unstable version, yet the proposal promises a notice entry with SHA-256.**
- Evidence:
  - The proposal "Notices" bullet records the Microsoft Visual C++ runtime "each with source, version, SHA-256 and verbatim terms".
  - D7 copies the DLLs from whichever Visual Studio toolchain runs the build (`InstallRequiredSystemLibraries`).
  - The `release-bundle-integrity` spec only records their SHA-256 in the report ("Each runtime-verified file…"). The notices requirement covers only files "in the lock file", and the runtime DLLs are not in the lock.
- Consequence:
  - Any Visual Studio update, or a different developer machine, changes the shipped `msvcp140.dll` / `vcruntime140*.dll` bytes and version. The notices entry's SHA-256 then goes stale silently, and the integrity check still passes.
  - `tesseract50.dll` imports `MSVCP140`, `VCRUNTIME140` and `VCRUNTIME140_1` (verified on the fork's binary). It therefore requires a runtime at least as new as the one it was built with (2022-era). An older toolchain's app-local copy would pass every check in this design and could still fail at load on a clean machine.

**M4. The Tesseract model path is opened with narrow-character file APIs, so a bundle under a non-ASCII path fails with `engineInitFailed`.**
- Evidence:
  - `tesseract50.dll` contains no `_wfopen` (verified). It imports only the narrow `api-ms-win-crt-stdio` / `filesystem` CRT, and it exports only `TessBaseAPIInit1-4`, all of which take `const char* datapath`.
  - D5 passes `datapath = <exe>/data/vision/tessdata`, which Dart would encode as UTF-8.
  - `windows/runner/runner.exe.manifest` declares no `<activeCodePage>UTF-8</activeCodePage>`, so the CRT interprets that path in the ANSI code page.
- Consequence: an app directory such as `C:\Users\<non-ASCII name>\…` makes initialisation fail. Neither the spec nor the Flow & State Gaps section mentions this. The failure is typed and visible, so the self-check will not report a false pass, but the clean-machine criterion fails for those users with no documented reason. The fork likely shares this limitation; per the project's fork-parity stance, recording it as a known limitation is an acceptable resolution.

### Suggestions

**S1. Spec "OCR engine initialises with the reference settings" needs functions D2 excludes.** Its "Engine initialises" THEN asserts that the engine reports language, OEM and PSM. D2 says the binding uses "only these functions", and that list lacks `TessBaseAPIGetInitLanguagesAsString`, `TessBaseAPIOem` and `TessBaseAPIGetPageSegMode`. All three are exported by the fork's `tesseract50.dll`. Add them to D2, or the THEN cannot be asserted.

**S2. The "Native step does not return" scenario cannot be tested as written.** D9 has `main` call `exit(3)`, and a test that calls `exit` kills the test runner. State in D9 that `runVisionSelfCheck` returns the exit code with an injectable step runner and that only `main` calls `exit`. Then the spec scenario can assert the returned code and the written report.

**S3. "The build needs network once" (proposal Impact) does not hold.** `flutter clean` deletes `.dart_tool/`, which wipes the input cache D8 places at `.dart_tool/blackgrid_vision_inputs/`. After any clean, the next build fails with `FATAL_ERROR` until the developer re-fetches. Either place the cache in a gitignored directory that `flutter clean` does not touch, or correct the claim.

**S4. The Mechanism Ledger overstates the CMake re-check.** It says the configure-time re-check stops cache tampering or stale files before install, but CMake configure re-runs only when its inputs change. Incremental builds install from the cache without re-hashing, and `install(CODE)` then binds whatever bytes were installed. The integrity check's lock-pin step still catches this afterwards. Either verify at install time (`install(CODE)` comparing against the lock) or reword the ledger row.

**S5. The OpenCV archive pin rests on GitHub archive stability.** If GitHub regenerates the tag archive (as happened in January 2023), the build fails closed for every developer. That is safe but disruptive. Record in the lock which URL is authoritative, and record the archive's tree/commit so the archive can be re-derived.

**S6. The second Open Question can be closed now.** On the fork's pinned bytes, `tesseract50.dll` imports `KERNEL32`, `WS2_32`, `MSVCP140`, `VCRUNTIME140`, `VCRUNTIME140_1`, `api-ms-win-crt-*` and `leptonica-1.82.0.dll`. `leptonica-1.82.0.dll` imports `GDI32`, `KERNEL32`, `USER32`, `VCRUNTIME140` and `api-ms-win-crt-*`. There is no OpenMP (`vcomp140`). The D7 list of three runtime DLLs is sufficient for Tesseract, and the allow-list needs `WS2_32`, `GDI32` and `USER32`.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **(C1)**
   - In `specs/vision-runtime/spec.md` "Vision ABI version is checked", replace "reports version 5.2.0" with the engine version actually embedded in the pinned `tesseract50.dll`. The fork's bytes show `5.0.0`; confirm it from `TessVersion()` at apply time. Make the same replacement in the "Matching ABI" scenario.
   - In design D5 step 6, compare against that value, and source it from the lock entry (for example an `engineVersion` field) rather than hard-coding it.
   - In `proposal.md` (Tesseract runtime and Notices bullets), design D2 and the ADR-0008 description, distinguish the charlesw `Tesseract` NuGet package 5.2.0 from the bundled Tesseract engine 5.0.0 and Leptonica 1.82.0. The notices entry must name the engine version.
2. **(M1)**
   - In the spec "Vision self-check mode reports bundle readiness", add a sentence that the report's `result` field is the authoritative outcome and that the report file is written last-and-complete. Keep the exit code as well.
   - In design D9, document the supported invocation that waits and shows the exit code (for example `Start-Process -Wait -PassThru blackgrid.exe -ArgumentList '--vision-self-check',<path>` and `$p.ExitCode`, or `start /wait` in `cmd`). Also have the report be written to a temporary file and renamed, so a partially written report is never read as a result.
3. **(M2)** In design D1, specify the configuration mapping:
   - OpenCV is built Release for the `Release` and `Profile` configurations.
   - OpenCV is built Debug (`/MTd`) for `Debug`, or the vision target is excluded from Debug builds, whichever the author chooses.
   - Each OpenCV configuration is built once and reused.

   Add the chosen behaviour to the Risks entry on build time.
4. **(M3)** Choose one option and state it in the proposal Notices bullet, D7 and the `release-bundle-integrity` spec:
   - (a) Make the Visual C++ runtime notice record the toolchain/redistributable version and terms without a SHA-256. Add an integrity-check step, with a failure scenario, that reads each shipped runtime DLL's PE file version and fails if it is older than a committed minimum. The minimum is the version `tesseract50.dll` requires, no older than the 2022-era toolset.
   - (b) Pin the runtime DLLs in the lock like the other third-party files, and extend the notices step to cover them.
5. **(M4)** Add a Flow & State Gaps entry and a spec scenario covering an application directory whose path contains non-ASCII characters. Choose one resolution and state it:
   - (a) Add `<activeCodePage>UTF-8</activeCodePage>` to `windows/runner/runner.exe.manifest`, so the narrow CRT `fopen` accepts UTF-8. Note the process-wide effect in D6/ADR-0008.
   - (b) Record it as a known limitation matching the fork. In that case, the self-check report must name the path when `engineInitFailed` occurs.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. A Critical/Moderate rebuttal counts only once marked "accepted by reviewer". -->

- **C1 fixed.**
  - spec: "Vision ABI version is checked" now names the pinned engine version (5.0.0 inside package 5.2.0), the "Matching ABI" scenario changed accordingly, and a new "Engine version differs from pin" scenario was added.
  - design: D2 (title, `packageVersion`/`engineVersion` in the lock, `TessVersion` confirmed when the lock is written), D3 (lock and manifest carry `engineVersion`) and D5 step 6 (compares against the manifest's `engineVersion`, nothing hard-coded).
  - proposal: the Tesseract runtime and Notices bullets.
  - ADR-0008 title.
- **M1 fixed.**
  - spec: a new requirement "Self-check report is complete and authoritative", with the scenarios "Report contents" and "Report never partially written". It was split out of the self-check requirement to stay under the 500-character limit.
  - design D9: tmp-then-rename write, `result` is authoritative, a documented `Start-Process -Wait -PassThru` / `start /wait` invocation, and `runVisionSelfCheck` returns the code with only `main` calling `exit` (covers S2). The sequence diagram is updated.
- **M2 fixed.**
  - design D1 "Configuration mapping": Release and Profile use the Release `/MT` prefix, Debug uses a separate Debug `/MTd` prefix, and each is built once and reused.
  - The Risks build-time entry is updated, including re-fetching after `flutter clean` (S3).
- **M3 fixed, option (a).**
  - spec: a new requirement "App-local Visual C++ runtime meets a committed minimum version" with 3 scenarios, and the notices requirement now also requires a Visual C++ runtime entry.
  - design: D7 (minimum version in `bundle_inventory.json`, no SHA-256) and D10 step 5 (runtime versions).
  - proposal: the Notices bullet.
  - S6 is folded into D7, and the OpenMP open question is removed.
- **M4 fixed, option (a).**
  - spec: scenario "Bundle under a non-ASCII path".
  - design D6: `<activeCodePage>UTF-8</activeCodePage>` in `runner.exe.manifest`, its process-wide effect, and the self-check names the datapath on `engineInitFailed`. There is a Flow & State Gaps entry with a qualification test over a Cyrillic temp path.
  - proposal: a new UTF-8 bullet. ADR-0008 records it.
- **S1 fixed.** D2's function list now includes `GetInitLanguagesAsString`, `Oem` and `GetPageSegMode`.
- **S4 and S5** are not changed. Install verifies installed bytes through the manifest on every install, and the integrity check covers pins. The archive-checksum risk is already in Risks.

## Round 2 (amendment re-check)

Scope: the D1 amendment in commit 8345f6d (OpenCV source taken through a custom ExternalProject `DOWNLOAD_COMMAND` running `windows/vision/extract_source.cmake` instead of `URL` + `URL_HASH`). Evidence read: `windows/vision/CMakeLists.txt`, `windows/vision/extract_source.cmake`, `windows/vision/verify_inputs.cmake`, `windows/CMakeLists.txt:104-105`, design D1/D8/Mechanism Ledger, and `specs/release-bundle-integrity/spec.md` "Third-party inputs are pinned before they enter a build".

### Guarantees preserved

- **Input pinned, altered/missing input refused.** `bgv_verify_inputs` still runs at configure time, before any target exists (`CMakeLists.txt:16`). It fails on a missing archive (naming `mise run vision:fetch`) or a hash mismatch (naming both hashes), so the spec's "Altered input refused" and "Input missing from the cache" scenarios still hold. `extract_source.cmake` hashes the archive again before every extraction and fails with both hashes. The archive path it receives is `BGV_INPUT_OPENCV_SOURCE`, which `bgv_verify_inputs` has just verified. `inputs[0]` is asserted to be `opencv-source`, so the SHA used for the directory key and the archive path come from the same lock entry.
- **No network.** No `URL` is set. The download step is a local `cmake -P`, and `UPDATE_COMMAND`/`PATCH_COMMAND` are empty. D8's "no CMake download" rejection still holds.
- **Partial extraction is not reused.** The stamp `.bgv-extracted-sha256` is written only after `file(ARCHIVE_EXTRACT)` succeeds, and any non-matching or missing stamp causes `REMOVE_RECURSE` of the whole destination before re-extraction. An interrupted extraction, or a truncated stamp, leads to a clean re-extract, not reuse.
- **No stale tree across pins.** The destination is keyed by the lock SHA (`src-<first 16 hex>`) and the stamp holds the full SHA, so a pin change can never reuse an extraction of different bytes. A prefix collision would only cause a re-extract.
- **Reuse without re-hashing is within the threat model.** On a stamp hit the step returns without hashing the archive. That is equivalent to the `URL_HASH` design, where ExternalProject never re-verifies the extracted tree once its download stamp exists. The reused tree was produced from verified bytes, and every configure re-hashes the cache. Editing the extracted tree or forging the stamp needs write access to the build directory, which is the same capability as forging ExternalProject's own stamps. That falls under "not tamper-proof" (`architecture.md:85`) and the Ledger's "Signature or Authenticode verification: No" row. The Ledger's "CMake configure re-check" row is unchanged and still accurate.
- **Configuration mapping.** The install prefix (`opencv-install/$<IF:$<CONFIG:Debug>,Debug,Release>`) and the `--config` mapping are unchanged and match D1's "Configuration mapping". Sharing one source tree across configurations is correct, because the source is configuration-independent.

### Findings

**R2-M1 (Moderate): Changing the pin breaks the build until someone deletes the OpenCV build tree by hand.** The amendment moves `SOURCE_DIR` to `${CMAKE_BINARY_DIR}/opencv/src-<sha16>/opencv-4.13.0`. `BINARY_DIR` is still the default `${CMAKE_BINARY_DIR}/opencv/src/bgv_opencv-build`, which does not depend on the SHA. ExternalProject records the source directory in the configure command (`tmp/bgv_opencv-cfgcmd.txt`), so the first build after a lock change re-runs the OpenCV configure. That configure then runs against a `CMakeCache.txt` generated from the old source directory, and CMake stops with "The source ... does not match the source ... used to generate cache".

This failure is fail-closed, but every developer hits it after the expected pin events, such as an OpenCV bump or the S5 archive re-derivation. The error does not name the fix, which is to delete `build/windows/x64/opencv`. With the original `URL` design, `SOURCE_DIR` was fixed, so this did not happen; the amendment introduced it. The install prefix has a smaller form of the same problem: files from an earlier pin that the new install does not overwrite stay in `opencv-install/<cfg>`.

**R2-m1 (Minor, wording): D1 says the download step "re-checks the archive against the lock SHA-256 (the URL_HASH equivalent)".** It re-checks only when it extracts. A completed extraction of the same SHA is reused without hashing; that is the intended behaviour, and the configure-time check covers the cache. D1 should say so, so that a later reader does not count on a per-configuration re-hash that does not happen.

### Verdict (Round 2)

VERDICT: APPROVE_WITH_CHANGES

### Required Changes (Round 2)

1. **(R2-M1)** In `windows/vision/CMakeLists.txt`, key the OpenCV build tree and the install root by the same SHA prefix as the source. For example, set `BINARY_DIR "${CMAKE_BINARY_DIR}/opencv/build-${BGV_OPENCV_SHORT}"` and `BGV_OPENCV_ROOT "${CMAKE_BINARY_DIR}/opencv-install-${BGV_OPENCV_SHORT}"`; alternatively put source, build and install under one `opencv-${BGV_OPENCV_SHORT}` directory. Then a pin change gets a fresh configure and install with no cache conflict and no leftover files from the earlier pin. Add one sentence about this to D1. The Ledger's "Removing old cache directories: No" row already covers the old directories that accumulate.
2. **(R2-m1)** In design D1, reword the amendment sentence: the download step hashes the archive against the lock before extracting, and reuses a completed extraction of the same SHA, identified by a stamp written after extraction. The configure-time `bgv_verify_inputs` check still re-hashes the cached archive on every configure.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

### Round 2 re-check (applied changes)

- **R2-M1 resolved.** In `windows/vision/CMakeLists.txt` the source (`opencv/src-<sha16>`), build (`BINARY_DIR opencv/build-<sha16>`) and install root (`opencv-install-<sha16>`) are now all keyed by the pinned hash, so a pin change starts a fresh configure and install. The link inputs (`BGV_OPENCV_PREFIX/lib/...`, lines 160-164) follow the keyed prefix. The coordinator reports that the Release build rebuilt cleanly from these directories; I did not run this re-check myself.
- **R2-m1 resolved.** D1 (`design.md:57`) now says that configure verifies the archive, that the download step re-hashes only when it extracts, that a completed extraction of the same SHA is reused, and that the build and install trees carry the hash prefix. Task 3.3 (`tasks.md:90`) matches.
- **Nit (not required):** `design.md:63` still names the prefixes `opencv-install/Release` and `opencv-install/Debug`; the actual paths are now `opencv-install-<sha16>/Release` and `opencv-install-<sha16>/Debug`. The configuration mapping it describes is still correct.

The Round 2 verdict stays APPROVE_WITH_CHANGES. The required changes are applied and re-checked: CHANGES_APPLIED for Round 2 is set to yes above.
