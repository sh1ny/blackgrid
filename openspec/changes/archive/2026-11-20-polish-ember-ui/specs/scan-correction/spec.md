# Spec Delta

## ADDED Requirements

### Requirement: The offer fits in the answer strip without its own scroll bar
The offer SHALL be shown at its full height in the answer strip, with no scroll view or height cap of its own. Its search results SHALL be shown as buttons that wrap onto further rows, like its candidates, each labelled as the result list labels it today. When the whole strip is taller than its existing limit, the strip's own scrolling SHALL apply as before.

#### Scenario: Full offer on a 1080p window
- **WHEN** the window is 1920 by 1080 logical pixels and an offer is shown with 5 candidates and 8 search results, on Map and then on Scanner
- **THEN** the offer has no scroll view of its own, every candidate, the text field and all 8 results are inside the visible strip, and the strip does not scroll

#### Scenario: Results wrap as buttons
- **WHEN** an offer's text field holds text that matches 8 catalog items
- **THEN** the 8 results are shown as buttons in ID order, wrapping onto further rows, and tapping one makes that item the selection as before

#### Scenario: No results still says so
- **WHEN** the offer's text field holds text that matches no catalog item
- **THEN** the offer shows that nothing matched, shows no result buttons, and the selection is unchanged

#### Scenario: Short window keeps the strip limit
- **WHEN** the window is 1280 by 600 logical pixels and an offer with 5 candidates and 8 results is shown
- **THEN** the offer itself has no scroll view, the answer strip stays within its existing height limit and scrolls, and every result can be reached by scrolling the strip
