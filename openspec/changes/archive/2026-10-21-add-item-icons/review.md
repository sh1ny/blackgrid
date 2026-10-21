# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Re-check (round 1, Required Changes only):** done by the reviewer against the current `design.md` and `specs/item-icons/spec.md`. Required Change 1 is applied: D2 deletes a superseded file only when its name differs and keeps a byte-identical body without rewriting it; the sequence diagram is updated; the link-change scenario carries "unless B's stored file is the same file"; a new scenario covers "A 200 with identical bytes keeps the cached file". Required Change 2 is applied: D2 names files `<sha256(itemId)[0:16]>-<sha256(bytes)[0:16]>.<ext>`, so no path uses the raw id; a new scenario covers an unsafe id (`../../x`, backslash, `:`). Required Change 3 is applied: the failure-wait requirement applies per item and link; D6, the ER diagram and the state diagram add `failedLink`; a new scenario covers "A new icon link clears the wait". S1-S3 were adopted: chained 1→2→3 upgrade with 2→3 and 1→3 tests, a failure wait kept in memory, and a startup gate before the first `acquire`. The S4 rebuttal is accepted: it was a Suggestion, and the author's cost argument holds.
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code harness). Skills loaded: dart-use-pattern-matching, dart-add-unit-test, flutter-add-widget-test, dart-write-documentation (all from `.claude/skills/`).
- **Reviewed:** `proposal.md`, `specs/item-icons/spec.md`, `design.md`; `openspec/roadmap.md` (M4.5, change 2 and exit criteria); `openspec/architecture.md` (resource bounds, in-force ADR index); ADR-0003, ADR-0005, ADR-0012. Source checked against the design's citations: `lib/data/catalog_client.dart`, `lib/data/catalog_normalizer.dart` (items loop and revision hash), `lib/domain/catalog.dart` (`CatalogItem.toJson/fromJson`, `CatalogSnapshot.fromJson`), `lib/data/database.dart` (schema 2, `onUpgrade`, `beforeOpen`, `commitCatalog`), `lib/data/tracker_client.dart`, `lib/data/local_paths.dart`, `lib/application/app_services.dart` (constructor, `open`, `dispose`), `lib/application/catalog_controller.dart` (`_refresh`), `lib/application/selection_controller.dart`, `lib/application/output_path_guard.dart`, `lib/data/scan_frame_recorder.dart`, `lib/ui/item_decision_card.dart`, `lib/ui/evidence_panels.dart` (`HistoryPanel`), `test/data/migration_test.dart`, `drift_schemas/`, `test/data/generated/`.

The design's code facts hold. `commitCatalog` rewrites the payload for an unchanged revision (`database.dart:129-148`). The revision is hashed from the wire bytes, so a new projection field does not change it (`catalog_normalizer.dart:395-404`). `CatalogSnapshot.fromJson` rejects any version other than 1 (`catalog.dart:366-369`). Scanner's wide card is the only layout with an image slot. The history leading icon is a constant.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. When a replacement icon has the same bytes, its file name equals the old one, and "delete superseded file" deletes the icon just stored.**

D2 names each file `<itemId>-<first 16 hex of sha256(bytes)>.<ext>`. The sequence diagram and the spec scenario "A changed icon link replaces the cached icon" both say: store the new file, write the row, then delete the old file.

Three paths can produce byte-identical content under the same item:
- a `200` revalidation whose ETag changed but whose image did not;
- the no-ETag case the Risks section allows, where revalidation is a plain GET that returns the same bytes;
- a link change from A to B where the image is the same.

In each case the new name equals the old one. The rename replaces the file in place and the row keeps the same `fileName`. Then "delete superseded file" removes the file the row names. The item then shows the generic icon, and on the next show the `exists` check triggers a fresh download. That is an extra GET the exit criterion's "one download per item" tests would not expect. On the link-change path the cycle can repeat.

The spec scenario also says outright that the cached file for A is removed after B is stored, which is wrong when the two names are equal.

**M2. The item id goes into a file name unvalidated, but the design treats the stored projection as untrusted.**

D1 re-validates `iconLink` in `fromJson` "so a tampered stored projection cannot inject another host". D2 then builds the file name from `itemId`.

