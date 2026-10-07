# Review

Architecture baseline review for the Specwright adoption (specwright-roadmap init, step 5), focused on how faithfully the documents describe the code.

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** cross-model CLI: Codex CLI 0.161.0 (`gpt-6.1-sol`), `codex exec -s read-only --ephemeral`, fresh context. It was given file paths only, not the authoring transcript.
- **Reviewed:** `openspec/architecture.md`; `docs/adr/README.md` and ADRs 0001-0007; intent from `STRATEGY.md`, `docs/IMPLEMENTATION_STRATEGY.md` and `openspec/roadmap.md`; source of truth in `lib/` (application, data, domain, maps, ui), `windows/` (CMake, runner, ocr, generated plugins), `tool/maps/pack.dart` and `prepare.dart`, `pubspec.yaml`, `assets/maps/active.json` plus the active manifest, and `drift_schemas/`.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

- None.

### Moderate

- **Generation fencing is overstated.** `openspec/architecture.md:11,115`, ADR-0002:16 and ADR-0004:20 imply universal fencing. `SettingsController.load/save` and `HistoryController.load/record` have no generation or disposal guards (`lib/application/settings_controller.dart:16-40`; `history_controller.dart:13-31`). Also, `MapController.contentGeneration` is public (`map_controller.dart:67`). A designer could incorrectly rely on existing protection against overlapping loads or publication after disposal.

- **The ownership table omits an independent durable writer.** Settings, pins and history are attributed solely to their controllers (`openspec/architecture.md:66-68`). `LegacyImport.commit` instead calls `database.commitImport`, which writes all three directly (`lib/data/legacy_import.dart:62-63`; `database.dart:265-289`). Controller snapshots are subsequently reloaded (`lib/ui/import_dialog.dart:70-74`). Ignoring this path would produce incorrect synchronization or write-serialization assumptions.

- **Pins are not validated at database load.** `openspec/architecture.md:67` promises load-time frame/revision validation. `readPins` calls `CustomPin.fromJson`, which does not call `validate` (`lib/data/database.dart:176-182`; `lib/domain/settings.dart:160-169`). Validation occurs later during projection (`lib/domain/map_coordinates.dart:118-125`). A migration designer could wrongly assume unsupported frames are rejected before reaching rendering.

- **Screenshot bookkeeping can grow even when the folder shrinks.** `openspec/architecture.md:98` says bookkeeping is pruned to present files. Only `_seen` and `_fileStamps` are pruned; `_knownContentIds` retains every encountered hash, and `_dirty` can retain deleted or excluded paths until rebinding (`lib/data/screenshot_directory_watcher.dart:49-52,100-102,251-266`). Deleting screenshots therefore does not bound this retained state.

- **The documented hung-OCR behavior does not describe the application path.** `openspec/architecture.md:100` and ADR-0004:29 promise `unavailable` for later panels. `MapSessionController` holds later work as replaceable pending requests until the active future completes (`lib/application/map_session_controller.dart:333-361`). A hung native call leaves processing pending indefinitely; service disposal also waits indefinitely (`:449-453`). Readers would design recovery around a failure result that never arrives.

- **The map-budget exhaustion behavior is incomplete.** `openspec/architecture.md:95` lists only LRU eviction. `_makeRoom` evicts only resources without leases and throws when active demand leaves no evictable resource (`lib/maps/native_map_scene.dart:221-233`). The budget also measures decoded raster bytes and approximate picture bytes, excluding GPU copies (`:14-22,41-50`). Treating 192 MiB as a total native-memory ceiling with guaranteed eviction would misguide capacity planning.

- **Important unbounded input flows are omitted.** Both HTTP clients buffer complete response bodies without byte caps (`lib/data/catalog_client.dart:30-43`; `tracker_client.dart:80-89`). Legacy import reads entire chosen files and materializes preview records without byte or record caps (`legacy_import.dart:22-49`; `lib/domain/import_preview.dart:26-30`). Tracker’s documented “30 s” flow also comprises two sequential requests, each with its own timeout (`tracker_client.dart:138,179`). The bounds table could lead readers to mistake transport deadlines for memory or whole-operation bounds.

