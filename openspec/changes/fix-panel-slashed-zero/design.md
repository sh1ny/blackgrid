# Design

## Triage

| Trigger | Applies? | Evidence |
|---|---|---|
| T1 Components (new component, or 3+ with directed relationships) | No | Two existing pure functions change: the parser's text normalisation and the matcher's name test. No component is added. |
| T2 State (persistent state, caches, 3+ state machine) | No | Both are stateless string functions (`lib/domain/raid_panel_text_parser.dart:335-352`, `lib/domain/raid_exfil_matcher.dart:106-115`). |
| T3 Concurrency (background work, workers/isolates, async, retries) | No | OCR scheduling in `lib/data/raid_panel_ocr.dart` is untouched; the parser runs synchronously inside it (`lib/data/raid_panel_ocr.dart:405`). |
| T4 Boundaries (data format, migration, shared interface, IPC, external) | No | No stored data, settings or public API changes. `RaidPanelEvidence` keeps its fields. |
| T5 Volume (grows without a fixed bound) | No | Input is one panel's OCR text. |
| T6 Risk (security, money, data loss, unrecoverable user data) | No | Read-only matching; the worst outcome is a wrong or missing highlight. |

TIER: LIGHT

## Context

- Rows are cut by label patterns that need a digit after `EXFIL`/`EXIT`/`TRANSIT`: `_exfilLine` and `_transitLine` require `0?(\d{1,2})` (`lib/domain/raid_panel_text_parser.dart:241-248`), and `_exfilInline`/`_transitInline` end a row only at a label followed by `0?\d` (`lib/domain/raid_panel_text_parser.dart:249-261`). `EXFILØ3` fails both, so the inline row runs on into the next one.
- Text normalisation already repairs some label misreads before parsing, including `EXFILO`→`EXFIL0` (`lib/domain/raid_panel_text_parser.dart:337-351`). It is applied to the OCR lines and to the merged text alike (`lib/domain/raid_panel_text_parser.dart:272-274`). It has no case for `Ø`, for a lower-case `o`, or for a misread one.
- A row is matched against an exit when the normalised row contains the name or the name contains the row (`lib/domain/raid_exfil_matcher.dart:109`). A row that has several candidates and no single winner rejects the panel (`lib/domain/raid_exfil_matcher.dart:48-60`, tie at `lib/domain/raid_exfil_matcher.dart:176`).
- The raw-text supplement already ignores names under four characters (`lib/domain/raid_exfil_matcher.dart:255`).
- Observed (offline OCR of the owner's 2026-11-25 Shoreline files, Release build): three of four panels were ambiguous on a joined row. With `Ø` read as `0` all four resolved, but a column-layout read (`TRANSIT0I TRANSIT04 …`) left a row `I`, which matched Transit to Terminal through the containment test above.

## Decisions

### D1: Repair the row number in normalisation, not in each pattern

- **Choice:** Extend the parser's text normalisation. After an upper-case `EXFIL`, `EXIT` or `TRANSIT` label (separated by spaces or tabs on the same line, so a label never takes the next line's text), a two-character row number not followed by a letter or digit whose first character is `0`, `Ø`, `O` or `o` is rewritten to digits: `Ø`/`O`/`o` become `0`, and `I`/`l`/`|` become `1`. The four label patterns stay as they are.
- **Rejected:** Widening the digit class in all four regular expressions (`[0-9ØOoIl|]`). That spreads one OCR rule across four patterns and their lookaheads, and the label patterns would then also take letters as row numbers wherever a label happens to be followed by `I` or `l`.
- **Reversal cost:** low
- **Important:** no. It is how S1 is done, and the behaviour users see is S1's.
- **Chosen by:** agent

### D2: Apply the short-row rule in the shared name test

- **Choice:** `namesMatch` returns true for a row under four normalised characters only on equality with the exit's name. Every row match goes through it (`lib/domain/raid_exfil_matcher.dart:48-50`), so one guard covers extracts and transits.
- **Rejected:** Dropping short rows in the parser. The parser cannot know which short names are real exits (`D-2`), and the matcher is where the current map's names are known.
- **Reversal cost:** low
- **Important:** no. It is how S2 is done.
- **Chosen by:** agent

### Decision summary

| # | Decision | Choice | Rejected | Reversal cost | Important | Chosen by |
|---|---|---|---|---|---|---|
| S1 | Slashed-zero row labels | Read `Ø`/`O` and `I`/`l`/`|` misreads in row numbers as digits | Loosen the tie rule for joined rows | low | yes | user |
| S2 | Short OCR rows | Match only by exact name under four characters | Drop short rows; fix only the `I` label | low | yes | user |
| S3 | Whole-panel ambiguity | Keep rejecting a panel with a truly ambiguous row | Accept the rest of the panel | low | no | agent |
| D1 | Where the label repair lives | Parser normalisation | Widen four label regexes | low | no | agent |
| D2 | Where the short-row rule lives | Matcher's `namesMatch` | Parser drops short rows | low | no | agent |

## Assumptions

- **A1:** Every exit row number on the panel starts with `0` (single-digit rows `01`–`09`). Not checked because the bundled pack lists exits but not their panel numbers. The two-digit case (`10`+) is left to the existing digit patterns, so D1 never rewrites it. Depends on it: D1 (only its scope; a `1x` number keeps working through the existing patterns).

## Carried constraints

- **C1:** A row number's zero can arrive as `Ø`, `O` or `o` and its one as `I`, `l` or `|`. Label patterns rely on normalisation to turn these into digits first. Kind: invariant. Destination: doc comment: lib/domain/raid_panel_text_parser.dart RaidPanelTextParser._normalize
- **C2:** A row shorter than four normalised characters matches only by exact name; containment would let label fragments match any exit. Kind: invariant. Destination: spec: specs/raid-panel-reading/spec.md → Requirement: Short rows match only by exact name
