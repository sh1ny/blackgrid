# map-marker-icons Specification

## Purpose
Defines Blackgrid's own icon set for map marker categories: which categories have an icon, the form and colours of the icon files, the provenance every file carries, and the offline check and preview that keep the set valid and reviewable.

## Requirements

### Requirement: Every marker category has exactly one icon
A release set SHALL contain exactly one icon for each marker category key: the 18 keys a prepared map marker can carry plus `CustomPins`. `Labels`, a legacy import key no marker carries, SHALL have no icon. A candidate set, used only for style rounds, MAY cover a subset but never an unknown or duplicated key. The set check SHALL fail and name the key when a rule is broken.

#### Scenario: Complete set passes
- **WHEN** the set check runs on a set with one valid icon for each of the 19 keys
- **THEN** it reports the coverage rule as passed and exits with status 0

#### Scenario: Missing category fails
- **WHEN** the set has no icon for `BtrStops`
- **THEN** the check exits non-zero and its report names `BtrStops` as missing

#### Scenario: Candidate subset passes coverage
- **WHEN** the check runs on a candidate set with icons for 6 of the 19 keys
- **THEN** the coverage rule passes, and every other rule still applies to those 6 icons

#### Scenario: Unknown or duplicate icon fails
- **WHEN** the manifest lists an icon for `Labels`, or two entries for `PmcExtracts`
- **THEN** the check exits non-zero and names the unknown key or the duplicated key

### Requirement: Icon files use the restricted single-tint vector form
Each icon SHALL be an SVG file of at most 8 KiB with a `0 0 24 24` view box. It SHALL contain only shape elements (`path`, `circle`, `ellipse`, `rect`, `polygon`, `polyline`, `line`, `g`) painted in one tint colour. It SHALL contain no raster image, text, font, script, style sheet, filter, link or external reference. It SHALL compile with the build-time vector compiler the map uses. The tint SHALL come from the category's colour role, so an icon file carries no category colour of its own.

#### Scenario: Valid glyph passes and compiles
- **WHEN** the check reads an icon drawn with `path` and `circle` elements in the tint colour only
- **THEN** the form rule passes for that file and the vector compiler produces non-empty output for it

#### Scenario: Forbidden content fails
- **WHEN** an icon file contains an `<image>` element, a `<text>` element or any `href` attribute
- **THEN** the check exits non-zero and names the file and the forbidden element or attribute

#### Scenario: Unlisted attribute fails
- **WHEN** an icon's `svg` or `path` element carries an `onload` attribute, or any attribute outside that element's allowed list
- **THEN** the check exits non-zero and names the file, the element and the attribute

#### Scenario: Default or inherited paint fails
- **WHEN** a `path` has no `fill` of its own and no ancestor sets one, so it would paint the SVG default black
- **THEN** the check exits non-zero and names the file and the shape's effective colour

#### Scenario: Second colour or wrong view box fails
- **WHEN** an icon file paints any colour other than the tint, or declares a view box other than `0 0 24 24`
- **THEN** the check exits non-zero and names the file and the offending colour or view box

#### Scenario: Oversized file fails
- **WHEN** an icon file is larger than 8 KiB
- **THEN** the check exits non-zero and names the file and its size

#### Scenario: File that does not compile fails
- **WHEN** an icon file is malformed XML, or the vector compiler rejects it or reports a warning for unsupported content
- **THEN** the check exits non-zero and names the file, and it does not report the set as valid

### Requirement: Category colours keep their meaning and contrast
Each category SHALL map to one named colour role. Extract keys SHALL use the exit role (green), `Hazards` and `HazardZones` the danger role (red), and `CustomPins` the pin role (light blue). No role SHALL use the highlight hue band (cyan, hue 170°–190°), which stays reserved for highlighted markers. Each role colour SHALL have a contrast ratio of at least 3:1 against the marker background `#090F0D`.

#### Scenario: Valid palette passes
- **WHEN** every role colour reaches 3:1 against `#090F0D`, sits outside 170°–190° hue, and the extract, hazard and pin keys use their required roles
- **THEN** the palette rule passes

#### Scenario: Required role broken fails
- **WHEN** `ScavExtracts` is mapped to any role other than the exit role
- **THEN** the check exits non-zero and names `ScavExtracts` and the required role

