# Spec Delta

## ADDED Requirements

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
