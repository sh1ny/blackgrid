## RENAMED Requirements

- FROM: `### Requirement: Floor control sits beside the picker`
- TO: `### Requirement: The floor rail sits under the picker`

## MODIFIED Requirements

### Requirement: The floor rail sits under the picker
The Map SHALL show a vertical floor rail under the picker, over the left edge of the map. It SHALL show the floor count and list the prepared floors from top to bottom, with the base in its authored position. Auto SHALL be available exactly when the map has floor extents. The rail SHALL be absent when artwork is unavailable or when the map has at most one floor and no Auto. It SHALL NOT resize the viewport or hide the artwork credit or pin bar.

#### Scenario: Choosing a floor
- **WHEN** a map with Ground and Underground floors is shown and the player chooses Underground
- **THEN** Underground changes visibility, its check reflects the change, and Ground stays drawn

#### Scenario: An exclusive deck is chosen
- **WHEN** the player chooses a different Icebreaker deck
- **THEN** only that deck is drawn and checked, and the row has a neutral selected fill, semibold text and a leading edge

#### Scenario: Multiple additive floors
- **WHEN** the player enables two non-base floors on an additive map
- **THEN** both are drawn and checked, and the always-drawn floor is checked and labelled "base"
- **AND** the highest visible non-base floor is current, or the base is current when no overlay is visible
- **AND** a dashed "below ground" divider appears immediately below the base if there are floors below it

#### Scenario: Reset to the base
- **WHEN** the player activates the base row on an additive map with visible overlays
- **THEN** the overlays are hidden, the base stays drawn, and Auto is off for that map

#### Scenario: Manual-only floors
- **WHEN** a map with multiple selectable floors has no floor extents
- **THEN** the rail shows the floors without Auto

#### Scenario: One floor with Auto
- **WHEN** a map has exactly one floor and floor extents
- **THEN** the rail shows Auto and that floor, and both step buttons are disabled

#### Scenario: Map with no floors
- **WHEN** the current map has no floor and no automatic floor support
- **THEN** no rail is shown

#### Scenario: One floor without Auto
- **WHEN** the current map has one floor and no automatic floor support
- **THEN** no rail is shown

#### Scenario: Artwork unavailable
- **WHEN** the selected map's artwork is not available
- **THEN** the picker stays usable and no rail is shown

## ADDED Requirements

### Requirement: The rail exposes floors outside its viewport
The rail SHALL scroll without moving the map, fade clipped edges, and count floors hidden or clipped there as "N more above" or "N more below". The compact line SHALL show the current floor, step buttons, Auto when on, and Expand. Collapse SHALL last for the mounted workspace; a new workspace SHALL start expanded. Where a popup overlaps the rail, the focused rail SHALL have paint and pointer priority; otherwise the popup SHALL have priority.

#### Scenario: More floors than fit
- **WHEN** a tall floor list is shown in a short map viewport and scrolled into the middle
- **THEN** the rail shows both directional counts and fades, and scrolling the rail keeps the map pan and zoom unchanged

#### Scenario: All floors fit
- **WHEN** the viewport grows enough to fit every floor
- **THEN** neither overflow count nor fade is shown and no floor is clipped

#### Scenario: Collapse and expand
- **WHEN** the player collapses and then expands the rail
- **THEN** the compact line shows the current floor and only shows an Auto tag while Auto is on
- **AND** reopening shows the current floor without changing visibility or Auto

#### Scenario: The rail disappears and returns
- **WHEN** the player collapses the rail, visits a map without a rail or another area, and returns
- **THEN** the rail is still collapsed, but creating a new Map workspace starts expanded

#### Scenario: A marker popup overlaps the rail
- **WHEN** a selected marker's popup overlaps the rail and focus moves from the canvas to the rail and back
- **THEN** the popup is readable and Close is clickable before and after rail focus
- **AND** while the rail has focus it paints above the popup and its keyboard target is visible and operable
- **AND** the marker selection and map view do not change when focus moves

### Requirement: The rail reports the player floor separately from Auto
On an Auto-capable map the expanded rail SHALL show an Auto switch and the status "Following you", "Waiting for a position" or "Off". In the expanded list, "You" SHALL mark the floor resolved from the current map's latest usable position whether or not Auto is on. The tag and status SHALL NOT claim a position when the height is unresolved or the evidence is cleared. The compact line SHALL use its Auto tag instead of the switch, status and floor-row tags.