#### Scenario: Reserved hue or low contrast fails
- **WHEN** a role colour has a hue of 185° or a contrast ratio of 2.4:1 against `#090F0D`
- **THEN** the check exits non-zero and names the role, its colour and the measured hue or ratio

### Requirement: Every icon file carries a complete provenance record
Each icon file SHALL have one provenance record in the manifest. The record SHALL hold the file's SHA-256, the author, the origin, the method (`hand-authored` or `ai-assisted`), the tools used (required for `ai-assisted`), the concept source (`none`, or a named tool with its prompt record), and the date. The recorded hash SHALL match the file's bytes.

#### Scenario: Complete matching record passes
- **WHEN** an icon's record names an `ai-assisted` method with its tool, and its SHA-256 equals the file's hash
- **THEN** the provenance rule passes for that file

#### Scenario: Missing or stale record fails
- **WHEN** an icon file has no record, or its recorded SHA-256 differs from the file's bytes after an edit
- **THEN** the check exits non-zero and names the file and whether the record is missing or stale

#### Scenario: Incomplete record fails
- **WHEN** a record has method `ai-assisted` with no tool, or a concept source with no prompt record
- **THEN** the check exits non-zero and names the file and the missing field

### Requirement: No third-party marker art enters the set
Every icon SHALL be project-authored. A provenance record SHALL NOT name a third-party origin, and its method SHALL be one of the two project-authored methods. A concept image from an image-generation tool SHALL be redrawn as a vector and SHALL NOT be committed as an icon. The check SHALL reject any record whose method or origin is outside the allowed values.

#### Scenario: Project-authored record passes
- **WHEN** every record has method `hand-authored` or `ai-assisted` and origin `project`
- **THEN** the origin rule passes

#### Scenario: Third-party or unknown origin fails
- **WHEN** a record has origin `tarkov.dev`, or a method such as `traced` or `imported`
- **THEN** the check exits non-zero and names the file and the rejected value

### Requirement: Preview sheet shows every icon in every state
The preview generator SHALL write one self-contained sheet that a browser opens offline. For every category the sheet SHALL show the icon at 24 px and enlarged, on dark, mid and light map tones, in the normal, selected, dimmed and highlighted states, with a colour-vision-deficiency row. When given more than one candidate set, the sheet SHALL show the sets side by side under their names. The generator SHALL refuse an invalid set.

#### Scenario: Sheet covers every category and state
- **WHEN** the generator runs on a valid set
- **THEN** the written sheet has one labelled entry per category for each state and background, and it references no network or file URL outside itself

#### Scenario: Candidate sets compared side by side
- **WHEN** the generator is given two named candidate sets
- **THEN** each category's row shows both sets' icons under their set names

#### Scenario: Too many candidate sets writes no sheet
- **WHEN** the generator is given five sets
- **THEN** it exits non-zero, names the limit of 4 and writes no sheet

#### Scenario: Invalid set writes no sheet
- **WHEN** the generator is given a set that fails the set check
- **THEN** it exits non-zero, prints the check's failures and writes no sheet, leaving any previous sheet untouched

### Requirement: The map draws each marker as its category's icon badge
The native map SHALL draw each visible marker as a badge: a disc in the marker background colour, a ring in the category's role colour, and the category's glyph tinted in that colour. Badge size, ring width and glyph area SHALL come from the release set's badge geometry. The placeholder ring with a centre dot SHALL NOT be drawn for a category that has an icon.

#### Scenario: Marker with an icon draws its badge
- **WHEN** the icons are loaded and a `PmcExtracts` marker is visible, not selected, highlighted or dimmed
- **THEN** the map draws a 24 px badge with an exit-green ring and the `PmcExtracts` glyph tinted exit green, and no centre dot

#### Scenario: Hazard zone keeps its outline and draws its icon
- **WHEN** a `HazardZones` marker with an outline is visible
- **THEN** the map draws the red zone polygon and, at the marker point, a badge with the `HazardZones` glyph in the danger colour

#### Scenario: Unknown filter key falls back
- **WHEN** a prepared map marker carries a filter key that has no icon in the set
- **THEN** the map draws a badge with a gold ring and a gold centre dot at that point, and every other marker still draws its own icon

