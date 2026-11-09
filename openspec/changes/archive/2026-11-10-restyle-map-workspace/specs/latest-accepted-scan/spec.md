# Spec Delta

## MODIFIED Requirements

### Requirement: Map shows scans in its one decision card
Map SHALL show accepted scans only through the shared answer strip, the same strip Scanner shows. It SHALL have no separate latest-scan panel. Scanning SHALL keep working while Map is the open screen: a scan accepted then SHALL become the current selection and the latest accepted scan, exactly as on Scanner.

#### Scenario: No separate panel
- **WHEN** Map is open
- **THEN** no "Latest accepted scan" panel is shown, and the map picker and the answer strip are shown

#### Scenario: Scan accepted with Map open
- **WHEN** Map is the open screen and a scan is accepted for item B
- **THEN** the answer strip shows item B as an accepted scan, and the latest accepted scan is item B

#### Scenario: Scan fenced with Map open
- **WHEN** Map is the open screen and a scan is published as accepted after the mode changed
- **THEN** the answer strip and the latest accepted scan are unchanged
