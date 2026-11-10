# Spec Delta

## ADDED Requirements

### Requirement: Diagnostics shows map data detail
Expanded, Diagnostics' Data sources part SHALL describe the map data: the mode selected for it, the mode whose data the map uses, its source, and the time of the last map data check. The visible Settings rows SHALL NOT show these lines.

#### Scenario: Fallback map data
- **WHEN** the selected mode is PvE, the map uses bundled PvP data, and Diagnostics is expanded
- **THEN** Data sources shows the selected mode PvE, the map data mode PvP and the bundled source

#### Scenario: Never checked
- **WHEN** no map data check has completed and Diagnostics is expanded
- **THEN** Data sources says the map data has not been checked, and the Item and map data section shows no source or mode line