#### Scenario: Manual selection away from the sampled floor
- **WHEN** a screenshot resolves a player's floor and the player manually chooses another floor
- **THEN** the status is "Off" and "You" remains on the resolved floor, not on the newly chosen one

#### Scenario: Unresolved position
- **WHEN** Auto is on and the current map has no position with usable height
- **THEN** the rail says "Waiting for a position", shows no "You" tag, and does not change floor selection

#### Scenario: Auto resumes
- **WHEN** the player turns Auto on with a position that resolves to a floor
- **THEN** the rail says "Following you" and selects the resolved floor under the existing visibility rules

#### Scenario: Auto is toggled while collapsed
- **WHEN** the player presses A with an Auto-capable rail collapsed and the canvas or rail focused
- **THEN** Auto toggles and the compact Auto tag reflects the new state without expanding the rail

### Requirement: Map shortcuts step floors and reach the rail
With primary focus on the Map canvas or focus in the floor rail, Page Up and Page Down SHALL step without wrapping, A SHALL toggle Auto when offered, and F SHALL focus the rail when present. With no rail these shortcuts SHALL do nothing. A step SHALL show and announce its destination and position in the stack. A successful step SHALL turn Auto off and select only its destination, keeping the base drawn on additive maps.

#### Scenario: Step with multiple overlays active
- **WHEN** the player presses Page Down from the highest active overlay on an additive map, and a floor exists below it
- **THEN** the next lower floor is current, every other non-base floor is hidden, and the base remains drawn
- **AND** a short toast names the destination and its position counted from the lowest floor, and is exposed as a live region

#### Scenario: At the end of the floor stack
- **WHEN** the player tries to step past the top or bottom floor
- **THEN** the floor selection and Auto are unchanged and the corresponding step button is disabled

#### Scenario: Shortcuts outside the map
- **WHEN** a text input, a control inside a marker popup, or another unrelated control has focus
- **THEN** neither typing A or F nor pressing Page Up or Page Down changes the floor rail

#### Scenario: No rail accepts floor shortcuts
- **WHEN** the canvas has focus while the current map has no rail
- **THEN** A, F, Page Up and Page Down do not change selection, move focus or show a floor toast

### Requirement: The rail supports keyboard and screen reader navigation
The expanded list SHALL have one Tab stop. Up/Down and Home/End SHALL move row focus and select on exclusive maps; additive rows SHALL change visibility only on activation. Fresh Escape SHALL return focus to the canvas without clearing selection, and repeats SHALL NOT clear it. Collapsing with focus SHALL focus Expand; expanding with focus SHALL reveal and focus the current floor. Controls SHALL have accessible names and states, visible focus and targets at least 24 logical pixels across.

#### Scenario: Exclusive keyboard navigation
- **WHEN** the player presses F on the Map with the exclusive rail expanded and then presses End
- **THEN** focus and selection move to the lowest floor, the row scrolls into view, and assistive technology can read its full name and checked state in a mutually exclusive group

#### Scenario: Additive keyboard navigation
- **WHEN** the player moves with Up or Down on an additive map and then activates the focused row with Space or Enter
- **THEN** moving alone changes no visibility, activation changes it, and assistive technology can read each row's visible state and identify the always-drawn base

#### Scenario: Escape with a map marker selected
- **WHEN** the player presses Escape with a rail control focused and keeps holding it after focus returns to the canvas
- **THEN** Escape repeats leave the marker selected
- **AND** after release, a new Escape press on the canvas clears the marker

#### Scenario: Focus on a collapsed rail
- **WHEN** the player presses F on the Map with the rail collapsed
- **THEN** Expand receives focus, and activating it reveals and focuses the current floor without selecting another floor
- **AND** the next row navigation key works without pressing Tab again

#### Scenario: Collapse keeps focus in the rail
- **WHEN** the player keyboard-activates Collapse on the expanded rail
- **THEN** the compact Expand action receives focus and Page Up or Page Down operates immediately without a Tab key
