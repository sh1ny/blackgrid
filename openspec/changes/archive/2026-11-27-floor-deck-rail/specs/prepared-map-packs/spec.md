## MODIFIED Requirements

### Requirement: Existing offline and metadata-only workflows remain independent
Offline check, default rebuild and metadata-only renewal SHALL use the verified active generation's own calibration, source lock and notices, not pending reviewed configuration for a different artwork candidate. They SHALL retain source-index integrity, reproducibility, six-source replacement and non-metadata preservation checks, while conditional marker overrides do not freeze historical metadata content.

#### Scenario: Pending source and calibration changes
- **WHEN** reviewed source locks, notices or calibration differ for a pending artwork candidate while the old generation remains active
- **THEN** offline check and default rebuild use the old verified generation without network acquisition, and metadata-only renewal retains its baseline context and six-source and non-metadata preservation gates

#### Scenario: Metadata-only preservation fails
- **WHEN** metadata-only renewal changes preserved artwork, calibration, notices or non-six source records
- **THEN** its existing validation rejects the candidate and active assets, pointer and declarations remain unchanged

## ADDED Requirements

### Requirement: Floor arrays preserve the reviewed bottom-to-top order
The builder SHALL write the floor array in the bottom-to-top order of its reviewed inventory. Validation SHALL reject a candidate whose floor order differs from its frozen calibration. The runtime SHALL preserve the array order for floor navigation, including the base's position. The order SHALL NOT replace the explicit base flag, change floor extents, or require a new manifest field.

#### Scenario: Base in the middle of a deck stack
- **WHEN** a reviewed inventory lists a lower floor, the base and a higher floor in that order
- **THEN** the prepared array preserves that order, and the app starts on the flagged base floor rather than the first array entry

#### Scenario: Floor order is changed after preparation
- **WHEN** a candidate swaps two floor records without the same swap in its frozen calibration
- **THEN** validation fails naming the map and does not promote the candidate

#### Scenario: Reordering does not change artwork or classification
- **WHEN** the pack is regenerated with an order-only change to its reviewed floor lists
- **THEN** floor IDs, attachments, extents, marker and label ownership, and artwork bytes and stacking are unchanged

### Requirement: An explicit offline rebuild may update only floor order
An explicit `maps:rebuild -- --reviewed-floor-order` SHALL apply the reviewed order to the verified active generation without acquiring inputs. It SHALL reject missing, additional or duplicate floor IDs and any permutation that would change additive raster stacking. It SHALL preserve every floor record, other calibration and source facts, artwork and other prepared outputs. Normal validation and publication checks SHALL still apply.

#### Scenario: A reviewed floor permutation is promoted
- **WHEN** the operator explicitly rebuilds with the same reviewed floor IDs in a new order and the new order preserves the existing additive raster overlay stack
- **THEN** the candidate preserves baseline floor records, non-floor calibration and artwork bytes, reports the reordered maps as floor-order changes, promotes the new array order, and reproduces on the default offline check

#### Scenario: The reviewed order is not a permutation
- **WHEN** a reviewed order drops, adds or duplicates a floor ID relative to the active calibration
- **THEN** the rebuild fails naming the map and leaves the active pointer and asset declarations unchanged

#### Scenario: The permutation would change raster stacking
- **WHEN** the reviewed floor order has the same IDs but would change the relative paint order of visible raster overlays on an additive map
- **THEN** the rebuild fails naming the map and leaves the active pointer and asset declarations unchanged

#### Scenario: The candidate drifts beyond the reorder
- **WHEN** the order-only rebuild changes an artwork hash, floor fact, non-calibration source record or other preserved value
- **THEN** it fails before promotion, naming the changed path or fact
