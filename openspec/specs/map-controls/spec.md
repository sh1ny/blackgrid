# map-controls Specification

## Purpose
Defines how the Map screen gives the main column to the map, and which controls and working lists the player uses to drive it, without settings or debug text on the work screen.

## Requirements

### Requirement: The map takes the main column
The Map screen SHALL show the map below the answer strip as its whole main column, with no settings panel, rail or debug text beside or above it. The map viewport SHALL keep its state across inspector changes and resizes.

#### Scenario: Wide and narrow windows
- **WHEN** Map is shown at 1660 by 870 and at 960 by 720 logical pixels
- **THEN** the answer strip is directly under the top bar and the map fills the main column below it, with no "Active map", "Marker preferences", "Manual item search" or "Map saved-file inputs" panel

#### Scenario: Inspector closes over a loaded map
- **WHEN** the inspector is closed, or the window crosses 1080 px, while a map is zoomed in
- **THEN** the same map stays mounted and keeps its zoom and pan position

### Requirement: Debug information stays off the Map screen
The Map screen SHALL NOT show log, screenshot or raid-panel status lines, file paths, coordinate frames, frame revisions or sampled positions. A save failure or a load notice the player must act on SHALL stay visible on the Map. The artwork attribution SHALL stay visible.

#### Scenario: Normal use
- **WHEN** Map shows a loaded map, a saved screenshot and a saved pin
- **THEN** no text beginning "Logs:", "Screenshots:" or "Saved evidence" is on the Map screen, no pin's coordinates, frame or revision is shown, and the map's attribution is shown

#### Scenario: Settings cannot be saved
- **WHEN** saving a marker switch fails
- **THEN** the save error is shown on the Map screen

#### Scenario: Selected pin shows no debug text
- **WHEN** a saved pin is selected
- **THEN** its label is shown and its frame and revision are not

### Requirement: Map picker switches the map by hand
The map's name SHALL be a button at the top left of the map that opens a menu listing every supported map, with a check on the current one and a footnote saying that choosing a map turns log following off until it is turned back on in Settings. The button SHALL show the displayed map, including one detected from the logs.

#### Scenario: Choosing a map
- **WHEN** the player opens the picker on Customs while following logs and chooses Woods
- **THEN** Woods is shown, the check moves to Woods, and Follow logs is off

#### Scenario: Picker while saving
- **WHEN** settings are being saved
- **THEN** the map entries cannot be chosen and the selected map does not change

### Requirement: Read latest screenshot is in the picker
The picker SHALL end with a "Read latest screenshot" item that applies the newest saved screenshot to the selected map as assumed evidence. The item SHALL be disabled while no screenshot folder is set and SHALL read "Reading latest…" and be disabled while a read runs.

#### Scenario: Reading the latest screenshot
- **WHEN** a screenshot folder is set and the player chooses "Read latest screenshot"
- **THEN** the latest screenshot is read for the selected map

#### Scenario: No screenshot folder
- **WHEN** no screenshot folder is set
- **THEN** the item is disabled and choosing it starts no read

#### Scenario: A read is running
- **WHEN** a read is in progress and the picker is opened
- **THEN** the item reads "Reading latest…" and is disabled

#### Scenario: Empty folder
- **WHEN** the screenshot folder holds no screenshot and the player chooses the item
- **THEN** a short plain-language notice says there is no screenshot to read, and the map is unchanged

#### Scenario: Screenshot cannot be read
- **WHEN** the newest screenshot file cannot be read
- **THEN** a short plain-language notice says the screenshot could not be read, with no file path

#### Scenario: Screenshot folder is unavailable
- **WHEN** the screenshot folder is missing or inaccessible and the player chooses the item
- **THEN** the notice says the screenshot could not be read, not that the folder is empty

#### Scenario: Superseded read
- **WHEN** the selected map changes while a read runs and the read is discarded
- **THEN** no notice is shown

### Requirement: Floor control sits beside the picker
A segmented control beside the picker SHALL offer Auto exactly when the prepared map has at least one floor extent, and then each of the map's floors. Choosing a floor SHALL change the visible layers as the floor chips did, and each visible layer SHALL show as selected. A map with no floors SHALL show no floor control.

#### Scenario: Choosing a floor
- **WHEN** a map with Ground and Underground floors is shown and the player chooses Underground
- **THEN** that floor's visibility changes and its segment shows its new state

#### Scenario: Manual-only floors
- **WHEN** a map with selectable floors has no floor extents
- **THEN** the floor segments are shown without Auto

#### Scenario: Map with no floors
- **WHEN** the current map has no floor policy floors and no automatic floor support
- **THEN** no floor control is shown

