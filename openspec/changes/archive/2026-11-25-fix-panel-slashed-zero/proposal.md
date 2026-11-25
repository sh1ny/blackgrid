# Proposal

## Why

Saved-panel extract matching rejects most Shoreline raid panels. On 2026-11-25 the owner saved four Shoreline screenshots with the exfil panel open; three were reported "ambiguous" and highlighted nothing. Windows OCR reads the game font's slashed zero as `Ø` in row labels (`EXFILØ3`, `TRANSITØ4`, `EXFILØI`). The panel parser only recognises a label followed by a digit, so it misses row boundaries and joins rows together. A joined row that names two exits with an equal score (`Road to Customs EXFILØ3 Railway Bridge`) makes the matcher reject the whole panel.

The defect has been there since M5's saved-panel reading. Screenshots from 2026-11-21, before the latest game update, already read `Ø`. Interchange only worked because its joined rows happened to have one clear winner. This is off-roadmap maintenance of M5's panel reading; it changes no milestone or exit criterion. The owner re-checks it in a raid ([user] task).

## What Changes

- Read `Ø` and `O` as `0`, and `I`, `l` and `|` as `1`, in the two-character number that follows an `EXFIL`, `EXIT` or `TRANSIT` row label. Rows then split at every label, as they already do when OCR reads a plain zero.
- An OCR row shorter than four letters and digits matches an exit only when it equals that exit's name. Containment and fuzzy similarity are not enough. A stray fragment such as `I`, left over from a label, no longer matches `Transit to Terminal` because the letter appears in it. Short real names such as Reserve's `D-2` still match exactly.
- Matching behaviour is otherwise unchanged. A row that still names two exits equally keeps rejecting the panel, and raw-text supplements keep their rules.

## Capabilities

### New Capabilities
- `raid-panel-reading`: How a saved screenshot's exfil panel text becomes extract and transit rows, and how those rows are matched to the current map's exits. M5 shipped this without a spec; this change records the row-splitting and short-row rules it touches.

### Modified Capabilities

None.

## Impact

`lib/domain/raid_panel_text_parser.dart` (label normalisation) and `lib/domain/raid_exfil_matcher.dart` (short-row rule). New tests use the recorded OCR text of the owner's Shoreline screenshots and the 2026-11-21 samples. No change to OCR, panel detection, data, settings or UI.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Accept slashed-zero row labels

- **Choice:** Read the slashed-zero and one misreads in the number after a row label as digits, so rows split at every label.
- **Rejected:** Loosening the matcher's tie rule to pick a winner from a joined row. A joined row is the defect, and breaking ties at random would hide real ambiguity.
- **Reversal cost:** low
- **Important:** yes, it changes which extracts users see highlighted.
- **Chosen by:** user ("yes go ahead with the slashed zero fix")

### S2: Short OCR rows match only by exact name

- **Choice:** A row under four letters and digits matches only an exit whose normalised name equals it.
- **Rejected:** Dropping short rows entirely, which would lose Reserve's `D-2` (two characters). Fixing only the `I` label misread, which leaves other stray fragments free to match any name that contains them.
- **Reversal cost:** low
- **Important:** yes, it changes matching that users see.
- **Chosen by:** user ("Ignore short rows (Recommended)"); the agent narrowed it to exact-only after finding `D-2`, which keeps the user's intent that fragments never match.

### S3: Keep the whole-panel ambiguity rule

- **Choice:** A row that still fits two exits equally keeps rejecting the panel.
- **Rejected:** Accepting the rest of the panel around an ambiguous row. That is a separate policy change, and the evidence here comes only from joined rows, which this change removes.
- **Reversal cost:** low
- **Important:** no, nothing users see changes from today's rule.
- **Chosen by:** agent

## Release Notes

Extract highlights from a saved raid screenshot now work when the exfil panel's row numbers are read with a slashed zero, which made most Shoreline panels fail.

### Fixed

- Reading extracts from a saved screenshot no longer joins panel rows when a row number's zero reads as a slashed zero, so Shoreline panels are no longer rejected as ambiguous, and a one-letter fragment no longer matches Transit to Terminal.
