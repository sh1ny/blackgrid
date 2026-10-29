# Tasks

## Test map

Test files: `test/data/catalog_normalizer_test.dart` (existing, normalizer and projection), `test/domain/decision_engine_test.dart` (existing), `test/ui/requirement_rows_test.dart` (new, pure row model, no widgets), `test/ui/requirement_panel_test.dart` (new, widget).

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| The catalog keeps craft and barter display facts | Craft facts kept | test/data/catalog_normalizer_test.dart | craft rows keep product, station, level and tool facts | green |
| The catalog keeps craft and barter display facts | Barter facts kept | test/data/catalog_normalizer_test.dart | barter rows keep offered item, trader, level and unlock facts | green |
| The catalog keeps craft and barter display facts | Tool flag kept | test/data/catalog_normalizer_test.dart | craft rows keep product, station, level and tool facts | green |
| The catalog keeps craft and barter display facts | Facts survive the cache | test/data/catalog_normalizer_test.dart | craft and barter display facts survive the projection round trip | green |
| The catalog keeps craft and barter display facts | Malformed display fact | test/data/catalog_normalizer_test.dart | malformed or missing display levels become absent without rejecting the catalog | green |
| Display facts never change validation | Existing reference check still rejects | test/data/catalog_normalizer_test.dart | an unknown craft product still invalidates the candidate | green |
| Display facts never change validation | Unresolvable craft unlock task | test/data/catalog_normalizer_test.dart | an unknown craft taskUnlock is kept as an id and does not reject the catalog | green |
| Craft and barter rows name their source | Craft row | test/ui/requirement_rows_test.dart | craft row titles the product with its count and names the station level | red |
| Craft and barter rows name their source | Barter row with an unlocking task | test/ui/requirement_rows_test.dart | barter row names the trader level and the unlocking task | red |
| Craft and barter rows name their source | Level absent | test/ui/requirement_rows_test.dart | a barter row without a trader level names the trader alone | red |
| Task and hideout rows name their source | Hideout row | test/ui/requirement_rows_test.dart | hideout row titles the station and its level | red |
| Task and hideout rows name their source | Task row | test/ui/requirement_rows_test.dart | task row titles the task name | red |
| A missing name falls back to its id | Missing trader translation | test/ui/requirement_rows_test.dart | a trader without a name falls back to its id | red |
| A missing name falls back to its id | Missing product item in a history catalog | test/ui/requirement_rows_test.dart | a product item missing from the catalog falls back to its id | red |
| A missing name falls back to its id | Resolved names hide ids | test/ui/requirement_rows_test.dart | a fully resolved craft row shows no 24-hex id | red |
| Each row tags its kind and states its need in plain words | Unknown progress | test/ui/requirement_rows_test.dart | unresolved hideout row reads Can't confirm with a Hideout tag | red |
| Each row tags its kind and states its need in plain words | Actionable task | test/ui/requirement_rows_test.dart | actionable task row reads Needed now with a Task tag | red |
| An irrelevant row says why it does not count | Craft row state | test/ui/requirement_rows_test.dart | craft row reads Optional use with no raw state or kind name | red |
| An irrelevant row says why it does not count | Gate excludes the player | test/ui/requirement_rows_test.dart | a gated-out task row reads Not for you | red |
| An irrelevant row says why it does not count | Non-FIR copy of a FIR obligation | test/ui/requirement_rows_test.dart | a non-FIR copy of a FIR obligation reads Needs found in raid with its remaining | red |
| Rows show quantities only when they mean something | Optional use with unknown remaining | test/ui/requirement_rows_test.dart | an optional use shows its fractional need without remaining or FIR | red |
| Rows show quantities only when they mean something | Needed now | test/ui/requirement_rows_test.dart | a needed-now hideout row shows need, remaining and its FIR rule | red |
| Rows show quantities only when they mean something | Done row | test/ui/requirement_rows_test.dart | a done row shows no remaining | red |
| Rows show quantities only when they mean something | Tool row | test/ui/requirement_rows_test.dart | a craft tool row says it is not used up instead of its need | red |
| Rows show quantities only when they mean something | Count unknown | test/ui/requirement_rows_test.dart | a row without a count shows no need | red |
| The reason line does not repeat the source | Hideout reason | test/ui/requirement_rows_test.dart | an obligation reason line drops the source name | red |
| The reason line does not repeat the source | Craft reason | test/ui/requirement_rows_test.dart | craft and barter rows have no reason line | red |
| Obligations come first and optional uses group after them | Mixed rows | test/ui/requirement_panel_test.dart | obligations by state, then a collapsed Optional uses header | red |
| Obligations come first and optional uses group after them | Open the group | test/ui/requirement_panel_test.dart | tapping Optional uses lists its rows | red |
| Obligations come first and optional uses group after them | Only optional uses | test/ui/requirement_panel_test.dart | only optional uses shows only the collapsed header | red |
| Obligations come first and optional uses group after them | A new item starts collapsed | test/ui/requirement_panel_test.dart | a newly inspected item starts with Optional uses collapsed | red |
| Obligations come first and optional uses group after them | No optional uses | test/ui/requirement_panel_test.dart | no Optional uses header without craft or barter rows | red |
| Older cached projections still load | Cached projection from before this change | test/data/catalog_normalizer_test.dart; test/ui/requirement_rows_test.dart | a stored projection without display facts still loads; an old craft row keeps its stored source name | red |
| Older cached projections still load | Refresh replaces the old projection | test/data/catalog_normalizer_test.dart | a fresh normalize names craft and barter sources after their product item | green |
| Row display does not change decisions | Same decision before and after | test/domain/decision_engine_test.dart; test/data/catalog_normalizer_test.dart | the existing decision and normalizer tests, unchanged apart from the craft/barter source name | green |
| Row display does not change decisions | Tool flag does not count | test/domain/decision_engine_test.dart | a craft tool stays an optional use and leaves the totals unchanged | green |

