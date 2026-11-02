# Spec Delta

## ADDED Requirements

### Requirement: Each flea sale is published once with its mode
Each flea sale read from the push-notifications log SHALL be published once as a flea-sale transition, with the identity and time of its record, the sold item, the count, the rouble payout when the sale paid in roubles, and the last session mode logged before it. A sale SHALL NOT change the raid phase or any raid. Reading the same session folder again SHALL publish it with the same identity.

#### Scenario: Sale during a session
- **WHEN** session mode PvE is logged, then a flea sale of 2 of one item paying 45 000 roubles is applied
- **THEN** one flea-sale transition is published with that record's identity and time, count 2, 45 000 roubles and mode PvE, and the phase is unchanged

#### Scenario: Sale before any mode is logged
- **WHEN** a flea sale is applied before any session mode was logged in the folder
- **THEN** the flea-sale transition is published with no mode

#### Scenario: Sale paid in another currency
- **WHEN** a flea sale whose payout holds no roubles is applied
- **THEN** the flea-sale transition is published with no rouble payout

#### Scenario: Replay after an app restart
- **WHEN** the same session folder is read again from the start after Blackgrid restarts
- **THEN** each flea sale is published again with the same record identity as before

#### Scenario: Sale during a raid
- **WHEN** a flea sale is applied while the phase is in raid
- **THEN** the phase stays in raid, the current raid is unchanged and one flea-sale transition is published
