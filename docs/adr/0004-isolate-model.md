# 0004 - Single process with purpose-specific isolates

- Status: accepted
- Date: 2026-10-07 (M1 PR #3; OCR worker in M5, PR #7)
- Source: [implementation strategy §3](../IMPLEMENTATION_STRATEGY.md#3-target-architecture), [§6](../IMPLEMENTATION_STRATEGY.md#6-scanner-strategy)

## Context and problem

Catalog decode, legacy import parsing, SQLite I/O and native OCR are expensive or blocking. They must not block rendering. Late results must not overwrite newer state.

## Decision

Blackgrid runs as one Flutter process. Work is placed as follows:

- **UI isolate:** controllers, the decision engine and map scene composition.
- **Drift background isolate:** all SQLite I/O (`lib/data/database.dart:80`).
- **One-shot `Isolate.run`:** bulk CPU work, i.e. catalog normalise, decode and encode, and legacy import parsing (`lib/data/catalog_client.dart:91`; `database.dart:307,314`; `lib/data/legacy_import.dart:74`).
- **One long-lived `Isolate.spawn` worker:** owns the blocking native panel-OCR calls. It admits one image at a time; a busy worker returns `unavailable` instead of queueing (`lib/data/raid_panel_ocr.dart:89-121`).

Generation counters fence catalog, progress, selection, map and session results; settings and history loads are not fenced (ADR-0002).

## Rejected alternative

- **A separate helper process for native/OCR work.** It gives stronger fault isolation but needs its own IPC, lifecycle and packaging. The strategy rules out a process boundary unless one is needed.

## Consequences

- **A native crash takes down the app.** Worker isolates share the process.
- **A blocking native call cannot be interrupted.** The panel-OCR call has no duration bound (`windows/ocr/panel_ocr.cpp:205`). A hung call leaves Map processing active, later requests pending or replaced (`lib/application/map_session_controller.dart:333-361`), and service disposal waiting indefinitely (`:449-453`). Only concurrent direct adapter calls return `unavailable`.
- **Item recognition (M2) is expected to follow this pattern** with its own warm worker. That worker must also add the duration bound §6 requires.
- **Reversal cost: medium.** Moving work into a helper process changes the transport, but not the domain or controllers.
