# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed:** openspec/changes/polish-map-rail/proposal.md, openspec/changes/polish-map-rail/specs/map-rail/spec.md, openspec/changes/polish-map-rail/design.md, openspec/roadmap.md (M4.5, change 1 and exit criterion 1), openspec/architecture.md (in-force ADR table), docs/adr/0002-sdk-notifiers-and-composition-root.md, openspec/specs/latest-accepted-scan/spec.md, lib/ui/map_screen.dart, lib/ui/theme.dart, lib/ui/shell.dart, test/ui/map_screen_test.dart, test/ui/latest_scan_card_test.dart, test/widget_test.dart, test/ui/scanner_screen_test.dart, test/support/map_widget_harness.dart, pubspec.yaml (dependencies). Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, flutter-add-widget-test; AGENTS.md "Dart and Flutter code".

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

The design holds up. D1 is right: the `PageStorage` identifier for the rail differs between the wide path (`map` → `map-rail-scroll`) and the compact path (`map` → `map-compact-scroll` → `map-rail-scroll`), so `ExpansionTile` with a `PageStorageKey` would lose the flag across the 1100 px breakpoint. A `bool` in `MapScreen`'s `State` above the `LayoutBuilder` survives both the `IndexedStack` tab switch (`lib/ui/shell.dart:161-171`) and the layout change. D3 uses the timer lifecycle that already exists (`lib/ui/map_screen.dart:27-63`), so no new timer code is needed. The design fits ADR-0002, which keeps UI-only state in widget `State`. The `latest-accepted-scan` "No separate panel" scenario and the `Active map` assertions in `test/widget_test.dart:19-23`, `test/ui/scanner_screen_test.dart:42-47` and `test/ui/latest_scan_card_test.dart:137` still hold, and the decision card moves up the rail, which only makes it easier to reach. The findings below are all about tests that would prove nothing, or THENs that cannot be asserted.

### Critical (blocking)

None.

### Moderate

**M1. Once the section moves to the bottom of a lazy `ListView`, it is not built at all, so the "collapsed" and "no timer" tests would pass without the feature.**
The rail is a lazy `ListView` (`lib/ui/map_screen.dart:340`). After D4, the fixed-height sections above Map saved-file inputs take 145 + 12 + 300 + 12 + 430 + 12 + 650 = 1561 px (at scale 1). The default harness window is 1912×823 (`test/support/map_widget_harness.dart:213`), so the rail's viewport plus its default 250 px cache extent ends far above the section, and the section's element is never built until the rail is scrolled. Two consequences follow:
- These checks would pass vacuously on today's code with only the reorder applied, so they would not prove the requirement: no `Logs:`/`Screenshots:` line, no Follow logs switch, no Read Latest button (scenario "Collapsed on first show"), and no age timer (scenario "No ticking while collapsed"). The same lazy build also means the scenario's positive THEN ("the 'Map saved-file inputs' title is shown") fails unless the test scrolls first.
- The existing tests at `test/ui/map_screen_test.dart:50-51`, `:88` and `:223-224` call `tester.ensureVisible(find.text(...))`. That throws when the finder matches nothing, which it will, because the widget was never built. The design's "one shared test helper" that expands the section must first scroll the rail with `scrollUntilVisible` on the `map-rail-scroll` `Scrollable`, as the marker-search test already does (`:130-139`). Only then can it tap the header.

The design's Risks section names the helper but not the scroll. The new tests for collapse and timers must bring the section into view, and assert that its header is found, before they assert that content is absent.

**M2. The scenario "Age resumes on expand" says the age "advances as time passes", and no allowed test can prove that.**
The age comes from `DateTime.now()` (`lib/ui/map_screen.dart:76-78`). `testWidgets` fakes timers but not `DateTime.now()`, and the repo has no `package:clock` (pubspec.yaml). `tester.pump(const Duration(seconds: 1))` fires the periodic timer but leaves the wall-clock age unchanged. A test could only see the number advance by waiting in real time, and AGENTS.md bans arbitrary sleeps. D3 also rules out new timer code, so injecting a clock is out of scope. As written, the THEN is either untested or tested with a banned sleep. Reword the THEN to something a fake-time test can assert, such as the age line being shown and the status content mounted. Required Change 2 gives the wording.

