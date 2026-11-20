# Spec Delta

## MODIFIED Requirements

### Requirement: Settings sections and their order
The page SHALL list, in its sidebar and in its scrolling column, the sections General, Live scan, Item and map data, Local progress, Game files, Raid timers, Map and Diagnostics, in that order. Choosing a section in the sidebar SHALL scroll it into view and move keyboard focus to it. Choosing Diagnostics SHALL also expand it.

#### Scenario: Sidebar order
- **WHEN** Settings opens
- **THEN** the sidebar lists the eight sections in the order above, followed by nothing else, and no section is named Tracker progress

#### Scenario: Jump to a section
- **WHEN** the player chooses Raid timers in the sidebar
- **THEN** the Raid timers section title is in view and holds keyboard focus

#### Scenario: Jump to Diagnostics
- **WHEN** Diagnostics is collapsed and the player chooses it in the sidebar
- **THEN** Diagnostics is expanded and in view

### Requirement: Diagnostics starts collapsed each time
Diagnostics SHALL be the last section, and SHALL be collapsed each time the page opens, whatever state it had when the page last closed.

#### Scenario: Reopen
- **WHEN** the player expands Diagnostics, goes back to the Map and opens Settings again
- **THEN** Diagnostics is collapsed

#### Scenario: Open at a section
- **WHEN** Settings opens at Local progress from the status bar
- **THEN** Diagnostics is collapsed

### Requirement: Changes save as they are made
Every setting SHALL save when it is changed, with no Save button. Text fields SHALL save on Enter or when focus leaves them. A refused or failed save SHALL keep the previous saved value and show a message under its row. A settings load notice or save error SHALL show at the top of the page.

#### Scenario: Switch saves at once
- **WHEN** the player turns Save marker filters off
- **THEN** it is saved without any further action

#### Scenario: Settings could not be read
- **WHEN** the saved settings could not be read at startup
- **THEN** the top of the page shows the load notice

### Requirement: Every setting stays reachable
Every control the Settings dialog had SHALL have a row on the page, with the same effect and the same enabled and disabled rules: theme, game mode, refresh item data, refresh map data, game log folder, screenshot folder, follow logs, save marker filters, every raid timer setting, live scan, record scan frames, scan key, and Diagnostics. No other screen SHALL open the Settings dialog.

#### Scenario: All controls present
- **WHEN** Settings opens
- **THEN** each control in the list above is on the page, and no control mentions a Tracker token, Tracker progress or Refresh progress

#### Scenario: Disabled rule kept
- **WHEN** live scan is off
- **THEN** record scan frames is disabled, as it was in the dialog

## ADDED Requirements

### Requirement: Settings opens at the section a link names
A link that names a section (the status bar's Item data and Progress items, and any other) SHALL open the page with that section in view and focused. When the page is already open, the link SHALL scroll to that section without reopening the page.

#### Scenario: Status bar Progress
- **WHEN** the player activates the status bar's Progress item from the Scanner
- **THEN** Settings opens with Local progress in view and focused, and Back returns to the Scanner

#### Scenario: Already open
- **WHEN** Settings is open at General and the player activates the status bar's Item data item
- **THEN** Item and map data scrolls into view, and Back still returns to the area Settings was first opened from

## REMOVED Requirements

### Requirement: Tracker progress section
**Reason**: The Tracker integration is removed.
**Migration**: Progress is shown and entered in Settings → Local progress; saved tokens are deleted at startup.

### Requirement: Settings opens at a requested section
**Reason**: Replaced by "Settings opens at the section a link names", which names the status bar's Progress item instead of the removed Tracker item.
**Migration**: None; links behave as before.
