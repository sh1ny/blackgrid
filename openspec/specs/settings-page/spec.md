# settings-page Specification

## Purpose
Defines the Settings page: one place where every Blackgrid setting lives, how it opens and closes beside the Map and Scanner, its sections and their order, and how changes are saved.

## Requirements

### Requirement: Settings opens as a page
The top bar's Settings action SHALL open Settings as a page in place of the answer strip, the main column and the inspector, while the top bar and the status bar stay. A "Back to Map" or "Back to Scanner" button, named for the area it came from, and Escape (once any open menu has closed) SHALL close it and show that area and the inspector as they were left. Choosing Map or Scanner in the top bar SHALL close it and show the chosen area.

#### Scenario: Open and go back
- **WHEN** the player opens Settings from the Map with Woods selected and presses "Back to Map"
- **THEN** the Map shows again with Woods selected, and the top bar and status bar stayed visible the whole time

#### Scenario: Inspector hidden while open
- **WHEN** the inspector is open on the Scanner and the player opens Settings, then presses Escape
- **THEN** the inspector is hidden and its toggle disabled while Settings is open, and after Escape the Scanner shows with the inspector open again

#### Scenario: Switch area from Settings
- **WHEN** Settings was opened from the Map and the player chooses Scanner in the top bar
- **THEN** Settings closes and the Scanner shows

#### Scenario: Choose the area Settings was opened from
- **WHEN** Settings was opened from the Scanner and the player chooses Scanner in the top bar's area switch
- **THEN** Settings closes and the Scanner shows; while Settings is open, neither area is shown as selected in the switch

#### Scenario: Item search from Settings
- **WHEN** Settings was opened from the Scanner and the player picks an item in the top bar's item search
- **THEN** Settings closes and the Scanner shows that item in the answer strip

#### Scenario: Escape with an unsaved invalid edit
- **WHEN** the player types "0:30" into the run-through length and presses Escape
- **THEN** Settings closes and the saved run-through length is unchanged

#### Scenario: Map keys while Settings is open
- **WHEN** a marker is selected on the Map and the player opens Settings from the top bar and presses N, Enter, Delete and then Escape
- **THEN** no pin editor, marker list or confirm opens, Settings closes on Escape, and the Map shows with the same marker selected

#### Scenario: Escape with a valid edit
- **WHEN** the player types `D:\Shots` into the screenshot folder and presses Escape without leaving the field
- **THEN** Settings closes and `D:\Shots` is saved as the screenshot folder

#### Scenario: Scan while Settings is open
- **WHEN** Settings is open and live scan accepts an item
- **THEN** Settings stays open, and after Back the answer strip shows that item

#### Scenario: Settings action while open
- **WHEN** Settings is open and the player activates Settings in the top bar again
- **THEN** Settings stays open at the same scroll position and no second Settings opens

### Requirement: Settings sections and their order
The page SHALL list, in its sidebar and in its scrolling column, the sections General, Live scan, Item and map data, Tracker progress, Local progress, Game files, Raid timers, Map and Diagnostics, in that order. Choosing a section in the sidebar SHALL scroll it into view and move keyboard focus to it. Choosing Diagnostics SHALL also expand it.

#### Scenario: Sidebar order
- **WHEN** Settings opens
- **THEN** the sidebar lists the nine sections in the order above, followed by nothing else

#### Scenario: Jump to a section
- **WHEN** the player chooses Raid timers in the sidebar
- **THEN** the Raid timers section title is in view and holds keyboard focus

#### Scenario: Jump to Diagnostics
- **WHEN** Diagnostics is collapsed and the player chooses it in the sidebar
- **THEN** Diagnostics is expanded and in view

