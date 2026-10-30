# 0025 - Release packaging: a per-user Inno Setup installer and a zip, unsigned for now

- Status: accepted
- Date: 2026-10-31 (M6 change `add-release-packaging`)
- Amends: [0024](0024-hosted-ci-runs-every-offline-gate.md), the CI step list only: `mise run package:release` runs after `mise run ci:qualification`
- Source: [design](../../openspec/changes/add-release-packaging/design.md) D1-D7

## Context and problem

A Blackgrid build is a loose Release folder under `build/windows/x64/runner/Release`. Nobody could be handed a version without copying that folder by hand, and nothing recorded which commit a bundle came from. M6 needs a download format and a recorded decision about installers and signing. Blackgrid keeps its data, including DPAPI-protected credentials that cannot be recreated, in `%LOCALAPPDATA%\Blackgrid`, so whatever installs or uninstalls the app must never touch that folder.

## Decision

- **Inno Setup, per user, with a fixed `AppId`.** `windows/installer/blackgrid.iss` builds a setup that installs without elevation (`PrivilegesRequired=lowest`, no override) into `{autopf}\Blackgrid`, which is `%LOCALAPPDATA%\Programs\Blackgrid`. Its `AppId` is `{3DBFACF4-DBDB-4BC3-A5CA-2EC50C0BB82E}`, generated once and never changed, so every later version upgrades the same install in place. Start menu shortcut; desktop shortcut only on an unchecked task; an unchecked "Launch Blackgrid" at the end.
- **Artifact names (D3).** `mise run package:release` writes into `build/release/`:
  - `Blackgrid-<version>-windows-x64.zip`, holding one top-level `Blackgrid-<version>/` folder with the bundle tree plus `THIRD_PARTY_NOTICES.md`;
  - `Blackgrid-<version>-windows-x64-setup.exe`;
  - `SHA256SUMS.txt` in `sha256sum` format (two spaces, LF, sorted by name).

  `<version>` is the full SemVer including `-beta.N`. The installer's displayed version is that SemVer; its numeric file version is `<major>.<minor>.<patch>.<build number>`.
- **Stamp plus a fresh `bundle:check` (D1).** `build:release` deletes `build/windows/x64/runner/blackgrid-build.json` before it builds and writes it (format, version, build number, 40-hex `HEAD`) only after `bundle:check` passes, through a temp file and a rename. `package` refuses unless the tree is clean, the stamp parses, its commit is `HEAD` and its version is the pubspec version; it then re-runs `bundle:check` on the bundle before writing anything.
- **Pinned compiler, unpacked portable (D2).** Inno Setup is pinned in `windows/installer/packaging.lock.json` (URL, size, SHA-256), fetched and verified by the existing `fetchInputs`, unpacked into `.dart_tool/blackgrid_packaging/innosetup-<sha256>/` with a `.complete` marker, and run only by absolute path from there. Never from `PATH`, never installed system-wide.
- **Every file replaced, nothing else deleted (D4).** Every `[Files]` entry carries `ignoreversion`, so an upgrade, downgrade or same-version rebuild replaces every bundled file. The script has no `[InstallDelete]`, `[UninstallDelete]`, `[UninstallRun]` or `[Code]` section: the uninstaller removes only what Setup's own log installed. An offline test asserts this structurally. A future delete entry must relax that test to paths that start with `{app}\` and contain no `..`.
- **`build/release/` is all-or-nothing (D5).** `package` clears it before admission and removes it on any failure, exiting 1 and naming the failed stage and that child's own exit code. `SHA256SUMS.txt` is written last; a consumer requires it.
- **CI packages after qualification (D6).** ADR-0024's step list gains a `Package` step (`mise run package:release`) after `Qualification`, with no `env:`, no condition and no cache. Nothing is uploaded; publishing is `publish-github-releases`. The release tool's child processes may carry a timeout that kills the whole process tree (`taskkill /T /F`); `package` uses 5 min for the compiler unpack and 20 min for the compile.
- **Unsigned until [#66](https://github.com/sh1ny/blackgrid/issues/66) (D7).** Nothing is signed and the script sets no `SignTool`. If #66 recommends signing, it wraps two points inside `package`: the bundle's `blackgrid.exe` and DLLs before the zip, and the setup through `SignTool=`. Callers do not change.

## Rejected alternatives

- **MSIX:** it virtualizes `%LOCALAPPDATA%`, which would hide Blackgrid's data from other installs, and an unsigned MSIX cannot be installed.
- **WiX MSI:** heavier authoring and tooling for no behaviour Blackgrid needs over Inno Setup.
- **A per-machine install, or per-machine with a per-user override:** needs elevation by default, which the owner ruled out.
- **Buying a code-signing certificate now:** the signing route is open in #66.
- **Packaging inside `build:release`:** CI would build twice, or qualification would test a different bundle from the one shipped.
- **An `ISCC.exe` from `PATH`, winget, Chocolatey or a committed binary:** unpinned, machine-wide, or binaries in the repo.

## Consequences

- Users get a download and an installer; the unsigned setup shows SmartScreen's "unknown publisher" until #66 lands.
- Every CI run downloads the compiler (about 7 MB) and spends the packaging step's time; `lzma2/normal` is the knob if it grows past about 5 min.
- **Reversal cost:** high for `AppId`, because a changed id makes the next version a second install beside the first. Low for everything else.
