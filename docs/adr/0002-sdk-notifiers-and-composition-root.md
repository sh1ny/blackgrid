# 0002 - SDK ChangeNotifier controllers and a hand-written composition root

- Status: accepted
- Date: 2026-10-06 (M1, PR #3)
- Source: [implementation strategy §9](../IMPLEMENTATION_STRATEGY.md#9-state-management-strategy)

## Context and problem

Catalog, progress, selection, map and session state must outlive navigation between Map and Scanner. Each must reject late async results after a mode, session or content change, and must be testable without a widget tree.

## Decision

- **Controllers.** Every application controller `extends ChangeNotifier` (`lib/application/*_controller.dart`).
- **Composition root.** `AppServices` (`lib/application/app_services.dart:27-106`) constructs them with explicit constructor injection. It is opened once by `BlackgridBootstrap` (`lib/ui/app.dart:28`) and disposed in a fixed order (`app_services.dart:181-199`).
- **Navigation.** The shell keeps both areas mounted in an `IndexedStack` (`lib/ui/shell.dart:160-171`).
- **Stale results.** The catalog, progress, selection, map and session controllers keep generation or epoch counters, and an async result publishes only if its counter is still current (e.g. `catalog_controller.dart:27-28`, `selection_controller.dart:58`, `map_session_controller.dart:56`). `SettingsController` and `HistoryController` have no generation or disposal guards (`settings_controller.dart:16-40`; `history_controller.dart:13-31`).
- **Dependencies.** None: no DI container, service locator, Riverpod, BLoC or event bus.

## Rejected alternative

- **Riverpod.** It offers stronger dependency composition and async caching, but it adds a framework and its lifetime rules for a small, fixed service graph.
- **BLoC/Cubit.** Rejected for its event/stream ceremony.

## Consequences

- **Testing.** Lifetimes and disposal are explicit and visible in one file. Tests inject fakes through constructors.
- **Every listener is notified on every change.** `MapController` notifies on every pan or zoom (`map_controller.dart:362-367`), which the strategy advised against. Fixing that is a change inside this decision, not a reversal.
- **Reversal cost: medium-high.** Every controller and every `ListenableBuilder` would move to a new framework.
