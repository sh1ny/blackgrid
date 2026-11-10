# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: The Data sources panel shows the catalog error`
- TO: `### Requirement: Settings shows the catalog error`

## MODIFIED Requirements

### Requirement: Settings shows the catalog error
When the catalog has an error, the Item and map data section of Settings SHALL show that error text with the item data line, and SHALL show no catalog error once a refresh succeeds. Item names that could not be loaded SHALL be reported there too. The status bar's item data status SHALL lead to that section, as workspace-shell requires.

#### Scenario: Failure shown in the panel
- **WHEN** a catalog refresh fails while a snapshot is kept
- **THEN** the Item and map data section shows "out of date" for item data and the error text, and the status bar shows item data out of date

#### Scenario: Error cleared by a successful refresh
- **WHEN** a later refresh succeeds
- **THEN** the section shows "up to date" and no catalog error

#### Scenario: Item names that could not be loaded
- **GIVEN** a snapshot whose localized names failed for one language
- **WHEN** the Item and map data section is shown
- **THEN** it says some item names could not be loaded, with the failure text
