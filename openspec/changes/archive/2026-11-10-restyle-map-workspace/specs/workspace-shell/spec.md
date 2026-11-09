# Spec Delta

## MODIFIED Requirements

### Requirement: Inspector preserves the workspace
On Scanner the inspector SHALL provide history, details, requirements and sources. On Map it SHALL provide This raid, Markers and Pins, and no item details. It SHALL start open above 1080px and closed otherwise, initialized once per shell session; later resizing SHALL preserve the user's open/closed state. At widths at most 1080px it SHALL float with a scrim. Closing or resizing SHALL retain the mounted workspace and return focus to the opener. Panel motion SHALL follow DESIGN.md and reduced-motion settings.

#### Scenario: Docked details
- **WHEN** the inspector is opened in a wide window on Scanner
- **THEN** it shows inspection details beside the workspace without replacing the current subject

#### Scenario: Resize with open details
- **WHEN** an open inspector crosses the 1080px threshold and is then closed with Escape
- **THEN** it becomes an overlay, preserves selection and detail expansion state, and returns focus to the opener without resetting the map viewport

#### Scenario: Scanner history leads the inspector
- **WHEN** Scanner's inspector opens with recent items
- **THEN** recent activity is the first working list and is visible without scrolling past empty detail panels; supporting details fit content or expand explicitly, and history retains lazy image leases

#### Scenario: Initial inspector state follows window width
- **WHEN** a new shell opens above 1080px or at or below 1080px
- **THEN** its inspector starts open or closed respectively, and a subsequent user toggle followed by resizing preserves the user's current state

#### Scenario: Map inspector holds working lists
- **WHEN** Map's inspector opens with an item selected
- **THEN** it shows This raid, Markers and Pins in that order, and no requirements, sources or history panel
