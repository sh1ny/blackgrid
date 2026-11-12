# Spec Delta

## MODIFIED Requirements

### Requirement: Settings sections and their order
The page SHALL list, in its sidebar and in its scrolling column, the sections General, Live scan, Item and map data, Tracker progress, Local progress, Game files, Raid timers, Map and Diagnostics, in that order. Choosing a section in the sidebar SHALL scroll it into view and move keyboard focus to it. Choosing Diagnostics SHALL also expand it.

#### Scenario: Sidebar order
- **WHEN** Settings opens
- **THEN** the sidebar lists the nine sections in the order above, followed by nothing else

#### Scenario: Jump to a section
- **WHEN** the player chooses Raid timers in the sidebar
- **THEN** the Raid timers section title is in view and holds keyboard focus

#### Scenario: Jump to Diagnostics
- **WHEN** Diagnostics is collapsed and the player chooses it in the sidebar
- **THEN** Diagnostics is expanded and in view

## ADDED Requirements

### Requirement: Local progress section
Local progress SHALL hold one row per game mode (PvP, PvE, seasonal) showing its wipe's start date and last log folder read, "No wipe yet", or that the wipe is unavailable. Each row SHALL have "Replay game logs", with a date that defaults to the wipe's start, and "Start a new wipe", with a required start date. The section SHALL show the running read, or the last run's result.

#### Scenario: Wipe shown
- **WHEN** PvE's wipe started 2026-11-01 and its last folder read is `log_2026.11.10_19-12-03_1.3.0.0.48484`
- **THEN** the PvE row shows the start date 2026-11-01 and that folder name, and its replay date defaults to 2026-11-01

#### Scenario: No wipe yet
- **WHEN** seasonal mode has no wipe
- **THEN** its row says "No wipe yet" and its replay date has no default until the player picks one

#### Scenario: Last result shown
- **WHEN** a PvE replay has finished reading 12 folders, recording 9 task events and skipping 1 message for no mode
- **THEN** the section shows that result with the mode and the time it finished

### Requirement: Local progress actions are disabled with a reason
Replay game logs and Start a new wipe SHALL be disabled while the player is queued, loading or in a raid, while another catch-up, replay or new wipe is running, and while no game log folder is found, each with its reason beside the actions. Start a new wipe SHALL ask the player to confirm, naming the mode and the new start date.

#### Scenario: In a raid
- **WHEN** the raid lifecycle phase is in raid
- **THEN** both actions are disabled in every row and the section says they are not available during a raid

#### Scenario: Confirm a new wipe
- **WHEN** the player chooses Start a new wipe for PvP with date 2026-11-12
- **THEN** a confirmation names PvP and 2026-11-12, and no cycle is created unless the player confirms

#### Scenario: Confirmation cancelled
- **WHEN** the player cancels the new-wipe confirmation
- **THEN** PvP's active wipe is unchanged and nothing is read