- **ADR-0006 overstates the exit-matching thresholds.** Its line 17 says matching uses similarity ≥0.78 **and** word overlap ≥0.72, citing lines 35-60. The actual predicate accepts equality or substring containment, either directional overlap threshold, **or** similarity (`lib/domain/raid_exfil_matcher.dart:106-114`), with additional raw-text matching. Readers would implement stricter acceptance rules and incompatible fixtures.

- **ADR-0007 makes an unbuilt platform decision binding.** Line 27 requires future input, capture and hotkeys to extend the runner or DLLs and demands a superseding ADR for plugins. Those capabilities do not exist. This conflicts with `docs/adr/README.md:3` and would prevent a future capture design from evaluating packaging alternatives on its own requirements.

- **History failure visibility is overstated.** `openspec/architecture.md:102` promises load/save errors in the history panel. `HistoryPanel` displays `history.error` only when rows are empty (`lib/ui/evidence_panels.dart:193-199`). A failed reload retains existing rows and hides its error; manual recording failures are routed to the decision card (`selection_controller.dart:84-86`; `item_decision_card.dart:198-205`). Readers could incorrectly assume retained history always carries a visible failure warning.

### Suggestions

- **Qualify the stale-market rule in ADR-0001:15.** Stale quotes force Check only when Flea eligibility is not explicitly false (`lib/domain/decision_engine.dart:100-114`). Otherwise, trader advice can remain valid. The current blanket wording could encourage an unnecessary regression that suppresses usable trader advice.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **Generation claims:** In `openspec/architecture.md:11`, replace “all fenced by generation counters” with “generation fences protect catalog, progress, selection, map and session publication; SettingsController and HistoryController lack generation/disposal guards.” In ADR-0002:16 and ADR-0004:20, replace universal fencing claims with the same scoped statement. In architecture line 115, replace “only `authorityVersion` is public” with “`authorityVersion`, map `contentGeneration`, and session epochs are exposed.”

2. **Durable writers:** In `openspec/architecture.md:64-68`, rename “Sole writer” to “Writer(s)”; add `LegacyImport` through `BlackgridDatabase.commitImport` to settings, pins and history. Add that successful import reloads controller snapshots through `AppServices.reloadAfterImport`, citing the actual write and reload paths.

3. **Pin validation:** In `openspec/architecture.md:67`, replace “Frame and revision validated at load” with “Database loads deserialize pins without validation; frame/revision validation occurs on save/import and when converting pins for projection.” Retain manifest validation separately and update citations accordingly.

4. **Screenshot retention:** Replace the bound and growth description in `openspec/architecture.md:98` with “No count cap. `_seen` and `_fileStamps` track present files; content hashes and unmatched dirty paths persist until rebinding, so retained state can grow independently of current folder size.”

5. **Hung OCR:** In `openspec/architecture.md:100` and ADR-0004:29, replace the later-panel `unavailable` claim with “A hung call leaves Map processing active, later requests pending/replaced, and service disposal waiting indefinitely. Concurrent direct adapter calls return `unavailable`.”

6. **Map budget:** In `openspec/architecture.md:95`, change the bound to “192 MiB of accounted decoded raster and approximate picture resources; excludes GPU copies.” Change “LRU eviction” to “Evict unleased resources; fail scene loading if active leased demand prevents admission,” citing `native_map_scene.dart:221-233`.

7. **Missing bounds:** In `openspec/architecture.md`, add bounds-table rows stating that catalog/Tracker response buffering and legacy-import input/preview sizes have no byte or record caps. Change Tracker’s “30 s” bound to “30 s per request; two sequential requests, plus parsing; no overall operation deadline.” Cite the buffering, sequential-request and import materialization paths.

