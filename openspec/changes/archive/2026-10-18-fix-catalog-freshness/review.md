# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed:** proposal.md, specs/catalog-authority/spec.md, design.md; docs/adr/0001-shared-conservative-decision-engine.md, docs/adr/0003-single-drift-sqlite-store.md, openspec/architecture.md (catalog boundary line), README.md (lines 168-185); lib/domain/catalog.dart, lib/data/catalog_normalizer.dart, lib/data/catalog_client.dart, lib/application/catalog_controller.dart, lib/application/selection_controller.dart, lib/application/app_services.dart (mode lockstep), lib/ui/settings_dialog.dart (progress mode), lib/domain/decision_engine.dart, lib/ui/evidence_panels.dart; test/fixtures/m1/catalog/fixture.dart, test/fixtures/m1/catalog/six_datasets.json, test/data/catalog_normalizer_test.dart, test/data/catalog_client_test.dart, test/application/catalog_controller_test.dart, test/domain/decision_engine_test.dart, test/support/m1_harness.dart, test/support/map_widget_harness.dart. Skills loaded: dart-add-unit-test, dart-use-pattern-matching, dart-write-documentation, dart-run-static-analysis.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

The core of the design holds up against the code. Dropping the `sourceFreshAt` clause from `authoritativeAt` (`catalog.dart:309-316`) is enough to make the live wire shape authoritative. Keeping `normalizerVersion` 1 is right, because `fromJson` rejects anything else (`catalog.dart:342`). The cached-snapshot path does not leak authority: `catalogStale` is set from the live status (`selection_controller.dart:163-164`). The cross-mode history path still gives Check, because progress and catalog modes are set together (`app_services.dart:217`) and a mismatched progress gives `progressKnown == false`. The fixture changes reach every consumer of `wireFixture()` through `fixtureNow`-clocked harnesses, so none of them start depending on the wall clock.

### Critical (blocking)

None.

### Moderate

**M1. The stalled-feed mitigation is overstated and contradicts ADR-0001.**
The Failure & Visibility row "Upstream feed stalls while still serving" says "Market quotes still expire after 1 h (`lastScanISO`), so sale advice drops to Check". The first Risks bullet says "The 1 h quote rule still guards sale prices". Neither holds in general:
- ADR-0001 says a stale Flea quote forces Check "only when Flea eligibility is not explicitly false; otherwise trader advice can stand". The code does the same: `decision_engine.dart:112-121` reaches `Recommendation.trader` with no quote when `_fleaEligible` returns `false` (`noFlea`, `FirState.no`, or player level below `minLevelForFlea`, `:372-380`). So trader Sell advice for those items has no time guard beyond download time.
- `quoteAt` comes only from the `items` dataset. A stall in `tasks` or `hideout` (separate routes, `catalog_client.dart:57-62`) while `items` stays fresh leaves Flea and Trader Sell advice resting on old requirement data. The quote rule cannot detect that.

Consequence: the residual risk of the settled "download time only" rule is understated in the record the user and the M4 live verification rely on. That record matters more here because the design itself notes that Sell advice becomes reachable in production for the first time. This finding does not reopen the decision. It asks only that the record be accurate.

**M2. D4's rationale is wrong, and the planned test cannot prove D4.**
D4 rejects keeping the source-time loop because "the items time would shorten `current` … while `authoritativeAt` still says authoritative. Status and decision authority would then disagree." But `updateAge` (`catalog_controller.dart:133-139`) demotes only when `authoritativeAt` is false. With the loop kept and D1 applied, the one-shot timer would fire at `itemsTime + 24 h`, find the snapshot still authoritative, do nothing, and never re-arm. The real defect is a lost expiry. Demotion at `observedAt + 24 h` would then depend on `SelectionController`'s 30 s poll (`selection_controller.dart:25-29`), and nothing would do it in a controller used without one.

