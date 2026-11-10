# Review

## Metadata

- **Round:** 1 (re-check of Required Changes)
- **Prior round:** Round 1 first run: APPROVE_WITH_CHANGES, CHANGES_APPLIED: no. One Critical (C1: the offstage Map keeps keyboard focus under Settings, so Escape and N/Enter/Delete act on the hidden map), three Moderate (M1: Escape drops a valid typed edit; M2: how an item pick closes Settings was unspecified, so a live scan could close it; M3: the map-refresh disabled rule contradicted "same enabled and disabled rules"), two Suggestions (re-targeting the same section; InheritedWidget opener with no caller outside the shell), six Required Changes.
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:** Only the six Required Changes and the two Suggestions, in openspec/changes/restyle-dialogs/design.md (D1, D3, D4, decision summary rows D1/D3/D4, T1 and T3 diagrams, Flow & State Gaps, Risks) and specs/settings-page/spec.md (requirements "Settings opens as a page" and "Item and map data section"). `openspec validate restyle-dialogs --strict` passes.

## Findings

### Critical (blocking)

None open. C1 is resolved: D1 now wraps the areas and the inspector in `ExcludeFocus(excluding: settingsOpen)`. It cites `Offstage` focus behaviour and `map_workspace.dart:401`. Opening Settings moves focus to the target section or the page title, and closing returns focus to the shell's root `Focus`. Flow & State Gaps has the "Map had keyboard focus when Settings opened" entry. The spec scenario "Map keys while Settings is open" covers N, Enter, Delete and Escape.

### Moderate

None open.
- M1 is resolved. D3 now routes every close path (Back, Escape, area choice, item pick) through one shell method. That method has each commit field with pending text call `onCommit` through `SettingsFlushScope` before it clears `_settings`, and it cites `settings_dialog.dart:663`, `:672`. The T3 diagram shows the flush before the unmount. The Risks rows now match, and the spec has the scenario "Escape with a valid edit".
- M2 is resolved. D4 adds `TopItemSearch.onPicked`, called after `selectManual`, and states that only that callback closes Settings and that a live scan never does. The T1 diagram shows it, Flow & State Gaps has the scan-while-open entry, and the spec has "Scan while Settings is open".
- M3 is resolved. The section requirement now disables Refresh map data "while no map data is available", and the "No map data available" scenario covers it.

### Suggestions

Both were adopted in D4. The private `_openSettings` carries an increasing request number, so asking again for the section already targeted still scrolls to it. The InheritedWidget opener was dropped, and its rejection is recorded.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. D1 focus exclusion and focus moving into the page, with Flow & State Gaps entry: satisfied.
2. Spec scenario "Map keys while Settings is open": satisfied.
3. D3 flush before unmount, with T3 and Risks updated: satisfied.
4. Spec scenario "Escape with a valid edit": satisfied.
5. `TopItemSearch.onPicked` as the only pick-close path, the scan-while-open gap, and spec scenario "Scan while Settings is open": satisfied.
6. Refresh map data disabled while no map data is available, with a scenario: satisfied.

CHANGES_APPLIED: yes

## Rebuttals
