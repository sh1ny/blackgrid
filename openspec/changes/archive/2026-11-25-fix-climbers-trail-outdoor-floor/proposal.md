# Proposal

## Why

Since #135, Shoreline's Climber’s Trail has taken the second-floor marker assignment from its height, hiding an outdoor exit on the ground map even when its exfil panel row matches (#139). This is corrective work alongside M10; it advances none of the alerts and window behaviour exit criteria.

## What Changes

- Keep the reviewed Climber’s Trail marker on Shoreline’s ground level without changing its coordinates, changing player Auto, or changing other markers’ floors.
- Preserve Underground ownership for Admin Basement and Transit to Labyrinth. Cover marker eligibility using the bundled Shoreline data offline.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-controls`: The bundled outdoor Climber’s Trail extract is eligible on Shoreline’s base floor even though its position alone resolves to the second floor.

## Impact

Shoreline reviewed marker calibration, existing source-placement guard, regenerated bundled map pack, and offline map tests. No panel parser or matcher, no player Auto policy, no artwork changes, and no new dependency or format.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Fix the extract without changing indoor exits or the panel parser

- **Choice:** Correct Climber’s Trail’s floor assignment and preserve the correctly classified underground routes.
- **Rejected:** A blanket extract-floor rule or parser workaround; both change behavior outside the reported failure.
- **Reversal cost:** Low.
- **Important:** Yes — restores ground-floor visibility.
- **Chosen by:** user (issue #139 and dispatch scope).

## Release Notes

Fix Shoreline’s Climber’s Trail marker on the ground map.

### Fixed

- Climber’s Trail shows on Shoreline’s ground level, and Admin Basement and Transit to Labyrinth stay on the underground floor.