Ordering within obligations (state rank, then catalog order) also gets a pure test in `test/ui/requirement_rows_test.dart`: `arrangeRequirementRows orders obligations by state and keeps catalog order within a state`.

## 1. Display facts in the catalog

Skills: `dart-add-unit-test`, `dart-write-documentation`, `dart-use-pattern-matching`. Design D1, D2, D3.

- [x] 1.1 Write the failing normalizer and projection tests in `test/data/catalog_normalizer_test.dart` for the rows "Craft facts kept", "Barter facts kept", "Tool flag kept", "Facts survive the cache", "Malformed display fact", "Existing reference check still rejects", "Unresolvable craft unlock task", "Cached projection from before this change" (data half: a projection JSON with the new keys removed still loads and its craft row's `sourceName` is `craft craft-a`) and "Refresh replaces the old projection". Edit the fixture per test through `wireFixture()` (add `attributes.tool`, a `taskUnlock`, a non-integer `level`), not by changing `six_datasets.json`. Verify each fails for the missing field or the old `sourceName`, not for a setup error.
- [x] 1.2 Add the optional display fields to `ItemRequirement` (`productItemId`, `productCount`, `traderId`, `traderLevel`, `unlockTaskId`, `unlockTaskName`, `stationName`, `tool`; craft rows reuse `stationId`/`stationLevel`), each with a `///` doc comment saying which kinds set it. Write each key only when non-null, as `iconLink` does, and read each as optional. Verify the round-trip and old-projection tests pass.
- [x] 1.3 In `normalizeCatalog`, fill the fields for crafts and barters with a lenient reader (wrong type or missing → null, never a throw). Resolve station and task names as label, then normalized name, then id. Set the craft and barter `sourceName` to the product item's resolved name. Leave every existing `ref(...)` and `_quantity` check exactly as it is, and add no reference check for a craft `taskUnlock`. Verify the 1.1 tests pass, then flip their rows green.
- [x] 1.4 Run `mise run test -- test/data test/domain` and update only assertions that pinned the old `craft <id>`/`barter <id>` source name. Verify no assertion on a state, remaining, total or recommendation changed. That keeps the "Same decision before and after" row green.

## 2. Reason detail without the source prefix

Skills: `dart-add-unit-test`, `dart-write-documentation`. Design D4.

- [x] 2.1 Write failing tests in `test/domain/decision_engine_test.dart`: every reason's `detail` equals its `message` without the `'<sourceName>: '` prefix, for a task, a hideout and a craft row; and the "Tool flag does not count" row (the same craft with and without `tool: true` gives the same state, remaining, totals and recommendation). Verify the `detail` test fails to compile or fails, and say why the tool test already passes, if it does.
- [x] 2.2 Add a required `detail` to `NeedReason` with a doc comment, and build `message` from it in `_need`. Change no state, remaining or branch. Verify the 2.1 tests and the whole `test/domain/decision_engine_test.dart` pass, then flip the rows green.

## 3. Row model

Skills: `dart-add-unit-test`, `dart-use-pattern-matching`, `dart-write-documentation`. Design D5, including the FIR-only exclusion rule.

- [ ] 3.1 Write the failing pure tests in `test/ui/requirement_rows_test.dart` for every row the test map assigns to that file, plus the obligation-order test. Build `NeedReason`s and a small `CatalogSnapshot` by hand, with names like `Workbench`, `Prapor`, `Gunsmith - Part 4` and 24-hex ids where an id fallback is asserted. Use no widget and no fixture file. Verify they fail because `lib/ui/requirement_rows.dart` is missing.
- [ ] 3.2 Implement `lib/ui/requirement_rows.dart` with no Flutter import: `RequirementRowView` (title, kind tag, state label, source line, needs, remaining, FIR line and reason, the optional ones nullable), `requirementRow(NeedReason, CatalogSnapshot?)` and `arrangeRequirementRows(List<NeedReason>)` returning obligations ordered needed now, needed later, can't confirm, done, then the rest, with catalog order kept within a state, and the optional uses in catalog order. Use a `switch` on `RequirementKind` and `NeedState`. Hideout titles come from the stored `sourceName` plus ` level <L>`, so old projections still read. `Needs N` and `N remaining` share one count formatter: whole numbers with no decimals, others trimmed, so `1.0 remaining` never appears. Verify every 3.1 test passes, then flip the rows green.

## 4. Requirements & uses panel

Skills: `flutter-add-widget-test`, `dart-write-documentation`. Design D5, D6.

- [ ] 4.1 Write the failing widget tests in `test/ui/requirement_panel_test.dart` for the five rows the test map assigns to that file. Drive `RequirementPanel` through a hand-written fake or the existing test `AppServices` support (see `test/ui/support/` and `test/ui/shell_test.dart:64`), selecting items from a small synthetic catalog. Use no sleeps, only `pump`/`pumpAndSettle`. Verify they fail on the old flat list.
- [ ] 4.2 Rewrite `RequirementPanel` as a `StatefulWidget` that builds one `ListView.builder` list from `arrangeRequirementRows`: obligation rows, then a tappable `Optional uses (N)` header when there are optional uses, then the optional rows only while it is open. Reset it to collapsed when `selection.selectedId` changes. Render each `RequirementRowView` with the kind tag, state, source line, needs and remaining, reason and FIR texts, leaving out absent ones. Keep the `requirement-scroll` `PageStorageKey`, the panel title, subtitle and empty texts. Verify the 4.1 tests and `test/ui/shell_test.dart` pass, then flip the rows green.

## 5. Integration checks

- [ ] 5.1 Run `dart format lib test`, `mise run analyze` and `mise run test`. Verify all three are clean and every test-map row reads green.
- [ ] 5.2 Run `openspec validate polish-requirement-rows --strict`. Verify it reports the change valid.

## Workflow follow-up

- The PR description links #43 with `Closes #43` and says what of the issue it delivers.
- User check, unverified until the user reports it: the in-raid read of the Requirements & uses panel on a heavily used item (for example a common barter currency), with live game data.
