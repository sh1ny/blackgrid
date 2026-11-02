# map-help Specification

## Purpose
Defines the map's help button and what its help tells the player: how their position reaches the map and which controls the map offers.

## Requirements

### Requirement: The map toolbar has a help button
The map toolbar SHALL show a `?` icon button with the tooltip "Map help". It SHALL be enabled whether or not artwork is loaded. Activating it SHALL open a help dialog that closes with its Close button or Escape, and returns keyboard focus to the map.

#### Scenario: Open and close the help
- **WHEN** the user clicks the `?` button and then Close
- **THEN** the help dialog opens and then closes, and the map keeps its view, selection and pins

#### Scenario: Help without artwork
- **WHEN** no map artwork is loaded and the user clicks the `?` button
- **THEN** the help dialog opens with the same content

#### Scenario: Escape closes only the dialog
- **WHEN** the help dialog is open, a marker is selected, and the user presses Escape
- **THEN** the dialog closes and the marker stays selected

### Requirement: Help explains how the player's position reaches the map
The help SHALL say, in plain language, that the player's position and facing come from screenshots taken with the game's own screenshot key during a raid, which Blackgrid reads from the screenshot folder set in Settings, and that Blackgrid never captures the screen for this. It SHALL say that without such a screenshot the map shows no position. It SHALL NOT name a specific key binding, since the key is set in the game.

#### Scenario: Position section content
- **WHEN** the help dialog is open
- **THEN** it shows a position section that mentions the game's screenshot key, the screenshot folder in Settings, and that no screenshot means no position

#### Scenario: No promise of live capture
- **WHEN** the help dialog's text is read
- **THEN** it contains no claim that Blackgrid captures, records or watches the game screen to find the player

### Requirement: Help lists the map controls
The help SHALL list the map's pointer and keyboard controls: drag or arrow keys to pan, wheel or `+`/`-` to zoom, Home to fit, C to centre on the player, Enter to browse markers, N or right-click to add a pin, Delete to remove the selected pin, Escape to clear the selection, and hovering an extract to show its area. It SHALL use the same player-facing wording rules as the rest of the app.

#### Scenario: Controls section content
- **WHEN** the help dialog is open
- **THEN** it lists each control above with its action

#### Scenario: Help text has no developer wording
- **WHEN** the help dialog's text is checked against the player-facing text rules
- **THEN** it contains no raw enum names, filter keys or internal identifiers such as `PmcExtracts`
