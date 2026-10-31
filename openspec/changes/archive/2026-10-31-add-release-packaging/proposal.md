# Proposal

## Why

Serves **M6 - Windows CI and releases**, change 2 of 4. A Blackgrid build is a loose Release folder under `build/windows/x64/runner/Release`. Nobody can be handed a version without copying that folder by hand. There is no installer, no download format and no recorded decision about installers or signing. M6's second exit criterion is that the installer format and code signing are decided and recorded in an ADR. This change records that decision and adds the packaging task. That task is what `publish-github-releases` (change 3) runs on a tag, and it makes the user-verified install check possible: "the user installs a published release from the installer and from the zip, and starts it".

The user decided on 2026-10-30:
- **Inno Setup** installer, not MSIX. Blackgrid keeps its data in `%LOCALAPPDATA%\Blackgrid`, which MSIX would virtualize, and an unsigned MSIX cannot be installed.
- **Unsigned for now.** Azure Trusted Signing is investigated separately in [#66](https://github.com/sh1ny/blackgrid/issues/66).
- **Per-user install**, with no admin prompt.

## What Changes

- **ADR-0025, Release packaging.** A zip and a per-user Inno Setup installer, built from the checked Release bundle, unsigned until #66 decides otherwise. Rejected: MSIX, WiX MSI, a per-machine install, and buying a certificate now.
- **Build stamp.** `mise run build:release` writes a small stamp next to the bundle once `bundle:check` passes. The stamp records the version, build number and commit. Packaging trusts only a bundle whose stamp names the current clean `HEAD`.
- **Pinned installer compiler.** Inno Setup 7.1.1 is pinned in a committed lock file with URL, size and SHA-256. It is downloaded and verified like the vision inputs, then unpacked in portable form into `.dart_tool/`, never on `PATH` or system-wide.
- **`mise run package:release`** (`release.dart package`) writes three files into `build/release/`:
  - `Blackgrid-<version>-windows-x64.zip`: the bundle plus `THIRD_PARTY_NOTICES.md`, under one top-level folder;
  - `Blackgrid-<version>-windows-x64-setup.exe`;
  - `SHA256SUMS.txt`, covering both.
- **Installer script** `windows/installer/blackgrid.iss`:
  - fixed `AppId`; installs to `%LOCALAPPDATA%\Programs\Blackgrid` without elevation;
  - Start menu shortcut, optional desktop shortcut;
  - upgrades in place and closes a running Blackgrid first;
  - the uninstaller removes only what it installed and never `%LOCALAPPDATA%\Blackgrid`.
- **CI packages every build.** The CI job gets a `Package` step after qualification, so a packaging regression shows on the PR before a tag depends on it. It uploads nothing; publishing is change 3.

## Capabilities

### New Capabilities
- `release-packaging`: turning a checked Release bundle into distributable packages. Covers the build stamp, the pinned installer compiler, the zip and installer layouts, the per-user install and uninstall behaviour, and the checksums.

### Modified Capabilities
- `continuous-integration`: the gate order gains a packaging step after the qualification tier.

## Impact

- **New:**
  - `tool/release/src/package_step.dart` and `tool/release/src/stamp.dart`;
  - `windows/installer/blackgrid.iss` and `windows/installer/packaging.lock.json`;
  - `docs/adr/0025-release-packaging.md`;
  - tests under `test/tool/release/`.
- **Changed:**
  - `tool/release/release.dart` (the `package` command);
  - `tool/release/src/build_step.dart` (writes the stamp);
  - `mise.toml` (the `package:release` task);
  - `tool/release/src/git.dart` (an optional timeout that kills a child process tree);
  - `.github/workflows/ci.yml` and `test/tool/ci/workflow_test.dart` (the `Package` step; ADR-0025 amends ADR-0024's CI step list);
  - `openspec/architecture.md` (the CI workflow row in the components table, the 0024 index row and a new 0025 index row).
- **Dependencies:** no new Dart packages. `archive` and `crypto` are already used by `tool/vision`. Inno Setup 7.1.1 is a pinned, hash-verified build tool, not shipped in the app.
- **Machine side effects:** the compiler is unpacked into `.dart_tool/` in portable form, with no uninstall entry, shortcuts or file associations. Only the design's last-resort fallback would register one; if apply has to use it, apply records that here. Nothing installs the produced setup on a developer machine; installing and starting a release is the user's check.
- **Out of scope:**
  - publishing, tag-triggered workflows, release notes and the README release flow (`publish-github-releases`);
  - code signing (#66);
  - auto-update.