8. **Exit matching:** In ADR-0006:17, replace the threshold sentence with “Names match by normalized equality/containment, directional word overlap ≥0.72, or similarity ≥0.78; strongest-match selection rejects ties, and raw-text supplementation applies additional rules.” Cite `raid_exfil_matcher.dart:106-114,145-176,190-275`.

9. **Future Windows scope:** Replace ADR-0007:27 with “Input, capture and hotkeys remain unimplemented; their platform packaging decision belongs to future change design.” Keep accepted status scoped to the implemented credentials channel and panel-OCR DLL.

10. **History visibility:** In `openspec/architecture.md:102`, replace the failure-visibility cells with “Load failures retain prior rows; the history panel shows errors only when empty. Manual record failures appear in the decision card.” Cite `history_controller.dart:13-31`, `evidence_panels.dart:193-199`, and `item_decision_card.dart:198-205`.

CHANGES_APPLIED: yes

## Rebuttals

Every finding was fixed as specified; none was rebutted. Before editing, the author checked the decisive claims against the code: `reloadAfterImport` (`app_services.dart:176`), leased-resource eviction that throws (`native_map_scene.dart:221-233`), the history panel showing errors only when empty (`evidence_panels.dart:193-199`), the OR-combined `namesMatch` predicate (`raid_exfil_matcher.dart:106-114`), `_knownContentIds` being cleared only on rebind (`screenshot_directory_watcher.dart:50,73,260`), disposal awaiting the active request (`map_session_controller.dart:449-453`), and the public `contentGeneration` (`map_controller.dart:67`).

1. Generation claims: fixed in `architecture.md` System triage and the Strategy vs. code table, ADR-0002 Decision and ADR-0004 Decision.
2. Durable writers: fixed. The column is now "Writer(s)"; `LegacyImport` via `commitImport` is added to settings, pins and history, with the `reloadAfterImport` path cited.
3. Pin validation: fixed, as specified.
4. Screenshot retention: fixed, as specified.
5. Hung OCR: fixed in `architecture.md` and ADR-0004.
6. Map budget: fixed, as specified.
7. Missing bounds: fixed. HTTP body and legacy-import rows are added; Tracker is now 30 s per request, two sequential requests, no overall deadline.
8. Exit matching: fixed in ADR-0006.
9. Future Windows scope: fixed in ADR-0007. The architecture index row is scoped the same way.
10. History visibility: fixed, as specified.
Suggestion (ADR-0001 stale-market rule): adopted, citing `decision_engine.dart:100-114`.

## Re-check of applied changes

The same reviewer (Codex CLI, `gpt-6.1-sol`, read-only, fresh context) re-checked only the required items.

**Pass 1:**

1. applied correctly
2. applied correctly
3. applied correctly
4. applied with error: `openspec/architecture.md:100` says bookkeeping grows with “every screenshot”; hashes are deduplicated, and unmatched paths can accumulate without screenshots (`lib/data/screenshot_directory_watcher.dart:100-102,251-266`). Growth is possible, not guaranteed per screenshot.
5. applied correctly
6. applied correctly
7. applied with error: requested bounds are correct, but `openspec/architecture.md:96` promises “existing data untouched” on failure. A successful commit followed by failed controller reload reports an import error without rolling back committed data (`lib/ui/import_dialog.dart:70-84`; `lib/application/app_services.dart:109-110,176-179`).
8. applied correctly
9. applied correctly
10. applied correctly

Suggestion (ADR-0001): applied correctly  
New errors introduced: Overstated screenshot growth (4); unconditional import failure guarantee (7).  
RESULT: OUTSTANDING

The author then made two fixes. The screenshot row now says "can grow with distinct screenshot contents and unmatched paths". The legacy-import row now separates a rolled-back failed commit from a committed import whose controller reload failed.

**Pass 2 (those two rows only):**

4. applied correctly
7. applied correctly
RESULT: ALL_APPLIED