### Requirement: Marker states keep their meaning on the badge
A selected marker SHALL draw at the selected badge size. A linked or raid-highlighted marker SHALL draw at the selected size with its ring and glyph in the highlight cyan instead of its role colour. A dimmed marker SHALL draw its whole badge (disc, ring and glyph) at 22% opacity. Highlight SHALL win over the role colour, and dimming SHALL apply on top of any other state.

#### Scenario: Selected marker grows
- **WHEN** the user selects a `locks` marker
- **THEN** that marker draws a 30 px badge in the utility colour, and the other markers stay 24 px

#### Scenario: Highlighted exit draws cyan
- **WHEN** a `ScavExtracts` marker is raid-highlighted
- **THEN** its badge is 30 px with a cyan ring and a cyan glyph, not exit green

#### Scenario: Dimmed marker fades as a whole
- **WHEN** a quest filter dims a `lootLoose` marker
- **THEN** its disc, ring and glyph all draw at 22% opacity

#### Scenario: Dimmed and highlighted together
- **WHEN** a marker is both highlighted and dimmed
- **THEN** it draws cyan at the selected size and at 22% opacity

### Requirement: Saved pins draw the pin icon
Each visible saved pin SHALL draw as a badge with the `CustomPins` glyph in the pin colour. A selected pin SHALL draw at the selected size. A pin whose label does not match the active map search SHALL draw at 22% opacity. Hiding `CustomPins` SHALL hide every pin badge.

#### Scenario: Pin draws its icon
- **WHEN** a saved pin on the current map is visible and the search is empty
- **THEN** it draws a 24 px badge with a light-blue ring and the light-blue `CustomPins` glyph

#### Scenario: Pin not matching the search dims
- **WHEN** the map search is `bunker` and a pin's label is `stash`
- **THEN** that pin's badge draws at 22% opacity

#### Scenario: Pins hidden
- **WHEN** the `CustomPins` filter is off
- **THEN** no pin badge is drawn

### Requirement: Missing or failed icons never block the map
Until the icons are loaded, and when the bundled manifest or any icon fails to load or decode, the map SHALL draw each affected marker as a fallback badge: the disc, the ring in the category's role colour once the manifest is loaded, otherwise in the key's fallback colour, and a centre dot. Markers, selection, hit testing and pins SHALL keep working. A load failure SHALL be logged once with the failing file.

#### Scenario: Fallback colours without a manifest
- **WHEN** the manifest has not loaded
- **THEN** fallback rings for `PmcExtracts`, `ScavExtracts` and `SharedExtracts` are exit green, for `Hazards` and `HazardZones` danger red, for saved pins light blue, and for every other key gold

#### Scenario: Icons still loading
- **WHEN** the map paints before the icons finish loading
- **THEN** every marker draws a fallback badge, and once loading completes the map repaints with the icons

#### Scenario: One icon fails to decode
- **WHEN** the bundled `locks` icon is corrupt and the rest are valid
- **THEN** `locks` markers draw the fallback badge in the utility colour, the other categories draw their icons, and one log entry names the `locks` file

#### Scenario: Manifest unreadable
- **WHEN** the bundled manifest is missing or is not valid JSON
- **THEN** every marker draws a fallback badge in its key's fallback colour (for example `lootLoose` gold, `PmcExtracts` green, a saved pin light blue), a log entry names the manifest, and selecting and hit testing markers still work

### Requirement: The bundled icons are the compiled release set
The app SHALL bundle the release set's manifest and one compiled vector file per manifest icon, compiled from its SVG with the set check's compile settings, and no SVG source or prompt record. An offline check SHALL fail when a compiled file differs from compiling its SVG, when an icon has no compiled file, or when a compiled file has no manifest icon.

#### Scenario: Compiled files in step
- **WHEN** every compiled file equals the output of compiling its SVG and each manifest icon has exactly one
- **THEN** the compile-sync check passes

#### Scenario: SVG edited without recompiling
- **WHEN** an icon's SVG is changed and its compiled file is not regenerated
- **THEN** the compile-sync check fails and names the stale compiled file

#### Scenario: Orphan compiled file
- **WHEN** the compiled directory holds `labels.vec`, which no manifest icon names
- **THEN** the compile-sync check fails and names `labels.vec` as unexpected
