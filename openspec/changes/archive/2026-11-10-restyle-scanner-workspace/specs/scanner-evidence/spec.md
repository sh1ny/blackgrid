# Spec Delta

## MODIFIED Requirements

### Requirement: Scan evidence panel is visible without scrolling
On the Scanner, scan evidence SHALL be a section of the main column that follows Why and Prices, as the scanner-workspace capability places it, and SHALL scroll with the column rather than inside a frame of its own. On a desktop window (at least 1100 logical pixels wide) of 870 logical pixels or more in height, with an item selected and ordinary single-line needs, its title SHALL be on screen with the column unscrolled. On every width the section SHALL follow the shared answer strip, with scan configuration in Settings.

#### Scenario: Desktop window
- **WHEN** Scanner is shown in a 1660 by 870 logical pixel window with an item that has up to three requirement rows
- **THEN** the Scan evidence title is on screen with the main column unscrolled, below Why and Prices

#### Scenario: Short desktop window
- **WHEN** Scanner is shown in a 1100 by 720 logical pixel window with a scan phase, a note and an accepted scan, at a text scale large enough that the column's content is taller than the window
- **THEN** the main column scrolls as one, every Scan evidence line can be scrolled into view, and nothing overflows

#### Scenario: Narrow window
- **WHEN** Scanner is shown in a 900 logical pixel wide window
- **THEN** Scan evidence comes after the answer strip, Why and Prices, with no configuration controls above the answer

### Requirement: Unaccepted scan evidence never produces a recommendation
Publishing a scan that is not accepted, whether rejected or failed, SHALL NOT change the current selection, the answer strip, the Why and Prices sections, or the history. Only an accepted scan reaches keep/sell advice, through the scan-decisions rules; the evidence panel itself never shows a recommendation.

#### Scenario: Accepted scan drives the decision card
- **WHEN** the user has manually selected item A and a scan is accepted for item B
- **THEN** the answer strip shows item B, and history gains one entry for B with source `scan`

#### Scenario: Rejected scan with a best candidate
- **WHEN** a scan is rejected with best candidate C
- **THEN** no decision, recommendation or history entry for C is shown
