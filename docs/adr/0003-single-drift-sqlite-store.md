# 0003 - One Drift SQLite database for durable state and the catalog cache

- Status: accepted
- Date: 2026-10-06 (M1, PR #3)
- Source: [implementation strategy §8](../IMPLEMENTATION_STRATEGY.md#8-data-and-persistence-strategy)

## Context and problem

The reference kept versioned JSON settings beside the executable and caches under app data, with separate backup machinery. Blackgrid needs these to be atomic and migratable:

- user records: settings, pins and history;
- a mode-scoped catalog cache that never replaces last-good data with partial data.

## Decision

- **The database.** One Drift database at `%LOCALAPPDATA%\Blackgrid\blackgrid.sqlite` (`lib/data/local_paths.dart:8-25`). It opens on a background isolate (`lib/data/database.dart:80`).
- **Tables.** `Preferences` (one JSON settings row), `PinRecords`, `ActivityRecords`, `CatalogRecords` + `ActiveCatalogs` and `ImportRecords` (`:15-75`).
- **Versioning.** `schemaVersion` is 2, with snapshots in `drift_schemas/`. Upgrades are explicit, and a newer on-disk version is refused (`:82-100`).
- **Catalog cache.** It stores the normalised snapshot (not raw upstream JSON), one per mode. It is swapped atomically in one transaction (`:126-154`).
- **Writes.** Every write is a transaction.
- **Credentials** are stored separately (ADR-0007).

## Rejected alternative

- **Versioned JSON files with a separate preferences API** (the reference's approach). It needs hand-written atomic-write and backup logic, and it creates a second authority for settings.

## Consequences

- **Multi-record writes are atomic.** A failed catalog refresh cannot leave partial data behind.
- **Every schema change needs a migration and a new drift schema snapshot.**
- **History has no row cap.** It is bounded only by uniqueness on (item, mode).
- **Reversal cost: high.** User data on disk would need a one-way migration, and every repository call would change.
