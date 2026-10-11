# M2 inspection corpus runner

## Scope

`test/qualification/inspection_corpus_test.dart` (tag `qualification`) runs the inspection recognition pipeline over a directory of user-supplied screenshots. It starts a real `VisionService` over the built Release bundle, runs `InspectionRecognitionJob` and `matchRecognitionOffUi` per case, and writes a report. It compares the run with an optional baseline of reference outcomes and fails when coverage is lower or false positives are higher.

The corpus is never committed: the images are game screenshots with unresolved redistribution status. The runner reads saved PNG files only. It does not touch the game, a game process or a live window.

The pure parts (corpus and baseline parsing, the targeted region, PNG conversion, per-case evaluation, report building and baseline comparison) live in `test/qualification/support/inspection_corpus.dart`. They are unit-tested offline in `test/qualification/inspection_corpus_support_test.dart`, which needs no bundle and runs in `mise run test`.

## Running

Set both variables, then run the tagged test:

| Variable | Meaning |
| --- | --- |
| `BLACKGRID_RELEASE_BUNDLE` | A built Release bundle, for example `build/windows/x64/runner/Release`. |
| `BLACKGRID_CORPUS_DIR` | The corpus directory described below. |

```powershell
$env:BLACKGRID_RELEASE_BUNDLE = 'build\windows\x64\runner\Release'
$env:BLACKGRID_CORPUS_DIR = 'D:\corpus\inspection'
mise exec -- flutter test --tags qualification test/qualification/inspection_corpus_test.dart
```

With either variable absent the test skips and prints the reason, before any library is loaded.

Per design D8, run it only while the game is not running: the vision worker loads the bundle's native libraries.

## Corpus layout

```text
<BLACKGRID_CORPUS_DIR>/
  corpus.json      required: the cases
  catalog.json     required: the catalog snapshot to match against
  baseline.json    optional: reference per-case outcomes
  <images>         PNG files named by the cases, relative to this directory
  out/             written by the run
    report.json
    crops/<case id>.png
```

The run writes nothing outside `out/` and refuses before its first write if a case image lies inside `out/`, if a write would overwrite an input, or if an output path passes through a symbolic link or junction. `report.json` is replaced through a temporary sibling, so a failed run leaves the previous report intact.

### `corpus.json`

```json
{
  "cases": [
    {
      "id": "kit-1080p",
      "image": "kit-1080p.png",
      "client": { "width": 1920, "height": 1080 },
      "kind": "targeted",
      "cursor": { "x": 500, "y": 300 },
      "expected": "5755356824597772cb798962"
    },
    {
      "id": "empty-4k",
      "image": "empty-4k.png",
      "client": { "width": 3840, "height": 2160 },
      "kind": "fullClient",
      "expected": "reject"
    }
  ]
}
```

- `id`: case name, unique without regard to case; it also names the crop file, so it uses only letters, digits, `.`, `_` and `-`, starts with a letter or digit, does not end with `.`, and is not a Windows device name such as `CON` or `AUX`.
- `image`: a PNG of the whole game client area, `client.width` by `client.height`.
- `kind`: `targeted` or `fullClient`.
- `cursor`: required for `targeted`; the cursor point in client pixels. The runner crops the capture region from it with the capture spec's rule, `(x - m/2, y - m/2, m + r, m)` with `m = floor(50 s)`, `r = floor(600 s)` and `s = min(W/1920, H/1080)`, clipped to the client. It uses the same `planTargeted` as the app.
- `expected`: the catalog item ID that must be accepted, or `reject` when nothing may be accepted.

A malformed corpus (duplicate IDs, an unknown kind, a missing cursor, a cursor outside the client) fails the run with a `FormatException` naming the case.

### `catalog.json`

A `CatalogSnapshot` in the app's own cache format (`CatalogSnapshot.toJson`, schema version 1), read with `CatalogSnapshot.fromJson`. Its `mode` is the game mode the run matches in. Use a snapshot from the app's catalog cache so the item IDs in `expected` are the ones the app would see.

### `baseline.json`

```json
{ "cases": { "kit-1080p": "5755356824597772cb798962", "empty-4k": "reject" } }
```

Reference per-case outcomes: an item ID, or `reject`. Cases absent from the baseline are not compared. Outcomes are judged against each case's `expected`.

## Flow per case

