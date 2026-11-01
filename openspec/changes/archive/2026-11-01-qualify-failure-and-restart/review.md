# Review

## Metadata

- **Round:** 1
- **Prior round:** none (this file is the re-check of round 1's Required Changes)
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer)
- **Reviewed:** openspec/changes/qualify-failure-and-restart/{proposal.md, design.md, specs/local-data-durability/spec.md, specs/legacy-import/spec.md, specs/catalog-authority/spec.md, specs/progress-authority/spec.md}; openspec/specs/catalog-authority/spec.md, openspec/specs/progress-authority/spec.md, openspec/specs/player-facing-text/spec.md; openspec/roadmap.md (M6 item 5); docs/adr/0003 (versioning lines); source: lib/data/database.dart, lib/application/settings_controller.dart, lib/domain/settings.dart, lib/application/history_controller.dart, lib/application/catalog_controller.dart, lib/data/catalog_client.dart, lib/data/tracker_client.dart, lib/application/progress_controller.dart, lib/data/legacy_import.dart, lib/ui/import_dialog.dart, lib/ui/app.dart, lib/ui/evidence_panels.dart, lib/ui/manual_controls.dart, lib/application/app_services.dart, lib/application/item_icon_cache.dart, lib/application/scan_coordinator.dart (save path), lib/data/credential_store.dart; tests test/data/migration_test.dart, test/data/database_test.dart, test/data/credential_store_test.dart; drift 2.35.1 sources (api/db_base.dart `beforeOpen`, executor/helpers/engines.dart `ensureOpen`/`_runMigrations`). Re-check: the edited sections of design.md (Context "Newer database", D2, D7, the State & Ownership `loadNotice` row, the Drift risk) and specs/local-data-durability/spec.md (the new scenario). Skills loaded: dart-use-pattern-matching, dart-add-unit-test, flutter-add-widget-test, dart-write-documentation.

## Findings

### Critical (blocking)

None.

### Moderate

**M1. D2 puts the typed refusal where it never runs: `onUpgrade` throws before `beforeOpen`.**
The design (Context, "Newer database"; D2) said `beforeOpen` throws the newer-version `StateError` (`database.dart:111-117`) and D2 changed only that throw. In drift 2.35.1, `GeneratedDatabase.beforeOpen` (`api/db_base.dart:117-140`) calls `onUpgrade` whenever `details.hadUpgrade` (`versionBefore != versionNow`), which includes 99 → 3, *before* it calls the user's `beforeOpen` callback. Blackgrid's `onUpgrade` throws `StateError('Unsupported database upgrade.')` for `from >= to` (`database.dart:102-105`), so the newer-version branch in `beforeOpen` is dead code today. `migration_test.dart:130` only asserts `throwsA(anything)`, which is why this was never noticed. Consequence: implementing D2 as written leaves the bootstrap showing the generic message for a newer database. (Fixed; see Rebuttals.)

**M2. D2's verifying test has to go through the production open path, which differs from the existing test in two ways.**
1. Production opens with `NativeDatabase.createInBackground` (`database.dart:95-96`). `migration_test.dart` and D8's helper use a foreground `NativeDatabase(file)`, where the exception type always survives.
2. The first query in `AppServices.initialize` is `itemIcons.open()` (`app_services.dart:234`). It catches every error and only logs it (`item_icon_cache.dart:126-131`), so the open failure is swallowed there. The exception the bootstrap sees comes from the second query (`readSettings`), which rethrows drift's cached `_migrationError` (`engines.dart:503-507`) from the background isolate.

Consequence: a test against a foreground database or a single direct query could pass while the app still shows the generic message. (Fixed; see Rebuttals.)

**M3. D7 never said that a load clears the settings notice, so it outlived an import that replaces the row.**
D7 cleared the settings part of `loadNotice` only on the next `SettingsController.save`. An import with Replace on rewrites the settings row inside `commitImport` (D5) and then reloads through `reloadAfterImport` → `initialize()` → `settings.load()` (`app_services.dart:355-358`). As written, nothing cleared the notice on that path, so the UI kept saying the saved settings could not be read while the imported settings were in use. (Fixed; see Rebuttals.)

### Suggestions

**S1. Name the decode errors the tolerant reads catch.** `AppSettings.fromJson` fails an unknown mode with `StateError` from `firstWhere` (`settings.dart:157`). Missing or mistyped fields fail as `TypeError` from the `as` casts. An unknown map or marker key fails as `FormatException`. `readActivity` fails as `ArgumentError` from `byName` (`database.dart:228-229`). The per-row decode should catch `Object`, with only the decode inside the `try` and the query outside it. Otherwise "Settings written by a newer version" still stops startup.

