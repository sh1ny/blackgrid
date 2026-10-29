# Proposal

## Why

The Requirements & uses panel shows craft and barter rows only a machine can read (`craft 655b598db71eeb7c4168c626`, `irrelevant • craft • remaining Unknown`, `FIR requirement: Unknown`), so a player cannot tell which recipe or trade a row means, where it happens or how many of the item it takes ([#43](https://github.com/sh1ny/blackgrid/issues/43)). An item used in a dozen recipes fills the panel with identical hex rows and pushes the real task and hideout needs off-screen.

This is M4.5 change 6. It serves the exit criterion "Requirements & uses rows name their source: a craft shows its product, count, station and level, a barter its offered item, trader level and unlocking task, a hideout row its station level. No raw tarkov.dev id appears when a name resolves, a missing name falls back to the id without dropping the row, and optional crafts and barters group after the obligations. Older cached catalog projections still load."

## What Changes

- The catalog normalizer keeps the display facts it already reads and then drops. For crafts it keeps the product item and count, the station and its level, the unlocking task and whether the required item is a tool. For barters it keeps the offered item and count, the trader and `minTraderLevel`, and the unlocking task. They become optional fields on `ItemRequirement`. Item and trader names resolve through the snapshot. Station and task names resolve at normalize time through the existing label dictionaries, because the snapshot has no station or task dictionary.
- Display facts never fail a catalog refresh. A missing or malformed display value becomes absent, and every existing integrity and reference check stays as it is.
- A craft or barter requirement's `sourceName` becomes its product or offered item's name, falling back to the item id, instead of `craft <id>` / `barter <id>`.
- `NeedReason` gains a `detail` (the reason without the source-name prefix). `message` keeps its current text.
- Each Requirements & uses row shows:
  - a title naming the source, with a kind tag (`Task`, `Hideout`, `Craft`, `Barter`);
  - a human state (`Needed now`, `Needed later`, `Done`, `Can't confirm`, `Optional use`, `Optional objective`, `Not for you`) instead of the raw `NeedState` name;
  - `Needs N` from the requirement count, or `Tool, not used up`;
  - `N remaining` only when it is known and the row still needs something;
  - the reason detail without the repeated source name;
  - the found-in-raid line only when the source states the rule.
- Obligations (task and hideout rows) are ordered by state: needed now, needed later, can't confirm, done, not for you. Craft and barter rows collapse under an `Optional uses (N)` header after them, collapsed by default.
- Older cached catalog projections without the new fields still load. Their craft and barter rows keep the stored `sourceName` until the next refresh replaces the snapshot.

Out of scope: `NeedState`, the decision rules, the totals, the recommendation and which requirements count as obligations stay unchanged. Crafts and barters stay optional uses. The catalog's integrity checks, `schemaVersion` and `normalizerVersion` stay as they are. The panel's subtitle and empty-state texts, the wording of the reason details themselves, and other panels belong to `plain-language-pass` (change 7).

## Capabilities

### New Capabilities
- `requirement-rows`: how the Requirements & uses panel names, labels, orders and groups an inspected item's requirement and use rows, and which display facts the catalog keeps to do so.

### Modified Capabilities
None. `catalog-authority` covers snapshot authority and source-time evidence, which this change does not touch.

## Impact

- `lib/data/catalog_normalizer.dart`: keep the display facts for crafts and barters; set the craft and barter `sourceName` from the product item.
- `lib/domain/catalog.dart`: optional display fields on `ItemRequirement`, written to and read from the cached projection.
- `lib/domain/decision.dart`, `lib/domain/decision_engine.dart`: `NeedReason.detail`. No change to states, remaining or totals.
- `lib/ui/evidence_panels.dart`: `RequirementPanel` rows, ordering and the collapsible optional-uses group, backed by a pure row-label function.
- Tests: normalizer and projection round-trip tests on the `six_datasets.json` fixture, unit tests for the row labels and ordering, and one widget test for the panel.
- No new dependency, no network or storage change. Its PR closes #43.
