# Review

## Metadata

- **Round:** 1
- **Prior round:** none (this run re-checks only Required Changes 1-3 of this round's APPROVE_WITH_CHANGES)
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:** openspec/changes/retire-tracker-token/proposal.md, design.md, all delta specs (legacy-import, local-data-durability, local-progress, manual-progress, player-facing-text, progress-authority, quest-checklist, raid-timers, scan-frame-recording, scanner-evidence, settings-diagnostics, settings-page, task-catalog, verdict-presentation, workspace-shell) against openspec/specs/<capability>/spec.md; openspec/roadmap.md (M9); AGENTS.md; docs/adr/0007, 0031, 0040, 0041, 0043, 0044; source: lib/domain/decision_engine.dart, decision.dart, progress.dart, inspection_context.dart, raid_timers.dart, catalog.dart, settings.dart; lib/application/selection_controller.dart, raid_timers_controller.dart, app_services.dart, catalog_controller.dart, local_progress_access.dart, task_log_progress_controller.dart, manual_progress_controller.dart, map_session_controller.dart; lib/data/credential_store.dart, local_paths.dart, legacy_import.dart; lib/ui/shell.dart, evidence_panels.dart, settings/local_progress_settings.dart; windows/runner/credential_protector.cpp, flutter_window.cpp, CMakeLists.txt; packages/blackgrid_progress/lib/src/player_progress.dart, task_rules.dart, edition_rules.dart, edition_table.dart. Re-check run: review.md Rebuttals, proposal.md, design.md and the specs/ deltas, re-read from disk; `openspec validate retire-tracker-token` reports the change valid. Skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis, flutter-add-widget-test.

## Findings

### Critical (blocking)

None.

### Moderate

**M1. D3's task mapping contradicts the in-force ADR-0043 rules it claims to follow, for started tasks, restartable failed tasks and level-1 minimums.**
S2 and D3 justify the unset semantics "as the availability rules do (ADR-0043)", but D3 only reuses the "unset = not started" half. ADR-0043 and `packages/blackgrid_progress/lib/src/task_rules.dart:33-52` also say:
- a **started** task is available "without gate reasons";
- a **failed** task is done only when it is not restartable (`state == failed && task.restartable != true`). A restartable failed task is evaluated as not started;
- a minimum level of 1 or less needs no recorded level (`minimum > 1`).

D3 instead says "failed means satisfied" and "otherwise the need continues as not started". That sends started tasks through `_gate` (`decision_engine.dart:298-379`) unchanged, where any `minPlayerLevel != null` with an unset level makes the gate unknown. This has concrete consequences on the main path the release notes recommend, a log replay:
- Logs record task states but no player level, so after a replay every started task's item need is `unresolved`. The verdict is Check for exactly the items the player needs now.
- When log gaps leave a prerequisite unrecorded (ADR-0044 names log deletion and the push-log gap), a recorded *started* task falls into the complete-only-prerequisite rule and reads "needed later".
- A restartable task that failed reads "task failed; no active obligation" (satisfied). The player may then sell an item they still need when they restart the task.

*Re-check: resolved.* See RC1 below.

**M2. The token clean-up misses the app's own encrypted temp files, so the folder and ciphertext can stay for good.**
`DpapiCredentialStore.writeCredential` writes ciphertext to `<mode>.dpapi.<pid>.<microseconds>.tmp` before `atomicReplace` (`lib/data/credential_store.dart:101-105`). D6 deleted only the three named files, so a crash leftover kept encrypted token data and the folder. That is the outcome S4 rejects.

*Re-check: resolved.* See RC2 below.

**M3. Main specs keep Tracker wording after archive: Purpose texts and renamed-in-place scenario titles.**
The `progress-authority` Purpose and its "assume the Tracker integration is enabled" preamble, the `raid-timers` and `local-progress` Purposes, and four Tracker-titled scenarios in MODIFIED requirements would all have survived archive.

*Re-check: resolved.* See RC3 below.

### Suggestions

- **S-a. D4 (edition gates always unknown) ignores ADR-0043's reviewed edition table.** The owner declined this suggestion and kept D4 (Rebuttals). Closed.
- **S-b. The "Unknown mode" scenario was not assertable as written.** Taken: its THEN now says the decision's open inputs include progress.
- **S-c. State faction case-normalisation and scav bonus key splitting.** Taken (design D3).
- **S-d. Loading versus unavailable wording.** Taken: the design records the "Progress unavailable" verdict reason while loading.
- **S-e. `AppServices` construction order.** Taken: the design's Context now covers composition order, and `open()` does not wait for the first read.
- **S-f. Docs.** Taken: README, THIRD_PARTY_NOTICES, STRATEGY and architecture.md are all in scope.
- **S-g (new, non-blocking).** The progress-authority scenario "Level unset" still says "a task with a minimum level". Under the updated requirement, a minimum of 1 does not make the need unresolved, so that scenario's fixture needs a minimum above 1. Consider saying "a minimum level above 1" so the scenario cannot be read as conflicting with "Level 1 minimum with no level".

## Re-check of Required Changes

- **RC1: applied.**
  - Design D3 now follows the ADR-0043 order. Started tasks skip `_gate` and are needed now (`task_rules.dart:45-50`). Failed tasks are satisfied unless `progressCatalog` marks them `restartable == true`, in which case they continue as not started. A level minimum of 1 or less passes with the level unset. The S2 and D3 summary rows are updated, and the D3 entry records that the owner agreed on 2026-11-19, as a `Chosen by: user` change requires.
  - The progress-authority requirement text matches, and it adds the scenarios "Started task skips its gates", "Started task with an unrecorded prerequisite", "Restartable failed task", "Non-restartable failed task" and "Level 1 minimum with no level". Each THEN can be asserted in an engine unit test.
  - On the open point, I accept that unknown `restartable` counts as not restartable, so the failed task is done. That is ADR-0043's own `restartable != true` rule (`task_rules.dart:38`). Advice and the availability rules now agree, which was the point of M1. My original Required Change left that choice to the user.
- **RC2: applied.** D6 and the local-data-durability requirement now also delete `<mode>.dpapi.*.tmp` for the three modes before the empty-folder delete. The design cites the source naming (`credential_store.dart:101-105`). The scenario "Temporary token file left by a crash" covers it, and "Unexpected file in the folder" still keeps foreign files.
- **RC3: applied.**
  - The design's ADRs section plans in-place Purpose rewrites of `progress-authority` (preamble dropped), `raid-timers` and `local-progress` during the docs task.
  - The four Tracker-titled requirements are now REMOVED and re-ADDED under new names, with new scenario titles:
    - settings-diagnostics: "Local progress error stays reachable" and "Local progress unavailable";
    - settings-page: "Status bar Progress";
    - scan-frame-recording: "Recording with local progress recorded".
  - Each REMOVED entry has a Reason and Migration. The proposal's Capabilities lines describe the replacements. `openspec validate` passes.
  - The remaining "Tracker" mentions in the deltas are legitimate: they are negative assertions (no text contains Tracker) or the legacy `TrackerProgressEnabled` key, which the import must name.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (M1) Align D3 with ADR-0043 for started tasks, restartable failed tasks and level-1 minimums, with matching progress-authority scenarios and updated S2/D3 rows. Applied.
2. (M2) Delete `{pvp,pve,seasonal}.dpapi.*.tmp` before the empty-folder delete, with a scenario. Applied.
3. (M3) Plan the Purpose rewrites, retitle the four Tracker-named scenarios, and fix the proposal's description. Applied.

CHANGES_APPLIED: yes

## Rebuttals

- **M1 / RC1: fixed.** The owner agreed to align with ADR-0043 on 2026-11-19 (the change touched S2 and D3, which they had chosen). Design D3 now has: a started task skips `_gate` and is needed now; a failed task is satisfied unless `progressCatalog` marks it `restartable == true`, in which case it is treated as not started; a level minimum of 1 or less passes with the level unset. The S2 and D3 entries and summary rows are updated, and proposal S2 too. progress-authority gained the scenarios "Started task skips its gates", "Started task with an unrecorded prerequisite", "Restartable failed task", "Non-restartable failed task" and "Level 1 minimum with no level". Unknown `restartable` (no progress catalog, or a null fact) counts as not restartable, so the failed task is done. That is ADR-0043's own rule (`task_rules.dart:38`, `restartable != true`), and keeping advice consistent with the availability rules is the point of RC1. The owner kept D4 (edition gates always unknown) when offered the edition-table suggestion. **Accepted by reviewer.**
- **M2 / RC2: fixed.** D6 and the local-data-durability requirement now also delete `<mode>.dpapi.*.tmp` for the three modes before the empty-folder delete. Added scenario: "Temporary token file left by a crash". "Unexpected file in the folder" is kept. **Accepted by reviewer.**
- **M3 / RC3: fixed.** The design's ADRs section now plans in-place Purpose rewrites for progress-authority (preamble dropped), raid-timers and local-progress during the docs task. Archive refuses to drop scenario titles from a MODIFIED block (`openspec validate` error), so each of the four affected requirements is now REMOVED and re-ADDED under a new name, with the retitled scenarios: settings-diagnostics "Problems the player must act on stay reachable from the main windows" ("Local progress error stays reachable") and "Diagnostics shows item data and progress source detail" ("Local progress unavailable"); settings-page "Settings opens at the section a link names" ("Status bar Progress"); scan-frame-recording "Recordings stay local and carry no credentials or progress" ("Recording with local progress recorded"). The proposal's Capabilities lines describe these replacements. **Accepted by reviewer.**
- **Suggestions taken:** the "Unknown mode" THEN now says "the decision's open inputs include progress". The design now covers faction upper-casing, scav bonus key splitting, `AppServices` composition order with no wait on the first read, the "Progress unavailable" verdict reason while loading, and the docs list (README, THIRD_PARTY_NOTICES, STRATEGY). The edition-table suggestion was declined by the owner (D4 kept).
