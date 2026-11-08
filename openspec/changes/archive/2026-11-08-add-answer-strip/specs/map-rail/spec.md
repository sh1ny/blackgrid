# Map rail delta

## MODIFIED Requirements

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
