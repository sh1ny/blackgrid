# Spec Delta

## MODIFIED Requirements

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
