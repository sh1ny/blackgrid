# Spec Delta

## ADDED Requirements

### Requirement: Unaccepted scan evidence never produces a recommendation
Publishing a scan that is not accepted, whether rejected or failed, SHALL NOT change the current selection, the decision card, the needs and sources panels, or the history. Only an accepted scan reaches keep/sell advice, through the scan-decisions rules; the evidence panel itself never shows a recommendation.

#### Scenario: Accepted scan drives the decision card
- **WHEN** the user has manually selected item A and a scan is accepted for item B
- **THEN** the decision card shows item B, and history gains one entry for B with source `scan`

#### Scenario: Rejected scan with a best candidate
- **WHEN** a scan is rejected with best candidate C
- **THEN** no decision, recommendation or history entry for C is shown

## REMOVED Requirements

### Requirement: Scan evidence never produces a recommendation
**Reason**: M4 lets accepted scans drive the decision (ADR-0017, superseding ADR-0013's "No decisions from scans before M4"). Its scenario "Accepted scan leaves the decision card alone" no longer holds.
**Migration**: Replaced by "Unaccepted scan evidence never produces a recommendation" in this spec and by the scan-decisions capability, which defines how an accepted scan becomes the selection.
