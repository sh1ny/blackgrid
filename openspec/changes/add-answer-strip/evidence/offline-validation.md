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

## Pre-ship fix round 1

The fresh source review found four gaps beyond the initial passing suite.
Regression tests reproduced each before the fixes: the actual history-file
importer excluded `Verdict`; a closed inspector remained focusable; selected
item plus docked details caused Scanner page scrolling at 1100×720; and the
recording-stop warning was not visible at 900/960px after Settings closed.

The importer now accepts optional named `Verdict` values, the closed focus
scope disables descendant traversal, desktop Scanner keeps its evidence
height fitted when narrowed by the inspector, and recording warnings precede
compact evidence. Reduced-motion animation completion is deferred safely.
The affected four-suite run passed 116 tests. The coordinator independently
ran `mise run analyze` and `mise run test`: no findings and 2,808 passed.

## Owner build-review corrections

All seven new mapped scenarios were red-confirmed before their initial fixes.
Later checks strengthened coverage: popup keyboard scrolling and mode-change
dismissal each failed before fixes; the 50-option cap/refine hint was verified
after implementation, not independently red-confirmed. Typing and Escape leave
selection and database history unchanged; a real result click records one pick.
Keyboard option visibility is checked at 1x and 2x in both rooms.

Additional regressions reproduced the centered status bar (x=309), a narrow
three-row strip, and an enlarged-text Requirements heading overflow. The status
bar now starts at x=0 with its first item at x=20, narrow fitting content uses
two rows, and Optional uses wraps within the inspector. The expanded-inspector
test initially dragged its nested history list; driving the outer inspector
position exposed the actual 162px heading overflow, which was then fixed.

The first full run had 2,811 passing and 15 failing tests. These failures were
legacy assertions searching globally for text now also visible in the initially
open inspector, obsolete Scanner placement, and the relocated search surface.
Assertions now target the answer strip, Map rail, top popup or Settings panel;
the Map width ratio is measured within the remaining workspace. Behavior
coverage was retained. Escape closes a focused docked inspector and returns
focus to its toggle, while Escape in search preserves the docked inspector.

Final coordinator checks: pinned `mise run analyze` reports no issues;
`mise run test` passes all 2,828 fast offline tests. All 47 delta scenarios map
once to named tests in their declared files. Release-note validation passes
with five Changed entries, strict OpenSpec validation passes, and the diff is
whitespace-clean. A fresh pre-ship review follows the group commit.

Synthetic widget fixtures were rendered and inspected at wide and 960px widths.
Final dark Scanner renders loaded Geist, Literata and MaterialIcons and show
right-aligned tools, available price/freshness, history first on wide windows,
and left-aligned status. Earlier light Map/Scanner renders were inspected for
geometry and typography with MaterialIcons missing; they do not prove icon
fidelity. Temporary render tests were removed. The fixtures use synthetic items,
not Physical Bitcoin or live prices. The other Claude session reported checking
the earlier Release build with Tarkov absent; that is its reported result, not
agent verification of this final build. No app or game was launched here;
live-game, final Release-build visuals and owner milestone judgment remain
unverified.

Pre-ship F1 regression: `inspector expansion survives closing and switching
areas` failed because Scanner detail content disappeared after reopening;
`map optional uses survive inspector close and area switch` failed because the
Map header returned collapsed; `optional uses survive unmount and reset on
hidden selection change` failed because the remounted panel lost its open
state. The latter two red runs temporarily disconnected the retained state to
reproduce the original local ownership. All three pass with the fix. The full
`requirement_panel_test.dart` suite passes (6 tests), and the focused shell
runs pass. Hidden selection changes reset Optional uses even when the user
returns to the earlier item. No app or game was launched.

The coordinator independently ran pinned analysis and the complete fast suite:
no issues and 2,831 passed. An intermediate full run exposed the inspector test
helper's old assumption that history is always last; preserving expansion made
the first Scanner history panel leave the lazy cache when scrolled to the bottom.
The helper now navigates to each area's actual history position and expands a
section only when needed. Its original failing scanner regression passes, and
the final complete run above includes the corrected helper.
