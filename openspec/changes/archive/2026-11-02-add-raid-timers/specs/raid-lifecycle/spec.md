# Spec Delta

## ADDED Requirements

### Requirement: A raid records its countdown and a guessed side
A raid entered from a queue SHALL record the time of the last raid-starting event since its queue, if any, and a guessed side: PMC when that event came more than 3 s before raid started, otherwise scav. A transit raid SHALL take the side of the raid it left. A reconnect SHALL keep the raid's side. A raid entered without a queue, or by a reconnect with no earlier raid known, SHALL have side unknown.

#### Scenario: PMC countdown
- **WHEN** queue entered, match found, raid starting at 19:40:51 and raid started at 19:41:06 are applied
- **THEN** the raid records raid starting at 19:40:51 and side PMC

#### Scenario: No countdown
- **WHEN** queue entered, match found and raid started are applied, with no raid-starting event
- **THEN** the raid records no raid-starting time and side scav

#### Scenario: Short countdown
- **WHEN** raid starting is applied at 19:41:04 and raid started at 19:41:06, after a queue
- **THEN** the raid's side is scav

#### Scenario: Countdown exactly 3 s
- **WHEN** raid starting is applied at 19:41:03.000 and raid started at 19:41:06.000, after a queue
- **THEN** the raid's side is scav

#### Scenario: Raid starting from an aborted queue
- **WHEN** a queue with raid starting at 19:30:00 is aborted, then a new queue, match found and raid started at 19:41:06 are applied
- **THEN** the raid records no raid-starting time and side scav

#### Scenario: Transit keeps the side
- **WHEN** a raid with side scav ends and a transit into another map starts a new raid
- **THEN** the new raid's entry is transit and its side is scav

#### Scenario: Reconnect keeps the side
- **WHEN** a raid with side PMC is interrupted by a client restart and continued by a reconnect
- **THEN** the continued raid's side is PMC

#### Scenario: No queue
- **WHEN** a raid starts while the phase is in menus with no queue entered since
- **THEN** the raid's side is unknown

#### Scenario: Reconnect after Blackgrid starts
- **WHEN** Blackgrid starts with only a new session folder holding profile selected, raid rejoined and raid started
- **THEN** the raid's entry is reconnect and its side is unknown
