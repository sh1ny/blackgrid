# Review

## Metadata

- **Round:** 2 (re-check of Required Changes)
- **Prior round:** Round 2 first run: APPROVE_WITH_CHANGES, CHANGES_APPLIED: no. No Critical; one Moderate (M1: the bottom sheet half of the amended `interface-theme` requirement had no scenario and no test map row, and "each with 12px corners" contradicted D8 and the theme, which round a sheet's top corners only); four Suggestions (S1 to S4, on D11's reasoning and DESIGN.md); three Required Changes.
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:** Only the three Required Changes, in `openspec/changes/restyle-dialogs/specs/interface-theme/spec.md` (requirement "Dialogs, sheets and the startup screen in Ember") and `openspec/changes/restyle-dialogs/tasks.md` (test map, task 4.3), read in the working tree and through `git diff HEAD -- openspec/changes/restyle-dialogs/`, with `review.md` as the list to check against. `openspec validate restyle-dialogs --strict` passes ("Change 'restyle-dialogs' is valid"). The Suggestions, design.md, the other delta specs and the uncommitted `lib/` and `test/` edits were not re-reviewed.
- **Skills loaded:** none named in the request.

## Findings

### Critical (blocking)

None.

### Moderate

None open. M1 is resolved:

- The requirement now has the scenario "Marker list sheet" (spec.md:16-18): when the marker list sheet opens on the Map, its surface is the panel colour with 12px top corners and its title is in the Literata Title role. It covers all three clauses the sheet half of the requirement states (surface, corners, title role).
- The requirement sentence (spec.md:6) now reads "a dialog with 12px corners and a sheet with 12px top corners", which matches D8 and `bottomSheetTheme`. The Stats scenario still says "12px corners" for the dialog, so the two agree.
- tasks.md:68 adds the test map row `interface-theme → Dialogs, sheets and the startup screen in Ember | Marker list sheet | test/ui/ember_surfaces_test.dart | interface-theme: Marker list sheet | red`. Task 4.3 (tasks.md:107) now says "Write the failing Map help closes and Marker list sheet tests" first and "Verify both rows turn green".

Nothing the edits touch was broken: the requirement keeps one `SHALL` sentence per obligation and five well-formed scenarios, every `interface-theme` scenario has exactly one test map row, the new row follows the `<capability>: <Scenario>` naming rule, and the proposal line and D11 are unchanged by these edits and still agree with the spec.

### Suggestions

- The new scenario is looser than the round 2 example in two places: it names no room ("the panel colour" rather than "the dark panel colour") and does not quote the title text. Neither was required (the example was offered as "for example"), and the requirement's "the theme's colours in both rooms" still binds. The test for the row should pin one room, or both as task 4.1 does for the dialogs, so that the surface assertion is concrete.
- S1 to S4 of the round 2 review are still open as suggestions; none was required.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. "Marker list sheet" scenario in `specs/interface-theme/spec.md` (panel surface, 12px top corners, title in the Literata Title role): satisfied.
2. "each with 12px corners" replaced with 12px corners for a dialog and 12px top corners for a sheet: satisfied.
3. Test map row for the scenario in `tasks.md`, named in task 4.3 as a failing test to write first and turn green: satisfied.

CHANGES_APPLIED: yes

## Rebuttals
