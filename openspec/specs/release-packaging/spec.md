# release-packaging Specification

## Purpose

Turns a checked Windows Release bundle into the packages a version is distributed as: a zip and a per-user installer, with checksums, built only from a bundle that is known to match the commit being packaged.

## Requirements

### Requirement: A release build records what it built
After the bundle check passes, a release build SHALL write a build stamp outside the bundle directory. The stamp SHALL record the version, the build number and the full commit hash of the built `HEAD`. A failed build or bundle check SHALL leave no stamp, including any stamp from an earlier build.

#### Scenario: Successful build writes a stamp
- **WHEN** `mise run build:release` builds version `0.6.0` at a `HEAD` with 412 commits and the bundle check passes
- **THEN** the stamp records version `0.6.0`, build number `412` and the full hash of that `HEAD`

#### Scenario: A failed bundle check leaves no stamp
- **WHEN** a stamp from an earlier build exists and the next build's bundle check fails
- **THEN** no stamp exists after the build, and the build exits non-zero

### Requirement: Packaging uses only a bundle stamped for the current clean HEAD
Packaging SHALL first clear `build/release/`, then refuse, before producing any output, unless all of these hold: the working tree is clean; the bundle directory and its stamp exist; the stamp's commit equals `HEAD`; and its version equals the `pubspec.yaml` version; and the offline bundle check passes on the bundle again. Each refusal SHALL say which condition failed and SHALL exit non-zero.

#### Scenario: Stamp matches HEAD
- **WHEN** the tree is clean, the stamp names the current `HEAD` and the pubspec version, and the bundle check passes
- **THEN** packaging proceeds to build the zip and the installer

#### Scenario: Bundle changed after the build
- **WHEN** the stamp matches `HEAD` but a bundled DLL was replaced after the build, so the bundle check fails
- **THEN** packaging exits non-zero at the bundle check, and `build/release/` holds no package

#### Scenario: Bundle built from another commit
- **WHEN** the stamp's commit differs from `HEAD`
- **THEN** packaging exits non-zero, naming both commits, and `build/release/` holds no package, including any from an earlier run

#### Scenario: No stamp
- **WHEN** the bundle directory exists but has no stamp
- **THEN** packaging exits non-zero and says to run `mise run build:release` first

#### Scenario: Dirty tree
- **WHEN** the working tree has a modified or untracked file
- **THEN** packaging exits non-zero, listing the files

### Requirement: The installer compiler is pinned and verified
Packaging SHALL obtain the installer compiler only from a committed lock entry that records its version, download URL, byte size and SHA-256. It SHALL refuse a download whose size or hash differs from the lock entry, and it SHALL NOT use an installer compiler found on `PATH` or installed elsewhere on the machine.

#### Scenario: Verified compiler
- **WHEN** the downloaded compiler installer matches the lock entry's size and SHA-256
- **THEN** it is installed into the repository's tool cache and used to build the installer

#### Scenario: Hash mismatch
- **WHEN** the downloaded bytes have a different SHA-256 from the lock entry
- **THEN** packaging exits non-zero, naming the expected and actual hashes, and nothing is installed or packaged

#### Scenario: Compiler on PATH
- **WHEN** an `ISCC.exe` from another install is on `PATH` and the cache is empty
- **THEN** packaging still downloads and verifies the pinned compiler and does not run the one on `PATH`

### Requirement: The zip holds exactly the bundle and the notices
Packaging SHALL write `Blackgrid-<version>-windows-x64.zip`. The zip SHALL hold one top-level folder, `Blackgrid-<version>/`, containing every file of the bundle at its bundle-relative path plus `THIRD_PARTY_NOTICES.md`, and nothing else.

#### Scenario: Zip contents
- **WHEN** version `0.6.0-beta.1` is packaged
- **THEN** `Blackgrid-0.6.0-beta.1-windows-x64.zip` lists `Blackgrid-0.6.0-beta.1/blackgrid.exe`, every other bundle file under the same folder, and `Blackgrid-0.6.0-beta.1/THIRD_PARTY_NOTICES.md`, and no other entry

#### Scenario: Notices missing
- **WHEN** `THIRD_PARTY_NOTICES.md` is missing from the repository
- **THEN** packaging exits non-zero, and no zip is left in `build/release/`

### Requirement: The installer installs per user and keeps user data
Packaging SHALL write `Blackgrid-<version>-windows-x64-setup.exe`. The installer SHALL:
- install without elevation into `%LOCALAPPDATA%\Programs\Blackgrid` by default;
- create a Start menu shortcut, and a desktop shortcut only when the user selects it;
- use one fixed application id, so a newer version upgrades the existing install in place.

Neither the installer nor its uninstaller SHALL delete `%LOCALAPPDATA%\Blackgrid`.

#### Scenario: Installer settings
- **WHEN** the installer script is compiled for version `0.6.0` with build number `412`
- **THEN** the script requests the lowest privileges, defaults to the per-user programs folder, uses the committed application id, and sets the file version `0.6.0.412` and the displayed version `0.6.0`

#### Scenario: User data on uninstall
- **WHEN** the installer script is checked
- **THEN** it has no `[InstallDelete]`, `[UninstallDelete]`, `[UninstallRun]` or `[Code]` section, so neither the installer nor the uninstaller can delete anything beyond the files Setup itself installed

#### Scenario: Upgrade or downgrade replaces every file
- **WHEN** the installer script's bundle file entry is checked
- **THEN** it carries the `ignoreversion` flag, so installing any version over another replaces every bundled file instead of keeping a file whose version number is the same or newer

#### Scenario: Prerelease version in file version
- **WHEN** version `0.6.0-beta.2` with build number `415` is packaged
- **THEN** the displayed version is `0.6.0-beta.2`, and the numeric file version is `0.6.0.415`

### Requirement: Packaging publishes checksums and leaves no partial set
Packaging SHALL write `SHA256SUMS.txt` with one `<sha256>  <file name>` line for the zip and one for the installer. If any stage fails, packaging SHALL remove what it wrote, so `build/release/` never holds a partial set, and SHALL exit 1, naming the failed stage and that stage's own exit code.

#### Scenario: Checksums match
- **WHEN** packaging succeeds
- **THEN** `build/release/` holds exactly the zip, the installer and `SHA256SUMS.txt`, and each listed hash equals the SHA-256 of that file

#### Scenario: Installer compile fails
- **WHEN** the installer compiler exits non-zero after the zip was written
- **THEN** packaging exits 1, names the installer stage and the compiler's exit code, and `build/release/` holds no zip, installer or checksum file
