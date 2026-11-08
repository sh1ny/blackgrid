# Workspace shell

## Purpose
Makes the current item and keep/sell answer immediately visible on Map and Scanner while keeping detail and configuration reachable.

## ADDED Requirements

### Requirement: Answer precedes the workspace
Map and Scanner SHALL show the current item picture and name, verdict plate, full reason, price freshness and per-item Found in raid directly below the top bar, before workspace or configuration content. The strip SHALL use DESIGN.md X10 in both rooms and grow to fit wrapped content. Raw item IDs SHALL NOT appear below item names.

#### Scenario: Answer first in both areas
- **WHEN** each area is shown at 1660 by 870 and 960 by 720 logical pixels
- **THEN** the strip is visible without scrolling directly below the top bar and above the workspace, with no configuration panel above it

#### Scenario: Missing item and long reason
- **WHEN** no item is selected, or an item's reason is too long for one line
- **THEN** the strip shows an explicit empty state without a verdict, or wraps the complete reason without overflow respectively

### Requirement: Selection semantics survive the new layout
The strip and inspector SHALL reflect the same current inspection. Existing manual selection, scan correction, history inspection, close-history and return-to-latest-scan actions SHALL remain available. Found in raid SHALL retain existing per-item reset, history and authority rules.

#### Scenario: Selection changes across areas
- **WHEN** an item is selected by search and the user switches between Map and Scanner
- **THEN** both areas show the same inspection and Found in raid value

#### Scenario: History and later rejected scan
- **WHEN** history is inspected or a later scan is rejected after an accepted scan
- **THEN** existing history isolation and accepted-item retention still apply, with no rejected candidate presented as an accepted answer

### Requirement: Top bar keeps navigation and timers reachable
The top bar SHALL contain the brand, Map/Scanner switch, item search with Ctrl K, enabled raid timers, inspector toggle and Settings, Stats and Import. It SHALL follow DESIGN.md X11: narrow layouts use the hex logo and icon actions with accessible labels and tooltips. Timer visibility and calculations SHALL use existing settings and rules.

#### Scenario: Wide navigation
- **WHEN** the wide shell is shown with all timers enabled
- **THEN** all three timers and labelled Settings, Stats and Import actions are in the top bar

#### Scenario: Narrow navigation and disabled timers
- **WHEN** the window is 960px wide and timer settings hide one timer
- **THEN** the remaining timers and all actions remain reachable without horizontal page scrolling, hidden timers are absent, and icon actions retain names and tooltips

### Requirement: Inspector preserves the workspace
Detailed inspection, requirements, sources and item history SHALL be reachable in an inspector. At widths at most 1080px it SHALL float with a scrim; closing or resizing it SHALL keep the underlying workspace mounted and return focus to its opener. Panel motion SHALL follow DESIGN.md and reduced-motion settings.

#### Scenario: Docked details
- **WHEN** the inspector is opened in a wide window
- **THEN** it shows inspection details beside the workspace without replacing the current subject

#### Scenario: Resize with open details
- **WHEN** an open inspector crosses the 1080px threshold and is then closed with Escape
- **THEN** it becomes an overlay, preserves selection and detail expansion state, and returns focus to the opener without resetting the map viewport

### Requirement: History rows show item pictures
The inspector SHALL use DESIGN.md X14 history rows with picture, name, recorded-verdict indicator and age. Pictures SHALL follow existing icon fallback rules. Dots SHALL use saved verdicts, never current advice. Missing verdicts SHALL show a distinct unknown indicator labelled "Verdict not recorded". Opening a row SHALL preserve existing history-inspection semantics and label its current advice separately from the recorded verdict.

#### Scenario: History selection
- **WHEN** a pictured history row is selected
- **THEN** the history inspection opens for that row with its recorded item identity and mode, and its row dot continues to show the saved verdict even if the current advice differs

#### Scenario: Missing history picture
- **WHEN** a history item's picture cannot load
- **THEN** its fallback frame and name remain visible and the row remains selectable


#### Scenario: Legacy history verdict
- **WHEN** a row has no stored verdict
- **THEN** its indicator says "Verdict not recorded" and does not use any of the six known verdict indicators

### Requirement: Status actions lead to their controls
The status bar SHALL let the user switch game mode, open Item data or Tracker Settings at the relevant section, and toggle live scan. Displaced configuration SHALL remain in the existing Settings dialog until the Settings page replaces it. Live scan status SHALL state actual pipeline state and use DESIGN.md X4.

#### Scenario: Settings targets
- **WHEN** the Item data or Tracker status is activated
- **THEN** Settings opens with that section visible and keyboard reachable

#### Scenario: Failed live scan save
- **WHEN** live scan is toggled through the status bar and saving fails
- **THEN** existing switch-on rollback and switch-off stopping rules apply and the error is visible; the status never falsely claims listening
