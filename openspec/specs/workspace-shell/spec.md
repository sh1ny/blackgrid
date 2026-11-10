# workspace-shell Specification

## Purpose
Makes the current item and keep/sell answer immediately visible on Map and Scanner while keeping detail and configuration reachable.

## Requirements

### Requirement: Answer precedes the workspace
Map and Scanner SHALL show the current item picture and name, verdict plate, full reason, per-item Found in raid and a price block directly below the top bar, before workspace or configuration content. Found in raid SHALL be one segmented control (Unknown, Yes, No) with a "Found in raid" label, beside the verdict plate, with the reason below both. Under the item name, a provenance line SHALL say where the shown item came from and, where known, its relative age: "Accepted scan · 12 s ago" (or "Accepted scan · just now"), "Corrected from a scan · 3 min ago · chosen by hand", "Chosen by hand" for a manual selection, and "Current advice · saved 3 min ago" for a history inspection, followed by " in PvE" when the saved mode differs from the current one. The line SHALL use the history rows' relative-age wording, move on with the same periodic age update, and never show a scan number. The price block SHALL show the Flea price with its per-slot price, the best trader's price and name, and the freshness tag, as aligned label and value rows. The strip SHALL use DESIGN.md X10 in both rooms and grow to fit wrapped content or text scaling. Missing prices SHALL be labelled honestly. Empty and ordinary single-line selected content SHALL share one normal height of at most 100 logical pixels. Raw item IDs SHALL NOT appear below item names.

#### Scenario: Answer first in both areas
- **WHEN** each area is shown at 1660 by 870 and 960 by 720 logical pixels
- **THEN** the strip is visible without scrolling directly below the top bar and above the workspace, with no configuration panel above it

#### Scenario: Missing item and long reason
- **WHEN** no item is selected, or an item's reason is too long for one line
- **THEN** the strip shows an explicit empty state without a verdict, or wraps the complete reason without overflow respectively

#### Scenario: Price and stable normal height
- **WHEN** an ordinary single-line item is selected, including a Check / May Need item with available prices
- **THEN** price and freshness are visible in the strip, and its height equals the empty state's and is at most 100 logical pixels; missing prices are explicit and long reasons or enlarged text can grow without truncation

#### Scenario: Found in raid sits beside the verdict
- **WHEN** the strip shows a selected item at 1660 by 870 logical pixels
- **THEN** the Found in raid control starts within 24 logical pixels of the verdict plate's right edge, their vertical centres are within 4 logical pixels, and the reason's top is below both

#### Scenario: Provenance line
- **GIVEN** the current mode is PvP
- **WHEN** the strip shows a scan accepted 12 seconds ago, then an item corrected by hand 3 minutes ago, then a history row saved in PvE 3 minutes ago
- **THEN** the provenance line reads "Accepted scan · 12 s ago", then "Corrected from a scan · 3 min ago · chosen by hand", then "Current advice · saved 3 min ago in PvE"

#### Scenario: Provenance age moves on
- **GIVEN** the strip shows a scan accepted just now and nothing else changes
- **WHEN** the clock passes 3 minutes and the periodic age update runs
- **THEN** the provenance line reads "Accepted scan · 3 min ago"

#### Scenario: Price block with both prices
- **GIVEN** an item with a Flea price of 21800, 2 slots, and Therapist at 9400
- **WHEN** the strip is shown at 1660 by 870 logical pixels
- **THEN** the price block at the strip's right end reads Flea "₽21800" with "₽10900 / slot", Trader "₽9400" with "Therapist", and the freshness tag

#### Scenario: Long reason with Found in raid at 1300px
- **GIVEN** a Check / May Need item whose reason is 120 characters long
- **WHEN** the strip is shown at 1300 by 870 logical pixels
- **THEN** the plate, the Found in raid control and the price block are fully visible with no overflow, the Found in raid control either follows the plate on its line or wraps directly under it, and the reason wraps without truncation

#### Scenario: Price block without a Flea price
- **GIVEN** an item that cannot be sold on the Flea and has no trader cash offer
- **WHEN** the strip is shown
- **THEN** the Flea row reads "Can't be sold on the Flea", the Trader row reads "Price unavailable", and no freshness tag is shown

### Requirement: Selection semantics survive the new layout
The strip and the Scanner's main column SHALL reflect the same current inspection. Existing manual selection, scan correction, history inspection, close-history and return-to-latest-scan actions SHALL remain available. Found in raid SHALL retain existing per-item reset, history and authority rules.

#### Scenario: Selection changes across areas
- **WHEN** an item is selected by search and the user switches between Map and Scanner
- **THEN** both areas show the same inspection and Found in raid value

#### Scenario: History and later rejected scan
- **WHEN** history is inspected or a later scan is rejected after an accepted scan
- **THEN** existing history isolation and accepted-item retention still apply, with no rejected candidate presented as an accepted answer

### Requirement: Top bar keeps navigation and timers reachable
The top bar SHALL contain, from left to right, the brand, the Map/Scanner switch as one segmented control, item search with Ctrl K, enabled raid timers, the inspector toggle, and Stats, Import and Settings as quiet buttons, Settings last. On a wide window the search field SHALL be no wider than 480 logical pixels. It SHALL follow DESIGN.md X11: narrow layouts use the hex logo and icon actions with accessible labels and tooltips. Timer visibility and calculations SHALL use existing settings and rules.

#### Scenario: Wide navigation
- **WHEN** the wide shell is shown with all timers enabled
- **THEN** all three timers and labelled Settings, Stats and Import actions are in the top bar

