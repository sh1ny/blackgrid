# Spec Delta

## MODIFIED Requirements

### Requirement: Targeted and fallback evidence are ranked into one outcome
Candidates SHALL be ranked by acceptance, then similarity, then marker score, then peak order, taking the first. When the best-ranked targeted entry is accepted, it SHALL be the outcome and fallback evidence SHALL NOT be matched. Otherwise targeted and full-client entries SHALL be ranked together, a targeted entry first on a full tie. No evidence SHALL be rejection `noMarker`; a matching failure, `matcherFailed`. An unaccepted outcome SHALL carry its evidence and no accepted item ID.

#### Scenario: Targeted accepted
- **WHEN** the targeted evidence holds one entry and it is accepted
- **THEN** the outcome is that accepted identity, and the fallback evidence is not consulted

#### Scenario: Targeted entries ranked among themselves
- **WHEN** the targeted evidence holds an unaccepted entry with marker .95 and an accepted entry with marker .85
- **THEN** the outcome is the accepted entry with marker .85, and the fallback evidence is not consulted

#### Scenario: Two accepted targeted entries
- **WHEN** the targeted evidence holds two accepted entries with similarities .90 and .97
- **THEN** the outcome is the entry with similarity .97

#### Scenario: Fallback chooses the accepted inspection
- **WHEN** targeted evidence is `noMarker`, and full-client evidence holds an unaccepted entry with marker .95 and an accepted entry with marker .85
- **THEN** the outcome is the accepted entry with marker .85

#### Scenario: Nothing accepted
- **WHEN** neither targeted nor full-client evidence is accepted
- **THEN** the outcome is a rejection carrying the highest-ranked evidence and its reason, and it reports no accepted item ID

#### Scenario: No marker anywhere
- **WHEN** neither the targeted nor the full-client result holds any evidence
- **THEN** the outcome is rejection `noMarker` carrying the best marker scores of both results

#### Scenario: Index from another mode
- **WHEN** an outcome is requested with an index whose mode differs from the caller's current mode
- **THEN** the result is rejection `catalogModeMismatch`, and no candidate is accepted
