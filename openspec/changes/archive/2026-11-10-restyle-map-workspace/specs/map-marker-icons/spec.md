# Spec Delta

## MODIFIED Requirements

### Requirement: Category colours keep their meaning and contrast
Each category SHALL map to one named colour role. Extract keys SHALL use the exit role (green), `Hazards` and `HazardZones` the danger role (red), and `CustomPins` the pin role (light blue). No role SHALL use the highlight hue band (cyan, hue 170°–190°), which stays reserved for highlighted markers. No role SHALL use the amber band (hue 25°–60° at HSL saturation 10% or more), which stays reserved for selection. Each role colour SHALL have a contrast ratio of at least 3:1 against the marker background `#090F0D`.

#### Scenario: Valid palette passes
- **WHEN** every role colour reaches 3:1 against `#090F0D`, sits outside 170°–190° hue and the amber band, and the extract, hazard and pin keys use their required roles
- **THEN** the palette rule passes

#### Scenario: Required role broken fails
- **WHEN** `ScavExtracts` is mapped to any role other than the exit role
- **THEN** the check exits non-zero and names `ScavExtracts` and the required role

#### Scenario: Reserved hue or low contrast fails
- **WHEN** a role colour has a hue of 185° or a contrast ratio of 2.4:1 against `#090F0D`
- **THEN** the check exits non-zero and names the role, its colour and the measured hue or ratio

#### Scenario: Amber role fails
- **WHEN** a role colour is `#E8A04A`
- **THEN** the check exits non-zero and names the role, its colour and its hue in the amber band

#### Scenario: Low-saturation grey near amber passes
- **WHEN** a role colour has a hue of 40° at 5% saturation and reaches 3:1
- **THEN** the amber rule passes for that role

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
- **THEN** the map draws a badge with a neutral grey ring and a neutral grey centre dot at that point, and every other marker still draws its own icon

### Requirement: Marker states keep their meaning on the badge
A selected marker SHALL draw at the selected badge size with its ring and glyph in Ember, the dark-room value on the map in both rooms. A linked or raid-highlighted marker SHALL draw at the selected size with its ring and glyph in the highlight cyan instead of its role colour. A dimmed marker SHALL draw its whole badge (disc, ring and glyph) at 22% opacity. Selection SHALL win over highlight, highlight SHALL win over the role colour, and dimming SHALL apply on top of any other state.

#### Scenario: Selected marker grows
- **WHEN** the user selects a `locks` marker
- **THEN** that marker draws a 30 px badge with an Ember ring and glyph, and the other markers stay 24 px

#### Scenario: Highlighted exit draws cyan
- **WHEN** a `ScavExtracts` marker is raid-highlighted
- **THEN** its badge is 30 px with a cyan ring and a cyan glyph, not exit green

#### Scenario: Dimmed marker fades as a whole
- **WHEN** a quest filter dims a `lootLoose` marker
- **THEN** its disc, ring and glyph all draw at 22% opacity

#### Scenario: Dimmed and highlighted together
- **WHEN** a marker is both highlighted and dimmed
- **THEN** it draws cyan at the selected size and at 22% opacity

#### Scenario: Selected and highlighted together
- **WHEN** a raid-highlighted `ScavExtracts` marker is selected
- **THEN** it draws at the selected size with an Ember ring and glyph, not cyan

#### Scenario: Selected marker in the light room
- **WHEN** the light room is active and a marker is selected
- **THEN** its ring and glyph use the same Ember value as in the dark room

### Requirement: Saved pins draw the pin icon
Each visible saved pin SHALL draw as a badge with the `CustomPins` glyph in the pin colour. A selected pin SHALL draw at the selected size with its ring and glyph in Ember. A pin whose label does not match the active map search SHALL draw at 22% opacity. Hiding `CustomPins` SHALL hide every pin badge.

#### Scenario: Pin draws its icon
- **WHEN** a saved pin on the current map is visible and the search is empty
- **THEN** it draws a 24 px badge with a light-blue ring and the light-blue `CustomPins` glyph

#### Scenario: Pin not matching the search dims
- **WHEN** the map search is `bunker` and a pin's label is `stash`
- **THEN** that pin's badge draws at 22% opacity

#### Scenario: Pins hidden
- **WHEN** the `CustomPins` filter is off
- **THEN** no pin badge is drawn

#### Scenario: Selected pin is Ember
- **WHEN** a saved pin is selected
- **THEN** it draws a 30 px badge with an Ember ring and the Ember `CustomPins` glyph

### Requirement: Missing or failed icons never block the map
Until the icons are loaded, and when the bundled manifest or any icon fails to load or decode, the map SHALL draw each affected marker as a fallback badge: the disc, the ring in the category's role colour once the manifest is loaded, otherwise in the key's fallback colour, and a centre dot. Markers, selection, hit testing and pins SHALL keep working. A load failure SHALL be logged once with the failing file.

#### Scenario: Fallback colours without a manifest
- **WHEN** the manifest has not loaded
- **THEN** fallback rings for `PmcExtracts`, `ScavExtracts` and `SharedExtracts` are exit green, for `Hazards` and `HazardZones` danger red, for saved pins light blue, and for every other key neutral grey

#### Scenario: Icons still loading
- **WHEN** the map paints before the icons finish loading
- **THEN** every marker draws a fallback badge, and once loading completes the map repaints with the icons

#### Scenario: One icon fails to decode
- **WHEN** the bundled `locks` icon is corrupt and the rest are valid
- **THEN** `locks` markers draw the fallback badge in the utility colour, the other categories draw their icons, and one log entry names the `locks` file

#### Scenario: Manifest unreadable
- **WHEN** the bundled manifest is missing or is not valid JSON
- **THEN** every marker draws a fallback badge in its key's fallback colour (for example `lootLoose` neutral grey, `PmcExtracts` green, a saved pin light blue), a log entry names the manifest, and selecting and hit testing markers still work
