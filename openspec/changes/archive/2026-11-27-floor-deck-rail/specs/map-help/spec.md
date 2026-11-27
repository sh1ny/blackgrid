## MODIFIED Requirements

### Requirement: Help lists the map controls
The help SHALL list the map's pointer and keyboard controls: drag or arrow keys to pan, wheel or `+`/`-` to zoom, Home to fit, C to centre on the player, Enter to browse markers, N or right-click to add a pin, Delete to remove the selected pin, Escape to clear selection on the canvas, and hovering an extract to show its area. It SHALL list Page Up and Page Down to step floors, A to toggle Auto, F to focus the floor rail, and Escape to return from the rail. It SHALL use the player-facing wording rules.

#### Scenario: Controls section content
- **WHEN** the help dialog is open
- **THEN** it lists each control above with its action

#### Scenario: Help text has no developer wording
- **WHEN** the help dialog's text is checked against the player-facing text rules
- **THEN** it contains no raw enum names, filter keys or internal identifiers such as `PmcExtracts`
