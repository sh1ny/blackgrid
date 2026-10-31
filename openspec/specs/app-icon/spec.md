# app-icon Specification

## Purpose
Defines Blackgrid's own application icon: where its source and its design candidates come from, the sizes and format of the committed Windows `.ico`, and how the executable, the installer and the uninstall entry use it.

## Requirements

### Requirement: The icon source is a project-owned SVG with a provenance record
The repository SHALL hold the icon's source as an SVG with a provenance record: author, method, tools, date and, when it redraws a concept image, which committed candidate it redraws. It MAY also hold a small-size SVG used only for the 16, 20 and 24 px images. The record SHALL name the candidate the user picked and the date of the pick. No source or candidate SHALL trace, or name as a style reference, third-party art.

#### Scenario: Source with a concept
- **WHEN** the user picks the scanner aperture concept
- **THEN** the source is an SVG redraw of it, and its provenance record names the committed concept PNG, the pick date and the redraw's author and tools

#### Scenario: Missing provenance
- **WHEN** the source SVG exists but its provenance record lacks the author or the picked candidate
- **THEN** the icon check fails and names the missing field

### Requirement: Concept candidates are committed with provenance
Each concept image the user supplied for comparison SHALL be committed under the design record's candidates folder with a provenance entry: that the user generated it, the tool (ChatGPT), the date, and the prompt when the user supplies it. A candidate without a provenance entry SHALL NOT appear on the comparison sheet.

#### Scenario: Four concepts recorded
- **WHEN** the four ChatGPT concepts are committed
- **THEN** each PNG has a provenance entry naming the user, ChatGPT and 2026-10-31

#### Scenario: Unrecorded candidate
- **WHEN** a PNG in the candidates folder has no provenance entry
- **THEN** the comparison sheet run exits non-zero, names the file and writes no sheet

### Requirement: The comparison sheet shows every candidate at the icon sizes
An offline command SHALL write one self-contained HTML sheet that shows every recorded candidate side by side, at each icon size and enlarged, on a light and a dark background. For each vector candidate, the sheet SHALL show the same rasters its `.ico` would hold. It SHALL load no external URL, script or font. A failed run SHALL leave any earlier sheet in place.

#### Scenario: Sheet with ten candidates
- **WHEN** four concept PNGs and six vector candidates are recorded
- **THEN** the sheet shows ten columns, each at 16, 20, 24, 32, 40, 48, 64, 96, 128 and 256 px on both backgrounds

#### Scenario: Invalid vector candidate
- **WHEN** one vector candidate fails to compile
- **THEN** the run exits non-zero, names that file, and an earlier sheet is unchanged

### Requirement: The committed icon holds every Windows size
`windows/runner/resources/app_icon.ico` SHALL hold exactly one square image at each of 16, 20, 24, 32, 40, 48, 64, 96, 128 and 256 px, each 32-bit with alpha. The images below 256 px SHALL be uncompressed bitmaps, and the 256 px image SHALL be PNG-compressed. The file SHALL differ from the Flutter default icon.

#### Scenario: Valid icon
- **WHEN** the icon test reads the committed `.ico`
- **THEN** it finds ten images, sized 16 to 256 px as listed, each 32 bits per pixel, and no image is fully transparent

#### Scenario: Missing size
- **WHEN** the `.ico` lacks the 20 px image or holds a duplicate 32 px image
- **THEN** the icon test fails and names the missing or duplicate size

#### Scenario: Flutter default restored
- **WHEN** the committed `.ico` has the SHA-256 of Flutter's default `app_icon.ico`
- **THEN** the icon test fails, saying the icon is the Flutter default

### Requirement: The icon is rebuilt from its source and stays in step
An offline command SHALL render the source SVG (and the small-size SVG, when present) to the `.ico`, and record the SHA-256 of each source file and of the `.ico` it wrote. It SHALL write the `.ico`, then the record, only after every size rendered and encoded, so a failed render or encode leaves both unchanged. The icon test SHALL fail when a source or the `.ico` differs from the recorded hash.

#### Scenario: Source edited without rebuild
- **WHEN** the source SVG is changed and the `.ico` is not rebuilt
- **THEN** the icon test fails, saying the source hash differs from the record, and names the rebuild command

#### Scenario: Render fails
- **WHEN** the source SVG holds an element the compiler rejects
- **THEN** the command exits non-zero, names the file, and the committed `.ico` and record are unchanged

#### Scenario: Record write fails
- **WHEN** the `.ico` was written and writing the record then fails
- **THEN** the command exits non-zero, naming the file and the rebuild command, and the icon test fails on the `.ico` hash until the command is run again

### Requirement: The executable, the installer and the uninstall entry use the committed icon
The executable's application icon resource SHALL be built from `windows/runner/resources/app_icon.ico`. The installer script SHALL take its setup icon from that file and its uninstall entry's icon from the installed `blackgrid.exe`.

#### Scenario: Installer script points at the icon
- **WHEN** the installer script test reads `windows/installer/blackgrid.iss`
- **THEN** `SetupIconFile` resolves to `windows/runner/resources/app_icon.ico` and `UninstallDisplayIcon` is `{app}\blackgrid.exe`

#### Scenario: Setup icon moved
- **WHEN** `SetupIconFile` names another file, or is removed
- **THEN** the installer script test fails and names the setting
