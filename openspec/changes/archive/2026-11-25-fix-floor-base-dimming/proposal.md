# Proposal

## Why

When the player picks a floor other than the base, Blackgrid fades the base level only if that floor is drawn from raster tiles. Reserve's 2nd to 5th floors fade the ground correctly, but Reserve Bunkers, every Streets floor and every other vector floor are drawn over a full-strength ground level, so underground floors are hard to read (issue #130, reported by the owner with screenshots). This is an unplanned bug fix; it serves no M10 exit criterion.

## What Changes

- The base floor fades whenever any other floor of the same map is visible, whatever that floor is drawn with: vector artwork or raster tiles.
- Raster maps fade their base tiles the same way: Labs First Level fades under Second Level or Technical.
- The fade strength stays as it is today (the base is drawn at about 20% opacity, as Reserve's 2nd Floor already shows).
- With only the base and its attached layers visible (for example Streets' `First_Floor`), nothing fades.
- Maps whose floors are exclusive (Icebreaker) hide the base when another floor is chosen, so they are unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `map-controls`: adds a requirement that a chosen non-base floor fades the base floor, for every kind of floor artwork.

## Impact

- `lib/maps/native_map_scene.dart`: the rule that decides when the base fades, and fading of base raster tiles.
- `test/maps/map_scene_test.dart`: the existing test pins the old tile-only rule (a vector overlay keeps the base at full alpha) and changes with it.
- No pack, data format, setting or API change. No map pack rebuild.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Fade the base for every non-base floor, vector or tile

- **Choice:** Fade the base whenever any non-base floor is visible, whatever its artwork kind.
- **Rejected:** Keeping the tile-only rule (copied from tarkov.dev), which leaves Reserve Bunkers and every Streets floor unfaded: the reported bug.
- **Reversal cost:** low
- **Important:** yes, it changes behaviour users see.
- **Chosen by:** user ("we need to dim anything else that's not the level we're currently on, especially for the underground levels")

### S2: Raster maps fade their base too

- **Choice:** On raster maps whose floors are not exclusive (Labs), base tiles fade under a visible non-base floor, the same way vector bases do.
- **Rejected:** Limiting the fix to vector maps, which would leave Labs as the one map where the ground competes with the chosen floor.
- **Reversal cost:** low
- **Important:** yes, it changes behaviour users see.
- **Chosen by:** user (same words: "anything else that's not the level we're currently on")

### S3: Keep today's fade strength

- **Choice:** Keep the existing fade (base at about 20% opacity).
- **Rejected:** A stronger or weaker fade. The owner's screenshot of Reserve 2nd Floor shows today's strength already separates the floors; the bug is only when it applies.
- **Reversal cost:** low
- **Important:** no, the strength users already see on tile floors does not change.
- **Chosen by:** agent

### S4: Only the base fades when several floors are visible

- **Choice:** When more than one non-base floor is visible at once, only the base fades; the chosen floors stay at full strength.
- **Rejected:** Fading all but one chosen floor, which needs a notion of the "current" floor that a multi-floor selection does not have.
- **Reversal cost:** low
- **Important:** no, it matches what tile floors already do today.
- **Chosen by:** agent

## Release Notes

Choosing a floor now fades the ground level on every map, so underground and upper floors are easy to read.

### Fixed

- Choosing Reserve Bunkers, any Streets floor or any other floor now fades the ground level the way Reserve's upper floors already did, and Labs fades its First Level under the other levels.
