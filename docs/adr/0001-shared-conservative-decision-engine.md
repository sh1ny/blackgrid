# 0001 - One shared conservative decision engine

- Status: accepted
- Date: 2026-10-06 (M1, PR #3)
- Source: [implementation strategy §6](../IMPLEMENTATION_STRATEGY.md#6-scanner-strategy)

## Context and problem

The reference app's sale resolver did not gate on item-instance FIR or market age, so it could recommend a confident Sell on unknown facts. Map and Scanner both show item advice. If each surface had its own rules, the two could disagree.

## Decision

`DecisionEngine` (`lib/domain/decision_engine.dart`) is pure Dart: no Flutter, HTTP, SQL or Win32 (`:1-7`). It is the only producer of a `Recommendation` (`keep`, `keepForLater`, `check`, `flea`, `trader`, `priceUnavailable`; `lib/domain/decision.dart:3-12`).

- **Order of rules.** A confirmed current need gives Keep and a known future need gives Keep for later. After that, unknown FIR or unknown or stale progression give Check, never Sell. A stale Flea quote forces Check only when Flea eligibility is not explicitly false; otherwise trader advice can stand (`decision_engine.dart:100-114`). Flea quotes are fresh for 1 h (`decision_engine.dart:99`).
- **One caller.** `SelectionController` is the only caller (`lib/application/selection_controller.dart:36,155`).
- **Both surfaces share it.** Map and Scanner render the same `ItemDecisionCard` from that controller (`lib/ui/map_screen.dart:395`; `lib/ui/scanner_screen.dart:27`).

## Rejected alternative

- **Reproduce the reference resolver's sale logic, with separate Map-card formatting.** Rejected because it allows unsafe Sell and lets the surfaces drift apart.

## Consequences

- Future Scanner work (M2/M4) must feed this engine, not add rules of its own.
- The engine is testable with fixture truth tables.
- **Reversal cost: medium.** It is a single module, but every surface and the safety fixtures depend on its outcomes and their ordering.
