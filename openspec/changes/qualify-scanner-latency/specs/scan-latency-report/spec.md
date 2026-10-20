# Spec Delta

## Purpose

Turns the scan timing log of a live session into the M4 latency and acceptance figures: targeted share of accepts, trigger to decision, trigger to fallback underway and total time, each with a verdict against its target. It runs offline on files and never touches the app or the game.

## ADDED Requirements

### Requirement: The report reads timing log files over a UTC window
The report SHALL read one or more timing log files given on the command line, such as `scan-timings.jsonl` and `scan-timings.1.jsonl`, and SHALL count only lines whose `utc` lies in the requested window: at or after `--since` and before `--until`, either bound optional. A line that is not a JSON object, has no `v` of 2 or 3, or has no valid `utc` SHALL be skipped and counted by reason. A file that cannot be read SHALL stop the report with an error naming it.

#### Scenario: Two files, one window
- **WHEN** the report reads both log files with `--since 2026-10-21T18:00:00Z` and the files hold 40 lines in that window and 900 before it
- **THEN** the report counts 40 lines and reports 900 outside the window

#### Scenario: Malformed and unknown lines
- **WHEN** the window holds a truncated line, a line with `"v":1` and 30 valid v3 lines
- **THEN** the report counts 30 lines and reports one skipped as malformed and one as an unsupported version

#### Scenario: Missing file
- **WHEN** a named log file does not exist
- **THEN** the report exits non-zero with an error naming that file and writes no report

### Requirement: Only v3 lines with recording off drive verdicts
Verdicts SHALL be computed only from v3 lines whose `recording` is false. Lines with `recording` true SHALL be excluded and counted. v2 lines SHALL be summarised in a separate section using proxies, the targeted pass's last stage for fallback underway and `published` for decided, each figure marked as a proxy, and SHALL never change a verdict.

#### Scenario: Recording-on lines excluded
- **WHEN** the window holds 50 v3 lines with recording off and 12 with recording on
- **THEN** the verdicts use the 50 lines, and the report states 12 lines excluded for recording

#### Scenario: Only v2 lines
- **WHEN** the window holds only v2 lines
- **THEN** every verdict is `indeterminate` with reason "no v3 lines", and the v2 section shows its proxy figures marked as proxies

### Requirement: Figures are computed per trigger source
The report SHALL compute every figure and verdict separately for `mouse` and `hotkey` scans, and SHALL list counts by trigger, end state and winning pass, with superseded and dropped scans counted but never sampled. Percentiles SHALL be nearest-rank over the stratum's samples in milliseconds (the sample at rank ceil(q × N) in ascending order), reporting N, p50, p95 and max.

#### Scenario: Nearest rank
- **WHEN** a stratum holds the 20 samples 10, 20, ..., 200 ms
- **THEN** its p95 is 190 ms, p50 is 100 ms and max is 200 ms, with N 20

#### Scenario: Superseded scans
- **WHEN** a mouse stratum holds 30 accepted and 5 superseded scans
- **THEN** the counts show 5 superseded, and only the 30 accepted scans give samples

#### Scenario: No hotkey scans
- **WHEN** the window holds mouse scans only
- **THEN** the hotkey stratum shows N 0 and every hotkey verdict is `indeterminate` with reason "no samples"

### Requirement: The report states the targeted share of accepts
For each trigger the report SHALL give the targeted share: accepts won by the targeted pass over all accepts, with verdict `pass` above 50 %, else `fail`.

#### Scenario: Most accepts targeted
- **WHEN** a mouse stratum has 30 accepts and 24 were won by the targeted pass
- **THEN** the targeted share is 80 % with verdict `pass`

#### Scenario: Half targeted
- **WHEN** a mouse stratum has 40 accepts and 20 were won by the targeted pass
- **THEN** the targeted share is 50 % with verdict `fail`

### Requirement: The report states each latency figure against its target
For each trigger the report SHALL give three p95 figures, each `pass` at or under its target, else `fail`: targeted decision, `ms.decided` of targeted accepts, at most 300 ms; fallback underway, the fallback pass's `started`, at most 300 ms; total, `ms.decided` or else `ms.published` of every published scan that ran the fallback pass, at most 1500 ms. An accepted scan with no `ms.decided` SHALL be counted, not sampled.

#### Scenario: All figures pass
- **WHEN** a mouse stratum has 24 targeted accepts with decided p95 240 ms, and 20 scans that ran the fallback with started p95 280 ms and total p95 900 ms
- **THEN** the three mouse latency verdicts are `pass`

#### Scenario: Targeted decision too slow
- **WHEN** the targeted decision p95 is 340 ms over 25 samples
- **THEN** the targeted decision verdict is `fail` and shows 340 ms against 300 ms

#### Scenario: Failed scan counts toward total
- **WHEN** a scan that ran the fallback ends failed with `visionTimeout` published at 1650 ms
- **THEN** it is a total sample of 1650 ms

#### Scenario: Accepted scan without a decision
- **WHEN** a targeted accept's line has `ms.published` but no `ms.decided`, because the mode changed before it was applied
- **THEN** it is counted as accepted without a decision and is not a targeted decision sample

### Requirement: Too few samples give no verdict
A percentile verdict SHALL be `indeterminate` when its stratum has fewer than 20 samples, and the targeted share verdict SHALL be `indeterminate` with fewer than 20 accepts. The figure SHALL still be shown with its N.

#### Scenario: Small sample
- **WHEN** the hotkey stratum has 8 targeted accepts with decided p95 210 ms
- **THEN** the hotkey targeted decision verdict is `indeterminate`, reason "fewer than 20 samples", and shows 210 ms with N 8

#### Scenario: Exactly twenty
- **WHEN** a stratum has exactly 20 samples with p95 under its target
- **THEN** its verdict is `pass`

### Requirement: The report is written as JSON and as a readable summary
The report SHALL write a JSON file with the window, input files, counts, skips, exclusions, every figure with N, p50, p95, max, target and verdict, and the v2 proxy section. It SHALL print the same figures as a readable table. It SHALL write no pixels, OCR text or item IDs. An existing output file SHALL NOT be overwritten unless `--force` is given.

#### Scenario: Report written
- **WHEN** the report runs with `--out report.json` and the file does not exist
- **THEN** `report.json` holds every figure with its verdict, and the console shows the same verdicts

#### Scenario: Output exists
- **WHEN** `report.json` already exists and `--force` is not given
- **THEN** the report exits non-zero, names the file and leaves it unchanged
