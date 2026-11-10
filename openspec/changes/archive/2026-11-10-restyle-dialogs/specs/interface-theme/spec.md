# Spec Delta

## ADDED Requirements

### Requirement: Dialogs, sheets and the startup screen in Ember
Every dialog the app opens SHALL use the Ember raised surface and every bottom sheet the Ember panel surface, a dialog with 12px corners and a sheet with 12px top corners, its title in the Literata Title role, Ember button variants with at most one primary action, and the theme's colours in both rooms. The startup screen SHALL use the Canvas surface of the room Windows asks for. Each dialog SHALL keep its wording, actions and keyboard behaviour.

#### Scenario: Stats dialog
- **WHEN** Stats opens in the light room
- **THEN** its surface is the light raised colour with 12px corners, "Close" is the only primary action and "Clear stats" is a quiet action

#### Scenario: Confirm dialog
- **WHEN** the player asks to remove a pin
- **THEN** the confirm dialog shows "Remove" as its one primary action and "Cancel" as a quiet action, and Escape cancels

#### Scenario: Marker list sheet
- **WHEN** the marker list sheet opens on the Map
- **THEN** its surface is the panel colour with 12px top corners, and its title is in the Literata Title role

#### Scenario: Map help closes
- **WHEN** Map help is open and the player presses Escape
- **THEN** it closes and keyboard focus is back on the map

#### Scenario: Startup error
- **WHEN** local storage cannot be opened
- **THEN** the startup screen shows the storage message word for word and "Retry opening local storage" in Ember styling