`itemId` is the raw key of the items dataset (`catalog_normalizer.dart:93`, `items[entry.key]`) or of the stored projection map (`catalog.dart:376-381`). Neither path checks its format. An id containing `..\`, `\`, `/` or `:`, or a reserved device name, would make the cache's tmp write, its rename and its "delete superseded" and eviction deletes act outside `item-icons\`. On NTFS, `:` writes to an alternate data stream. The startup sweep also matches files to rows by name.

The same threat model the design already accepts for `iconLink` applies here, and with more damage, because the cache deletes files.

**M3. Two SHALL requirements conflict when the link changes during a failure wait.**

"Cached icons have no time-based expiry" says that when the icon link changes, Blackgrid SHALL download the new link the next time the item is shown. "A failed icon request is not retried for 24 hours" says Blackgrid SHALL send no icon request for that item for 24 hours.

The design keys `failedUntil` on the item row (D2, D6) and does not say whether a new `iconLink` clears it. Consider an item whose old link got a `404`, followed by a catalog refresh that fixes the link inside 24 hours. One requirement forces a GET and the other forbids it. The implementer and the tests will pick different answers.

Both choices stay bounded. A link changes only on a committed catalog refresh, so clearing the wait on a link change adds at most one request per refresh.

### Suggestions

**S1. Specify the migration as a chain of steps, and keep the v1 path tested.**

Today `onUpgrade` throws on anything other than `from == 1 && to == 2` (`database.dart:85-90`). The design says only "the migration from 2 creates the table".

A guard rewritten as `from == 2 && to == 3` would refuse every v1 database that the current code still upgrades. The existing test `committed v1 schema migrates additively to v2` (`test/data/migration_test.dart:15-39`, `migrateAndValidate(db, 2)`) also stops compiling against a v3 `BlackgridDatabase` unless it is updated.

Suggested approach:
- State that the upgrade applies its steps in order: 1→2 creates `ImportRecords`, 2→3 creates `ItemIconRecords`.
- Generate `schema_v3.dart` together with `drift_schema_v3.json`.
- Add a test for 2→3 and a test for 1→3. Each should check that existing preferences, activity and the active catalog are kept.

**S2. Keep the failure wait in memory when its database write fails.**

The Failure table says a failed upsert treats the item as failed for 24 hours. But the wait is itself a row write, and the in-memory index is "updated only after each database write succeeds". If the database keeps failing (a full disk, for example), no wait is recorded. Every show of the item then sends a new GET and stores nothing.

An in-memory `failedUntil` in the index, used when the persisted one cannot be written, keeps the "no retry storm" exit criterion true in that case too.

**S3. State that the startup sweep finishes before the first `acquire` is admitted.**

The sweep deletes files that no row names. If a download runs alongside it, the sweep can delete a file that was just renamed into place but whose row is not written yet. That item would then show the generic icon and download again.

One sentence would close this, for example: `open()` loads the index and sweeps the folder before `AppServices.initialize` returns, and `acquire` before that point gives `generic`.

**S4. Consider whether scrolling the history list should abort downloads that are already in flight.**

The roadmap asks only that a newer scan cancel the older download. The design generalises this to "every lease dropped". `HistoryPanel` is a `ListView.builder`, so a scroll that moves an uncached row past the cache extent aborts that row's request, and scrolling back sends a new one. An icon is about 2 KB and cancelling saves almost nothing, while each re-request goes against "about one request per item".

One option is to cancel only queued entries and the card's superseded download, and let a history row's download that is already on the wire finish and be stored. Low priority.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **M1.** In `design.md` D2 and the "Download and cancel sequence" diagram, state that the superseded file is deleted only when its name differs from the new `fileName`. Writing bytes identical to the stored file keeps it, and a `200` with identical bytes only updates `etag` and `validatedAt`.
   In `specs/item-icons/spec.md`, scenario "A changed icon link replaces the cached icon", change the THEN to: "the cached file for A is removed after B is stored, unless B's stored file is the same file".
   Add to "Shown icons are revalidated at most every 30 days" a scenario: a `200` revalidation returning bytes identical to the cached icon leaves the icon shown and its file present, and the next show sends no request.
2. **M2.** In `design.md` D2, add that the cache derives no path from an unvalidated `itemId`. Either it accepts only ids that match a fixed safe pattern (for example `^[0-9a-f]{24}$`, the live id format, or a bounded `[A-Za-z0-9_-]` set) and treats any other item as having no icon link, or it names files from a hash of the item id instead of the raw id.
   In `specs/item-icons/spec.md`, requirement "Icon links come only from the catalog and only from assets.tarkov.dev", add a scenario: an item whose id contains a path separator or `..` gets no icon request, shows the generic icon, and the cache writes nothing outside its folder.
3. **M3.** Decide how a link change interacts with the failure wait, and write the decision in both places:
   - `design.md` D6: keep `failedUntil` together with the `iconLink` it was recorded for. The recommended choice is that a new link clears the wait.
   - `specs/item-icons/spec.md`: add a scenario to "A failed icon request is not retried for 24 hours", for example: "WHEN an item's download for link A failed and, within 24 hours, the catalog gives link B and the item is shown, THEN exactly one GET is sent to B".

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

- **M1:** fixed. design.md D2 deletes a superseded file only when its name differs, and keeps a byte-identical file in place. The sequence diagram is updated. The spec scenario "A changed icon link replaces the cached icon" now says "unless B's stored file is the same file". A new scenario covers "A 200 with identical bytes keeps the cached file".
- **M2:** fixed. design.md D2 names files `<sha256(itemId)[0:16]>-<sha256(bytes)[0:16]>.<ext>`, so no path derives from the raw id. The live catalog has a non-hex id (`customdogtags12345678910`), so the hash was chosen over a hex-only pattern. A new spec scenario covers an unsafe item id.
- **M3:** fixed. The failure requirement now applies per item and link, and a different link clears the wait. design.md D6 stores `failedLink` beside `failedUntil` (ER and state diagrams updated). A new spec scenario covers "A new icon link clears the wait".
- **S1:** adopted. design.md D2 chains the upgrade 1→2→3 and requires 2→3 and 1→3 migration tests that keep existing data.
- **S2:** adopted. design.md D6 and the State table record the failure wait in memory first and keep it when its database write fails.
- **S3:** adopted. A new State row, Startup gate: `open()` loads the index and sweeps before `initialize` returns, and an earlier `acquire` gets `generic` and enqueues nothing.
- **S4:** not adopted. An aborted download stores nothing, so a later GET is still the first completed download for that item. One uniform rule (abort when the last lease drops) keeps the cache simpler than separate card and row policies. Each re-request costs about 2 KB, and only after a scroll that moves an uncached row out of the build window while its request is on the wire.
- **Reviewer re-check:** M1, M2 and M3 are fixed as cited. S1-S3 are adopted. The S4 rebuttal is accepted by the reviewer.
