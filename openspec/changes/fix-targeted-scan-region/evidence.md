# Evidence

## Offline replay over recorded scans (task 6.4)

**Status: passed (agent, 2026-10-17).** The first attempt stopped because `tasklist` showed the game running (PID 55696). After the user closed it, `tasklist /FI "IMAGENAME eq EscapeFromTarkov.exe"` (and `blackgrid.exe`) showed no match, and the replay ran on saved PNGs only.

- **Bundle:** `mise run build:release` built 0.1.0+321, and the bundle check passed.
- **Inputs:** copies of `scan-frames\20261014-122522` and `scan-frames\20261017-130909`, and the catalog from a read-only copy of `blackgrid.sqlite`, all outside the repository in `F:\Dev\Dart\blackgrid-replay\`.
- **Catalog:** the task named the PvP catalog, but no PvP catalog was cached. The database has only ever held one catalog row: `json.tarkov.dev:seasonal`, revision `15902a60…6950`, observed 2026-10-10, before both sessions. That is the snapshot the app matched against when the sessions were recorded, so it was used. `REPLAY.md` now tells the reader to export the recorded mode rather than hard-coding PvP.
- **Command:** `mise exec -- flutter test --tags qualification test/qualification/targeted_region_replay_test.dart`, with the four `BLACKGRID_*` variables set. It passed in 42 s, and the report is at `run-1\out\replay.json`.

| Measure | Result |
|---|---|
| Frames used | 70 (50 + 20) |
| Frames skipped | 0 (`noImage` 0, `clipped` 0, `fullClient` 0; no partial final line) |
| Full-client accepts | 39 |
| Also accepted by the targeted band | 39, a share of 1.00 |
| Conflicting accepts (hard rule) | **0**: passed |
| Misses | 0 (none outside the band, none rejected inside it) |
| Both passes rejected | 31: 28 `noMarker`, 2 `ambiguous`, 1 `belowSimilarity`, the same reason in both passes each time |
| Targeted job time | p50 51 ms, p95 74 ms, max 81 ms |
| Full-client job time | p50 171 ms, p95 286 ms, max 305 ms |

Offline, the full-client pass accepts 39 frames, compared with the 36 accepts the app published live. The replay compares the two passes on the same frames. It does not use the live outcomes, which are hint fields (CORPUS.md). The job times are offline worker times on this machine. They exclude the settle wait, capture and matching, so they are not the live latency (task 7.3).

## Integration checks (task 7.1, agent, 2026-10-17)

- `dart format --set-exit-if-changed` on the changed Dart files and `test/qualification/`: 33 files, 0 changed.
- `mise run analyze`: no issues found.
- `mise run test`: 1313 passed, 0 failed.
- `openspec validate fix-targeted-scan-region --strict` (task 7.2): valid.

## User-verified checks (task 7.3)

These need the game and belong to the user. The agent does not run them. Run with frame recording off.

| Check | Status |
|---|---|
| Live scans at the user's resolution: share of accepts by pass (targeted vs full-client), from `scan-timings.jsonl` | unverified |
| Targeted publish latency ≤300 ms p95, computed by the agent from the log the user supplies | unverified |
