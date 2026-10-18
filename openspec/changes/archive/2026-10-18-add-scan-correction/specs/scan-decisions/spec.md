# Spec Delta

## MODIFIED Requirements

### Requirement: An accepted scan becomes the current selection
When a scan is published as accepted for item X, the app SHALL make X the current selection: the decision card, needs and sources panels SHALL show X and its decision, on Scanner and on Map. The newest selection SHALL win: an accepted scan, a manual selection, a history selection and a picked scan correction each replace whatever was shown, in the order they happened.

#### Scenario: Accepted scan replaces a manual selection
- **WHEN** the user has manually selected item A and a scan is then accepted for item B
- **THEN** the decision card shows item B and its decision

#### Scenario: Manual selection after a scan
- **WHEN** a scan was accepted for item B and the user then manually selects item A
- **THEN** the decision card shows item A, and a later refresh does not bring back item B

#### Scenario: Accepted scan while a history row is open
- **WHEN** the user has a history row for item A open and a scan is accepted for item B
- **THEN** the history view closes and the decision card shows item B in the live mode

#### Scenario: Accepted scan after a correction
- **WHEN** the user picked item C from a scan's correction offer and a scan is then accepted for item B
- **THEN** the decision card shows item B as an accepted scan, no longer labelled as corrected

### Requirement: FIR resets on every new accepted scan
Transient FIR SHALL reset to unknown on every accepted scan that drives a decision, even when it is the same item as before. It SHALL also reset on a picked scan correction, even when it is the item already shown, and on a mode or session change. A FIR value the user sets SHALL apply only to the current scan or correction.

#### Scenario: Same item scanned again
- **WHEN** a scan is accepted for item B, the user sets FIR to yes, and a second scan is accepted for item B
- **THEN** FIR is unknown and the decision is computed with FIR unknown

#### Scenario: Session change
- **WHEN** a scan is accepted for item B, the user sets FIR to yes, and the game session then changes
- **THEN** FIR is unknown

#### Scenario: Correction to the item already shown
- **WHEN** a scan is accepted for item B, the user sets FIR to yes, and the user then picks B from a later scan's correction offer
- **THEN** FIR is unknown and the decision is computed with FIR unknown