#### Scenario: Artwork unavailable
- **WHEN** the selected map's artwork is not available
- **THEN** the picker stays usable and no floor segment is shown

### Requirement: Map actions stay on the map
Fit, zoom in, zoom out, center on player, pin at view center, browse markers and Map help SHALL be icon controls on the map, each with a tooltip and an accessible name. Each SHALL stay enabled and disabled under the same conditions as before this change, and every keyboard and pointer control SHALL keep working.

#### Scenario: Actions are reachable
- **WHEN** a map is loaded and a player position is known
- **THEN** all seven controls are enabled and on the map

#### Scenario: No position or no artwork
- **WHEN** no player position is known and no artwork is loaded
- **THEN** center on player and fit are disabled, and Map help stays enabled

#### Scenario: Keyboard on an on-map control
- **WHEN** the Zoom in control has keyboard focus and the player presses Enter
- **THEN** the map zooms in and the marker browser does not open

### Requirement: This raid lists the matched extracts
The Map inspector SHALL start with a This raid section listing each matched extract whose category and floor are visible, whether or not it is in view, with its badge and name and the age of the screenshot that matched it. Choosing a row SHALL select that marker and bring it into view. With no match it SHALL show a one-line empty state.

#### Scenario: Matched extracts
- **WHEN** the last raid-panel reading matched two extracts on the current map
- **THEN** both are listed with their badges, and choosing one selects it on the map

#### Scenario: No reading
- **WHEN** no raid-panel reading has matched an extract on this map
- **THEN** the section shows only its empty state

#### Scenario: Matched extract is hidden
- **WHEN** a matched extract's category is switched off
- **THEN** that extract is not listed and no hidden marker can be selected from the section

#### Scenario: Matched extract outside the view
- **WHEN** the map is zoomed in so that a matched extract is outside the viewport
- **THEN** that extract is still listed

#### Scenario: Choosing an off-view row
- **WHEN** the player chooses a row whose extract is outside the viewport
- **THEN** the view pans at the same zoom until the marker is in view, and its bubble opens

#### Scenario: Choosing an in-view row
- **WHEN** the player chooses a row whose extract is already in view
- **THEN** the view does not move and its bubble opens

#### Scenario: Selected pin gives way
- **WHEN** a saved pin is selected and the player chooses a This raid row
- **THEN** only that marker is selected, and the pin's action bar closes

#### Scenario: Age advances
- **WHEN** the section stays shown for a minute after a match
- **THEN** the age it shows has advanced by a minute

#### Scenario: Later non-panel screenshot
- **WHEN** a later screenshot has no raid panel and the earlier matches are retained
- **THEN** the age shown stays that of the screenshot that matched them

### Requirement: Pins section manages this map's pins
The Map inspector SHALL end with a Pins section holding an Add pin action and one row per saved pin on the map, with its badge and label and no coordinates, frame or revision. Choosing a row SHALL open the pin editor, and each row SHALL offer removal with confirmation. While settings are being saved these actions SHALL be disabled.

#### Scenario: Pins listed
- **WHEN** the current map has two saved pins
- **THEN** both rows are shown with their labels and badges, and choosing one opens its editor

#### Scenario: No pins
- **WHEN** the current map has no saved pins
- **THEN** the section shows Add pin and the text "No saved pins for this map"

#### Scenario: Removal while saving
- **WHEN** settings are being saved
- **THEN** Add pin, row selection and removal do nothing

### Requirement: A selected pin has an action bar on the map
While a saved pin is selected, a bar at the bottom of the map SHALL show the pin's label with Edit, Remove and Close actions. It SHALL NOT take height from the map. While settings are being saved, Edit and Remove SHALL be disabled.

#### Scenario: Pin selected
- **WHEN** the player selects a saved pin on the map
- **THEN** the bar shows its label, Edit, Remove and Close, and the map keeps its height

#### Scenario: Pin closed
- **WHEN** the player chooses Close
- **THEN** the bar is gone and the pin is no longer selected

#### Scenario: Actions while saving
- **WHEN** settings are being saved while a pin is selected
- **THEN** Edit and Remove are disabled and Close still works

### Requirement: The map credit names the map's creator
The artwork attribution at the bottom left of the Map SHALL read `Map creator: <author>`, where `<author>` is the shown map's author from its map pack, in the theme's primary ink. When the pack gives no author for the map, it SHALL show the map's name alone, without the prefix. It SHALL stay one line and shorten with an ellipsis when it does not fit.

