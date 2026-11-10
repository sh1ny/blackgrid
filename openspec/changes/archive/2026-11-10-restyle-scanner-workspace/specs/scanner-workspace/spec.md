# Spec Delta

## Purpose

Defines what the Scanner's main column and inspector show and where, so the details behind the answer strip read at a glance, following the approved B view of DESIGN.md X10.

## ADDED Requirements

### Requirement: Scanner main column sections
The Scanner's main column SHALL show three sections in this order: Why, Prices, Scan evidence, preceded only by the recording-stopped note when scanner-evidence shows one. Each has a sentence-case title and a subtitle, flat on the column surface with no bordered card. When the main column is at least 720 logical pixels wide, Why and Prices SHALL sit side by side with Scan evidence below them; when narrower, all three SHALL stack.

#### Scenario: Wide window places Why beside Prices
- **GIVEN** an item is selected and the inspector is open
- **WHEN** Scanner is shown at 1660 by 870 logical pixels
- **THEN** Why's left edge is at the main column's content edge, after its padding, Prices starts to the right of Why with the same top, Scan evidence starts below the lower of the two, and all three lie within the main column

#### Scenario: Narrow window stacks the sections
- **WHEN** Scanner is shown at 1100 by 720 logical pixels with the inspector docked open and an item selected, so the main column is under 720 logical pixels wide
- **THEN** Why, Prices and Scan evidence are stacked top to bottom in that order, each the full main-column width, and the column scrolls when they do not fit, with no overflow

#### Scenario: No bordered card
- **WHEN** the main column is rendered in either room
- **THEN** no section is wrapped in a container with its own border or a fill different from the column surface

### Requirement: Why lists the item's needs
Why SHALL open with one summary line of the still-needed totals, found in raid and not found in raid, each written as a whole number or "Unknown". Below it SHALL be the decision's warnings, leaving out one that only repeats the found-in-raid question the strip already asks, then the item's requirement rows as dense rows, following the requirement-rows rules for titles, kinds, states, counts, ordering and the collapsed optional uses.

#### Scenario: Needs for a selected item
- **GIVEN** an item needed by the hideout station "Medstation" level 1 for 1 found-in-raid item, with found in raid unknown
- **WHEN** Why is rendered
- **THEN** it shows the summary line with found in raid "1", and a row titled "Medstation level 1" with its kind tag "Hideout" and its state label

#### Scenario: No item or unavailable item data
- **WHEN** no item is selected, or the selected item's data is unavailable
- **THEN** Why shows "Pick or scan an item to see its needs." or "Item data unavailable" respectively, and no summary line or rows

#### Scenario: Warning that repeats the found-in-raid question
- **GIVEN** a Check / May Need decision with found in raid unknown and one other warning
- **WHEN** Why is rendered
- **THEN** it shows the other warning and not "Found in raid unknown for this item"

#### Scenario: Recording stopped
- **GIVEN** frame recording stopped with a warning
- **WHEN** Scanner is shown
- **THEN** the recording-stopped note is above Why, and Why, Prices and Scan evidence follow in order

#### Scenario: Needs unknown
- **GIVEN** a selected item whose needed totals are not known
- **WHEN** Why is rendered
- **THEN** both totals read "Unknown" and no number is invented

### Requirement: Prices breaks the price down
Prices SHALL show dense rows, with the values right-aligned in tabular figures:
- Flea: "24 h average" and the Flea price;
- Trader: the best trader's name and price;
- Per slot: the Flea and trader prices per inventory slot;
- Updated: "tarkov.dev" and the freshness tag.

Its subtitle SHALL say that prices are per item and per slot, before Flea fees.

#### Scenario: Item with both prices
- **GIVEN** an item with a Flea price of 21800, Therapist at 9400, and 2 slots
- **WHEN** Prices is rendered
- **THEN** it shows Flea "₽21800", Trader "Therapist" "₽9400", Per slot "₽10900" for the Flea and "₽4700" for the trader, and an Updated row carrying the freshness tag

#### Scenario: Item that cannot be sold on the Flea
- **GIVEN** an item that cannot be sold on the Flea, with a trader price
- **WHEN** Prices is rendered
- **THEN** the Flea row reads "Can't be sold on the Flea", no Flea per-slot value or freshness tag is shown, and the trader rows are shown

#### Scenario: Missing prices
- **GIVEN** an item with no Flea price and no trader cash offer
- **WHEN** Prices is rendered
- **THEN** each missing value reads "Price unavailable", and no row is left blank

### Requirement: Scan evidence follows the details
Scan evidence SHALL be the last section of the main column and SHALL apply the scanner-evidence rules for phase, the accepted or latest scan summary and the not-accepted note. It SHALL show no debug detail.

#### Scenario: Accepted scan
- **GIVEN** a scan accepted "Salewa first aid kit"
- **WHEN** Scanner is shown
- **THEN** Scan evidence, below Why and Prices, names "Salewa first aid kit" as the matched item

#### Scenario: No scan yet
- **WHEN** no scan has been published in the session
- **THEN** Scan evidence says no scan is published yet, and Why and Prices still show the selected item's details

### Requirement: Scanner inspector holds recent items and the live scan note
The Scanner inspector SHALL show a scrolling Recent items section and, pinned below it, a Live scan section. Recent items SHALL be a flat list of DESIGN.md X14 rows, each laid out at its full row height, with no fixed-height box between the rows and the list's scroll view. Each row SHALL show a relative age: "just now" under 10 seconds, then "N s", "N min", "N h" or "N d". The Live scan section SHALL say whether live scan is on and point to the status bar and Settings.

#### Scenario: Recent items without clipping
- **GIVEN** 12 history rows
- **WHEN** the Scanner inspector is shown at 1660 by 870 logical pixels
- **THEN** each row is laid out at its full X14 height, no ancestor between a row and the Recent items scroll view constrains its height, and the Live scan section stays on screen below the list while the list is scrolled to its end

#### Scenario: Relative ages
- **GIVEN** rows recorded 5 seconds, 12 seconds, 3 minutes, 5 hours and 2 days before now
- **WHEN** the list is rendered
- **THEN** their ages read "just now", "12 s", "3 min", "5 h" and "2 d"

#### Scenario: Ages move on while shown
- **GIVEN** a row showing "just now" and nothing else changes
- **WHEN** the clock passes 3 minutes and the periodic age update runs
- **THEN** the row reads "3 min"

#### Scenario: Empty history
- **WHEN** there are no history rows
- **THEN** Recent items reads "No items yet." and the Live scan section is still shown

#### Scenario: History read fails
- **GIVEN** history could not be read
- **WHEN** the inspector is shown
- **THEN** the error is shown in the error ink under Recent items, and any rows already loaded stay selectable
