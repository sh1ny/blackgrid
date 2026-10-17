# Evidence

## Offline replay over recorded scans (task 6.4)

**Status: not run.** On 2026-10-17 `tasklist /FI "IMAGENAME eq EscapeFromTarkov.exe"` showed the game running (PID 55696), so the agent stopped before building the bundle or running the replay (AGENTS.md). It runs once the user confirms the game is closed.

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
