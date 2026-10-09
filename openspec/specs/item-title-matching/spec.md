# item-title-matching Specification

## Purpose
Turns recognised inspection title text into an accepted, mode-scoped catalog identity or a typed rejection, using the reference's baseline gates and safeguards, so that no unaccepted evidence ever becomes an item identity.

## Requirements

### Requirement: Titles and catalog names are normalised the same way
Normalisation SHALL apply Unicode NFKC, then lower case. It SHALL keep letters (Lu, Ll, Lt, Lm, Lo), decimal digits (Nd) and letter numbers (Nl), and turn every run of other characters into a single space. Leading and trailing separators SHALL be dropped. Blank input SHALL normalise to the empty string.

#### Scenario: Punctuation and spacing fold
- **WHEN** "SR-2M 9x21 (20 pcs)" is normalised
- **THEN** the result is "sr 2m 9x21 20 pcs"

#### Scenario: Compatibility characters fold
- **WHEN** a title containing a full-width "ＡＫ－７４" is normalised
- **THEN** the result is "ak 74"

#### Scenario: Whitespace-only title
- **WHEN** a title of only spaces and punctuation is normalised
- **THEN** the result is the empty string

### Requirement: Match index is built from one immutable catalog snapshot
A match index SHALL be built from one catalog snapshot and SHALL record that snapshot's mode and revision. Each item's candidate name SHALL be its normalised `normalizedName`, or its normalised name when that is blank. The index SHALL not change after it is built.

#### Scenario: Index records its source
- **WHEN** an index is built from a PvE snapshot at revision "r42"
- **THEN** every match result from it reports mode `pve` and revision "r42"

#### Scenario: Kebab-case normalised names
- **WHEN** an item's `normalizedName` is "salewa-first-aid-kit"
- **THEN** its candidate name is "salewa first aid kit"

#### Scenario: Empty catalog
- **WHEN** a title is matched against an index built from a snapshot with no items
- **THEN** the result is rejection `emptyCatalog`

### Requirement: Similarity is the better of two edit measures
The similarity of two normalised strings SHALL be the greater of 1 − Levenshtein ÷ longer length, and a compact similarity in which inserting or deleting a space costs nothing, measured over non-space lengths. Two empty strings SHALL have similarity 1.

#### Scenario: Spacing difference only
- **WHEN** "comtac ii" is compared with "comtacii"
- **THEN** the similarity is 1.0

#### Scenario: One substitution
- **WHEN** "salewa" is compared with "salewo"
- **THEN** the similarity is 1 − 1/6

### Requirement: Titles that are too short or are UI chrome are rejected before matching
A title whose normalised length is below 3 SHALL be rejected as `titleTooShort`. A normalised title exactly equal to a localised UI-chrome label SHALL be rejected as `uiChrome`. The labels are: "subject search", "поиск предмета", "rechercher un objet", "buscar objeto", "procurar item", "cerca oggetto", "szukaj przedmiotu", "搜索物品", "아이템 검색" and "アイテム検索".

#### Scenario: Length at the gate
- **WHEN** a title normalises to "m4a" (length 3) and matches a catalog item exactly
- **THEN** the match is evaluated rather than rejected as `titleTooShort`

#### Scenario: Length below the gate
- **WHEN** a title normalises to "ak" (length 2)
- **THEN** the result is `titleTooShort`, even if a catalog item is named "AK"

#### Scenario: Chrome label
- **WHEN** the OCR text is "Subject Search"
- **THEN** the result is `uiChrome`, even if a catalog item's name contains "search"

### Requirement: Best and runner-up are chosen deterministically
The matcher SHALL score every candidate. A candidate whose normalised name equals the current best's SHALL count as a duplicate: it SHALL not become the runner-up, and the smaller ID (ordinal) SHALL be kept as best. The margin SHALL be the best score minus the runner-up score; an exact tie between different names SHALL give margin 0.

#### Scenario: Duplicate names
- **WHEN** two items with IDs "b2" and "a1" both normalise to "gas analyzer" and the title is "Gas analyzer"
- **THEN** the best is "a1" with similarity 1.0, and "b2" is not the runner-up

#### Scenario: Distinct names tie
- **WHEN** two distinct candidate names score exactly 0.8 and nothing scores higher
- **THEN** the margin is 0, and the result is decided by the near-tie rule

### Requirement: Scores and gates are evaluated in single precision
Similarities, the margin and every gate comparison SHALL be evaluated in IEEE single precision, as the reference does: each similarity is rounded to single precision, the margin is the single-precision difference, and each gate constant is its single-precision value.

