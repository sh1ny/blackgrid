# Spec Delta

## MODIFIED Requirements

### Requirement: Best and runner-up are chosen deterministically
The matcher SHALL score every candidate. A candidate whose normalised name equals the current best's SHALL count as a duplicate: it SHALL not become the runner-up, and the smaller ID (ordinal) SHALL be kept as best. The margin SHALL be the best score minus the runner-up score; an exact tie between different names SHALL give margin 0. Every scored result SHALL also carry up to 5 candidates with distinct normalised names, ranked by similarity descending then ID (ordinal), each with its ID and similarity, drawn from the same candidates as the best (after any quantity restriction). The first SHALL be the best and the second the runner-up, except when the best shares its display name: then the candidates SHALL follow the same-name listing rule, and the runner-up and margin SHALL stay as computed here.

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
- **WHEN** items "b2" and "a1" both normalise to "gas analyzer" but are named "Gas analyzer" and "Gas Analyzer (old)", item "c3" normalises to "gas mask", and the title is "Gas analyzer"
- **THEN** the candidates are "a1" then "c3", and "b2" is not among them

#### Scenario: Same display name in the candidates
- **WHEN** items "b2" and "a1" are both named "Gas analyzer", item "c3" is named "Gas mask", and the title is "Gas analyzer"
- **THEN** the candidates are "a1", "b2", then "c3", and the runner-up is still "c3"

#### Scenario: Fewer candidates than five
- **WHEN** the index holds two items
- **THEN** the result carries two candidates

#### Scenario: Rejected before scoring
- **WHEN** a title is rejected `titleTooShort`, `uiChrome`, `emptyCatalog` or `catalogModeMismatch`
- **THEN** the result carries no candidates

#### Scenario: Quantity restriction
- **WHEN** the title's quantity restricts the candidates to the two items whose raw names end in that quantity
- **THEN** the result's candidates are only those two items

## ADDED Requirements

### Requirement: A best candidate sharing its display name is ambiguous
An item's display name SHALL be its raw name normalised as titles are. When the best candidate would be accepted and another indexed item has the same display name, the result SHALL be `ambiguous` instead, keeping its best, runner-up and margin. A result below the similarity gate SHALL stay `belowSimilarity`. Items whose display names differ SHALL be matched as before.

#### Scenario: Weapon case variants
- **WHEN** the catalog holds "Weapon case" with normalised name "weapon-case" and "Weapon case" with normalised name "weapon-case-1", and the title reads "Weaponcase"
- **THEN** the result is `ambiguous`, not accepted, and no item ID is accepted

#### Scenario: Equal normalised names
- **WHEN** items "b2" and "a1" are both named "Gas analyzer" with equal normalised names, and the title is "Gas analyzer"
- **THEN** the best is "a1", "b2" is not the runner-up, and the result is `ambiguous`

#### Scenario: Unique display name
- **WHEN** the catalog holds "Item case" and "Weapon case" once each, and the title reads "Weapon case"
- **THEN** the Weapon case is accepted, as before

#### Scenario: Shared name below the gate
- **WHEN** the best candidate shares its display name and its similarity is .50
- **THEN** the result is `belowSimilarity`

### Requirement: Same-name items are listed among the candidates
When the best candidate shares its display name, the result's candidates SHALL list the best first, then every other indexed item with that display name in ID order, each with its own similarity, then the remaining candidates by the usual ranking, at most 5 in all. Same-name items SHALL be listed even when their normalised names are equal.

#### Scenario: Two variants
- **WHEN** a title reading "Weapon case" matches the two Weapon case items at 1.0 and .909, and "Item case" scores .80
- **THEN** the candidates are the "weapon-case" item at 1.0, the "weapon-case-1" item at .909, then "Item case" at .80

#### Scenario: More same-name items than fit
- **WHEN** the best candidate shares its display name with 49 other items
- **THEN** the candidates are the best and the first 4 other same-name items in ID order, and no other candidate
