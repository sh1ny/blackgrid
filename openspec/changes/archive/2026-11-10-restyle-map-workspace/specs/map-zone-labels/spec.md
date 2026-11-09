# Spec Delta

## MODIFIED Requirements

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
