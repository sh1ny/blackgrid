# Spec Delta

## MODIFIED Requirements

### Requirement: Every scan records stage timings
Each scan SHALL record monotonic timestamps, on the trigger and capture clock, of the trigger, of publication, and, for each pass it ran (targeted, fallback), of every stage that pass reached: pass start, capture request, acquisition start and end, capture answer, vision submission, job start, marker, title, preprocess and OCR stages, job end, matching start and end. A pass's start SHALL be the moment its phase (`targeted`, or `fallback underway`) is published, before any wait for its capture. A pass's job sub-stages SHALL come from that pass's own evidence. A scan accepted and then made the current selection SHALL also record when that selection and its decision were applied. A stage not reached SHALL be absent, never zero.

#### Scenario: Accepted targeted scan timings
- **WHEN** a scan is accepted from the targeted pass and becomes the current selection
- **THEN** its record holds the trigger, the targeted pass start and every targeted stage, publication and decision, non-decreasing in that order, and no fallback stages

#### Scenario: Fallback wins
- **WHEN** a scan's targeted pass is rejected after OCR and its fallback pass is accepted
- **THEN** its record holds the targeted pass's own marker, title, preprocess and OCR stages as well as the fallback pass's, and the fallback pass start is before the fallback capture request

#### Scenario: Fallback start before its wait
- **WHEN** a mouse scan's targeted pass ends rejected 120 ms after the trigger
- **THEN** its fallback pass start is at about 120 ms, and its fallback capture request is at 200 ms or later

#### Scenario: Scan ended early
- **WHEN** a scan ends because the targeted capture failed
- **THEN** its record holds the trigger, the targeted pass start, capture request and capture answer, and every later stage and the decision are absent

#### Scenario: Accepted scan that drives no decision
- **WHEN** a scan is published accepted after the live mode changed since its trigger, so it does not become the current selection
- **THEN** its record holds publication and no decision timestamp

### Requirement: Each finished scan is logged as one JSON line
Every scan that ends (accepted, rejected, failed or superseded) SHALL be appended as one UTF-8 JSON line to `logs/scan-timings.jsonl` in the app's local data folder, after its publication and decision have been applied. The line SHALL hold schema version 3, UTC time, the trigger source (`mouse` or `hotkey`), whether frame recording touched the scan (`recording`: true when recording was on when the scan started or any of its frames was copied for recording), end state, item ID or rejection or failure reason, per-pass marker and candidate scores, OCR text, per-pass stage durations in milliseconds from the trigger including the pass start as `started`, the decision as `ms.decided` when recorded, and dropped and superseded counts. It SHALL hold no pixels or crop bytes.

#### Scenario: Accepted scan line
- **WHEN** a scan started by a mouse release with recording off ends accepted from the fallback pass and becomes the current selection
- **THEN** the log gains one line with `"v":3`, `"trigger":"mouse"`, `"recording":false`, end state `accepted`, the item ID, `fallback` as the winning pass, `ms.decided`, and under `ms` a `targeted` and a `fallback` object with a millisecond value for every stage each pass recorded, including `started`

#### Scenario: Hotkey scan line
- **WHEN** a scan started by the hotkey ends accepted from the targeted pass
- **THEN** the log gains one line with `"v":3` and `"trigger":"hotkey"`

#### Scenario: Recording on
- **WHEN** frame recording is on when a scan starts, and recording turns off before the scan ends
- **THEN** the scan's line holds `"recording":true`

#### Scenario: Recording turned on mid-scan
- **WHEN** recording is off when a scan starts and is turned on before its fallback pass, whose frame is then copied for recording
- **THEN** the scan's line holds `"recording":true`

#### Scenario: Rejected scan line
- **WHEN** a scan ends rejected `ambiguous` after both passes
- **THEN** its line holds no `ms.decided`, and `ms.fallback.started` is present

#### Scenario: Superseded scan line
- **WHEN** a scan is superseded during its vision stage
- **THEN** the log gains one line with end state `superseded`, only the stages reached before supersession, and no `ms.published` or `ms.decided`
