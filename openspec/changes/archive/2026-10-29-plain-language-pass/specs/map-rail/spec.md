# Spec Delta

## MODIFIED Requirements

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
