# Spec Delta

## MODIFIED Requirements

### Requirement: Best and runner-up are chosen deterministically
The matcher SHALL score every candidate. A candidate whose normalised name equals the current best's SHALL count as a duplicate: it SHALL not become the runner-up, and the smaller ID (ordinal) SHALL be kept as best. The margin SHALL be the best score minus the runner-up score; an exact tie between different names SHALL give margin 0. Every scored result SHALL also carry up to 5 candidates with distinct normalised names, ranked by similarity descending then ID (ordinal), each with its ID and similarity, drawn from the same candidates as the best (after any quantity restriction). The first SHALL be the best and the second the runner-up.

#### Scenario: Duplicate names
- **WHEN** two items with IDs "b2" and "a1" both normalise to "gas analyzer" and the title is "Gas analyzer"
- **THEN** the best is "a1" with similarity 1.0, and "b2" is not the runner-up

#### Scenario: Distinct names tie
- **WHEN** two distinct candidate names score exactly 0.8 and nothing scores higher
- **THEN** the margin is 0, and the result is decided by the near-tie rule

#### Scenario: Ranked candidates
- **WHEN** seven items with distinct names score .9, .8, .7, .6, .5, .4 and .3 against a title
- **THEN** the result's candidates are the five scoring .9 to .5 in that order, the first is the best and the second is the runner-up

#### Scenario: Duplicate names in the candidates
- **WHEN** items "b2" and "a1" both normalise to "gas analyzer", item "c3" normalises to "gas mask", and the title is "Gas analyzer"
- **THEN** the candidates are "a1" then "c3", and "b2" is not among them

#### Scenario: Fewer candidates than five
- **WHEN** the index holds two items
- **THEN** the result carries two candidates

#### Scenario: Rejected before scoring
- **WHEN** a title is rejected `titleTooShort`, `uiChrome`, `emptyCatalog` or `catalogModeMismatch`
- **THEN** the result carries no candidates

#### Scenario: Quantity restriction
- **WHEN** the title's quantity restricts the candidates to the two items whose raw names end in that quantity
- **THEN** the result's candidates are only those two items
