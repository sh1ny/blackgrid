# M4 qualification protocol

This is the user's procedure for the M4 checks that need the game: the live latency session, the reference timing baseline and the reference corpus outcomes. Results go into [EVIDENCE.md](EVIDENCE.md).

**Agents never run these steps.** Every step that launches Blackgrid or the reference companion while Escape from Tarkov runs, or that needs the game at all, is the user's ([AGENTS.md](../../../AGENTS.md)). An agent may run the offline report and the offline corpus comparison on files the user hands over. Until the user reports a step, its criterion stays `unverified` in `EVIDENCE.md`.

The steps map to these M4 exit criteria ([roadmap](../../../openspec/roadmap.md)):

| Exit criterion | Steps |
|---|---|
| The targeted pass accepts scans (most accepts targeted, recording off) | 1, 2, 3 |
| The global hotkey runs the same pipeline (live hotkey scan) | 2 |
| Map shows the latest accepted scan, scanning works with Map open (live) | 2 |
| The reference timing baseline is recorded on the named Windows setup | 1, 4 |
| Live latency: targeted ≤300 ms p95 to decision, fallback visibly underway by about 300 ms, ≤1.5 s p95 total | 1, 2, 3 |
| Corpus coverage at least the reference's, false positives no worse | 5 |

## 1. Name the setup

Before the first scan, record the setup as an `environment` block with the fields of the M0 [environment contract](../m0/contracts.md#environment), and paste it into `EVIDENCE.md`:

```json
{
  "record_type": "environment",
  "setup_alias": "<alias, not a machine or account name>",
  "hardware": { "cpu": "", "gpu": "", "ram_bytes": 0 },
  "windows": { "version": "", "architecture": "x64" },
  "runtime": { "sdk": "<Flutter version from mise.toml>" },
  "app_build": { "id": "<git commit>", "version": "<BLACKGRID_VERSION>" },
  "display": { "width": 0, "height": 0, "os_scale_percent": 100, "origin": { "x": 0, "y": 0 }, "topology": "" },
  "viewport": { "width": 0, "height": 0, "client_width": 0, "client_height": 0, "ui_scale": 1.0 },
  "observer": null,
  "locale": "en",
  "display_mode": "<windowed | borderless | fullscreen>",
  "warm_state": "warm"
}
```

Use the same setup for the Blackgrid session (step 2) and the reference baseline (step 4). A field you cannot read stays `null` with a reason.

## 2. Live session, recording off

1. Build and start Blackgrid from the commit named in `app_build`. Close the reference companion.
2. Note the UTC time just before the first scan. This is the report's `--since`.
3. In Scanner, switch live scan on. Leave **Record scan frames off** for the whole session. A scan touched by recording is excluded from the figures (its line has `"recording":true`), so a session with recording on gives no verdict.
4. Scan at least **40 items with the mouse** (release over the item to inspect) and at least **20 with the hotkey** (F9 unless rebound). Mix item kinds and screen positions. Include at least one **Weapon case**, and if possible both variants (flea-listable and no-flea).
   - A Weapon case, or any other item whose name the catalog shares with another item (ammo packs, dogtags, gear crates and other cases), now ends `ambiguous` and offers a correction instead of a recommendation (ADR-0021). Each such row shows `flea`, `no flea` or `flea unknown` and the last 6 characters of the item ID. Pick the right variant and note whether the labels let you tell them apart.
   - **These shared-name scans pay the full fallback before the offer appears**, because an ambiguous targeted result falls back to the full-client pass. They count toward the total figure (step 3). If the total p95 fails, check how many of the slow scans were shared names before reading it as a pipeline regression.
5. Do some scans with **Map open**, and check that its decision card follows the latest accepted scan.
6. Note the UTC time after the last scan (`--until`, optional), then switch live scan off.

The live hotkey and Map checks are recorded in `EVIDENCE.md` from what you saw.

## 3. Run the latency report

The timing log is in `%LOCALAPPDATA%\Blackgrid\logs\`: `scan-timings.jsonl` and, after a rotation, `scan-timings.1.jsonl`. Pass the rotated file only when it exists: the report stops if a named file is missing. The commands below do that. The report works offline on the files and never touches the app or the game.

```powershell
$logs = "$env:LOCALAPPDATA\Blackgrid\logs"
$files = @("$logs\scan-timings.jsonl") + @(Get-Item "$logs\scan-timings.1.jsonl" -ErrorAction SilentlyContinue | ForEach-Object FullName)
mise run qualification:scan-latency -- --since 2026-10-21T18:00:00Z --out docs\qualification\m4\latency-report.json @files
```

- `--until <utc>` closes the window; `--force` overwrites an existing `--out` file.
- The report gives, per trigger (`mouse` and `hotkey`, never pooled): counts by end state and winning pass, the targeted share of accepts, and nearest-rank N, p50, p95 and max for targeted trigger-to-decision, trigger-to-`fallback underway` and total trigger to decision (to publication for a scan with no decision). Each has a verdict: `pass`, `fail`, or `indeterminate` below 20 samples. It also shows the fallback capture request p95 as "real fallback work began", for information.
- Lines with recording on are excluded and counted. Lines older than v3 are shown as proxies and never drive a verdict.

Either send the report file and the two log files to the agent, or record the verdicts in `EVIDENCE.md` yourself. The report holds no pixels, OCR text or item IDs.

## 4. Reference timing baseline

Record the reference companion's timing on the same named setup, following the private recipe in [`tool/qualification/reference/instrumentation-recipe.md`](../../../tool/qualification/reference/instrumentation-recipe.md): its permission and isolation steps, its internal clock events (including fallback deadline, actual fallback work start and decision completion as separate events), and its user-operated observation clock.

- Keep mouse and hotkey triggers separate, as Blackgrid's report does.
- Record N, p50, p95 and max for each figure, the outcome counts and every missing stage, with the recipe's nearest-rank rule.
- Store raw recordings and private traces in owner-controlled storage. Only the summary goes into `EVIDENCE.md`.

## 5. Corpus and reference outcomes

1. Restore the labelled corpus to `F:\Dev\Dart\blackgrid-corpus\inspection` (or another folder outside Git), in the layout of [the M2 corpus runner](../m2/CORPUS.md#corpus-layout): `corpus.json`, `catalog.json` and the PNGs. The corpus was rebuilt there on 2026-10-20 from the surviving recording and the confirmed labels in `corpus-labels-20261014-122522.json` (see `EVIDENCE.md`, Corpus). `mise run qualification:build-corpus` rebuilds it again if needed.
2. Run the reference companion on the same cases and write its outcomes into `baseline.json` in that folder: an item ID or `reject` per case ([CORPUS.md, `baseline.json`](../m2/CORPUS.md#baselinejson)). Do not copy Blackgrid's outcomes into it.
3. Tell the agent the folder. The agent runs the offline comparison with the game closed:

   ```powershell
   $env:BLACKGRID_RELEASE_BUNDLE = 'build\windows\x64\runner\Release'
   $env:BLACKGRID_CORPUS_DIR = 'F:\Dev\Dart\blackgrid-corpus\inspection'
   mise exec -- flutter test --tags qualification test/qualification/inspection_corpus_test.dart
   ```

The corpus criterion is judged from the unmodified comparison. Regressions to an `ambiguous` reject within a same-name group are listed separately in `EVIDENCE.md`, but they still count until you decide whether the M4 coverage criterion is amended for them (ADR-0021).
