# Review

## Metadata

- **Round:** 4
- **Prior round:** Round 3 APPROVE: no Critical or Moderate findings, suggestions S-a to S-e. This round re-reviews the apply-time spec amendment in commit 12b9ffd ("amend specs").
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:**
  - The change: openspec/changes/restyle-scanner-workspace/proposal.md, design.md, tasks.md, review.md (round 3) and every delta under specs/ (scanner-workspace, workspace-shell, verdict-presentation, scanner-evidence, catalog-authority, player-facing-text, item-icons, scan-decisions, scan-correction, latest-accepted-scan, settings-diagnostics, settings-page).
  - The amendment: `git show 12b9ffd`. It changes one line, the WHEN of the scenario "Narrow window stacks the sections" in specs/scanner-workspace/spec.md, from "960 by 720 logical pixels with an item selected" to "1100 by 720 logical pixels with the inspector docked open and an item selected, so the main column is under 720 logical pixels wide". The commit touches no other file.
  - Source at the branch: lib/ui/shell.dart `initState`-time inspector default (`:92-97`, open when width > 1080), `_main()` (`:394-450`: overlay when width <= 1080, `panelWidth` 352 clamped, main padding `fromLTRB(14, 14, inspectorOpen && !overlay ? panelWidth + 28 : 14, 14)`), and the column chain above it (`SafeArea` > `Column` > `Expanded` > `Stack` > `Positioned.fill`, no other horizontal inset).
  - Context only, from the work tree (apply in progress): lib/ui/scanner_screen.dart (`sideBySideColumnWidth = 720`, `LayoutBuilder` on the outer constraints, `EmberSpace.lg` padding inside) and test/ui/scanner_workspace_test.dart (the narrow scenario test and the "Side by side from 720 pixels of column" boundary test).
  - Project rules: AGENTS.md "Dart and Flutter code".
  - Skills loaded: none were named in the request.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Amendment check

- **The old scenario contradicted its own requirement; the new one agrees with it.**
  - The requirement (unchanged) and design D1 key the layout on the main column's width: side by side at 720 logical pixels or more, stacked below.
  - At 960 by 720, `_main()` treats the inspector as an overlay (960 <= 1080), so the main column's right padding is 14 and the column is 960 - 14 - 14 = 932 wide. The 720 rule therefore puts Why beside Prices, and the old scenario's "stacked" outcome could not hold without breaking the requirement or D1. The amendment fixes a real contradiction.
  - At 1100 by 720, the inspector opens docked by default (1100 > 1080, `shell.dart:94`), and the right padding is 352 + 28 = 380, so the column is 1100 - 14 - 380 = 706 wide, under 720. The new scenario's "stacked" outcome follows from the rule. The commit message's 932 and 706 figures match the code.
  - The WHEN now states the precondition ("inspector docked open", "so the main column is under 720 logical pixels wide"), so the scenario stays honest if the shell's padding or panel width later change: a test can assert the precondition, and the work-tree test does (`expect(column.width, lessThan(720))`).
- **Classification.** This is a clarification of the scenario's setup, not a behaviour change: the normative 720px rule and D1 are untouched, and no other requirement or scenario depended on stacking at 960.
- **Other scenarios that use narrow windows still hold under the 720 rule.**
  - scanner-evidence "Narrow window" (900 wide): overlay, column 872, Why beside Prices; its THEN only requires Scan evidence to come after the strip, Why and Prices, which holds in either layout.
  - scanner-evidence "Short desktop window" (1100 by 720): stacked, scrolls as one; consistent.
  - workspace-shell "Answer first in both areas" (960 by 720) and verdict-presentation "A long reason at the narrowest card" (960px) concern the strip, not the sections; unaffected.
- **AGENTS.md.** The scenario stays provable at the widget layer at a fixed window size; it needs no sleeps, fixtures or qualification tag.

### Critical (blocking)

None.

### Moderate

None.

### Suggestions

- **S-a. tasks.md 3.1 still names the old geometry.** It reads "wide 1660×870 and narrow 960×720 geometry". The amended scenario (and the test already written for it) uses 1100×720 with the inspector docked. Change "narrow 960×720" to "narrow 1100×720 with the inspector docked" when 3.1 is ticked, so the task record matches the spec. tasks.md is outside the verdict's scope, so this does not void anything.
- **S-b. Round 3 suggestions still open.** Round 3's S-b (the design's T3 tables and the "Inspector closed at narrow width: … no timer runs" line still describe only the list-owned tick, while D12 also mounts the tick in the strip), S-c (D3 does not place the strip's close-history and "Back to latest scan" actions) and S-d (D12 does not record its departures from the B view's provenance strings) are not reflected in design.md yet. They remain non-blocking; fold them in the next time design.md is touched. Round 3's S-a (the "Unknown found-in-raid state" scenario body) and S-e (X14 row tags) are likewise still pending their planned task edits.

## Verdict

VERDICT: APPROVE

## Required Changes

<!-- APPROVE_WITH_CHANGES only: numbered exact edits. -->

CHANGES_APPLIED: n/a

## Rebuttals
