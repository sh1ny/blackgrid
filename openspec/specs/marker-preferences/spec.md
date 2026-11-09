# marker-preferences Specification

## Purpose

Defines how the Map rail's Marker preferences panel lets a player show or hide marker categories: the grid of icon tiles, the player-facing category labels and their order, the tile states, and the bulk and search controls that sit with them.

## Requirements

### Requirement: Category keys have fixed player-facing labels
Every saveable marker category key a prepared marker can carry, plus `CustomPins`, SHALL have one fixed player-facing label. Where a category name is shown for a key with no label, the key itself SHALL be shown.

#### Scenario: Labels for known keys
- **WHEN** the labels are read for `PmcExtracts`, `ScavExtracts`, `BossSpawns`, `BtrStops`, `lootContainers`, `lootLoose` and `CustomPins`
- **THEN** they are "PMC extracts", "Scav extracts", "Bosses", "BTR stops", "Containers", "Loose loot" and "Saved pins"

#### Scenario: Every known key is labelled
- **WHEN** the labels are read for each of the 19 marker category keys
- **THEN** each has a non-empty label, no two keys share a label, and the only labels equal to their key are the single words "Hazards", "Transits" and "Switches"

#### Scenario: Every saveable key has a label
- **WHEN** the saveable marker preference keys are compared with the labelled keys
- **THEN** they are the same set, apart from `Labels`, which no marker carries and which has no label

### Requirement: Bulk, search and quest controls keep working
Show all and Hide all SHALL set every row's category, and only those, to shown or hidden. They SHALL NOT write a key that is not a saveable marker preference. The marker search and the quest name filter SHALL behave as before this change. The quest trader filter SHALL be one chip per trader on this map plus All. An active trader not on this map SHALL stay shown as a selected chip. Save marker filters SHALL be in Settings. None of them SHALL change a row's shown or hidden state.

#### Scenario: Hide all then Show all
- **WHEN** the user clicks Hide all
- **THEN** every row shows the hidden state and no marker or pin is drawn, and after Show all every row shows the shown state and every marker is drawn

#### Scenario: Show all keeps other maps' choices
- **WHEN** `ScavSpawns` was hidden on another map and the current map has no `ScavSpawns` markers, and the user clicks Show all
- **THEN** the saved `ScavSpawns` entry is still hidden

#### Scenario: Bulk action with an unsaveable category
- **WHEN** the current map carries `Ziplines` markers, the user clicks Hide all and the app is started again with the same settings
- **THEN** the settings load, the saved filters hold no `Ziplines` entry, and the `Ziplines` markers were drawn throughout

#### Scenario: Search dims without hiding
- **WHEN** the user types `tunnel` in the marker search
- **THEN** non-matching markers are dimmed, and every row keeps its shown or hidden state

#### Scenario: Quest filter keeps tiles
- **WHEN** the user chooses the `Prapor` chip while "Quest items" is shown
- **THEN** the "Quest items" row still shows the shown state

#### Scenario: Active trader absent from the map
- **WHEN** the `Prapor` chip is active and the player switches to a map with no Prapor quests
- **THEN** a selected `Prapor` chip is still shown, and choosing All clears the filter

### Requirement: Marker lists use the category labels
The "Visible map markers and pins" list SHALL show each marker's category by its player-facing label, and each map marker's semantics label SHALL name its category the same way. A key with no label SHALL show the key.

#### Scenario: List subtitle uses the label
- **WHEN** the user opens the visible-markers list with a `lootLoose` marker named "Jacket"
- **THEN** that row's subtitle is "Loose loot", not `lootLoose`

#### Scenario: Unknown key in the list
- **WHEN** a visible marker carries the key `Ziplines`
- **THEN** its row's subtitle is `Ziplines`

### Requirement: Each applicable category is one marker row
The Markers section SHALL show one 30px row for each marker category the current map can show and Blackgrid can save as a preference, plus Saved pins. Each row SHALL show the category's map badge, its player-facing label, its count on this map and a toggle switch. It SHALL NOT show the raw category key when the key has a label.

