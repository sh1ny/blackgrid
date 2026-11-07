# map-marker-popups Specification

## Purpose

Gives players readable information at a selected built-in map marker while preserving map navigation, accessibility and truthful use of prepared data.

## Requirements

### Requirement: Marker selection opens one bubble
The map SHALL show one marker information bubble when an eligible built-in marker is selected by pointer, the marker browser or accessibility action. Selecting another marker SHALL replace its contents without changing the map view.

#### Scenario: Select a marker
- **WHEN** a player selects an eligible marker by clicking its badge, choosing it in the marker browser, or activating its accessibility target
- **THEN** one bubble shows that marker and the map view does not move

#### Scenario: Overlapping badges
- **WHEN** multiple eligible badges are within the inclusive hit radius at equal distance from a pointer selection
- **THEN** the topmost painted badge is selected; a strictly nearer eligible badge wins regardless of paint order

#### Scenario: Replace selection
- **WHEN** a player selects a different eligible marker while a bubble is open
- **THEN** the bubble shows the new marker and no bubble for the previous marker remains

#### Scenario: Stale browser result
- **WHEN** map content changes while the marker browser is open and the player chooses an old result
- **THEN** the old marker is not selected and no stale bubble appears

### Requirement: Marker selection is cleared consistently
Closing the bubble, pressing Escape on the map, clicking empty map space or selecting a saved pin SHALL clear marker selection and its selection-linked highlights. Saved-pin details and editing SHALL remain available.

#### Scenario: Close marker bubble
- **WHEN** a marker and its linked switches are highlighted and the player activates the bubble's Close control
- **THEN** the bubble, marker selection and selection-linked switch highlights disappear

#### Scenario: Pin selection
- **WHEN** a marker is selected and the player selects a saved pin
- **THEN** marker selection and its bubble clear and the pin's details remain available

#### Scenario: Empty map and Escape
- **WHEN** a marker is selected and the player clicks empty map space or presses Escape with the map active
- **THEN** marker selection and its bubble clear

### Requirement: Bubble tracks the badge within the viewport
The bubble SHALL use the selected badge's projected anchor, stay within the map viewport and remain fixed in screen size across map zoom. It SHALL prefer placement above the badge, then below, clamp to available space and visibly tether to the anchor when displaced. Long content SHALL scroll.

#### Scenario: Pan and zoom
- **WHEN** a selected marker remains onscreen while the player pans or zooms
- **THEN** the bubble follows its projected badge, stays inside the viewport and retains its screen-size text

#### Scenario: Edge or small viewport
- **WHEN** a selected badge is near a viewport edge or its bubble cannot fit above it
- **THEN** the bubble uses space below where possible, is clamped inside the viewport and remains visibly tethered to the badge

#### Scenario: Long content
- **WHEN** the bubble's contents exceed its available height
- **THEN** the bubble stays within the viewport and the remaining contents can be scrolled into view

### Requirement: Offscreen and ineligible selections differ
A selected eligible marker SHALL remain selected while its badge anchor is offscreen, with its bubble hidden until the anchor re-enters the viewport. Selection SHALL clear permanently when floor, category or quest filtering makes the marker ineligible, or map content is replaced.

#### Scenario: Anchor leaves and returns
- **WHEN** panning moves the selected badge anchor outside the viewport and then back inside
- **THEN** its bubble hides while outside and returns for the same selection on re-entry

#### Scenario: Outline remains visible but anchor leaves
- **WHEN** a selected marker's outline intersects the viewport but its badge anchor is outside
- **THEN** the bubble is hidden and the marker remains selected

#### Scenario: Eligibility or content changes
- **WHEN** a selected marker becomes ineligible through floor, category or quest filtering, or the selected map or its content is replaced
- **THEN** selection, bubble and selection-linked highlights clear and do not return merely because the filter is reversed

#### Scenario: Search only dims
- **WHEN** marker search dims the selected marker without making it ineligible
- **THEN** the selection remains and its bubble continues to follow its anchor

### Requirement: Bubble interaction respects map and focus
The bubble SHALL expose named, keyboard-operable controls and SHALL consume its own pointer and scroll input without selecting, panning or zooming the map. Uncovered map space SHALL retain navigation. Focused bubble controls SHALL receive their keys before map shortcuts; an open modal SHALL receive Escape before the map.

