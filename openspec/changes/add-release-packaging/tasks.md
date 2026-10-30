# Tasks

## Test map

Installer behaviour that only a real install can show (shortcuts, the upgrade in place, the uninstall leaving `%LOCALAPPDATA%\Blackgrid`) is proved offline by the installer-script test, which parses `windows/installer/blackgrid.iss` and asserts the directives that produce it. Running the produced setup is the user's M6 check, never an agent's (design Mechanism Ledger).

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| A release build records what it built | Successful build writes a stamp | test/tool/release/build_test.dart | a passing build writes a stamp with version, build number and HEAD commit | green |
| A release build records what it built | A failed bundle check leaves no stamp | test/tool/release/build_test.dart | a failing bundle check deletes an earlier stamp and writes none | green |
| Packaging uses only a bundle stamped for the current clean HEAD | Stamp matches HEAD | test/tool/release/package_test.dart | a fresh stamp passes admission and re-runs bundle:check before packaging | green |
| Packaging uses only a bundle stamped for the current clean HEAD | Bundle changed after the build | test/tool/release/package_test.dart | a failing bundle:check re-run refuses and leaves no package | green |
| Packaging uses only a bundle stamped for the current clean HEAD | Bundle built from another commit | test/tool/release/package_test.dart | a stamp for another commit refuses naming both commits and clears earlier output | green |
| Packaging uses only a bundle stamped for the current clean HEAD | No stamp | test/tool/release/package_test.dart | a missing stamp refuses and points to build:release | green |
| Packaging uses only a bundle stamped for the current clean HEAD | Dirty tree | test/tool/release/package_test.dart | a dirty tree refuses listing the files | green |
| The installer compiler is pinned and verified | Verified compiler | test/tool/release/package_test.dart | the pinned compiler is fetched, unpacked once with a complete marker and reused | green |
| The installer compiler is pinned and verified | Hash mismatch | test/tool/release/package_test.dart | a fetch hash mismatch fails naming both hashes and unpacks nothing | green |
| The installer compiler is pinned and verified | Compiler on PATH | test/tool/release/package_test.dart | ISCC runs only by absolute path from the packaging cache | green |
| The zip holds exactly the bundle and the notices | Zip contents | test/tool/release/package_test.dart | the zip holds the bundle and notices under one versioned folder and nothing else | green |
| The zip holds exactly the bundle and the notices | Notices missing | test/tool/release/package_test.dart | missing notices fail and leave no zip | green |
| The installer installs per user and keeps user data | Installer settings | test/tool/release/installer_script_test.dart | the script requests lowest privileges, the per-user folder and the committed AppId | green |
| The installer installs per user and keeps user data | Installer settings | test/tool/release/package_test.dart | ISCC gets the display version, the numeric file version and absolute paths | green |
| The installer installs per user and keeps user data | User data on uninstall | test/tool/release/installer_script_test.dart | the script has no install-delete, uninstall-delete, uninstall-run or code section | green |
| The installer installs per user and keeps user data | Upgrade or downgrade replaces every file | test/tool/release/installer_script_test.dart | every files entry carries ignoreversion | green |
| The installer installs per user and keeps user data | Prerelease version in file version | test/tool/release/package_test.dart | a beta version keeps its prerelease in the display version and drops it from the file version | green |
| Packaging publishes checksums and leaves no partial set | Checksums match | test/tool/release/package_test.dart | a successful run leaves exactly the zip, the installer and matching SHA256SUMS.txt | green |
| Packaging publishes checksums and leaves no partial set | Installer compile fails | test/tool/release/package_test.dart | a failing ISCC exits 1 naming the stage and its code and removes build/release | green |
| CI runs the gates in order and stops at the first failure | All gates pass | test/tool/ci/workflow_test.dart | gate steps run in order analyze, test, build:release, ci:qualification, package:release | green |
| CI runs the gates in order and stops at the first failure | Analysis fails | test/tool/ci/workflow_test.dart | no gate step has continue-on-error or an always()/failure() condition | green |
| CI runs the gates in order and stops at the first failure | The bundle check fails | test/tool/release/build_test.dart | bundle:check failure fails the build with its output | green |
| CI runs the gates in order and stops at the first failure | Packaging fails | test/tool/ci/workflow_test.dart | the package step is last, sets no env and has no condition | green |

## 1. ADR-0025 and the architecture index