### Requirement: Settings opens at a requested section
A link that names a section (the status bar's Item data and Tracker items, and any other) SHALL open the page with that section in view and focused. When the page is already open, the link SHALL scroll to that section without reopening the page.

#### Scenario: Status bar Tracker
- **WHEN** the player activates the status bar's Tracker item from the Scanner
- **THEN** Settings opens with Tracker progress in view and focused, and Back returns to the Scanner

#### Scenario: Already open
- **WHEN** Settings is open at General and the player activates the status bar's Item data item
- **THEN** Item and map data scrolls into view, and Back still returns to the area Settings was first opened from

### Requirement: Diagnostics starts collapsed each time
Diagnostics SHALL be the last section, and SHALL be collapsed each time the page opens, whatever state it had when the page last closed.

#### Scenario: Reopen
- **WHEN** the player expands Diagnostics, goes back to the Map and opens Settings again
- **THEN** Diagnostics is collapsed

#### Scenario: Open at a section
- **WHEN** Settings opens at Tracker progress from the status bar
- **THEN** Diagnostics is collapsed

### Requirement: Settings rows
Each setting SHALL be one row: its name, a one-line explanation, and its control on the right. On/off settings SHALL use the toggle switch of DESIGN.md X13, and the whole row SHALL toggle it. The column SHALL be at most 720px wide, with the page title in the Literata Display role and section titles in the Literata Title role.

#### Scenario: Toggle by row
- **WHEN** the player clicks the name of the "Follow logs" row
- **THEN** Follow logs changes and is saved

#### Scenario: Wide window
- **WHEN** the window is 1920px wide
- **THEN** the settings column is no wider than 720px

#### Scenario: Setting disabled while saving
- **WHEN** a save is in flight and the player clicks another switch row
- **THEN** that switch does not change and nothing else is saved

### Requirement: General, Live scan and Map sections
General SHALL hold the theme choice, the game mode (PvP, PvE, Seasonal) and the app version. Live scan SHALL hold live scan on or off with its state, the scan key with its state, record scan frames with its status, and any live scan, hotkey, recording or timing log error. Map SHALL hold Save marker filters.

#### Scenario: Game mode
- **WHEN** the player chooses PvE in General
- **THEN** the app's mode becomes PvE and the status bar shows PvE

#### Scenario: Scan key refused
- **WHEN** the player picks a scan key that cannot be registered
- **THEN** the Live scan section shows the hotkey error and the key still in force

#### Scenario: Live scan unavailable
- **WHEN** live scan is unavailable
- **THEN** the Live scan section says it is unavailable and why

### Requirement: Item and map data section
Item and map data SHALL hold Refresh item data with one plain line on the item data's freshness, and Refresh map data with one plain line on the map data's freshness. Each refresh SHALL be disabled while it runs or while no game mode is known, and Refresh map data also while no map data is available. A failed refresh SHALL show its failure in plain words in this section.

#### Scenario: Refresh map data
- **WHEN** the mode is PvP and the player presses Refresh map data
- **THEN** the button reads "Refreshing map data…" and is disabled until the refresh ends

#### Scenario: Unknown mode
- **WHEN** no game mode is known
- **THEN** both refresh buttons are disabled

#### Scenario: No map data available
- **WHEN** a game mode is known but no map data is available
- **THEN** Refresh map data is disabled and Refresh item data is enabled

#### Scenario: Map data refresh fails
- **WHEN** the map data refresh fails
- **THEN** the section says the map data refresh failed, and the map keeps the data it had

### Requirement: Tracker progress section
Tracker progress SHALL hold Use Tracker progress, whether a token is saved and for which mode, a hidden token field with Save token and Remove token, Refresh progress, the progress status, and the note that the token is stored encrypted for the Windows account. The token SHALL be cleared from the field after each token action, and SHALL never be shown.

#### Scenario: Save token
- **WHEN** the mode is PvP and the player enters a token and presses Save token
- **THEN** the section says the token is saved for PvP and the field is empty

#### Scenario: Token action fails
- **WHEN** saving the token fails
- **THEN** the section says "Tracker token operation failed. Nothing was stored as plain text."

#### Scenario: No mode
- **WHEN** no game mode is known
- **THEN** Save token and Remove token are disabled

### Requirement: Game files section
Game files SHALL hold the game log folder and the screenshot folder, each saved on Enter or when focus leaves the field, and Follow logs. An empty folder SHALL mean the default location, as today. A folder save that fails SHALL keep the typed text and show that it was not saved.

#### Scenario: Save a folder on Enter
- **WHEN** the player types `D:\Shots` in the screenshot folder and presses Enter
- **THEN** `D:\Shots` is saved as the screenshot folder

#### Scenario: Save on leaving
- **WHEN** the player types a game log folder and moves focus to another row
- **THEN** that folder is saved

#### Scenario: Save fails
- **WHEN** saving a typed folder fails
- **THEN** the field keeps the typed text, says it was not saved, and the folder in use is unchanged

### Requirement: Changes save as they are made
Every setting SHALL save when it is changed, with no Save button, except the Tracker token, which saves only on Save token. Text fields SHALL save on Enter or when focus leaves them. A refused or failed save SHALL keep the previous saved value and show a message under its row. A settings load notice or save error SHALL show at the top of the page.

#### Scenario: Switch saves at once
- **WHEN** the player turns Save marker filters off
- **THEN** it is saved without any further action

#### Scenario: Settings could not be read
- **WHEN** the saved settings could not be read at startup
- **THEN** the top of the page shows the load notice

### Requirement: Every setting stays reachable
Every control the Settings dialog had SHALL have a row on the page, with the same effect and the same enabled and disabled rules: theme, game mode, refresh item data, refresh map data, game log folder, screenshot folder, follow logs, save marker filters, every raid timer setting, live scan, record scan frames, scan key, use Tracker progress, token save and remove, refresh progress, and Diagnostics. No other screen SHALL open the Settings dialog.

#### Scenario: All controls present
- **WHEN** Settings opens
- **THEN** each control in the list above is on the page

#### Scenario: Disabled rule kept
- **WHEN** live scan is off
- **THEN** record scan frames is disabled, as it was in the dialog

### Requirement: Local progress section
Local progress SHALL hold one row per game mode (PvP, PvE, seasonal) showing its wipe's start date and last log folder read, "No wipe yet", or that the wipe is unavailable. Each row SHALL have "Replay game logs", with a date that defaults to the wipe's start, and "Start a new wipe", with a required start date. The section SHALL show the running read, or the last run's result.

#### Scenario: Wipe shown
- **WHEN** PvE's wipe started 2026-11-01 and its last folder read is `log_2026.11.10_19-12-03_1.3.0.0.48484`
- **THEN** the PvE row shows the start date 2026-11-01 and that folder name, and its replay date defaults to 2026-11-01

#### Scenario: No wipe yet
- **WHEN** seasonal mode has no wipe
- **THEN** its row says "No wipe yet" and its replay date has no default until the player picks one

#### Scenario: Last result shown
- **WHEN** a PvE replay has finished reading 12 folders, recording 9 task events and skipping 1 message for no mode
- **THEN** the section shows that result with the mode and the time it finished

### Requirement: Replay recovery is explicit
The section SHALL warn that closing Blackgrid stops replay and that the player must replay again from the same date to finish it. An interrupted or failed replay result SHALL show its original selected retry date.

#### Scenario: Replay recovery guidance
- **WHEN** a replay selected from October 20 fails or is interrupted
- **THEN** its result identifies October 20 as the retry date, and the section explains that closing Blackgrid stops replay and requires replaying again from the same date

### Requirement: Local progress actions are disabled with a reason
Replay game logs and Start a new wipe SHALL be disabled while the player is queued, loading or in a raid, while another catch-up, replay or new wipe is running, and while no game log folder is found, each with its reason beside the actions. Start a new wipe SHALL ask the player to confirm, naming the mode and the new start date.

#### Scenario: In a raid
- **WHEN** the raid lifecycle phase is in raid
- **THEN** both actions are disabled in every row and the section says they are not available during a raid

#### Scenario: Confirm a new wipe
- **WHEN** the player chooses Start a new wipe for PvP with date 2026-11-12
- **THEN** a confirmation names PvP and 2026-11-12, and no cycle is created unless the player confirms

#### Scenario: Confirmation cancelled
- **WHEN** the player cancels the new-wipe confirmation
- **THEN** PvP's active wipe is unchanged and nothing is read
