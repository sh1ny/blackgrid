# 0052 - Floor navigation follows prepared order

- Status: accepted
- Date: 2026-11-27
- Source: `floor-deck-rail` (S2, D1, D2)
- Supplements: [ADR-0033](0033-map-packs-proven-by-reproduction.md) and [ADR-0050](0050-floor-extents-are-pack-owned.md)

## Context

The floor rail needs the vertical order of every selectable floor, including bases that sit above lower decks or basements. Floor extents classify positions; ranges can overlap and do not define navigation order. The prepared floor array also affects the relative order of raster tiles, so reordering it must not change existing artwork.

## Decision

- The reviewed floor arrays in `tool/maps/calibration.dart` and `tool/maps/inventory.dart` run bottom to top. Preparation copies the order into the existing manifest array. The app uses that array for navigation and reverses it for the rail. It does not sort by extents or move the base. The explicit base flag and existing extent and drawing rules remain in force.
- `mise run maps:rebuild -- --reviewed-floor-order` uses the verified active generation and admits only a permutation of each map's existing floor identities. On additive maps the base paints first when faded, and non-base raster floors retain their existing relative paint order. Reject a permutation that would change that raster order. Preserve all non-order facts and artwork bytes and use the existing validation and publication transaction.
- The default rebuild, offline check and metadata-only renewal continue to use the active generation's frozen calibration, source lock and notices. They do not import a pending authored reorder. Artwork staging and publication keep their existing calibration admission checks.

## Consequences

Floor navigation no longer needs a computed order or a new manifest field. A reorder that would change the additive raster stack needs a separate artwork change. The order-only rebuild reports the affected maps for the owner's check before merge.
