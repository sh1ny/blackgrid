# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: Built hideout levels come from Tracker progress for the same mode`
- TO: `### Requirement: Built hideout levels come from local progress for the same mode`

## MODIFIED Requirements

### Requirement: Built hideout levels come from local progress for the same mode
A hideout level SHALL count as built only when the local progress of the cooldown's mode records that station at that level or higher. A station with no recorded level SHALL count as not built. When the mode's local progress cannot be read, no bonus SHALL apply and the scav entry SHALL say the length has no hideout bonuses because progress is unavailable. Progress SHALL count however old it is.

#### Scenario: Progress for the mode
- **WHEN** PvP local progress records Intelligence Center at level 1
- **THEN** the PvP cooldown length includes its −0.15 bonus

#### Scenario: Higher level counts lower bonuses
- **WHEN** PvP local progress records Intelligence Center at level 3
- **THEN** the PvP cooldown length includes the bonuses of Intelligence Center levels 1, 2 and 3 that the item data lists

#### Scenario: Progress for another mode
- **WHEN** only PvE local progress records Intelligence Center and the PvP cooldown is shown
- **THEN** no Intelligence Center bonus applies to the PvP length

#### Scenario: Progress unavailable
- **WHEN** PvP's local progress cannot be read and the PvP cooldown is shown
- **THEN** no hideout bonus applies and the scav entry says progress is unavailable, so there are no hideout bonuses

#### Scenario: Stale progress
- **WHEN** the PvP station level was recorded a week ago
- **THEN** the PvP cooldown length still includes its bonus
