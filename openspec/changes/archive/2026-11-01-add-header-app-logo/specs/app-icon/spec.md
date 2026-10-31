# Spec Delta

## ADDED Requirements

### Requirement: The icon build also writes the in-app vector
The rebuild command SHALL compile the source SVG, with the flags the map marker icons use, to `assets/app_icon/app_icon.vec`, and record that file's SHA-256 in the source record under `app_icon.vec`. It SHALL write the `.ico`, then the `.vec`, then the record, only after every size rendered and encoded, so a failed compile, render or encode leaves all three unchanged. A record that does not yet hold the `app_icon.vec` hash SHALL still be accepted by the rebuild command, which adds it.

#### Scenario: Rebuild writes the vector
- **WHEN** `mise run icon:build` runs on a valid source
- **THEN** `assets/app_icon/app_icon.vec` holds the compiled source, and the record's `sha256` lists `app_icon.svg`, `app_icon.ico` and `app_icon.vec` with the hashes of the files written

#### Scenario: Compile fails
- **WHEN** the source SVG holds an element the compiler rejects
- **THEN** the command exits non-zero, names the file, and the committed `.ico`, `.vec` and record are unchanged

#### Scenario: Record from before the vector
- **WHEN** the rebuild command runs on a valid source whose record's `sha256` has no `app_icon.vec` entry
- **THEN** the command succeeds and the record it writes holds the `app_icon.vec` hash

### Requirement: The in-app vector stays in step with the source
The offline icon test SHALL fail when `assets/app_icon/app_icon.vec` is missing, when the record holds no hash for it, when it differs from its recorded hash, or when it differs from the bytes that compiling the committed `app_icon.svg` produces. Each failure SHALL name the `.vec` and the rebuild command.

#### Scenario: Vector in step
- **WHEN** the committed `.vec`, source and record come from the same rebuild
- **THEN** the icon test's vector checks pass

#### Scenario: Source edited without rebuild
- **WHEN** `app_icon.svg` is changed and the rebuild command is not run
- **THEN** the icon test fails on the source hash and on the `.vec` no longer matching the compiled source, naming `mise run icon:build`

#### Scenario: Vector without a recorded hash
- **WHEN** the `.vec` is committed and the record's `sha256` has no `app_icon.vec` entry
- **THEN** the icon test fails, saying the file exists but the record has no hash for `app_icon.vec`, and names the rebuild command

#### Scenario: Vector missing
- **WHEN** `assets/app_icon/app_icon.vec` is absent
- **THEN** the icon test fails, naming the missing `.vec` and the rebuild command

#### Scenario: Vector replaced by hand
- **WHEN** the `.vec` is overwritten with other bytes and the record is left alone
- **THEN** the icon test fails, saying the `app_icon.vec` hash differs from the record, and names the rebuild command

### Requirement: The app header and the startup screen show the application icon
The app header SHALL draw the committed in-app vector at 32 by 32 logical pixels, and the startup screen at 54 by 54, where the generic hub icon was, beside or above the `BLACKGRID` name. The logo SHALL be decorative: it SHALL add no semantics node, so the accessible name stays the `BLACKGRID` text. If the vector cannot load, an empty space of the same size SHALL stand in, with the rest of the layout unchanged and no error widget shown.

#### Scenario: Header shows the logo
- **WHEN** the app shell is shown
- **THEN** the header holds the logo drawn from `assets/app_icon/app_icon.vec` at 32 by 32 beside `BLACKGRID`, and no `Icons.hub_outlined`

#### Scenario: Startup screen shows the logo
- **WHEN** the app is opening local storage, or showing the storage error
- **THEN** the screen shows the logo from `assets/app_icon/app_icon.vec` at 54 by 54 above `BLACKGRID`, and no `Icons.hub_outlined`

#### Scenario: Logo is not announced
- **WHEN** a screen reader reads the header
- **THEN** it reads `BLACKGRID` and `TRACK. PLAN. SURVIVE.`, and nothing for the logo

#### Scenario: Vector fails to load
- **WHEN** loading the `.vec` fails
- **THEN** the header shows an empty 32 by 32 box where the logo goes, the `BLACKGRID` text stays in the same place, no error widget is shown, and `FlutterError.onError` is not called