#### Scenario: Rows for the current map
- **WHEN** Map shows a map with three `PmcExtracts`, one `Hazards` and two `lootLoose` markers and one saved pin
- **THEN** the section shows exactly four rows, "PMC extracts" 3, "Hazards" 1, "Loose loot" 2 and "Saved pins" 1, and no text `PmcExtracts`, `lootLoose` or `CustomPins`

#### Scenario: Unsaveable category gets no row
- **WHEN** the current map's markers carry `PmcExtracts` and a key `Ziplines` that is not a saveable marker preference
- **THEN** the section shows "PMC extracts" and "Saved pins" rows only, and the `Ziplines` markers are still drawn

#### Scenario: Map with no markers
- **WHEN** the current map has no prepared markers, or its prepared map is unavailable
- **THEN** the section shows only the "Saved pins" row

### Requirement: Rows follow a fixed grouped order
The rows SHALL appear under the group headings Extracts, Quests, Danger, Bosses, Spawns, Loot, Utility and Yours, in that order, omitting a group with no rows. Extracts holds the extract and transit categories, and Yours holds Saved pins. The order SHALL NOT depend on the raw key's spelling or on the order the map lists its markers in.

#### Scenario: Grouped order
- **WHEN** the current map shows `lootLoose`, `PmcExtracts`, `QuestItems`, `BossSpawns` and `locks`
- **THEN** the rows read, in order, "PMC extracts", "Quest items", "Bosses", "Loose loot", "Locks", "Saved pins" under their headings, and no Danger or Spawns heading is shown

#### Scenario: Map order does not matter
- **WHEN** one map lists its markers as `locks`, `PmcExtracts` and another lists them as `PmcExtracts`, `locks`
- **THEN** both show the rows "PMC extracts", "Locks", "Saved pins" in that order

### Requirement: Clicking a row shows or hides its category
Clicking anywhere on a row SHALL toggle its category's visibility: the same `markerFilters` entry changes, and it is restored on the next launch only when Save marker filters is on. While settings are being saved, the rows SHALL NOT respond to clicks.

#### Scenario: Hide one category
- **WHEN** every category is shown and the user clicks the "PMC extracts" row
- **THEN** `PmcExtracts` markers are no longer drawn, the other categories still are, and the row shows the hidden state

#### Scenario: Click while saving
- **WHEN** settings are being saved and the user clicks the "Hazards" row
- **THEN** the `Hazards` visibility does not change

### Requirement: Row state does not rely on colour alone
A shown row SHALL draw its badge at full opacity with its switch on. A hidden row SHALL draw its badge at the dimmed-marker opacity with a muted label and its switch off. The switch SHALL use ink, not Ember. Each row SHALL be announced to assistive technology as a toggle with its label and state.

#### Scenario: Shown and hidden rows differ
- **WHEN** "Scav extracts" is shown and "Hazards" is hidden
- **THEN** the "Scav extracts" switch is on with a full-opacity badge, and the "Hazards" switch is off with a badge at 22% opacity

#### Scenario: Semantics reflect the state
- **WHEN** "Hazards" is hidden
- **THEN** its row's semantics are a toggle labelled "Hazards" in the off state, and after a click they report the on state

### Requirement: Rows draw the map's badge and its fallback
A row's badge SHALL look like the category's unselected, undimmed badge on the map. Until the marker icons are loaded, and for a category whose icon failed to load, the row SHALL draw the map's fallback badge for that key. The list SHALL show and accept clicks without waiting for the icons.

#### Scenario: Icon row matches the map
- **WHEN** the icons are loaded and the "PMC extracts" row is shown
- **THEN** its badge has the exit-green ring and the `PmcExtracts` glyph tinted exit green, with no centre dot

#### Scenario: Icons still loading
- **WHEN** the section is shown before the icons finish loading
- **THEN** each row draws a fallback badge with a centre dot, clicking a row still toggles it, and once loading completes the rows redraw with their glyphs
