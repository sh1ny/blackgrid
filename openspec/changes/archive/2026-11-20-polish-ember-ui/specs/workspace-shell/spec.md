# Spec Delta

## MODIFIED Requirements

### Requirement: Top bar keeps navigation and timers reachable
The top bar SHALL contain, from left to right, the brand, the Map/Scanner switch as one segmented control, item search with Ctrl K, enabled raid timers, the inspector toggle, and Stats, Import and Settings as quiet buttons, Settings last. On a wide window the search field SHALL be no wider than 480 logical pixels, and the width it does not use SHALL lie between the search field and the timers, so Settings ends at the top bar's right edge at every wide window width. It SHALL follow DESIGN.md X11: narrow layouts use the hex logo and icon actions with accessible labels and tooltips. Timer visibility and calculations SHALL use existing settings and rules.

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

#### Scenario: Tools reach the right edge on a very wide window
- **WHEN** the wide top bar is shown at 1920, 2560 and 3440 logical pixels wide, with all timers enabled and with every timer hidden
- **THEN** in each case the search field is at most 480 logical pixels wide, it starts right after the area switch, and the gap between Settings' right edge and the top bar's right edge is the same as at 1660 logical pixels wide, at most 16 logical pixels

#### Scenario: Segmented area switch
- **WHEN** the user selects Map, then Scanner, in the top bar's segmented control
- **THEN** the selected segment is marked selected for assistive technology, the other is not, and the area shown changes each time
