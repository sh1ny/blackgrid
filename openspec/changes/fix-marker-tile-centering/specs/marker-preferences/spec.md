## MODIFIED Requirements

### Requirement: Each applicable category is one icon tile
Marker preferences SHALL show one tile for each marker category the current map can show and Blackgrid can save as a preference, plus Saved pins. Each tile SHALL show the category's map badge above its player-facing label, both centred horizontally in the tile whatever the label's length. Every tile SHALL have the same width and height, whatever its label's length, and SHALL NOT show the raw category key when the key has a label.

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


#### Scenario: One-line and two-line labels are centred
- **WHEN** the panel shows the "Locks" tile, whose label fits on one line, and the "Stationary weapons" tile, whose label wraps to two lines
- **THEN** in each tile the badge's horizontal centre and the label's horizontal centre equal the tile's horizontal centre

#### Scenario: Centred at a larger tile scale
- **WHEN** the grid is drawn with tiles scaled larger than the default
- **THEN** the "Locks" tile's badge and label are still centred horizontally in the tile
