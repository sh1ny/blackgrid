# Spec Delta

## MODIFIED Requirements

### Requirement: Game files section
Game files SHALL hold the game log folder and the screenshot folder, each saved on Enter or when focus leaves the field, then the screenshot cleanup switch "Delete a raid's screenshots after it ends", saved as soon as it is toggled, with its last-result line under it, and Follow logs. An empty folder SHALL mean the default location, as today. A folder save that fails SHALL keep the typed text and show that it was not saved.

#### Scenario: Save a folder on Enter
- **WHEN** the player types `D:\Shots` in the screenshot folder and presses Enter
- **THEN** `D:\Shots` is saved as the screenshot folder

#### Scenario: Save on leaving
- **WHEN** the player types a game log folder and moves focus to another row
- **THEN** that folder is saved

#### Scenario: Save fails
- **WHEN** saving a typed folder fails
- **THEN** the field keeps the typed text, says it was not saved, and the folder in use is unchanged

#### Scenario: The cleanup switch sits under the screenshot folder
- **WHEN** the player opens Game files
- **THEN** the cleanup switch follows the screenshot folder row and is off until the player switches it on

#### Scenario: Switching cleanup on
- **WHEN** the player switches cleanup on
- **THEN** the setting is saved at once and Follow logs and both folders are unchanged
