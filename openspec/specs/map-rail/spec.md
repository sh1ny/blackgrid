# map-rail Specification

## Purpose
Defines what the Map screen's side rail shows and in what order, so the sections a player reads in a raid come first and the developer-facing saved-file inputs stay out of the way until asked for.

## Requirements

### Requirement: Map saved-file inputs starts collapsed
Settings SHALL end with a collapsible Diagnostics section that starts collapsed each time Settings opens. Collapsed, it SHALL show only its title row. Expanded, it SHALL show the map input status lines. The log, screenshot and raid panel status lines SHALL show plain-language labels, never raw state names, and their times SHALL be in local time. Collapsing SHALL NOT change any map input setting. The Follow logs switch SHALL be in Settings and Read Latest SHALL be in the map picker, not in this section.

#### Scenario: Collapsed on first show
- **WHEN** Settings is opened
- **THEN** the "Diagnostics" title is shown, and no "Logs:" or "Screenshots:" status line is shown

#### Scenario: Expanding shows the inputs
- **WHEN** the user clicks the collapsed "Diagnostics" title
- **THEN** the status lines are shown, and no Read Latest button is in the section

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
While Diagnostics is collapsed, Settings SHALL NOT run a timer that refreshes the saved-file age. Expanding the section SHALL show the current age, and the age SHALL then update once a second as before.

#### Scenario: No ticking while collapsed
- **WHEN** a saved screenshot with a known modification time is the evidence source and the section is collapsed
- **THEN** the saved-file status content is not in the widget tree, so nothing refreshes the saved-file age

#### Scenario: Age resumes on expand
- **WHEN** the section is expanded with that saved screenshot
- **THEN** the "Saved evidence age" line is shown with the age at the time of expansion, and the saved-file status stays mounted while the section is expanded, so its once-a-second refresh runs as before
