# map-rail Specification

## Purpose
Defines what the Map screen's side rail shows and in what order, so the sections a player reads in a raid come first and the developer-facing saved-file inputs stay out of the way until asked for.

## Requirements

### Requirement: Rail order puts raid-time sections first
The Map screen SHALL show the shared answer strip before its workspace and rail. The rail SHALL retain Active map, Marker preferences, Manual item search and Map saved-file inputs, in that order, until map restyling moves them. It SHALL NOT duplicate the strip's decision card. These controls SHALL remain reachable in wide and compact layouts.

#### Scenario: Wide layout order
- **WHEN** Map is shown in a window at least 1100 px wide
- **THEN** the answer strip precedes the workspace and the rail retains Active map, Marker preferences, Manual item search and Map saved-file inputs in that order

#### Scenario: Compact layout order
- **WHEN** Map is shown in a window narrower than 1100 px
- **THEN** the answer strip remains above the map workspace and the retained rail controls are reachable below or beside it in the same order

#### Scenario: Active map row stays alone
- **WHEN** a scan has been accepted
- **THEN** the shared strip shows the current inspection, the Active map row stays alone, and no duplicate decision card or Latest accepted scan panel appears in the rail

### Requirement: Map saved-file inputs starts collapsed
Map saved-file inputs SHALL be a collapsible section that starts collapsed. Collapsed, it SHALL show only its title row, with none of its status lines, the Follow logs switch or the Read Latest button. Expanding it SHALL show the status lines, the Follow logs switch and the Read Latest button. The log, screenshot and raid panel status lines SHALL show plain-language labels, never raw state names, and their times SHALL be in local time. Collapsing SHALL NOT change any map input setting.

#### Scenario: Collapsed on first show
- **WHEN** Map is shown for the first time after launch
- **THEN** the "Map saved-file inputs" title is shown, and no "Logs:" or "Screenshots:" status line, no Follow logs switch and no Read Latest button is shown

#### Scenario: Expanding shows the inputs
- **WHEN** the user clicks the collapsed "Map saved-file inputs" title
- **THEN** the status lines, the Follow logs switch and the Read Latest button are shown, and Read Latest reads the latest screenshot when clicked

#### Scenario: Status lines use labels
- **WHEN** the section is expanded while the log folder is being watched and the screenshot folder is missing
- **THEN** the "Logs:" line says the folder is being watched and the "Screenshots:" line says the folder was not found, and neither line contains `watching` or `missing` as a bare state name

#### Scenario: Collapsing keeps settings
- **WHEN** Follow logs is off, the user expands the section and then collapses it
- **THEN** Follow logs is still off, and the selected map and the stored manual map are unchanged

#### Scenario: Pending screenshot while collapsed
- **WHEN** the section is collapsed and a saved screenshot is being processed
- **THEN** the section stays collapsed, and expanding it shows the processing line for that screenshot

### Requirement: Collapsed section does no periodic work
While Map saved-file inputs is collapsed, the rail SHALL NOT run a timer that refreshes the saved-file age. Expanding the section SHALL show the current age, and the age SHALL then update once a second as before.

#### Scenario: No ticking while collapsed
- **WHEN** a saved screenshot with a known modification time is the evidence source and the section is collapsed
- **THEN** the saved-file status content is not in the widget tree, so nothing refreshes the saved-file age

#### Scenario: Age resumes on expand
- **WHEN** the section is expanded with that saved screenshot
- **THEN** the "Saved evidence age" line is shown with the age at the time of expansion, and the saved-file status stays mounted while the section is expanded, so its once-a-second refresh runs as before

### Requirement: Expansion state lasts for the session only
The expanded or collapsed state of Map saved-file inputs SHALL survive switching between Map and Scanner, and a resize across the compact-layout breakpoint. It SHALL NOT be saved to settings, so each launch starts collapsed.

#### Scenario: Survives a tab switch
- **WHEN** the user expands the section, switches to Scanner and back to Map
- **THEN** the section is still expanded

#### Scenario: Survives a layout change
- **WHEN** the user expands the section in the wide layout and the window narrows below 1100 px
- **THEN** the section is still expanded in the compact layout

#### Scenario: New launch starts collapsed
- **WHEN** the section was expanded and the app is started again with the same settings
- **THEN** the section is collapsed
