# Spec Delta

## ADDED Requirements

### Requirement: Same-name candidates are told apart in the offer
When two or more rows the offer lists, candidates and search results together, have the same display name, each of those rows SHALL also show its flea status from the live catalog (`flea`, `no flea`, or `flea unknown` when the catalog does not say) and the last 6 characters of its ID. Unknown SHALL never show as `flea`. Other rows SHALL show as before.

#### Scenario: Weapon case variants
- **WHEN** a scan ends rejected `ambiguous` with candidates "Weapon case" (ID ending `4b423c`, flea-listable) at 1.0 and "Weapon case" (ID ending `045d88`, no flea) at .909
- **THEN** the offer lists "Weapon case · flea · 4b423c" first and "Weapon case · no flea · 045d88" second, each with its similarity, and shows no recommendation

#### Scenario: Only one listed same-name item
- **WHEN** an offer lists "Weapon case" and "Item case", and the other Weapon case variant is not in the live catalog
- **THEN** both rows show only name and similarity

#### Scenario: Unknown flea status
- **WHEN** an offer lists two "Weapon case" candidates, one flea-listable and one whose catalog entry does not say whether it can be sold on the flea market
- **THEN** the second row shows `flea unknown` and never `flea`

#### Scenario: Variant found through the search
- **WHEN** a scan ends `ambiguous` with a best candidate in a same-name group of 12 items, so 7 variants are not among the candidates, and the user finds a sixth variant through the offer's search
- **THEN** that search row shows the variant's name, flea status and the last 6 characters of its ID

#### Scenario: Picking a variant
- **WHEN** the user picks the "no flea" Weapon case row
- **THEN** the current selection is the no-flea Weapon case and its decision is shown, as for any picked correction
