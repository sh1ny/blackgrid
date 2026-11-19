# Spec Delta

## MODIFIED Requirements

### Requirement: Bulk, search and quest controls keep working
Show all and Hide all SHALL set every row's category, and only those, to shown or hidden. They SHALL NOT write a key that is not a saveable marker preference. The marker search and the quest name filter SHALL behave as before this change, and the active-quest filter and Show all quests SHALL apply beside the quest name and trader filters. The quest trader filter SHALL be one chip per trader on this map plus All. An active trader not on this map SHALL stay shown as a selected chip. Save marker filters SHALL be in Settings. None of them SHALL change a row's shown or hidden state.

#### Scenario: Hide all then Show all
- **WHEN** the user clicks Hide all
- **THEN** every row shows the hidden state and no marker or pin is drawn, and after Show all every row shows the shown state and every marker that the active-quest filter leaves eligible is drawn

#### Scenario: Show all keeps other maps' choices
- **WHEN** `ScavSpawns` was hidden on another map and the current map has no `ScavSpawns` markers, and the user clicks Show all
- **THEN** the saved `ScavSpawns` entry is still hidden

#### Scenario: Bulk action with an unsaveable category
- **WHEN** the current map carries `Ziplines` markers, the user clicks Hide all and the app is started again with the same settings
- **THEN** the settings load, the saved filters hold no `Ziplines` entry, and the `Ziplines` markers were drawn throughout

#### Scenario: Search dims without hiding
- **WHEN** the user types `tunnel` in the marker search
- **THEN** non-matching markers are dimmed, and every row keeps its shown or hidden state

#### Scenario: Quest filter keeps tiles
- **WHEN** the user chooses the `Prapor` chip while "Quest items" is shown
- **THEN** the "Quest items" row still shows the shown state

#### Scenario: Active trader absent from the map
- **WHEN** the `Prapor` chip is active and the player switches to a map with no Prapor quests
- **THEN** a selected `Prapor` chip is still shown, and choosing All clears the filter

## ADDED Requirements

### Requirement: Show all quests switch
The Markers section SHALL show a Show all quests switch in the Quests group, off by default, that turns the active-quest marker filter off. It SHALL be announced as a toggle with its label and state, use ink like the rows, and be restored on the next launch only when Save marker filters is on. Show all, Hide all and the category rows SHALL NOT change it, and it SHALL NOT change a row's shown or hidden state.

#### Scenario: Turn the switch on
- **WHEN** the player turns Show all quests on while task C is not started
- **THEN** C's quest markers are drawn, and every category row keeps its state

#### Scenario: Not saved without Save marker filters
- **WHEN** Save marker filters is off, the player turns Show all quests on and starts the app again
- **THEN** Show all quests is off

#### Scenario: Saved with marker filters
- **WHEN** Save marker filters is on, the player turns Show all quests on and starts the app again
- **THEN** Show all quests is on

#### Scenario: Hide all keeps the switch
- **WHEN** Show all quests is on and the player clicks Hide all, then Show all
- **THEN** Show all quests is still on

#### Scenario: Map without quest markers
- **WHEN** the current map has no quest objective or quest item markers
- **THEN** the switch is not shown, and its saved value is unchanged