1. A `targeted` case runs the targeted job on the cropped region and matches it. When the outcome is not accepted, the full-client job also runs on the whole image as the fallback, and both results are matched together (targeted evidence ranks first), as in the app's flow.
2. A `fullClient` case runs the full-client job once and matches its evidence. The best accepted peak wins.

## Report

`out/report.json` holds:

- `summary`: `expectedItemCases`, `correct`, `coverage` (correct over expected; 1 with no item cases) and `falsePositives` (an item accepted that was not the expected one, including any acceptance on a `reject` case).
- `families`: per client size, the full-client job times in milliseconds, the maximum, the 1500 ms deadline and `withinDeadline`. The deadline is reported, not enforced.
- `cases`: per case, `expected`, `outcome` (item ID or `reject`), `rejectReason`, `correct`, `falsePositive`, `usedFallback`, `targetedMarkerScore`, `fallbackMarkerScore`, the deciding `text` (OCR) and `cropPath`, the best and runner-up candidate IDs and scores, and `fullClientMs`.
- `baseline`: present with a baseline file: `passed`, both tallies, and the lists `regressions`, `newFalsePositives` and `improvements`.

Each thresholded title crop of the deciding evidence is written as a grayscale PNG under `out/crops/`. A crop may be a downscaled preview when the job capped it.

## Pass rule

Without a baseline the run only reports. With one, the test fails when the number of correct cases is below the baseline's or the number of false positives is above it, over the cases present in both.

## Recording a corpus from live scans

Instead of taking screenshots by hand, the user can record the frames of their own live scans (ADR-0015). The agent never records: it needs the game running, which belongs to the user.

### Recording

- The "Record scan frames" switch is in the Scanner panel. It is off at every start (never persisted) and can be switched on only while live scan is `ready`. Leaving `ready` turns it off.
- Each recording session writes to `%LOCALAPPDATA%\Blackgrid\scan-frames\<yyyyMMdd-HHmmss>[-N]\` (`-N` separates two sessions started in the same second). The panel shows the path.
- The folder holds `<id>-full.png`, `<id>-targeted.png` and `frames.jsonl`. The id is `<session folder name>-NNNN`, where `NNNN` is the scan number.
- The recorder holds at most 2 scans at a time and drops (and counts) the rest; a session stops at 500 hand-offs. Click one item at a time.

### `frames.jsonl`

One JSON object per published scan, appended after its PNGs exist. Version 1 (`v: 1`) has these fields:

- Corpus fields: `id`, `image` (the `<id>-full.png` file name, or null when no whole-client frame exists), `client` (`{width, height}`), `kind` and `cursor` (`{x, y}`, omitted for `fullClient`).
- `captured` (`{left, top, width, height}`): the client-pixel rectangle the full PNG covers; null with `image`.
- Hint fields: `clipped`, `strip` (the `<id>-targeted.png` file name, or null), `outcome` (`accepted`, `rejected` or `failed`), `acceptedId`, `rejectReason`, `failure`, `fullFailure` (why no whole-client frame exists), `text` (the OCR text), `targetedMarkerScore`, `fallbackMarkerScore`, `stripCapturedAtUtc` and `fullCapturedAtUtc`.
- There is no `expected`. Labelling is the user's.

### Mapping to `corpus.json`

1. Keep the lines whose `image` is not null and whose `clipped` is `false`.
2. Copy `id`, `image`, `client`, `kind` and `cursor` into a case, unchanged.
3. Add `expected` from the user's own label: the catalog item ID, or `reject`.
4. Put the PNGs named by `image` beside `corpus.json`. Ids carry the session folder name, so several sessions can be merged into one corpus directory without renaming.

The hint fields are never labels. `outcome`, `acceptedId`, `rejectReason`, `text` and the scores are what the app saw at record time. Copying `acceptedId` into `expected` would make the corpus agree with the app by construction, not independently of it.

### Clipped lines

A line with `clipped: true` is not a valid case as recorded. The runner requires the image size to equal `client`, and the capture is clip-not-pad (ADR-0010), so a clipped image is smaller than the client. `captured` gives the offset of the image inside the client, which a later tool could use to place the cursor; until then, drop those lines or take that screenshot by hand.

### Reading the file

Readers skip an unparseable final line: a crash during an append can leave a partial one. Every other line names PNGs that exist.

### Timings

Timings and timing-log lines from a recording session include the pixel copy and the extra whole-client capture after a targeted acceptance, and a click made during that capture can wait up to 500 ms. Judge latency with recording off.
