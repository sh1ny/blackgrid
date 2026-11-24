# Design

## Triage

| Trigger | Applies? | Evidence |
|---|---|---|
| T1 Components (new component, or 3+ with directed relationships) | no | One condition and one paint loop inside `NativeMapScene` (`lib/maps/native_map_scene.dart:277-283`, `:333-354`). |
| T2 State (persistent state, caches, 3+ state machine) | no | `_dimBase` is a final field computed per scene from its immutable selection (`lib/maps/native_map_scene.dart:277`, `:290`); nothing is stored or cached anew. |
| T3 Concurrency (background work, workers/isolates, async, retries) | no | Painting is synchronous (`lib/maps/native_map_scene.dart:317-356`); scene loading is unchanged. |
| T4 Boundaries (data format, migration, shared interface, IPC, external) | no | No pack, format or public API changes; `NativeMapScene`'s public members stay as they are. |
| T5 Volume (grows without a fixed bound) | no | Same tiles and pictures as today, drawn with a different paint. |
| T6 Risk (security, money, data loss, unrecoverable user data) | no | Rendering only. |

TIER: LIGHT

## Context

- The base fades only when a visible non-base floor is drawn from raster tiles over vector artwork: `_dimBase` requires `map.kind == 'vector'` and a visible tile whose floor is not the base (`lib/maps/native_map_scene.dart:277-283`). Vector overlay floors (Reserve Bunkers, every Streets floor) therefore leave the base at full strength.
- The fade wraps each base picture in `saveLayer(null, _dimPaint)` (`lib/maps/native_map_scene.dart:334-345`); `_dimPaint` is black at alpha 51 (`lib/maps/native_map_scene.dart:367-368`). A layer paint's alpha is the layer's opacity on restore, so the base is drawn at 51/255 opacity. The existing test asserts the faded base pixel's alpha is below 128 (`test/maps/map_scene_test.dart:541`).
- Raster tiles are drawn after all pictures with one shared `_tilePaint` and no fade (`lib/maps/native_map_scene.dart:347-354`), so on a raster map (Labs) the base tiles never fade.
- Vector components carry the id of the floor that owns them, attached layers included: the pack loader passes the owning `floorId` to every component of a floor, including its `attachedIds` (`lib/maps/prepared_map.dart:274-288`). Tiles carry their floor's id the same way (`lib/maps/prepared_map.dart:252`, `:272`). So "item belongs to the base" is `floorId == base.id` for both.
- `selectedOverlayIds` holds only non-base floors: choosing the base resets the selection to empty (`lib/domain/map_floors.dart:235`, `:250`). On an exclusive map the base is hidden whenever an overlay is selected (`lib/domain/map_floors.dart:266`), so nothing of the base is drawn to fade.
- Visible tiles keep `map.tiles` order (`lib/maps/native_map_scene.dart:395-402`).

## Decisions

### D1: The fade condition is "any non-base floor is selected"

- **Choice:** `_dimBase` becomes `selection.selectedOverlayIds.isNotEmpty`, for every map kind. On an exclusive map the base is not drawn then, so the flag has no effect.
- **Rejected:** Deriving the flag from which drawn items belong to non-base floors (pictures and tiles), as today's rule does for tiles, because it ties the fade to how floors are drawn, which is the cause of this bug, and needs loaded content to decide something the selection already states.
- **Reversal cost:** low
- **Important:** yes, it changes what users see (implements S1 and S2).
- **Chosen by:** user (the owner's request, recorded in proposal S1 and S2)

### D2: Base tiles fade through a tile paint at the same opacity

- **Choice:** Draw each base tile with a second tile paint whose colour has the same alpha as `_dimPaint` (51), so a faded base tile is drawn at 51/255 opacity, the same strength as a faded base picture. Tiles keep their order.
- **Rejected:** Wrapping the base tiles in one `saveLayer`, because base and overlay tiles are interleaved in `map.tiles` order and grouping them would either change draw order or need one layer per run, for no visible difference: tiles of one floor do not overlap.
- **Reversal cost:** low
- **Important:** no, the strength is the one users already see; only where it applies changes, which D1 records.
- **Chosen by:** agent

### Decision summary

| # | Decision | Choice | Rejected | Reversal cost | Important | Chosen by |
|---|---|---|---|---|---|---|
| S1 | Fade base for every non-base floor | Any artwork kind | Tile-only rule | low | yes (what users see) | user |
| S2 | Raster maps fade their base | Labs base tiles fade | Vector maps only | low | yes (what users see) | user |
| S3 | Fade strength | Keep ~20% opacity | Stronger or weaker | low | no | agent |
| S4 | Several floors visible | Only the base fades | Fade all but one | low | no | agent |
| D1 | Fade condition | Any selected non-base floor | Derive from drawn items | low | yes (what users see) | user |
| D2 | Fading base tiles | Tile paint at alpha 51 | One `saveLayer` around base tiles | low | no | agent |

## Assumptions

None

## Carried constraints

- **C1:** The base fades whenever any non-base floor is selected, independent of whether floors are drawn as vector artwork or raster tiles; the earlier tarkov.dev-style tile-only rule is a rejected alternative. Kind: rejected alternative. Destination: doc comment: lib/maps/native_map_scene.dart NativeMapScene._dimBase
- **C2:** Faded base pictures and faded base tiles must use the same opacity, so every floor fades at one strength. Kind: invariant. Destination: doc comment: lib/maps/native_map_scene.dart NativeMapScene._dimPaint
