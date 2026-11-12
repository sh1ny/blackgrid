# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:** openspec/changes/add-task-catalog/proposal.md, specs/task-catalog/spec.md, design.md; openspec/architecture.md (component, state and ADR rows), openspec/roadmap.md (M9), docs/adr/0041; lib/data/catalog_normalizer.dart, lib/data/catalog_client.dart, lib/data/wire_json.dart, lib/domain/catalog.dart (CatalogSnapshot JSON), lib/data/database.dart (loadCatalog/commitCatalog, decode/encode adapters), lib/application/catalog_controller.dart, mise.toml, pubspec.yaml, analysis_options.yaml, .github/workflows/gates.yml, tool/release and tool/maps pubspec/lock readers, test/fixtures/m1/catalog/six_datasets.json; live `json.tarkov.dev/regular/tasks` and `/regular/hideout` (re-fetched 2026-11-12, read-only, deleted after). Skills loaded: dart-use-pattern-matching, dart-add-unit-test, dart-run-static-analysis, dart-write-documentation. Re-check run: only the Required Changes (C1, M1, M2) and Suggestions S-a to S-d were checked, against the current proposal.md, spec.md and design.md and the Rebuttals in review.md.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Critical (blocking)

**C1. The spec promises leniency that the unchanged item parse (D3) already refuses, so a spec scenario cannot pass.**
The requirement "Task facts are retained" said a value "absent or of the wrong type SHALL be kept as unknown". Its scenario "Missing flag stays unknown" sent `minPlayerLevel: "ten"` and expected the refresh to succeed. D3 keeps the existing `ItemRequirement`/`RequirementGate` parse unchanged and runs it first. That parse calls `gate(j, task: true)` for every task (`catalog_normalizer.dart:227`), and `gate()` reads `_integer(j['minPlayerLevel'])` (`:203`). `_integer` throws for a string. `CatalogClient.fetch` maps the exception to `CatalogFailure.invalid` (`catalog_client.dart:117-125`), so the refresh is rejected. The same was true for:
- `factionName` of the wrong type (`:204`);
- prerequisite statuses (`:176`);
- a missing objective `type` (`:233`);
- the count, found-in-raid, optional and item fields of item objectives (`:242-251`).

The proposal's S3 claim that odd facts never block updates was therefore untrue for these fields.
*Status: resolved. See Rebuttals.*

### Moderate

**M1. Absent lists become "none", which erases the unknown that the existing model keeps.**
Neither the spec nor D2 said what an absent `taskRequirements`, `traderRequirements` or `failConditions` on a task means, or an absent requirement list on a station level. The existing parse records that gap as `RequirementGate.incomplete` (`catalog_normalizer.dart:212-220`). An empty list in its place would let the rules call a task "available" when its prerequisite data is missing. The existing fixture has no `failConditions`, so an absent list must also not reject the refresh.
*Status: resolved.*

**M2. Which objective types carry which facts was not defined, and the live wire uses four item shapes.**
- `items`: `findItem`, `giveItem`, `plantItem`, `sellItem`;
- a single `item`: `buildWeapon`;
- `useAny`: `useItem`;
- `questItem`: the three quest-item types (218 objectives);
- `markerItem`: `mark`.

`traderStanding` had no facts class either. The sealed `ObjectiveFacts` contract would have been set by accident.
*Status: resolved.*

### Suggestions

- **S-a.** D5's rationale "no prestige dataset" was wrong: the live `tasks` payload has `data.prestige` and `data.questItems`. *Applied.*
- **S-b.** `mise.toml` `test:all` should also run the package tests. *Applied (D1).*
- **S-c.** The station scenario should assert the wire skill ID `HideoutManagement`. *Applied.*
- **S-d.** Keep the raw type string for unknown objective types. *Applied (spec objective requirement, D2).*