The spec scenario "Old items update time does not shorten the window" asserts only "still `current` at T + 2 h". That passes with the loop left in, because the early timer fires at T + 1 h and does not demote. D5's claim that this test "fails on the current code, which arms the timer at `itemsTime + 24 h`" is true only because the current code never reaches `current` at all, which is the D1 bug, not D4. As planned, no test fails if D4 is skipped.

### Suggestions

**S1. The evidence panel subtitle contradicts the new rule.** `evidence_panels.dart:103` reads `'Observation is not source freshness'`. After this change, observation time is exactly what catalog freshness is measured from. The design lists only `:120-123`. Add `:103` to the panel edit so the panel stops telling the user the opposite of the rule.

**S2. Name a test layer for "Evidence view with no items update time".** No existing test asserts evidence-panel text (no test references `Source freshness` or the subtitle), and D5 does not say where this scenario is proven. Either put the label in a pure function and unit-test it, or add a minimal `flutter-add-widget-test` over `evidence_panels.dart`. Otherwise the THEN has no planned assertion.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. In design.md, Failure & Visibility, row "Upstream feed stalls while still serving", and in Risks / Trade-offs, the first bullet: replace the claim that the 1 h quote rule makes sale advice drop to Check. State that it guards only Flea advice and only against a stalled `items` dataset. State that Trader advice for Flea-ineligible items (ADR-0001; `decision_engine.dart:112-121,372-380`), and any Sell advice after a stall in `tasks`/`hideout`, is bounded only by the 24 h download-time rule. Record this as an accepted residual risk of the user's 2026-10-18 decision.
2. In spec.md, requirement "Current catalog status expires 24 h after observation", scenario "Old items update time does not shorten the window": extend the THEN, or add a second scenario, so that a catalog observed at T with an items source time of T − 23 h is still `current` at T + 2 h and becomes `stale` at T + 24 h + 1 ms through the expiry timer alone (no `updateAge` call, no further fetch). In design.md D4, replace the "status and decision authority would then disagree" rationale with the lost-expiry defect described in M2. In D5, stop claiming that the controller test fails on the current code for the D4 reason.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

- [x] M1: applied (reviewer re-check, new run, 2026-10-18). The Mechanism Ledger row "Items-liveness gate" (design.md:139) no longer says a stalled feed is caught for sale advice. It now says the gate would cover only `items`, "whose Flea quotes the 1 h rule already guards", and points to the accepted residual risk in Failure & Visibility. That matches design.md:119 and :146, which stay as checked in the previous re-check. A search of design.md, proposal.md and specs/catalog-authority/spec.md for the quote rule, `lastScan`, "stall", "sale advice" and "to Check" finds no remaining claim that the 1 h quote rule catches a stalled feed for sale advice. design.md:24 and :152 describe the rule as unchanged. design.md:118 is the expiry-timer row, a different subject. proposal.md:19 ("still forces Check on stale quotes") says the rule is unchanged and makes no stalled-feed claim. It skips ADR-0001's Flea-eligibility exception, but it is not the claim M1 targets, and design.md now records that exception. The spec makes no such claim. Previous re-check text: the Ledger row still said "A stalled feed is already caught for sale advice by the 1 h quote rule"; that is now fixed.
- [x] M2: applied (reviewer re-check, 2026-10-18). The spec scenario "Old items update time does not shorten the window" (spec.md:39-41) now requires `current` at T + 2 h and `stale` at T + 24 h + 1 ms through the expiry timer alone, with no other age check and no further fetch. With the source-time loop kept (`catalog_controller.dart:111-117`), the timer would fire at T + 1 h, `updateAge` (`:133-139`) would do nothing, and no timer would re-arm, so this THEN fails if D4 is skipped. D4's rationale is now the lost-expiry defect (design.md:50). D5 describes the timer-only controller test and no longer claims a D4-specific failure on the current code (design.md:55).
- [x] S1, S2: deferred to tasks.md as the author says. No design or spec change was needed.
- Scope check: the change folder is untracked, so there is no diff against round 1. proposal.md was last modified at 14:57, before review.md, so it was not edited after the review. In spec.md and design.md, the text now differs from the round-1 findings only at the places named above. No other changed claim was found.
