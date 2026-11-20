# Design

## Triage

| Trigger | Applies? | Evidence |
|---|---|---|
| T1 Components (new component, or 3+ with directed relationships) | no | Edits inside three existing widgets: `lib/ui/shell.dart`, `lib/ui/answer_strip.dart` with `lib/ui/correction_offer_block.dart`, and `lib/ui/map_workspace.dart`. No new widget or service. |
| T2 State (persistent state, caches, 3+ state machine) | no | No state is added or changed. The offer's query and results stay owned by `SelectionController` (`correction_offer_block.dart:58-60`). |
| T3 Concurrency (background work, workers/isolates, async, retries) | no | Layout and text only. |
| T4 Boundaries (data format, migration, shared interface, IPC, external) | no | The map pack's `attribution` map is read as before (`lib/maps/prepared_map.dart:408-409,432`). No format or interface change. |
| T5 Volume (grows without a fixed bound) | no | Offer results stay capped at `correctionSearchLimit = 8` (`lib/application/scan_correction.dart:10`) and candidates at 5 (`scan-correction` spec). |
| T6 Risk (security, money, data loss, unrecoverable user data) | no | No data is written. No contact with the game. |

TIER: LIGHT

## Context

Scope and decisions S1–S4 are in proposal.md. What the code does today:

- **Top bar.** The wide bar is a `Row` (`shell.dart:225`) of brand, area switch, `Flexible(ConstrainedBox(maxWidth: 480, search))`, `Spacer()`, timers, inspector toggle and the three actions (`shell.dart:489-541`). `Flexible` and `Spacer` both have flex 1, so each gets half the free width. Once half the free width is more than 480 px, the search field uses only 480 px of its half. A `Row` with `MainAxisAlignment.start` does not hand the rest to anyone, so the unused width ends up after Settings. At 1660 px wide (the width `test/ui/shell_test.dart:1751` uses) half the free width is under 480 px, so the test passes. DESIGN.md X11 already says "the space beyond it separates the search from the timers".
- **Correction offer.** The answer strip wraps the offer in `ConstrainedBox(maxHeight: clamp(18 % of window height, 64, 130))` and `SingleChildScrollView` (`answer_strip.dart:155-169`). The offer lays out a header row, the OCR text, a `Wrap` of up to 5 candidate `OutlinedButton`s, a text field and up to 8 results as full-width `InkWell` rows (`correction_offer_block.dart:75-152`). That stack is taller than 130 px whenever there are results. The whole strip is also capped at 55 % of the window height inside its own scroll view (`shell.dart:233-241`), and that cap stays.
- **Map credit.** `Text('${map.attribution['author'] ?? map.name}')` in `EmberType.label` with `_overlayInk.inkSecondary` (`map_workspace.dart:938-952`). `_overlayInk` is always `EmberColors.dark` (`map_workspace.dart:57`), because the controls sit over the map artwork whatever the app theme is. In the dark palette `ink` is `#E8E6E1` and `inkSecondary` is `#AAA69F` (`lib/ui/ember/ember_tokens.dart:115-116`). Every map in the active pack has an `author`.
- **ADR-0037.** Colours come only from the Ember theme. Primary ink is an existing token, so there is no new colour and no literal.

## Decisions

### D1: The search slot takes all the free width and left-aligns the field inside it

- **Choice:** replace `Flexible(...)` + `Spacer()` with one `Expanded` that holds the 480 px-capped search field aligned to its start. All free width goes to that slot, and the field sits right after the area switch. Timers and tools always follow the slot, so Settings ends at the bar's right padding at any width. The compact `Wrap` layout (`shell.dart:217-224`) is unchanged.
- **Rejected:** setting `MainAxisAlignment.spaceBetween` or a large flex on the `Spacer`. Both still depend on how the `Row` splits flex between the two children, and a later item with flex would bring the gap back. Rejected too: right-aligning the tool group in its own `Expanded`, which would put the leftover width between the timers and the tools rather than after the search, against DESIGN.md X11.
- **Reversal cost:** low
- **Important:** no. It brings back behaviour the spec and DESIGN.md X11 already require.
- **Chosen by:** agent

### D2: Offer results become `OutlinedButton`s in a `Wrap`, with their keys and labels kept

- **Choice:** render the results the way candidates are rendered (`correction_offer_block.dart:96-107`): one `Wrap` (spacing 8, run spacing 8) of `OutlinedButton`s keyed `correction-result-<id>`, each labelled with `_rowLabel`. The answer strip drops the offer's `ConstrainedBox` + `SingleChildScrollView`. The "No items match" line stays as it is.
- **Rejected:** keeping full-width rows and making the offer two columns (candidates beside search). It adds a layout breakpoint for a block that is shown only after a failed scan, and it still grows with results.
- **Reversal cost:** low
- **Important:** yes. It changes what users see. S2 settles it.
- **Chosen by:** user

### D3: The credit uses the overlay palette's `ink` and reads `Map creator: <author>`

- **Choice:** `_overlayInk.ink` (dark palette primary ink, the same colour in both app themes because the overlay always uses the dark palette). The text is `Map creator: $author` when `attribution['author']` is a non-empty string, else `map.name`. The rest of the line (one line, ellipsis, `clearWidth` cap) is unchanged.
- **Rejected:** taking the ink from the app theme (`context.ember.ink`). In the light theme that is a dark ink over the dark map artwork, which is the reason `_overlayInk` exists.
- **Reversal cost:** low
- **Important:** yes. It changes what users see. S3 and S4 settle it.
- **Chosen by:** user

### Decision summary

| # | Decision | Choice | Rejected | Reversal cost | Important | Chosen by |
|---|---|---|---|---|---|---|
| S1 | Scope | Exactly the three listed fixes | Extra fixes from the progress screens | low | yes | user |
| S2 | How the offer fits | Compact block, results as wrapping buttons | Vertical list at its natural height | low | yes | user |
| S3 | Credit ink | Primary ink | Prose ink; larger secondary ink | low | yes | user |
| S4 | Credit without an author | Map name, without the prefix | `Map creator: unknown` | low | no | agent |
| D1 | Top-bar free width | One `Expanded` search slot, field aligned to its start | `spaceBetween` or a Spacer flex; a right-aligned tool group | low | no | agent |
| D2 | Result layout | `OutlinedButton`s in a `Wrap`, same keys and labels | Two-column offer | low | yes | user |
| D3 | Credit colour source | Overlay palette `ink` | App theme `ink` | low | yes | user |