**M3. The scenario "No ticking while collapsed" asserts a private timer that no test can observe.**
The THEN says "no periodic timer for the saved-file age is pending". `flutter_test` has no public API for pending periodic timers in the middle of a test. Its periodic-timer check runs only after the tree is disposed, at the end of the test. The timer is a private field of the private `_MapInputStatusState`. Under D3, the guarantee is structural: the timer exists only while the status widget is mounted. State the THEN in those observable terms: the status content is not in the tree. Required Change 3 gives the wording, and the call site can key the status widget so a test can find it.

### Suggestions

**S1. Pass the toggle key through the header, not the panel.** D2 lists the constructor as `title, icon, expanded, onExpandedChanged, child`, yet says the header `InkWell` is "keyed `Key('map-inputs-toggle')` at the call site". With that constructor, a call-site key can only sit on the whole `CollapsibleGridPanel`. Once the panel is expanded, `tester.tap(find.byKey(...))` hits the centre of the expanded panel, which can land on the Follow logs `SwitchListTile` or a status line instead of the header. The "Collapsing keeps settings" test would then either flip Follow logs or fail to collapse. Add a `toggleKey` (or `headerKey`) parameter that is applied to the `InkWell`, or have tests tap `find.text('Map saved-file inputs')`.

**S2.** `CollapsibleGridPanel` is a new public class in `lib/ui/theme.dart`. Give it a `///` summary and document `expanded` as a "Whether" property, following dart-write-documentation. `GridPanel` has no doc comment, so the file sets no example to copy.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. design.md, "Risks / Trade-offs", first bullet: say that the shared test helper first scrolls the rail (`scrollUntilVisible` on the `Scrollable` under `PageStorageKey('map-rail-scroll')`) until the "Map saved-file inputs" header is built, and then taps it. Add that every collapsed-state assertion first brings the header into view and asserts that it is found, so that absence checks are not vacuous (M1).
2. specs/map-rail/spec.md, scenario "Age resumes on expand": replace the THEN with "the 'Saved evidence age' line is shown with the age at the time of expansion, and the saved-file status stays mounted while the section is expanded, so its once-a-second refresh runs as before" (M2). Do not require a test to watch the number advance.
3. specs/map-rail/spec.md, scenario "No ticking while collapsed": replace the THEN with "the saved-file status content is not in the widget tree, so nothing refreshes the saved-file age" (M3). In design.md D3, say that the call site gives `_MapInputStatus` a key (for example `Key('map-input-status')`) that tests use to assert it is absent when collapsed and present when expanded.

CHANGES_APPLIED: yes

## Rebuttals

Author, after round 1:

- Required change 1 (M1): fixed. design.md Risks / Trade-offs, first bullet: the shared helper scrolls the rail with `scrollUntilVisible` on the `map-rail-scroll` `Scrollable` until the header is built, then taps `Key('map-inputs-toggle')`. Collapsed-state assertions first find the header.
- Required change 2 (M2): fixed. The THEN of spec scenario "Age resumes on expand" now uses the given wording.
- Required change 3 (M3): fixed. The THEN of spec scenario "No ticking while collapsed" now uses the given wording, and D3 keys `_MapInputStatus` with `Key('map-input-status')`.
- S1: applied. D2 adds an optional `toggleKey` on the header `InkWell`, and the call site passes `Key('map-inputs-toggle')`.
- S2: applied. D2 requires `///` docs on `CollapsibleGridPanel` and its parameters.

Reviewer re-check (2026-10-20):

- Required change 1 (M1): applied. design.md "Risks / Trade-offs", first bullet, says the shared helper scrolls the `map-rail-scroll` `Scrollable` with `scrollUntilVisible` until the header is built, taps `Key('map-inputs-toggle')`, and that every collapsed-state assertion first finds the header.
- Required change 2 (M2): applied. In specs/map-rail/spec.md, the THEN of "Age resumes on expand" now uses the given wording, and no scenario still needs real time to pass.
- Required change 3 (M3): applied. In specs/map-rail/spec.md, the THEN of "No ticking while collapsed" now says the status content is not in the widget tree. design.md D3 keys `_MapInputStatus` with `Key('map-input-status')` and explains why the test asserts absence.
- S1: applied. design.md D2 adds an optional `toggleKey` on the header `InkWell`, and the call site passes `Key('map-inputs-toggle')`.
- S2: applied. design.md D2 requires `///` docs on `CollapsibleGridPanel` and its parameters.
- I re-checked only these items. M1-M3 are resolved, and no finding is open.
