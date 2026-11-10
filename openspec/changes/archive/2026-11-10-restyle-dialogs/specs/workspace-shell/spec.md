# Spec Delta

## MODIFIED Requirements

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
