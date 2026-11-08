# Offline validation for add-answer-strip

Validation was run on Windows with the Flutter version pinned by `mise.toml`.
No application or game was launched. Live-game visual judgment remains for the
owner at milestone close.

## Integration checks

- `dart format` through `mise exec` on the changed Dart files; a final
  `dart format --output=none --set-exit-if-changed` checked 38 changed Dart
  files and reported zero changes.
- `mise run analyze`: no issues.
- `mise run test`: 2,802 passed, with qualification tests excluded by the
  task's normal configuration.
- `mise exec -- flutter test test/ui/theme_source_test.dart`: two passed;
  this source check rejects colour literals in `lib/ui` outside Ember roles.
- Scenario mapping audit: all 40 delta-spec scenarios appear exactly once in
  the test map, all 40 rows are green, and each named test string occurs in
  the specified test file. The full offline suite above ran these files.
- `mise run release-notes -- --check openspec/changes/add-answer-strip/proposal.md`:
  passed, three Changed entries in the final consolidated notes.
- `openspec validate add-answer-strip --strict`: passed.
- `git diff --check`: passed.

## Covered behavior and boundaries

Offline widget fixtures exercise both Ember rooms at the planned sizes and
text scales; inspector docking and overlay at 1080/1081 pixels; retained map
pan, zoom, and detail expansion; Escape, focus return, and reduced motion;
history verdict labels and unknown/mode-mismatch fallbacks; image lease bounds;
Settings section targeting, hotkey states, recording counters and failure;
timer visibility; map controls; and Scanner evidence frame/internal scrolling.
Additional focused coverage checks history rows at the 352px inspector width
and text scale 2, one shared FIR selector across both workspaces, and the
correction offer for selected and empty states at 960×720 and text scale 2.

The first full offline run exposed 34 failures after the workspace move. The
correction offer, history-write failure and retired-scan guidance were hidden by
the closed inspector, and FIR controls were duplicated. The shared strip now
exposes the correction controls, source and error status, and a single FIR
selector. Legacy widget assertions were retargeted to the shared strip or the
actual inspector, preserving history isolation, selection, correction, scan
fencing, rail-order and Settings behaviors. The new enlarged-text correction
test reproduced a 37px overflow before bounding its internal scroll area.

Initial red evidence for some group 2 and 3 test cases had limits: seven
Settings cases were added after relocation and reverse-checked by temporarily
removing and restoring the panel; some initially failing rail-order tests had
fixture errors and later strengthened assertions are passing evidence only.
The original group commit messages record those distinctions.

Impeccable's native audit guidance was applied as a source and offline-widget
check of focus, semantics, motion, layout and theme roles. Its web-only
mechanical detector was not run or claimed as Flutter coverage. No rendered
app inspection, live-game test, platform performance measurement, complete
screen-reader audit, or live contrast measurement is claimed here.
