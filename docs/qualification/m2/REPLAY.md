# M2 targeted-region replay

## Scope

`test/qualification/targeted_region_replay_test.dart` (tag `qualification`) replays recorded live scans (ADR-0015) against the centred targeted band (ADR-0016). For each replayable frame it crops the band from the recorded whole-client PNG with the app's own `planTargeted`, runs the targeted job on the crop and matches it alone, then runs the full-client job on the whole PNG and matches it alone. It writes one report and fails on any conflicting accept.

The runner reads saved recording folders and a catalog file only. It does not touch the game, a game process or a live window. The recordings and the catalog are never committed.

The pure parts (`frames.jsonl` parsing, the band, per-frame classification, the summary, the report and the output guard) live in `test/qualification/support/targeted_region_replay.dart`. They are unit-tested offline in `test/qualification/targeted_region_replay_support_test.dart`, which needs no bundle and runs in `mise run test`.

## Inputs

| Variable | Meaning |
| --- | --- |
| `BLACKGRID_RELEASE_BUNDLE` | A built Release bundle, for example `build\windows\x64\runner\Release`. |
| `BLACKGRID_RECORDING_DIRS` | One or more recording session folders, separated by `;`. Each holds a `frames.jsonl` and the PNGs it names. |
| `BLACKGRID_REPLAY_CATALOG` | The path of a `catalog.json` outside the repository (see below). |
| `BLACKGRID_REPLAY_OUT` | A run folder; the report goes to `<run folder>\out\replay.json`. |

With any variable absent the test skips and prints which one is missing, before any library is loaded. It also skips, naming the path, when the bundle folder, a recording folder's `frames.jsonl` or the catalog file does not exist.

Per AGENTS.md, run it only while the game is not running: the vision worker loads the bundle's native libraries.

```powershell
$env:BLACKGRID_RELEASE_BUNDLE = 'build\windows\x64\runner\Release'
$env:BLACKGRID_RECORDING_DIRS = 'D:\replay\rec\20261017-101500;D:\replay\rec\20261017-113000'
$env:BLACKGRID_REPLAY_CATALOG = 'D:\replay\catalog.json'
$env:BLACKGRID_REPLAY_OUT = 'D:\replay\run-1'
mise exec -- flutter test --tags qualification test/qualification/targeted_region_replay_test.dart
```

Copy the session folders out of `%LOCALAPPDATA%\Blackgrid\scan-frames\` first, so the run reads a stable copy.

## Exporting the catalog

The app caches each mode's catalog in `%LOCALAPPDATA%\Blackgrid\blackgrid.sqlite`. The table `catalog_records` holds the payloads (column `payload`, the JSON of `CatalogSnapshot.toJson`), and `active_catalogs` points each `cache_key` at the active row through `record_id`. The keys are `json.tarkov.dev:pvp` and `json.tarkov.dev:seasonal`. Export the mode the sessions were recorded in: `frames.jsonl` does not record it, so list the cached keys first (`SELECT cache_key FROM active_catalogs;`) and, when both are cached, ask whoever recorded the sessions. The replay reads that payload unchanged with `CatalogSnapshot.fromJson`, and matches in the snapshot's own `mode`.

Export it from a copy, never from the live file:

1. Close Blackgrid.
2. Copy `blackgrid.sqlite` and any `blackgrid.sqlite-wal` and `blackgrid.sqlite-shm` beside it to a scratch folder outside the repository.
3. Write the payload with the `sqlite3` CLI, opened read-only. `writefile` writes the bytes as stored (UTF-8), so no shell redirection can re-encode them:

```powershell
$scratch = 'D:\replay\db'
New-Item -ItemType Directory -Force $scratch | Out-Null
Copy-Item "$env:LOCALAPPDATA\Blackgrid\blackgrid.sqlite*" $scratch
sqlite3 -readonly "$scratch\blackgrid.sqlite" "SELECT writefile('D:\replay\catalog.json', r.payload) FROM catalog_records r JOIN active_catalogs a ON a.record_id = r.id WHERE a.cache_key = 'json.tarkov.dev:<mode>';"
```

The command prints the number of bytes written; no output means no catalog is cached for that key. Keep `catalog.json` outside the repository.

## Frames replayed

`frames.jsonl` is read by the rules of `CORPUS.md`:

- A line with `image: null` is skipped (`noImage`), and a line with `clipped: true` is skipped (`clipped`): a clipped image is smaller than the client.
- A `fullClient` line is skipped (`fullClient`): it has no cursor, so there is no trigger point to plan the band from.
- An unparseable final line, left by a crash mid-append, is dropped and reported. Any other malformed line, a duplicate id, or a file of more than 500 lines fails the run with a `FormatException` naming the line.
- The hint fields (`outcome`, `acceptedId`, `rejectReason`, `text`, the scores) are never read. They are what the app saw at record time, not truth.

Each replayed frame's PNG must be exactly the client size, or the run fails.

## Report

`<BLACKGRID_REPLAY_OUT>\out\replay.json` is replaced through a temporary sibling, so a failed run leaves the previous report intact. The run refuses before the first job and again before the write when the report would lie inside a recording folder or the bundle, would overwrite the catalog, or passes through a symbolic link or junction.

- `version`: 1.
- `summary`: `frames`, `fullClientAccepts`, `alsoAcceptedByTargeted`, `share` (the second over the first; null with no full-client accept), `agreements`, `bothRejected`, `conflictCount`, `conflicts` (frame ids), `misses` (`winnerOutsideBand` and `insideBandRejected`, each a list of frame ids), and `targetedMs` and `fullClientMs` (each `count`, nearest-rank `p50`, `p90`, `p95`, `p99`, and `max`, in milliseconds).
- `sessions`: per folder, `directory`, `frames` replayed, `skipped` (`noImage`, `clipped`, `fullClient`) and `partialFinalLine`.
- `frames`: per frame, `id`, `session`, `band` (`left`, `top`, `width`, `height` in client pixels), `targetedAccepted` and `fullClientAccepted` (item id or null), `targetedRejectReason` and `fullClientRejectReason`, `targetedMs` and `fullClientMs`, `fullWinnerInBand`, `verdict` (`agreement`, `bothRejected`, `conflict` or `miss`) and `missCause`.

`fullWinnerInBand` says whether the top-left corner of the full-client winner's marker lies inside the band; it is null when the full-client pass rejected. Job times are measured around each submission and include the hand-off to the worker.

## Pass rule

Hard: no conflicting accept. A frame is a conflict when the targeted pass accepts an item that the full-client pass does not accept: the full-client pass rejects, or accepts another item. Any conflict fails the test, after the report is written.

Reported, not enforced: the share of full-client accepts that the targeted pass also accepts, each miss with its cause (the winner's marker outside the band, or inside it and still rejected), and the job-time distribution of both kinds.
