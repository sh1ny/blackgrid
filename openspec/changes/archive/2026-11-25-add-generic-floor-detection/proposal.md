# Proposal

## Why

Reserve and Streets never follow the player's floor automatically because Blackgrid only enables Auto for Labs and Icebreaker and models floors as a single height band. Issue [#131](https://github.com/sh1ny/blackgrid/issues/131) replaces this gate with the layer extents the pack already carries as frozen evidence, including the horizontal bounds needed on Reserve.

This is off-roadmap Map maintenance, linked to M5's deferred automatic-floor owner check ([roadmap, Other](../../roadmap.md#other)); it does not change M10 or the roadmap. Real raid verification remains owner-only and unverified.

## What Changes

- Prepare automatic floor extents for all supported maps from frozen interactive layer metadata. Link extents to exactly one prepared floor or fail the build with its map and layer.
- Replace the prepared floor's single height-band field with validated extents. Rebuild and commit the bundled pack with the app that reads it.
- Offer Auto by default on any map with extents. Classify a sampled player position in game coordinates; an unmatched known position selects the base and unknown height leaves the current selection alone. A manual floor choice disables Auto for that map until re-enabled.
- Use the same position classifier for unassigned markers. Keep explicit marker ownership, place-label floor assignment, floor artwork and additive/exclusive visibility semantics. Base-level dimming (#130), screenshot acquisition and the transit-map fix are out of scope.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-controls`: eligibility, position-based floor following, unassigned marker inference and manual override.
- `prepared-map-packs`: floor extents, source linking, validation and active pack format.

## Impact

`tool/maps/` preparation and validation; prepared pack manifest and loader; floor policy and MapController; offline map tests and the active bundled generation. No source acquisition change or new runtime dependency.

Branch gate: the clean Orca worktree's HEAD, local `main` and the fenced `origin/main` fetch all resolved to `e39c52b715d79829cd681251d480808db47ac594`. The coordinator approved starting `feat/add-generic-floor-detection` from that commit without switching the main checkout.

## Decision Making

DECISION_MAKING: important
Source: setting

- **S1 — Cover every supported map with extents in this change.** Choice: use one source-driven rule; no map-specific runtime exceptions. Rejected: fix Reserve and Streets separately while retaining hard-coded policies. Reversal cost: medium. Important: yes (player-visible behavior). Chosen by: user (#131).
- **S2 — Keep the change outside M10.** Choice: Map maintenance linked to the deferred M5 owner check. Rejected: add a milestone or change the M10 plan. Reversal cost: low. Important: no. Chosen by: user (via coordinator).
- **S3 — Share spatial inference with unassigned markers.** Choice: use the same position rule for the player and unassigned markers while retaining explicit ownership. Rejected: leave unassigned vector markers on the old rule and use height-only inference elsewhere. Reversal cost: medium. Important: yes (marker visibility changes). Chosen by: user (via coordinator).

## Release Notes

Blackgrid uses saved position samples to follow floors on supported multi-floor maps, including Reserve and Streets. You can still choose a floor by hand.

### Fixed

- Map Auto follows floors on multi-floor maps such as Reserve and Streets, using each map's floor heights and area bounds, instead of only on Labs and Icebreaker. You can still choose a floor by hand.
- Map markers without an assigned floor follow the same floor rules as your position; markers with an assigned floor keep it.
