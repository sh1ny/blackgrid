# marker-preferences Specification

## Purpose

Defines how the Map rail's Marker preferences panel lets a player show or hide marker categories: the grid of icon tiles, the player-facing category labels and their order, the tile states, and the bulk and search controls that sit with them.

## Requirements

### Requirement: Each applicable category is one icon tile
Marker preferences SHALL show one tile for each marker category the current map can show and Blackgrid can save as a preference, plus Saved pins. Each tile SHALL show the category's map badge above its player-facing label. Every tile SHALL have the same width and height, whatever its label's length, and SHALL NOT show the raw category key when the key has a label.

#### Scenario: Tiles for the current map
- **WHEN** Map shows a map whose markers carry `PmcExtracts`, `Hazards` and `lootLoose`
- **THEN** the panel shows exactly four tiles, labelled "PMC extracts", "Hazards", "Loose loot" and "Saved pins", and no text `PmcExtracts`, `lootLoose` or `CustomPins`

#### Scenario: Tiles are the same size
- **WHEN** the panel shows the "BTR stops" and "Stationary weapons" tiles
- **THEN** both tiles have the same width and the same height

#### Scenario: Unsaveable category gets no tile
- **WHEN** the current map's markers carry `PmcExtracts` and a key `Ziplines` that is not a saveable marker preference
- **THEN** the panel shows "PMC extracts" and "Saved pins" tiles only, and the `Ziplines` markers are still drawn

#### Scenario: Map with no markers
- **WHEN** the current map has no prepared markers, or its prepared map is unavailable
- **THEN** the panel shows only the "Saved pins" tile

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

### Requirement: Tiles follow a fixed grouped order
The tiles SHALL appear in a fixed order that groups related categories: extracts and transits, then quests, then danger (hazards, bosses, cultists), then spawns, then loot, then utility, then Saved pins last. The order SHALL NOT depend on the raw key's spelling or on the order the map lists its markers in.

#### Scenario: Grouped order
- **WHEN** the current map shows `lootLoose`, `PmcExtracts`, `QuestItems`, `BossSpawns` and `locks`
- **THEN** the tiles read, in order, "PMC extracts", "Quest items", "Bosses", "Loose loot", "Locks", "Saved pins"

#### Scenario: Map order does not matter
- **WHEN** one map lists its markers as `locks`, `PmcExtracts` and another lists them as `PmcExtracts`, `locks`
- **THEN** both show the tiles "PMC extracts", "Locks", "Saved pins" in that order

### Requirement: Clicking a tile shows or hides its category
Clicking anywhere on a tile SHALL toggle its category's visibility, exactly as the category's filter did before this change: the same `markerFilters` entry changes, and it is restored on the next launch only when Save marker filters is on. While settings are being saved, the tiles SHALL NOT respond to clicks.

#### Scenario: Hide one category
- **WHEN** every category is shown and the user clicks the "PMC extracts" tile
- **THEN** `PmcExtracts` markers are no longer drawn, the other categories still are, and the tile shows the hidden state

#### Scenario: Show it again
- **WHEN** "PMC extracts" is hidden and the user clicks its tile
- **THEN** `PmcExtracts` markers are drawn again and the tile shows the shown state

#### Scenario: Click while saving
- **WHEN** settings are being saved and the user clicks the "Hazards" tile
- **THEN** the `Hazards` visibility does not change

### Requirement: Tile state does not rely on colour alone
A shown tile SHALL draw its badge at full opacity with a check mark. A hidden tile SHALL draw its badge at the dimmed-marker opacity with a muted label and no check mark. Each tile SHALL be announced to assistive technology as a toggle with its label and its shown or hidden state.

#### Scenario: Shown and hidden tiles differ without colour
- **WHEN** "Scav extracts" is shown and "Hazards" is hidden
- **THEN** the "Scav extracts" tile has a check mark and a full-opacity badge, and the "Hazards" tile has no check mark and a badge at 22% opacity

#### Scenario: Semantics reflect the state
- **WHEN** "Hazards" is hidden
- **THEN** its tile's semantics are a toggle labelled "Hazards" in the off state, and after a click they report the on state

### Requirement: Tiles draw the map's badge and its fallback
A tile's badge SHALL look like the category's unselected, undimmed badge on the map: the same disc, ring colour and glyph. Until the marker icons are loaded, and for a category whose icon failed to load, the tile SHALL draw the map's fallback badge for that key. The grid SHALL show and accept clicks without waiting for the icons, and SHALL redraw with the icons once they load.

#### Scenario: Icon tile matches the map
- **WHEN** the icons are loaded and the "PMC extracts" tile is shown
- **THEN** its badge has the exit-green ring and the `PmcExtracts` glyph tinted exit green, with no centre dot

#### Scenario: Icons still loading
- **WHEN** the panel is shown before the icons finish loading
- **THEN** each tile draws a fallback badge with a centre dot, clicking a tile still toggles it, and once loading completes the tiles redraw with their glyphs

#### Scenario: One icon failed
- **WHEN** the `locks` icon failed to decode and the rest loaded
- **THEN** the "Locks" tile draws the fallback badge in the utility colour and every other tile draws its glyph

### Requirement: Bulk, search and quest controls keep working
Show all and Hide all SHALL set every tile's category, and only those, to shown or hidden. They SHALL NOT write a key that is not a saveable marker preference. The marker search, the quest name and trader filters and Save marker filters SHALL behave as before this change, and none of them SHALL change a tile's shown or hidden state.

#### Scenario: Hide all then Show all
- **WHEN** the user clicks Hide all
- **THEN** every tile shows the hidden state and no marker or pin is drawn, and after Show all every tile shows the shown state and every marker is drawn

#### Scenario: Show all keeps other maps' choices
- **WHEN** `ScavSpawns` was hidden on another map and the current map has no `ScavSpawns` markers, and the user clicks Show all
- **THEN** the saved `ScavSpawns` entry is still hidden

#### Scenario: Bulk action with an unsaveable category
- **WHEN** the current map carries `Ziplines` markers, the user clicks Hide all and the app is started again with the same settings
- **THEN** the settings load, the saved filters hold no `Ziplines` entry, and the `Ziplines` markers were drawn throughout

#### Scenario: Search dims without hiding
- **WHEN** the user types `tunnel` in the marker search
- **THEN** non-matching markers are dimmed, and every tile keeps its shown or hidden state

#### Scenario: Quest filter keeps tiles
- **WHEN** the user sets Quest trader to `Prapor` while "Quest items" is shown
- **THEN** the "Quest items" tile still shows the shown state

### Requirement: Marker lists use the category labels
The "Visible map markers and pins" list SHALL show each marker's category by its player-facing label, and each map marker's semantics label SHALL name its category the same way. A key with no label SHALL show the key.

#### Scenario: List subtitle uses the label
- **WHEN** the user opens the visible-markers list with a `lootLoose` marker named "Jacket"
- **THEN** that row's subtitle is "Loose loot", not `lootLoose`

#### Scenario: Unknown key in the list
- **WHEN** a visible marker carries the key `Ziplines`
- **THEN** its row's subtitle is `Ziplines`
