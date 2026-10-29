# Design

## Triage

| Trigger | Applies? | Evidence |
|---|---|---|
| T1 Components (new component, or 3+ with directed relationships) | no | One widget's layout inside `_MarkerTile` (`lib/ui/marker_preferences.dart:108`); no new component. |
| T2 State (persistent state, caches, 3+ state machine) | no | No state changes; the shown/hidden toggle and settings saving are untouched. |
| T3 Concurrency (background work, workers/isolates, async, retries) | no | Synchronous layout only. |
| T4 Boundaries (data format, migration, shared interface, IPC, external) | no | `MarkerPreferencesGrid`'s constructor and keys stay the same; no stored data. |
| T5 Volume (grows without a fixed bound) | no | The tile count is the fixed set of saveable categories plus Saved pins. |
| T6 Risk (security, money, data loss, unrecoverable user data) | no | Display only. |

TIER: LIGHT

## Context

See proposal.md for the bug. In `_MarkerTile.build`, the tile's fixed-size `SizedBox` holds a `Padding`, then a `Stack` (`lib/ui/marker_preferences.dart:108`). The Stack's children are a centred `Column` (badge, gap, label at line 110) and the shown-state check mark, which is `Positioned(top: -4, right: -2)` at line 136. The Stack uses the default `StackFit.loose` and `AlignmentDirectional.topStart`. A non-positioned child therefore gets loose constraints and sizes to its content. The Column's width is the width of its widest child, so a one-line label narrower than the tile leaves the whole Column at the tile's top-left. A label that wraps to two lines fills the available width, so its Column, and the Column's centred badge, look centred. Vertically the Column already takes the full height (its main axis size is the default `max`), so only the horizontal position is wrong.

Existing tests in `test/ui/marker_preferences_test.dart` check the tile size (line 288), the check mark and dimming (line 388), and semantics (line 430). None measures horizontal position, which is why the bug passed.

## Decisions

### D1: Make the Stack fill the tile

- **Choice:** set `fit: StackFit.expand` on the tile's Stack. The Column then gets the tile's full padded width and height, and its default `crossAxisAlignment: center` and existing `mainAxisAlignment: center` centre the badge and label both ways. The `Positioned` check mark keeps its top-right place, because positioned children ignore `fit`.
- **Rejected:** wrapping the Column in `Center` or `Align`, or giving the Stack `alignment: Alignment.center`. Either centres the shrunken Column as a block, but a label wrapping to two lines then depends on the Column's own width again. It also adds a layer, or moves the check mark's reference point (`alignment` affects only non-positioned children, but it reads as if it moved the badge's anchor), for no gain over letting the Column fill the tile. Also rejected: moving the check mark out of the Stack into a tile-level overlay so that the Column can sit directly in the Padding. That restructures the tile's hit area and its semantics tree, which existing tests pin, to fix a one-line constraint problem.
- **Reversal cost:** low. One argument on one widget, guarded by a widget test.

### D2: Prove centring with a geometry widget test

- **Choice:** a widget test pumps `MarkerPreferencesGrid` with the `locks` and `stationaryWeapons` keys. It finds each tile by `ValueKey('marker-tile-<key>')` and compares `tester.getCenter(...).dx` of the tile, its badge `CustomPaint` and its label `Text`, within a small tolerance. It runs once at the default scale and once at a larger `scale`. A one-line label at scale 1 fails today, so the test is red first.
- **Rejected:** a golden image test. A golden pins font rendering and colour as well as layout, so it breaks on unrelated theme or font changes, and the repo's tile tests already assert geometry and paint directly instead of through goldens.
- **Reversal cost:** low.