#### Scenario: Margin at the gate
- **WHEN** over 20-character names the best similarity is 0.95 and the runner-up 0.90, and the confirming matcher picked a different item
- **THEN** the margin is 0.0500000119 in single precision, at least the .05 gate, and the best is accepted

#### Scenario: Margin just below the gate in single precision
- **WHEN** the single-precision margin is the largest single-precision value below 0.05
- **THEN** the near-tie rule decides the result

### Requirement: Baseline acceptance gates
The matcher SHALL accept the best candidate only when its similarity is at least .55 and either the margin is at least .05 or the near-tie rule accepts it. Otherwise the result SHALL be `belowSimilarity` or `ambiguous`. Every result SHALL carry the normalised title, the best and runner-up IDs and scores, and the margin.

#### Scenario: Clear accept
- **WHEN** the best similarity is .90 and the runner-up is .60
- **THEN** the best is accepted with similarity .90, runner-up .60 and margin .30

#### Scenario: Similarity just below the gate
- **WHEN** the best similarity is .5499
- **THEN** the result is `belowSimilarity` carrying .5499

#### Scenario: Margin just below .05 without confirmation
- **WHEN** the best is .80, the runner-up is .7501, and the confirming matcher picked a different item
- **THEN** the result is `ambiguous` with margin .0499

### Requirement: Near-ties need confirmation, and the closest ties also need quantity agreement
When the margin is below .05, the best candidate SHALL be accepted only if the confirming matcher picked the same item with confidence at least .55. When the margin is below .03, it SHALL also need a matching quantity: a title quantity token of 10 or more equal to the last number in the best candidate's raw name.

#### Scenario: Confirmed near-tie
- **WHEN** the margin is .04 and the confirming matcher picked the best item with confidence .70
- **THEN** the best is accepted

#### Scenario: Close tie with quantity agreement
- **WHEN** the margin is .01, the confirming matcher agrees, and the title "5.56x45 (20 pcs)" has quantity 20, as does the best candidate's raw name
- **THEN** the best is accepted

#### Scenario: Close tie without quantity
- **WHEN** the margin is .01, the confirming matcher agrees, and the title has no number of 10 or more
- **THEN** the result is `ambiguous`

### Requirement: Confirming matcher compares lower-cased raw names
The confirming matcher SHALL compare the trimmed, lower-cased title with each item's lower-cased raw name by normalised Levenshtein. The first candidate in catalog ID order SHALL win ties. It SHALL report an item only at confidence .55 or more, and none when the title is within .85 similarity of a UI-chrome label. Confusable Cyrillic capitals SHALL map to Latin first.

#### Scenario: Confirming pick
- **WHEN** the title is "Salewa first aid kit" and the catalog holds "Salewa first aid kit" and "Grizzly medical kit"
- **THEN** the confirming matcher reports the Salewa item with confidence 1.0

#### Scenario: Near-chrome title
- **WHEN** the title is "Subject Serch"
- **THEN** the confirming matcher reports no item

#### Scenario: Cyrillic look-alike capitals
- **WHEN** the title contains Cyrillic "АК" in place of Latin "AK"
- **THEN** the confirming matcher compares it as Latin "ak"

### Requirement: A title quantity restricts candidates
The matcher SHALL take the title's last run of digits as a number, ignoring digits once the value passes 100000. "@" SHALL read as 0. An "i" or "l" outside a number, at the start or after a non-alphanumeric character and followed by a digit or "@", SHALL read as 1. When the number is 10 or more and a candidate whose raw name's last number equals it scores .55 or more, only such candidates SHALL count.

#### Scenario: OCR confusion in quantity
- **WHEN** the title is "5.56x45 (i2@ pcs)"
- **THEN** the title quantity is 120

#### Scenario: Quantity selects the variant
- **WHEN** the catalog holds "Ammo pack (20 pcs)" and "Ammo pack (200 pcs)" and the title reads "Ammo pack (200 pcs)"
- **THEN** only the 200-pcs item is considered, and it is accepted

#### Scenario: Quantity with no matching candidate
- **WHEN** the title's number is 2000 and no candidate whose raw name's last number is 2000 has similarity of at least .55
- **THEN** no restriction applies, and all candidates are scored

### Requirement: Targeted and fallback evidence are ranked into one outcome
A recognition outcome SHALL be the matched targeted evidence when accepted. Otherwise, given full-client evidence, it SHALL rank by acceptance, then similarity, then marker score, then peak order, and take the first. With no evidence at all it SHALL be rejection `noMarker`; if matching itself fails, `matcherFailed`. An unaccepted outcome SHALL carry its evidence and SHALL NOT expose an accepted item ID.

#### Scenario: Targeted accepted
- **WHEN** the targeted evidence is accepted
- **THEN** the outcome is that accepted identity, and the fallback evidence is not consulted

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