**S2. Say whether `readPins` runs `CustomPin.validate()`.** D1 counts an undecodable "frame" as skipped, but `CustomPin.fromJson` does not validate (`settings.dart:229-238`), and `map_geometry.dart:351` treats every frame other than labs-native as legacy. Such a pin would be drawn at the wrong place instead of being counted.

**S3. Import preview and skipped pin rows.** `LegacyImport.previewFiles` also calls `readPins` and `readActivity` (`legacy_import.dart:35-36`). An unreadable pin row is then missing from `destinationPins`, so the preview reports "add" for an imported pin with the same `(mapId, pinId)`. With Replace off, `commitImport` skips that write (`database.dart:321-326`). This is rare. List the caller and accept or handle the mismatch.

**S4. D5's rejection rationale is one-sided.** `SettingsController.save` still writes a whole row from its in-memory `_settings`, so a tracked hotkey or live-scan save that lands after the commit but before `reloadAfterImport` reloads still overwrites the imported preferences. This is existing behaviour. Note it in Flow & State Gaps.

Checked and found sound: catalog throw sites do separate transport, timeout, non-200 and validation failures (`catalog_client.dart:29-84`). Translation failures stay `localizationErrors`. The Tracker `malformed` throw sites come after or apart from the identity and mode checks (`tracker_client.dart:141-204`). The selection treats non-current progress as degraded (`selection_controller.dart:435`). The corrupt-token path already maps to `CredentialUnavailable` (`credential_store.dart:73-86`). The TEMP-trigger approach matches the existing `RAISE(ABORT)` pattern (`database_test.dart:182`). No new player-facing string contains a banned term. Every decision stays inside ADR-0002 and ADR-0003. The user's 2026-11-01 decisions are respected.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **design.md, Context "Newer database" and D2 (fixes M1):** Correct the fact that drift runs `onUpgrade` before `beforeOpen` for a newer file. Make `onUpgrade` throw `NewerDatabaseException(from, to)` when `from > to`, before any migrator call or transaction, and keep `StateError` for other unsupported upgrades. State what happens to the `beforeOpen` check.
2. **design.md, D2 assumption and Risks (fixes M2):** The test that pins down the arriving type opens the `user_version 99` file through `BlackgridDatabase.open(file)` (`createInBackground`). It asserts on the error from a second query after a first query failed, or drives `AppServices`'s initialize sequence. The bootstrap check matches what that test proves, and the check that the bytes are unchanged is kept.
3. **design.md, D7 and the State & Ownership `loadNotice` row (fixes M3):** Every `load` recomputes the notice, and `reloadAfterImport` reaches `load`. Add a scenario to specs/local-data-durability/spec.md saying a successful Replace import clears the settings message.

CHANGES_APPLIED: yes

## Rebuttals

The reviewer re-checked only the Required Changes, in design.md and specs/local-data-durability/spec.md:

1. **M1: fixed.**
   - Context "Newer database" (design.md:22-23) now states that drift calls `onUpgrade` before `beforeOpen`, so `StateError('Unsupported database upgrade.')` fires first.
   - D2 (design.md:54-55) makes `onUpgrade` throw `NewerDatabaseException(onDisk: from, supported: to)` when `from > to`, before any migrator call or transaction.
   - `from < 1` keeps the `StateError`, and the unreachable `beforeOpen` check is removed.
   - This matches drift 2.35.1 `db_base.dart:117-140`.
2. **M2: fixed.**
   - Context (design.md:24) records the background isolate and the swallowed first query in `itemIcons.open()`.
   - The D2 assumption (design.md:60) and the Drift risk (design.md:241) require a test through `BlackgridDatabase.open(file)` on a `user_version 99` file. The test ignores the failure of a first query and asserts the error type from a second query, or drives `AppServices.initialize` directly.
   - The bootstrap check (design.md:56) follows what that test proves, and the check that the file's bytes are unchanged is kept.
3. **M3: fixed.**
   - D7 (design.md:101-103) recomputes the settings sentence on every `load`: set when the record is unreadable, cleared otherwise.
   - D7 also states that `reloadAfterImport` reaches `load`, so a Replace import clears the notice.
   - The `loadNotice` row in State & Ownership (design.md:182) matches.
   - specs/local-data-durability/spec.md:43-45 adds the scenario "Replace import clears the message".

Suggestions S1-S4 were not required and were not re-checked.