Re-check note: I confirmed on the live wire that `markerItem`, `item` (`buildWeapon`) and `questItem` are plain ID strings and that `useAny` is a list of IDs. The D2 and spec table therefore reads all of them correctly. The quest-item row also accepts an `{id}` object.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **(C1)** Narrow the spec's leniency to values the existing item-requirement parse does not already validate, rewrite the "Missing flag stays unknown" scenario, add a reject-as-today scenario, and correct D5 and the proposal's S3 and "Validation" text. The owner was to confirm, because S3 is user-chosen. *Applied and re-checked.*
   - The spec now has the "Already-validated task fields keep today's strictness" requirement, with a reject-as-today scenario and a valid-values scenario.
   - The scenario now uses an absent `minPlayerLevel`, `factionName: "Marauder"` and `kappaRequired: "yes"`. None of these is checked by the existing parse, so it can pass.
   - D5 lists the strict fields with correct code citations.
   - S3 and "Validation" are narrowed and record the user's decision of 2026-11-12.
2. **(M1)** Keep absent lists as unknown, never as an empty list, without rejecting the refresh, and add a no-`failConditions` scenario. *Applied and re-checked.*
   - The spec has the "Absent lists stay unknown" requirement, with the no-`failConditions` scenario and an empty-list-means-none scenario.
   - D2 states that absent lists are `null` and a present empty list is `[]`.
   - The existing parse accepts every one of these lists when absent (`?? []` at `:169`, `:178`, `:187`, `:211`), and it does not read `failConditions`, so nothing rejects.
3. **(M2)** Add a type-to-facts table to D2 and the spec. *Applied and re-checked.*
   - The spec has the "Item-bearing objectives carry their items" and "Target objectives carry their targets" requirements, each with failure scenarios.
   - D2 maps every type to `ItemFacts`, `QuestItemFacts`, `TaskStatusFacts`, `TraderLevelFacts`, `TraderStandingFacts`, `SkillFacts` or `NoFacts`, and says how found in raid reads for each type.

CHANGES_APPLIED: yes

## Rebuttals

- **C1:** fixed. The user chose to narrow S3 on 2026-11-12 ("Narrow S3"). The spec's "Task facts are retained" now keeps unknowns only for values the item parse does not already validate. A new requirement, "Already-validated task fields keep today's strictness", has a reject-as-today scenario and a valid-values scenario. The "Missing flag stays unknown" scenario now uses an absent `minPlayerLevel`, `factionName: "Marauder"` and `kappaRequired: "yes"`. Design D5 lists both groups with code citations, and the proposal's S3 and "Validation" text are updated. **Accepted by reviewer.**
- **M1:** fixed. The new spec requirement "Absent lists stay unknown" has a no-`failConditions` scenario and an empty-list-means-none scenario. Design D2 states that absent lists are `null` and empty lists are `[]`. **Accepted by reviewer.**
- **M2:** fixed. The spec requirements "Item-bearing objectives carry their items" (type table, including `sellItem`, `buildWeapon`, `useItem`, `mark` and the quest-item types) and "Target objectives carry their targets" (`taskStatus`, `traderLevel`, `traderStanding`, `skill`; every other type carries none) each have failure scenarios. Design D2 maps each type to `ItemFacts`, `QuestItemFacts`, `TaskStatusFacts`, `TraderLevelFacts`, `TraderStandingFacts`, `SkillFacts` or `NoFacts`. **Accepted by reviewer.**
- **S-a:** fixed. D5 now says `data.prestige` and `data.questItems` exist but are not retained in this change, and leaves the choice to `add-task-rules`. **Accepted by reviewer.**
- **S-b:** fixed. D1 now adds the package's `dart test` to both `test` and `test:all`. **Accepted by reviewer.**
- **S-c:** fixed. The station scenario asserts the station ID and the skill ID `HideoutManagement`. **Accepted by reviewer.**
- **S-d:** fixed. Unknown objective types keep their raw type string (spec objective requirement, D2). **Accepted by reviewer.**