#### Scenario: Map with an author
- **WHEN** Map shows a loaded map whose pack names the author `Shebuka`
- **THEN** the attribution reads `Map creator: Shebuka` in the theme's primary ink

#### Scenario: Map without an author
- **WHEN** Map shows a loaded map whose pack gives no author and whose name is `Customs`
- **THEN** the attribution reads `Customs`, and no text on the Map begins `Map creator:`

#### Scenario: Long credit on a narrow map
- **WHEN** the author's name is longer than the space left beside the map controls
- **THEN** the attribution stays on one line, ends in an ellipsis and does not overlap the controls

### Requirement: Auto follows the sampled player position
Auto SHALL initially be on for a map with extents. A known position matches an extent in its lower-inclusive, upper-exclusive height range and inside or on an edge of one rectangle in game-space X/Z, if bounded. The narrowest matching height span SHALL win. Equal spans SHALL use ascending floor ID. A known unmatched position SHALL select base. Unknown height SHALL leave the selection unchanged.

#### Scenario: Position changes at the same height
- **WHEN** Auto is on and a Reserve position at height −9 moves from inside a command-bunker rectangle to outside every matching rectangle
- **THEN** Bunkers is selected at the first position and base at the second

#### Scenario: Height-only extent
- **WHEN** Auto is on and a Streets position at height −9 is followed by one at height 16
- **THEN** Underground is selected first and the 3rd Floor second, regardless of their horizontal coordinates

#### Scenario: Overlapping extents
- **WHEN** a position matches a wide extent and two equally narrow extents on floors `Narrow_A` and `Narrow_B`, with both floor and extent iteration order varied
- **THEN** `Narrow_A` wins in both orders

#### Scenario: Unknown height
- **WHEN** an Auto position update does not have a height
- **THEN** the current floor selection stays unchanged rather than falling back to ground

#### Scenario: Exclusive map
- **WHEN** the known position selects a non-base floor of an exclusive map
- **THEN** only the selected floor's layers are visible; on a later unmatched known position only the base floor's layers are visible

### Requirement: Manual floor selection overrides Auto
A manual floor selection SHALL disable Auto on that map, without affecting Auto on other maps. Re-enabling Auto SHALL apply the latest position if its floor resolves. Existing additive and exclusive visibility rules SHALL stay in force.

#### Scenario: Manual choice overrides Auto only on that map
- **WHEN** the player manually chooses a floor on one Auto-capable map, visits another Auto-capable map, then returns and receives a position on a different floor
- **THEN** Auto still follows samples on the second map, the first retains its manual floor, and re-enabling Auto on the first applies its latest known position

### Requirement: Unassigned markers use the prepared floor extents
A marker's explicit prepared floor ownership SHALL take precedence. An unassigned marker SHALL use the same position-based floor classification as player Auto, independent of whether Auto is currently on. A marker without a resolvable floor SHALL follow the existing unknown-floor visibility policy.

#### Scenario: Spatial inference for an unassigned marker
- **WHEN** an unassigned marker's position matches a hidden floor by both height and rectangle
- **THEN** that floor's visibility controls marker paint and hit eligibility

#### Scenario: Marker outside a rectangle
- **WHEN** an unassigned marker lies within a floor's extent height but outside every rectangle and no other extent matches
- **THEN** the marker is eligible on the base floor

#### Scenario: Explicit marker ownership
- **WHEN** a marker's explicit floor differs from its inferred floor
- **THEN** eligibility follows its explicit floor

### Requirement: A chosen floor fades the base floor
While any non-base floor is visible, the base floor and its attached layers SHALL be drawn faded, at one strength on every map, whether that floor is vector artwork or raster tiles. Otherwise the base SHALL be drawn at full strength. Chosen floors SHALL stay at full strength.

#### Scenario: Vector underground floor
- **WHEN** Reserve is shown and the player chooses Bunkers
- **THEN** the ground level is drawn faded under the bunkers

#### Scenario: Vector upper floor
- **WHEN** Streets is shown and the player chooses the second floor
- **THEN** the ground level, with its attached first floor, is drawn faded

#### Scenario: Tile floor over vector artwork
- **WHEN** Reserve is shown and the player chooses the second floor
- **THEN** the ground level is drawn faded at the same strength as under Bunkers

#### Scenario: Raster map
- **WHEN** Labs is shown and the Second Level is visible
- **THEN** the First Level is drawn faded

#### Scenario: Base only
- **WHEN** a map shows only its base floor and the layers attached to it
- **THEN** the base is drawn at full strength

#### Scenario: Exclusive floors
- **WHEN** Icebreaker is shown and the player chooses a floor other than its base
- **THEN** only the chosen floor is drawn, as before
