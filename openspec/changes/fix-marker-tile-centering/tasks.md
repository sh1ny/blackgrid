# Tasks

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| marker-preferences → Each applicable category is one icon tile | One-line and two-line labels are centred | test/ui/marker_preferences_test.dart | tile badge and label are centred whatever the label's length | green |
| marker-preferences → Each applicable category is one icon tile | Centred at a larger tile scale | test/ui/marker_preferences_test.dart | tile badge and label stay centred at a larger scale | green |
| marker-preferences → Each applicable category is one icon tile | Tiles for the current map | test/ui/marker_preferences_test.dart | shows one labelled tile per saveable map key plus Saved pins | green |
| marker-preferences → Each applicable category is one icon tile | Tiles are the same size | test/ui/marker_preferences_test.dart | every tile has the same size whatever its label | green |
| marker-preferences → Each applicable category is one icon tile | Unsaveable category gets no tile | test/ui/map_screen_test.dart | unsaveable marker key gets no tile and stays drawn | green |
| marker-preferences → Each applicable category is one icon tile | Map with no markers | test/ui/marker_preferences_test.dart | map without markers shows only the Saved pins tile | green |

## 1. Centre each tile's badge and label

- [x] 1.1 Add the widget tests "tile badge and label are centred whatever the label's length" (keys `locks` and `stationaryWeapons`, scale 1) and "tile badge and label stay centred at a larger scale" (key `locks`, scale 1.5) to `test/ui/marker_preferences_test.dart`. Each compares the horizontal centre of the tile (`ValueKey('marker-tile-<key>')`), its badge `CustomPaint` and its label `Text`, within 0.5 logical pixels. Verify with `mise exec -- flutter test test/ui/marker_preferences_test.dart` that the "Locks" checks fail because the badge and label sit left of the tile centre.
- [x] 1.2 Set `fit: StackFit.expand` on the tile's `Stack` in `_MarkerTile.build` (`lib/ui/marker_preferences.dart`). Verify that both new tests pass and flip their rows green, and that every other test in `test/ui/marker_preferences_test.dart` still passes, including the check mark test "shown tile has a check mark and hidden tile is dimmed".
- [x] 1.3 Re-run the unchanged scenarios' tests: `mise exec -- flutter test test/ui/marker_preferences_test.dart test/ui/map_screen_test.dart`. Verify that the four green rows still pass.

## 2. Verify

- [x] 2.1 Run `mise exec -- dart format lib/ui/marker_preferences.dart test/ui/marker_preferences_test.dart`, `mise run analyze` and `mise run test`. Verify that formatting leaves no diff, analysis reports no issues and every test passes.

## Workflow follow-up

- The user re-checks the Marker preferences look in the running app (M4.5 user-verified check). Agents do not perform it.