#### Scenario: Narrow navigation and disabled timers
- **WHEN** the window is 960px wide and timer settings hide one timer
- **THEN** the remaining timers and all actions remain reachable without horizontal page scrolling, hidden timers are absent, and icon actions retain names and tooltips

#### Scenario: Anchored search results and explicit selection
- **WHEN** the user types in top search, navigates results by keyboard and dismisses or confirms a result
- **THEN** a height-bounded lazy list of at most 50 options appears at the field in both areas, more matches show a refine-search hint, typing or dismissal creates no selection or history, arrows change the active displayed result, Escape dismisses results and confirmation selects and records only the chosen item

#### Scenario: Wide tools alignment
- **WHEN** the wide top bar is shown with enabled timers
- **THEN** search is at most 480 logical pixels wide, timers and tools align at the right edge, the actions read Stats, Import, Settings from left to right as quiet buttons with no outline and timer entries have hairline separators; compact and enlarged-text layouts retain reachable actions without horizontal overflow

#### Scenario: Segmented area switch
- **WHEN** the user selects Map, then Scanner, in the top bar's segmented control
- **THEN** the selected segment is marked selected for assistive technology, the other is not, and the area shown changes each time

### Requirement: Inspector preserves the workspace
On Scanner the inspector SHALL provide Recent items, which scrolls, and a Live scan note pinned below it, and no item details, requirements or data-sources panel; those details live in the Scanner's main column. On Map it SHALL provide This raid, Markers and Pins, and no item details. It SHALL start open above 1080px and closed otherwise, initialized once per shell session; later resizing SHALL preserve the user's open/closed state. At widths at most 1080px it SHALL float with a scrim. Closing or resizing SHALL retain the mounted workspace and return focus to the opener. Panel motion SHALL follow DESIGN.md and reduced-motion settings.

#### Scenario: Docked details
- **WHEN** the inspector is opened in a wide window on Scanner
- **THEN** it shows Recent items and the Live scan note beside the main column, and no Inspection details, Requirements or Sources panel

#### Scenario: Resize with open details
- **WHEN** an open inspector crosses the 1080px threshold and is then closed with Escape
- **THEN** it becomes an overlay, preserves selection and the optional-uses expansion state, and returns focus to the opener without resetting the map viewport

#### Scenario: Scanner history leads the inspector
- **WHEN** Scanner's inspector opens with recent items
- **THEN** Recent items is the first section, its rows size to their content with none cut off by a fixed-height box, and history retains lazy image leases

#### Scenario: Initial inspector state follows window width
- **WHEN** a new shell opens above 1080px or at or below 1080px
- **THEN** its inspector starts open or closed respectively, and a subsequent user toggle followed by resizing preserves the user's current state

#### Scenario: Map inspector holds working lists
- **WHEN** Map's inspector opens with an item selected
- **THEN** it shows This raid, Markers and Pins in that order, and no requirements, sources or history panel

### Requirement: History rows show item pictures
The inspector SHALL use DESIGN.md X14 history rows with picture, name, recorded-verdict indicator and a relative age, in one line with no source subtitle. A row whose game mode differs from the current mode SHALL also show that mode's name as a Label-type tag, and a row recorded from an imported scan SHALL show an "Imported scan" Label-type tag. Pictures SHALL follow existing icon fallback rules. Dots SHALL use saved verdicts, never current advice. Missing verdicts SHALL show a distinct unknown indicator labelled "Verdict not recorded". Opening a row SHALL preserve existing history-inspection semantics and label its current advice separately from the recorded verdict.

#### Scenario: History selection
- **WHEN** a pictured history row is selected
- **THEN** the history inspection opens for that row with its recorded item identity and mode, and its row dot continues to show the saved verdict even if the current advice differs

#### Scenario: Missing history picture
- **WHEN** a history item's picture cannot load
- **THEN** its fallback frame and name remain visible and the row remains selectable

#### Scenario: Legacy history verdict
- **WHEN** a row has no stored verdict
- **THEN** its indicator says "Verdict not recorded" and does not use any of the six known verdict indicators

#### Scenario: Rows from another game mode
- **GIVEN** the current mode is PvP and history holds the same item from PvP and from PvE
- **WHEN** Recent items is shown
- **THEN** the PvE row shows a "PvE" tag and the PvP row shows no mode tag

#### Scenario: Imported scan row
- **GIVEN** history holds an imported scan of an item in the current mode
- **WHEN** Recent items is shown
- **THEN** that row shows an "Imported scan" tag and no `importedScan` text

### Requirement: Status actions lead to their controls
The status bar SHALL let the user switch game mode, open the Settings page at Item and map data or at Tracker progress, and toggle live scan. Every setting displaced from the work screens SHALL live on the Settings page. Live scan status SHALL state actual pipeline state and use DESIGN.md X4.

#### Scenario: Settings targets
- **WHEN** the Item data or Tracker status is activated
- **THEN** the Settings page opens with Item and map data or Tracker progress visible and keyboard reachable

#### Scenario: Settings target while the page is open
- **WHEN** the Settings page is open at General and the Tracker status is activated
- **THEN** Tracker progress scrolls into view and no second Settings opens

#### Scenario: Failed live scan save
- **WHEN** live scan is toggled through the status bar and saving fails
- **THEN** existing switch-on rollback and switch-off stopping rules apply and the error is visible; the status never falsely claims listening

#### Scenario: Status bar presentation and binding
- **WHEN** the status bar is shown at normal scale and live scan changes binding or state
- **THEN** its height is 28px, items start at the left, no touch icon precedes game mode, and live scan shows a 6px state dot with truthful words and the active key or click-only guidance; unavailable state includes its reason and the existing status actions remain usable
