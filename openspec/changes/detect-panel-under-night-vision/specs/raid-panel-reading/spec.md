# Raid panel reading

## ADDED Requirements

### Requirement: Detect exfil headers dimmed by night vision

Blackgrid SHALL identify saved screenshots with an exfil panel even when night vision dims its header. Night-vision scenery alone SHALL NOT be treated as an exfil panel.

#### Scenario: Dimmed header on Shoreline
- **WHEN** a saved screenshot has a dim yellow-green header like the owner's 2026-11-25 Shoreline screenshot at raid time 12.26
- **THEN** Blackgrid detects the exfil panel and proceeds to read it

#### Scenario: Standard header
- **WHEN** a saved screenshot has a standard bright green exfil panel header
- **THEN** Blackgrid continues to detect the exfil panel and proceeds to read it

#### Scenario: Night-vision scenery without a panel
- **WHEN** a saved screenshot has night-vision scenery but no exfil panel
- **THEN** Blackgrid reports no exfil panel and does not run panel recognition