- [x] 1.1 Generate the installer `AppId` GUID once, with `[guid]::NewGuid()`, uppercase. Then write `docs/adr/0025-release-packaging.md` (MADR-short, `Status: accepted`, today's date, `Amends: [0024](0024-hosted-ci-runs-every-offline-gate.md)`, CI step list only) from the design's ADRs section and D1-D7:
  - Inno Setup, per user, with the fixed `AppId` value written out;
  - artifact names (D3);
  - stamp plus fresh `bundle:check` (D1);
  - the pinned compiler, unpacked portable (D2);
  - `ignoreversion` and no delete, run or code sections (D4);
  - `build/release/` is all-or-nothing (D5);
  - CI packages after qualification (D6);
  - unsigned until #66, and where signing goes (D7);
  - rejected: MSIX, WiX MSI, a per-machine install, buying a certificate now;
  - reversal cost: high for `AppId`, low otherwise.

  In `openspec/architecture.md`, add the 0025 index row, note "amended by 0025" on the 0024 row, and add `package:release` to the CI workflow row. Verify: the file exists, both index rows link correctly, and `git diff docs/adr/0024-hosted-ci-runs-every-offline-gate.md docs/adr/0009-release-versioning.md` is empty.

## 2. Pinned compiler and child-process timeout

- [x] 2.1 Pick D2's unpack method on the dev machine. This needs no game check: it runs only the Inno Setup installer.
  - Download `https://github.com/jrsoftware/issrc/releases/download/is-7_1_1/innosetup-7.1.1-x64.exe` into a new, empty scratch directory, and measure its size and SHA-256.
  - Try option 1, `/PORTABLE=1 /VERYSILENT /SUPPRESSMSGBOXES /SP- /NORESTART /CURRENTUSER /NOICONS /DIR=<scratch>\is /LOG=<scratch>\is.log`. Confirm that `<scratch>\is\ISCC.exe` exists and that no new key appears under `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall`. Compare `reg query` before and after.
  - Only if option 1 fails, try option 2 (`innoextract`), then option 3. If option 3 is used, record its machine side effects in proposal.md's Impact.
  - Write `windows/installer/packaging.lock.json` (format 1) with one `inno-setup` entry: name, version `7.1.1`, the URL, size, SHA-256, license `Inno Setup License`, and `unpack: "portable"`, or the method chosen.

  Verify: `dart run tool/vision/fetch_runtime.dart --lock windows/installer/packaging.lock.json --cache .dart_tool/blackgrid_packaging/downloads` downloads and verifies it, and a second run reports it reused.
- [x] 2.2 Read the `dart-add-unit-test`, `dart-use-pattern-matching` and `dart-write-documentation` skills. Then add an optional `Duration? timeout` to `CommandRunner.run` (`tool/release/src/git.dart`), per D6b:
  - On expiry, `ProcessCommandRunner` kills the child's process tree with `taskkill /PID <pid> /T /F` and returns a typed timeout result (exit code `-1`, with a `timedOut` flag).
  - Existing callers pass none, so their behaviour is unchanged.
  - Update the fakes in `test/tool/release/*_test.dart` to the new signature.

  Test it with a real `ProcessCommandRunner` call to `pwsh -NoProfile -Command "Start-Sleep 30"` under a 1 s timeout. The test asserts `timedOut` and that the process is gone; it uses no sleeps in the test itself. Verify: `mise exec -- flutter test test/tool/release` passes.

## 3. Installer script

- [x] 3.1 Write failing tests in `test/tool/release/installer_script_test.dart` for the three installer-script rows of the Test map. The test parses `windows/installer/blackgrid.iss` into sections and `key=value` or `Name: …; Flags: …` entries. It asserts:
  - `PrivilegesRequired=lowest` and no `PrivilegesRequiredOverridesAllowed`;
  - `DefaultDirName={autopf}\Blackgrid`;
  - `AppId` equals the value in ADR-0025;
  - `VersionInfoVersion={#FileVersion}` and `AppVersion={#AppVersion}`;
  - `ignoreversion` on every `[Files]` entry;
  - no `[InstallDelete]`, `[UninstallDelete]`, `[UninstallRun]` or `[Code]` section, case-insensitive.

  Verify they fail because the script does not exist.
- [x] 3.2 Write `windows/installer/blackgrid.iss` per D4:
  - defines `AppVersion`, `FileVersion`, `SourceDir`, `NoticesFile`, `OutputDir`, `OutputBaseFilename`;
  - `ArchitecturesAllowed=x64os`, `MinVersion=10.0`, `CloseApplications=yes`, `Compression=lzma2/max`;
  - Start menu icon, and a desktop icon under the unchecked `desktopicon` task;
  - an unchecked post-install launch entry.

  Verify: the 3.1 tests pass, and the three installer-script rows are green.

## 4. Build stamp

- [x] 4.1 Write failing tests in `test/tool/release/build_test.dart` for the two stamp rows:
  - a passing build writes `build/windows/x64/runner/blackgrid-build.json` with `format`, `version`, `buildNumber` and the 40-hex `HEAD`;
  - with a stale stamp present, a failing `bundle:check` leaves no stamp.

  Use the existing Git fixture and `FakeRunner`. Verify they fail for the missing stamp.
- [x] 4.2 Implement the stamp in `tool/release/src/stamp.dart` (a typed read and write that rejects malformed JSON) and `build_step.dart`:
  - delete the stamp first;
  - write it through a temp file and a rename, only after `bundle:check` passes.

  Verify: all of `build_test.dart` passes, and the two stamp rows are green.

## 5. Package step

- [x] 5.1 Write failing tests in `test/tool/release/package_test.dart` for every `package_test.dart` row of the Test map.
  - **Fixtures:** a real Git fixture with a tiny synthetic bundle (a few small files, one in a subfolder), a stamp, `pubspec.yaml` and `THIRD_PARTY_NOTICES.md`.
  - **Fakes:** a `FakeRunner` that stubs `mise run bundle:check`, the compiler unpack and `ISCC.exe`, the last by writing a small fake setup file into `/O`. A `fetch` function parameter is injected, returning a fake installer file or throwing `FetchException`.
  - **Assertions:** the exact ISCC arguments, including the `/D` defines and absolute paths, and that the executable path is under `.dart_tool/blackgrid_packaging/innosetup-<sha>/`. Also the zip entries, read back with `package:archive`; the `SHA256SUMS.txt` content; exit codes; and that `build/release/` is absent after each refusal or failure, including when output from a pre-existing earlier run was there.

  Verify they fail because `package_step.dart` does not exist.
- [x] 5.2 Implement `tool/release/src/package_step.dart` per D1, D2, D3 and D5:
  - clear `build/release/`, then run admission;
  - `bundle:check` re-run;
  - fetch the compiler through the injected `fetchInputs`;
  - unpack into `innosetup-<sha>/` under a 5 min timeout, then write `.complete` (a directory without the marker is deleted first);
  - write the zip with `ZipFileEncoder`;
  - run ISCC under a 20 min timeout;
  - write `SHA256SUMS.txt` via a temp file and a rename, LF, sorted;
  - on any failure, remove `build/release/` and exit 1, naming the stage and the child's code.

  Exit codes follow D5: the design's Failure table rows that say "passed through" predate D5's exit-1 rule, which governs. Add the `package` command to `tool/release/release.dart` (usage text, no arguments) and `[tasks."package:release"]` to `mise.toml`. Verify: `package_test.dart` passes, and its rows are green.

## 6. CI packaging step

- [x] 6.1 In `test/tool/ci/workflow_test.dart`, add `package:release` as the last entry of `gates` and rename the order test to its Test map name. Add the test `the package step is last, sets no env and has no condition`. Verify both fail against the current workflow.
- [x] 6.2 Add a `Package` step (`run: mise run package:release`) after `Qualification` in `.github/workflows/ci.yml`, with no `env:`, `if:` or `continue-on-error`. Verify: `mise exec -- flutter test test/tool/ci` passes, including the unchanged no-games scope, cache and permission tests, and the CI rows are green.

## 7. Integration checks

- [ ] 7.1 Run `mise run analyze`, `mise run test` and `dart format --output=none --set-exit-if-changed .`. Verify all pass.
- [ ] 7.2 Package locally, end to end, with no game check needed: nothing launches the app or the produced setup.
  - Run `mise run build:release` then `mise run package:release` on the clean branch head.
  - Verify that `build/release/` holds exactly the three files, and that `Get-FileHash` matches `SHA256SUMS.txt`.
  - Verify that the zip lists `Blackgrid-<version>/blackgrid.exe` and `THIRD_PARTY_NOTICES.md`.
  - Verify that the setup's file version (`(Get-Item ...setup.exe).VersionInfo`) is `<core>.<build>`.

  Record the outcome in the PR description. Do not run the produced setup.

## Workflow follow-up

- The PR's CI run must show the new `Package` step green on `windows-2025`; record its duration. If it exceeds about 5 min, consider `lzma2/normal` (design Risks).
- User check (M6 exit criterion 4, after `publish-github-releases`): install a published release from the installer and from the zip, and start it. It stays unverified until the user reports it.
