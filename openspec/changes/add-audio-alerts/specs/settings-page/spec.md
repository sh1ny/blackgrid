# Spec Delta

## MODIFIED Requirements

### Requirement: Settings sections and their order
The page SHALL list, in its sidebar and in its scrolling column, the sections General, Live scan, Item and map data, Local progress, Game files, Raid timers, Alerts, Map and Diagnostics, in that order. Choosing a section in the sidebar SHALL scroll it into view and move keyboard focus to it. Choosing Diagnostics SHALL also expand it.

#### Scenario: Sidebar order
- **WHEN** Settings opens
- **THEN** the sidebar lists the nine sections in the order above, followed by nothing else, and no section is named Tracker progress

#### Scenario: Jump to a section
- **WHEN** the player chooses Raid timers in the sidebar
- **THEN** the Raid timers section title is in view and holds keyboard focus

#### Scenario: Jump to Alerts
- **WHEN** the player chooses Alerts in the sidebar
- **THEN** the Alerts section title is in view and holds keyboard focus

#### Scenario: Jump to Diagnostics
- **WHEN** Diagnostics is collapsed and the player chooses it in the sidebar
- **THEN** Diagnostics is expanded and in view