#### Scenario: Operate and scroll inside bubble
- **WHEN** the player clicks a bubble control or scrolls over its content
- **THEN** that control or content responds without a map click, pan or zoom

#### Scenario: Navigate outside bubble
- **WHEN** the player drags or uses the wheel on uncovered map space
- **THEN** the map pans or zooms and the selected bubble tracks the marker

#### Scenario: Keyboard and help precedence
- **WHEN** a bubble control has keyboard focus and the player presses Enter, N or Delete, or the map help dialog is open and Escape is pressed
- **THEN** the focused control receives its applicable key without a map shortcut, or help closes without clearing marker selection, respectively

#### Scenario: Popup focus isolates map navigation keys
- **WHEN** a bubble control has focus and the player presses a map navigation shortcut, including an arrow key
- **THEN** the map does not pan or zoom, and input handled by the focused control is not stolen

#### Scenario: Accessible dismissal
- **WHEN** a player navigates to the bubble's labelled Close control using the keyboard or assistive technology and activates it
- **THEN** the marker selection clears and keyboard focus remains usable on the map

### Requirement: Summaries reflect prepared marker facts
The bubble SHALL use player-facing category and marker names from the active validated marker generation, whether downloaded, cached or bundled, and show available category-specific facts without inventing data or initiating a map-data request. Quest markers show their quest and objective or item text; extracts show linked switch names and required or payment item counts; locks show lock type and key name; containers show their name; bosses show their name and available boss-wide spawn chance.

#### Scenario: Quest and container
- **WHEN** a selected quest objective contains a translated quest name and objective description, or a container has an available display name
- **THEN** the bubble shows those available names and description in plain language

#### Scenario: Linked extract and lock
- **WHEN** an extract contains a required item count and a source link to a named switch on the same map, or a lock has a lock type and a named key
- **THEN** the bubble shows the count and item name and linked switch name, or the lock type and key name, respectively

#### Scenario: Missing or misleading fields
- **WHEN** an optional fact is absent, a marker name is only its raw category key, a switch is not source-linked on the same map, or a boss chance is missing or invalid
- **THEN** the bubble uses the player-facing category label instead of the raw fallback name, omits unavailable optional facts and does not invent a switch or chance

#### Scenario: Boss chance scope
- **WHEN** the active boss-wide spawn chance is 0.35
- **THEN** the bubble presents 35% as the boss spawn chance and does not claim it is the chance for that location

#### Scenario: Refreshed marker facts
- **WHEN** a validated replacement changes a marker's facts and the player selects a marker from that generation
- **THEN** the bubble shows the new available facts without initiating a map-data request

### Requirement: Item names use only the matching loaded catalog
The bubble SHALL resolve item and key names from the already loaded catalog for the active mode, including its last-good snapshot, and SHALL update when that catalog changes. Opening or updating a bubble SHALL NOT initiate a catalog request. Unresolved names SHALL say they are unavailable without displaying raw IDs.

#### Scenario: Loaded name and update
- **WHEN** an active-mode catalog resolves a required item and a later active-mode catalog gives it a different name
- **THEN** the open bubble shows the first name and updates to the later name without initiating a request

#### Scenario: Missing, mismatched or failed catalog
- **WHEN** the catalog is absent, belongs to another mode, lacks the ID, or refresh fails without a matching last-good name
- **THEN** the bubble says the item or key name is unavailable and does not show its ID in the summary

#### Scenario: Failed refresh with last-good data
- **WHEN** refresh fails but the active-mode last-good catalog contains the key
- **THEN** the bubble continues to show that key's last-good name without a popup-triggered request

### Requirement: Marker bubbles contain summaries only
The bubble SHALL show only player-facing marker summaries and SHALL NOT expose raw Details, diagnostic previews, category or filter keys, coordinates, or source fields. Prepared marker details and source SHALL remain available internally for summary derivation.

#### Scenario: Summary without raw details
- **WHEN** a marker with raw category, filter, coordinates and source data is selected
- **THEN** its available player-facing summary is shown without a Details control or raw diagnostic data
