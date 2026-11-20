# Spec Delta

## MODIFIED Requirements

### Requirement: Status actions lead to their controls
The status bar SHALL let the user switch game mode, open the Settings page at Item and map data or at Local progress, and toggle live scan. Every setting displaced from the work screens SHALL live on the Settings page. Live scan status SHALL state actual pipeline state and use DESIGN.md X4. The Progress item SHALL read "Progress loading" until the first read of the effective mode's local progress ends, "Progress local" once it has been read, and "Progress unavailable" when it cannot be read or the mode is `unknown`. A re-read after an edit SHALL keep "Progress local".

#### Scenario: Settings targets
- **WHEN** the Item data or Progress status is activated
- **THEN** the Settings page opens with Item and map data or Local progress visible and keyboard reachable

#### Scenario: Settings target while the page is open
- **WHEN** the Settings page is open at General and the Progress status is activated
- **THEN** Local progress scrolls into view and no second Settings opens

#### Scenario: Progress status words
- **WHEN** the effective mode is PvP and PvP's local progress can be read
- **THEN** the status bar says "Progress local" and no status bar text contains "Tracker"

#### Scenario: Loading after a mode switch
- **WHEN** the player switches to PvE and PvE's local progress has not been read yet
- **THEN** the status bar says "Progress loading", and "Progress local" once the read ends

#### Scenario: Edit keeps the label
- **WHEN** the status bar says "Progress local" and the player ticks an objective
- **THEN** the status bar never says "Progress loading" while the new values are read

#### Scenario: Progress unavailable
- **WHEN** the effective mode is PvP and PvP's wipe history is unavailable, or the effective mode is `unknown`
- **THEN** the status bar says "Progress unavailable"

#### Scenario: Failed live scan save
- **WHEN** live scan is toggled through the status bar and saving fails
- **THEN** existing switch-on rollback and switch-off stopping rules apply and the error is visible; the status never falsely claims listening

#### Scenario: Status bar presentation and binding
- **WHEN** the status bar is shown at normal scale and live scan changes binding or state
- **THEN** its height is 28px, items start at the left, no touch icon precedes game mode, and live scan shows a 6px state dot with truthful words and the active key or click-only guidance; unavailable state includes its reason and the existing status actions remain usable
