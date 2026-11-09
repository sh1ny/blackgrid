# map-zone-labels Specification

## Purpose
Defines how the native map draws marker names and zone outlines on its canvas: which markers carry a name, its colour and style, how zone outlines are coloured, and when an outline is shown and can be clicked.

## Requirements

### Requirement: Extracts and transits show their names beside their badges
The native map SHALL draw the name of every drawn `PmcExtracts`, `ScavExtracts`, `SharedExtracts` and `Transits` badge beside that badge, to its right and vertically centred on it. No other category SHALL get a name label. A marker whose badge is not drawn (category hidden, other floor, outside the viewport) SHALL draw no name.

#### Scenario: Visible extract shows its name
- **WHEN** a `PmcExtracts` marker named "Med Tent Gate" is drawn on the map
- **THEN** the text "Med Tent Gate" is drawn starting to the right of its badge, vertically centred on the badge point

#### Scenario: Other categories stay unnamed
- **WHEN** a `locks` marker and a `HazardZones` marker are drawn
- **THEN** neither name is drawn on the canvas

#### Scenario: Hidden category draws no name
- **WHEN** the user hides `ScavExtracts` in the marker preferences
- **THEN** no Scav extract badge and no Scav extract name is drawn, and PMC extract names still are

#### Scenario: Extract with an empty name
- **WHEN** an extract marker's name is empty or only whitespace
- **THEN** its badge is drawn and no label is drawn for it

### Requirement: Name labels are coloured by faction
A name label SHALL use one colour per faction: PMC for `PmcExtracts`, Scav for `ScavExtracts`, shared for `SharedExtracts` and transit for `Transits`. The four colours SHALL differ from each other, reach a contrast of at least 3:1 against `#090F0D`, and lie outside the cyan highlight band (hue 170°–190°) and the amber band (hue 25°–60°), each at HSL saturation 10% or more. Badges keep their role colours.

#### Scenario: Each faction draws its own colour
- **WHEN** one PMC, one Scav, one shared extract and one transit are drawn
- **THEN** their four names are drawn in four different colours, and all four badges keep the exit-green ring

#### Scenario: Palette rule rejects a bad label colour
- **WHEN** a faction label colour has a contrast below 3:1 against `#090F0D`, a hue inside 170°–190° or 25°–60° at 10% saturation or more, or equals another faction's colour
- **THEN** the palette test fails and names the faction, its colour and the broken rule

#### Scenario: Highlighted extract keeps its faction name colour
- **WHEN** a `ScavExtracts` marker is raid-highlighted
- **THEN** its badge draws cyan and its name is still drawn in the Scav label colour

### Requirement: Name labels stay readable at every zoom
A name label SHALL be drawn at a fixed screen size that does not change with zoom, with a dark halo in the marker background colour behind the text. A label SHALL follow its badge's dimming: a dimmed marker draws its name at the dimmed opacity (22%). Names SHALL be drawn after zone outlines and before badges, so a badge is never covered by another marker's name.

#### Scenario: Zooming keeps the text size
- **WHEN** the user zooms in from fit to twice the scale
- **THEN** each extract name is drawn at the same font size as before, beside its badge's new position

#### Scenario: Dimmed extract fades its name
- **WHEN** a search dims a `SharedExtracts` marker
- **THEN** its badge and its name both draw at 22% opacity

#### Scenario: Overlapping badge stays on top
- **WHEN** a transit's name extends over a nearby `locks` badge
- **THEN** the `locks` badge is drawn above that name

### Requirement: Zone outlines use their category colour
A marker outline SHALL be filled and stroked in its category's role colour from the marker icon set, not in a single hazard red. A category with no role colour SHALL use the fallback badge colour. A dimmed marker's outline SHALL draw at reduced opacity, as before. A selected marker's outline SHALL be stroked and filled in Ember.

#### Scenario: Categories draw their own outline colours
- **WHEN** a `HazardZones`, a `QuestObjectives` and a `Switches` outline are drawn
- **THEN** they are drawn in the danger red, the quest lime and the utility violet respectively

#### Scenario: Icons not loaded yet
- **WHEN** the marker icon set has not finished loading and a `QuestObjectives` outline is drawn
- **THEN** it is drawn in the neutral grey fallback badge colour, not in red

#### Scenario: Selected outline is Ember
- **WHEN** a `PmcExtracts` marker with an outline is selected
- **THEN** its outline is drawn in Ember, and it is drawn in exit green when the marker is only hovered

### Requirement: Extract and transit outlines show on hover or selection
The outline of a `PmcExtracts`, `ScavExtracts`, `SharedExtracts` or `Transits` marker SHALL be drawn only while the pointer hovers over that marker or the marker is selected. Every other category's outline SHALL be drawn whenever its marker is drawn. Hover SHALL end when the pointer leaves the marker or the map, and when the selected map changes.

#### Scenario: Extract outline is hidden at rest
- **WHEN** a `PmcExtracts` marker with an outline is drawn, not hovered and not selected
- **THEN** its badge and name are drawn and its outline is not

#### Scenario: Hover reveals the outline
- **WHEN** the pointer moves over that extract's badge
- **THEN** its outline is drawn in exit green, and it disappears when the pointer moves away

#### Scenario: Moving into the revealed outline keeps it
- **WHEN** the pointer hovers an extract's badge and then moves inside that extract's now-drawn outline
- **THEN** the outline stays drawn while the pointer is inside it

#### Scenario: Selection keeps the outline
- **WHEN** the user clicks the extract and then moves the pointer off it
- **THEN** its outline stays drawn until the selection is cleared

#### Scenario: Hazard zone outline always shows
- **WHEN** a `HazardZones` marker is drawn and neither hovered nor selected
- **THEN** its outline is drawn

#### Scenario: Pointer leaves the map
- **WHEN** an extract is hovered and the pointer leaves the map viewport
- **THEN** its outline is no longer drawn unless it is selected

### Requirement: A hidden outline is not a click target
A click inside an outline that is not drawn SHALL NOT select that marker; only its badge selects it. The map's accessibility target for a marker whose outline is not drawn SHALL cover only its badge. A drawn outline keeps selecting its marker as before.

#### Scenario: Click inside a hidden extract area
- **WHEN** the user clicks inside an extract's polygon, away from its badge, while the outline is hidden
- **THEN** that extract is not selected

#### Scenario: Click inside a drawn hazard zone
- **WHEN** the user clicks inside a `HazardZones` outline away from its badge
- **THEN** that hazard zone is selected

#### Scenario: Accessibility target of an extract
- **WHEN** the map builds its accessibility targets and an extract's outline is hidden
- **THEN** that extract's target is the badge circle, not the polygon's bounds
