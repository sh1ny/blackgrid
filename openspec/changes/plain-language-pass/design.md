# Design

## Triage

| Trigger | Applies? | Evidence |
|---|---|---|
| T1 Components (new component, or 3+ with directed relationships) | yes (when unsure, it applies) | Two new shared UI pieces: a label module used by about 10 widgets, and a `DetailsSection` widget used by two panels. Neither is a process or service, but the labels form a shared UI contract. |
| T2 State (persistent state, caches, 3+ state machine) | no | Only two in-memory, two-state booleans (Details expanded), never saved. No persistent state changes. |
| T3 Concurrency (background work, workers/isolates, async, retries) | no | The crop decode in `lib/ui/scan_evidence_panel.dart:76-98` stays as it is: eager, once per report id. Only the widget that shows it moves into Details. No timer is added (D5). |
| T4 Boundaries (data format, migration, shared interface, IPC, external) | no | Display only. The timing log (v3, ADR-0020), `frames.jsonl`, settings, Drift and stored enum names (`ActivitySource` stored by name, ADR-0017) do not change. |
| T5 Volume (grows without a fixed bound) | no | The recent scans list stays at 10, and history is unchanged. |
| T6 Risk (security, money, data loss, unrecoverable user data) | no | No credential, storage or decision path changes. The decision engine (ADR-0001) is untouched. |

TIER: FULL

## Context

See `proposal.md` for the why. Current state:

- Raw enum names reach the screen through `.name` interpolation at `lib/ui/shell.dart:214,219`, `lib/ui/manual_controls.dart:76,80`, `lib/ui/settings_dialog.dart:125,260`, `lib/ui/evidence_panels.dart:228,266,302`, `lib/ui/item_decision_card.dart:217` (`fir.name`), `lib/ui/map_screen.dart:111,115,155` and `lib/ui/scan_evidence_panel.dart:184,206,221,238,241,247,374,375`.
- Label helpers already exist in two places: `modeLabel` and `mapLabel` in `lib/ui/theme.dart:238-248`, and `markerCategoryLabel` in `lib/domain/marker_categories.dart:40`. `_endLabel` (`scan_evidence_panel.dart:454`) and `_recommendationLabel` (`item_decision_card.dart:14`) are local exhaustive switches. That last pattern is the one to follow.
- A session-only collapsible precedent exists: `CollapsibleGridPanel` (`lib/ui/theme.dart:139`) is stateless, builds its child only while expanded, and its flag is owned above the `LayoutBuilder` in `_MapScreenState._inputsExpanded` (`lib/ui/map_screen.dart:209-212`), so it survives tab switches (the shell's `IndexedStack`, `lib/ui/shell.dart:161`) and breakpoint changes.
- `ScannerScreen` (`lib/ui/scanner_screen.dart:26`) is stateless and builds the evidence and source panels inside its `LayoutBuilder`. The compact and desktop branches build different subtrees, so state held inside those panels is lost on a breakpoint change.
- Times are shown as `toUtc().toIso8601String()` in the history rows (`evidence_panels.dart:368`), the source panel (`:238,258,271,276`) and the Map saved-file lines (`map_screen.dart:129,147`).
- Tests assert today's wording in about 15 places (`Reason:`, `Failure:`, `Pass:`, `Logs:`, `Margin`, `Scan running: targeted`, `Fallback underway`, `Live scan on`, `Catalog:`, plus 30 keyed lookups such as `scan-reason` and `scan-phase` in `test/ui/scan_evidence_panel_test.dart`).

## Decisions

### D1: One label module in `lib/ui/labels.dart` with an exhaustive switch per enum

- **Choice:** One top-level function per shown kind: `catalogStatusLabel`, `progressStatusLabel`, `mapInputStatusLabel`, `raidPanelStateLabel`, `scanRejectReasonLabel`, `scanFailureCodeLabel` (all 32 codes; several vision codes may share one label such as "Item reader error"), `scanPassLabel`, `firLabel`, `activitySourceLabel`, plus `localTimeLabel` (D5). Each is an exhaustive `switch` expression, so a new enum value fails analysis until it gets a label. `modeLabel` and `mapLabel` stay in `theme.dart`, since many files import them from there.
- **Rejected:** a `label` getter on each enum in `lib/domain` and `lib/application`, because it puts UI wording into domain and coordinator types (`ScanFailureCode`'s names are the spec and timing-log reasons, ADR-0013 and ADR-0020), and those layers have no UI imports today. Also rejected: a `Map<Enum, String>` table, which loses exhaustiveness checking.
- **Reversal cost:** low. These are pure functions behind call sites.

### D2: Developer detail goes behind a stateless `DetailsSection` whose flag is owned by `ScannerScreen`

- **Choice:** Add `DetailsSection` to `theme.dart`: a "Details" title row with a chevron, a whole-row button, and a `WidgetBuilder` child called only while `expanded`. It follows `CollapsibleGridPanel`, but sits inline inside a panel. `ScannerScreen` becomes a `StatefulWidget` holding `scanDetailsExpanded` and `sourceDetailsExpanded` above its `LayoutBuilder`. It passes each flag and setter to `ScanEvidencePanel` and `SourcePanel` as required constructor parameters. Never saved.
- **Rejected:** state inside each panel, because the compact and desktop branches rebuild the panels in different subtrees, so the flag would reset on a resize, unlike map-rail's established behaviour. Also rejected: a `ChangeNotifier` on `AppServices`, which turns view-only state into app state (ADR-0002 composition root) for two booleans. And rejected: the diagnostics setting, which the user declined on 2026-10-29.
- **Reversal cost:** low.

### D3: The scan evidence open view is a plain summary, and everything diagnostic is in Details

- **Choice:** The open view shows the phase in words ("Reading the item…", "Trying a wider scan…"), the note in words ("Last scan not recognised: <reason label>", best candidate "<name> (not accepted)"), the shown scan's item name or reason label, and the recent list as "<item name or reason label>" plus " · hotkey" when the hotkey started it. Details holds, in this order: the note scan's code, OCR text and marker score; the shown scan's end state, pass label, marker score, crop image, OCR text, best and runner-up with scores, margin, item ID and code; the timings block (`Scan #N`, per-pass stages, total); and each recent entry's end state and total. Existing `Key`s (`scan-reason`, `scan-pass`, `scan-timing-*`, `scan-recent-*`) stay on the widgets that carry the same fact, so tests move rather than vanish. The reason key now holds the label in the open view, and `scan-reason-code` holds the raw code in Details.
- **Rejected:** dropping the raw codes entirely, because codes in Details are what a user pastes into a bug report, and they match the timing log. Also rejected: a separate "Scan diagnostics" panel, which adds a third panel to an already dense column and still shows developer detail in the open.
- **Reversal cost:** low.

### D4: The Source authority panel becomes "Data sources" with status sentences

- **Choice:** The open view shows "Item data: <catalogStatusLabel> · updated <localTimeLabel(observedAt)>" (or "not downloaded yet"), "Prices: <localTimeLabel(quote)>" or "price time unknown", "Tracker progress: <progressStatusLabel>", the existing catalog error and warning lines (`evidence_panels.dart:241-253`) with their wording made plain, and the Refresh read-only progress button. Details holds the source URL, the items source update (`itemsSourceUpdateLabel`), the UTC times, the freshness limits line and the cooldown end.
- **Rejected:** collapsing the whole panel, because whether prices are current is player-relevant when deciding to sell.
- **Reversal cost:** low.

### D5: Local time is a pure label, computed at build time without a ticking timer

- **Choice:** `localTimeLabel(DateTime? t, {required DateTime now})` returns `HH:mm` when `t.toLocal()` falls on `now`'s local day, `d MMM HH:mm` for another day (formatted by hand: no `intl` dependency is added, see the Mechanism ledger), and "unknown" for null. Widgets pass `DateTime.now()`. Unit tests pass a fixed `now`.
- **Rejected:** relative ages ("2 h ago"), because they go stale without a once-a-minute timer in every panel, and map-rail forbids periodic work in collapsed sections. Absolute local times never go stale, except across midnight, where "14:32" for yesterday persists until the next rebuild, which is harmless.
- **Reversal cost:** low.

### D6: Plain wording is enforced by two offline source checks, not by reviewing strings

- **Choice:** `test/ui/plain_language_source_test.dart` reads source files as text (pure file IO, no widgets).
  - **Check A**, over `lib/ui/**/*.dart`: fails on any hit of `\b\w*(?:[sS]tatus|[sS]tate|[rR]eason|[cC]ode|[pP]ass|[fF]ir|[sS]ource)\??\.name\b` on a non-comment line, outside the arguments of `Key(`, `ValueKey(` and `PageStorageKey(` (`manual_controls.dart:31` uses `mode.name` in a `ValueKey`). It names the file:line. The pattern catches bare and destructured receivers (`${reason.name}` from `ScanRejected(:final reason)`, `${pass.name}`, `catalogStatus.name`, `source.name`) as well as member chains. The check's own tests run it over in-memory samples: `'Catalog: ${catalog.status.name}'` and `'Reason: ${reason.name}'` must hit, and `ValueKey('x-${mode.name}')` and `item.name` must not.
  - **Check B**, over `lib/ui/**/*.dart`, the player-visible message files in `lib/application` (`selection_controller.dart`, `settings_controller.dart`, `progress_controller.dart`, `catalog_controller.dart`, `map_controller.dart`, `history_controller.dart`) and `lib/data/legacy_import.dart`: it extracts single- and double-quoted literals on non-comment lines. It skips literals passed to `Key(`, `ValueKey(`, `PageStorageKey(` or `debugLabel:`. It fails on a case-insensitive word-stem match of the banned terms in the `player-facing-text` spec (`identit` catches "identities", `normali[sz]` catches both spellings; `M1` is case-sensitive and whole-word).
  - **Wire names stay as they are.** A persisted wire name is never reworded to satisfy Check B. `pin_editor.dart:81` replaces its two frame literals with `MapCoordinateFrame.labsNativeNormalized.wireName` and `MapCoordinateFrame.legacyNormalized.wireName` (`lib/domain/map_coordinates.dart:96-97`). `CustomPin.validate()` (`lib/domain/settings.dart:206-211`) accepts only those names, so rewording them would break every new pin save.
  - **Label tests** iterate `Enum.values` for every kind, so coverage is exhaustive.
- **Rejected:** a custom analyzer lint, because the repo has no custom lint package and adding one is a dependency and a build step for a two-rule check. Also rejected: golden screenshots, which are brittle and do not name the offending string.
- **Reversal cost:** low.

### D7: The rest of the wording is rewritten in place, per surface

- **Choice:** Rewrite in each file without new abstractions. The main rewrites:

| Where | Today | After |
|---|---|---|
| Shell search hint | Search real items or canonical IDs… | Search items… |
| Footer | MANUAL INSPECTION · Catalog stale · Progress missing | Game mode PvP · Item data out of date · Tracker not connected |
| Decision card titles | Current manual inspection / Shared item decision • not an accepted scan | Picked item / Chosen by hand |
| Decision card | Identity retained • catalog unavailable | Item data unavailable |
| Decision card | Flea • gross RUB / Requirement remainder / Mode: PvP • FIR: unknown • Values are gross, not profit. | Flea price / Still needed / PvP · Found in raid: unknown · Prices before fees |
| Empty card (`theme.dart:225`) | Manual inspection · M1 • no accepted scan | Pick or scan an item |
| Manual controls | Selecting an identity is not a scan. / Enter a name, short name or canonical ID. / Refresh to download all six datasets. | Picking an item here does not scan. / Type an item name. / Refresh to download item data. |
| History | Item activity • manual picks and accepted scans / No durable item activity yet. / `importedScan` / ISO | Items you picked or scanned / No items yet. / Imported scan / local time |
| Settings | Blackgrid configuration / DPAPI / Protected credential: … / progress authority cleared | Settings / "Your Tracker token is stored encrypted for your Windows account." / Tracker token: saved / not saved / Token removed |
| Import dialog | Explicit one-time legacy import / Source digest / committed atomically | Import saved settings and history / File fingerprint / Import finished; your files were not changed |
| Import plan rows (`legacy_import.dart:347-348` and the other `reason:` strings) | identity retained even if catalog identity is unavailable / ISO times | kept even if the item is missing from the current catalog / local time via `localTimeLabel` |
| Controller messages | Stored identity is not present in this mode's current catalog… (`selection_controller.dart:369`) / previous durable settings remain (`settings_controller.dart:36`) / the durable record remains (`:96`) / Protected credential unavailable / save failed / removal failed (`progress_controller.dart:72,97,116`) / Credential prefix does not match selected mode (`:84`) / Prepared map inventory… / Prepared artwork… (`map_controller.dart:125,457`) / Item activity could not be loaded (`history_controller.dart:35`) | This item is not in the current item data for this mode; the history row is kept. / Your previous settings are kept. / The pin is kept. / Tracker token unavailable / could not be saved / could not be removed / This token is for a different game mode / Map list could not be opened / Map picture could not be loaded / History could not be loaded |
| Pin editor | Add durable pin record / Normalized X / retained pin frame text | Add pin / Position across (0–1) / Position down (0–1) / Points outside the map are allowed. |
| Map rail | Native local artwork • durable pins • offline map capability / N saved pin records | (no subtitle) / N saved pins |
| Map saved-file lines | Logs: watching / Raid panel: partial / ISO times | Logs: watching folder / Raid panel: partly read / local time |

  Exact wording of lines not listed follows the spec rules, the banned-term check and the label module. `catalog_controller.dart:68,124` ("Stored catalog unavailable", "Catalog refresh failed; last-good data retained") keep their wording: `catalog-authority` pins them, and they contain no banned term. The `ItemDefinition.normalizedName` fallback subtitle in `manual_controls.dart:151` becomes no subtitle when `shortName` is null.
- **Rejected:** a central string table or l10n setup (`flutter_localizations`), because there is one language and no translation requirement, and the setup changes every widget's string access, which is far larger than the problem.
- **Reversal cost:** low.

## Diagrams (FULL)

```mermaid
graph TD
  L[lib/ui/labels.dart<br/>exhaustive label functions + localTimeLabel]
  D[theme.dart DetailsSection<br/>stateless, builds child only when expanded]
  SS[ScannerScreen State<br/>scanDetailsExpanded, sourceDetailsExpanded]
  SE[ScanEvidencePanel]
  SP[SourcePanel 'Data sources']
  Other[shell, decision card, manual controls,<br/>history, settings, import, pin editor, map screen/workspace]
  SS -->|flag + setter| SE
  SS -->|flag + setter| SP
  SE --> D
  SP --> D
  SE --> L
  SP --> L
  Other --> L
  T[test/ui/plain_language_source_test.dart] -.reads files.-> Other
  T -.reads files.-> SE
  T -.reads files.-> SP
  LT[test/ui/labels_test.dart] -.Enum.values.-> L
```

## State & Ownership (FULL)

| State | Owner (sole writer) | Lifetime | Invalidation / rebuild | Authoritative copy |
|---|---|---|---|---|
| `scanDetailsExpanded` | `_ScannerScreenState` via its setter | App session (the `IndexedStack` keeps the screen alive) | Never saved; false at launch | `_ScannerScreenState` |
| `sourceDetailsExpanded` | `_ScannerScreenState` via its setter | App session | Never saved; false at launch | `_ScannerScreenState` |
| Decoded crop image | `_ScanEvidencePanelState` (unchanged) | Per shown report id | Unchanged (`scan_evidence_panel.dart:76`) | Unchanged |

## Failure & Visibility (FULL)

| Component | Fails / dies mid-operation → | Recovery | Retry safe? | Who finds out |
|---|---|---|---|---|
| Label functions | An unlabelled new enum value fails analysis (exhaustive switch) | Add the label | n/a | Developer, through `mise run analyze` |
| Source checks | A raw `.name` in `lib/ui`, or a banned term in a file Check B scans (D6), fails the suite | Use a label or reword | n/a | Developer and CI, through `mise run test` with file:line |
| `DetailsSection` | The child builder throws, which surfaces as the usual Flutter error widget, only while expanded | Fix the builder | n/a | User sees the error box, the test suite catches it |
| `localTimeLabel` | A null time shows "unknown" | n/a | n/a | User sees "unknown" |

## Resource Bounds (FULL)

| Queue / buffer / cache / transfer | Bound | At the bound | Timeout | At 10x / 100x |
|---|---|---|---|---|
| Recent scans list | 10 (unchanged, scanner-evidence) | Oldest dropped | n/a | Unchanged |
| Details content | Built only while expanded | n/a | n/a | n/a |
| Source check file scan | Files under `lib/ui` (about 25), plus 6 controller files and `lib/data/legacy_import.dart` | n/a | Test default | Linear in file count, well under a second |

## Flow & State Gaps (FULL)

- **New scan while Details is expanded:** Details stays expanded and shows the new scan's detail. The flag tracks the user's choice, not the subject, which is wanted for watching scans live.
- **Crop decoded while collapsed:** the decode still runs once per report id, so expanding shows the crop at once. No decode is started or cancelled by toggling.
- **Tests and midnight:** widget tests that assert a time label build the expected text with `localTimeLabel` from the same observed time and a `now` taken in the test, so a run that crosses midnight still agrees with itself. Exact day-boundary behaviour is proven only in `labels_test.dart` with a fixed `now`.
- **Midnight rollover:** a time label computed before midnight keeps its time-only form until the next rebuild (D5). This is accepted.
- **Catalog mode change while a history row is shown:** unchanged. Rows from another mode keep falling back to the ID (`evidence_panels.dart:332-337`), as the spec's no-name scenario requires.
- **Narrow layout:** `ScannerScreen`'s compact list gives each panel a fixed height (`scanner_screen.dart:70-85`). Expanded Details scrolls inside the panel's existing `ListView`. No height changes.

## Mechanism Ledger (FULL)

| Mechanism | Built? | Why (harm nobody catches / expensive later) | Evidence that would change the call |
|---|---|---|---|
| Exhaustive label switches | yes | Without them, a new enum value silently shows a raw name, which nobody notices until a player reads it | n/a |
| Source check for `.name` and banned terms | yes | Wording regressions are invisible to every other test. The exit criterion's "string inventory" needs a repeatable agent check | A lint package arriving in the repo |
| Saving the Details state | no | The spec says session only, and saving needs a settings field and a migration | The user asks for Details to stay open across launches |
| Relative-time ticker | no | D5 | Players asking for "x ago" |
| `intl` dependency for date formatting | no | Two fixed formats, written by hand. A new dependency would need a licence review and a bundle change | A need for locale-specific formats |
| Localization framework | no | One language (D7) | A translation requirement |
| Lazy crop decode on expand | no | The crop is tiny (title strip), and changing the decode lifecycle adds T3 risk for no measurable gain | Profiling showing the decode on the UI frame budget |

## Risks / Trade-offs

- [Many tests assert old wording] → Keys stay on the same facts (D3), and wording assertions move to the label functions' tests. Widget tests assert labels by calling the label function, not by copying literals.
- [The banned-term regex misreads multi-line or adjacent-string literals] → Check B joins adjacent literals per statement line and is scoped to the files listed in D6. A false positive names the file:line and is fixed by rewording. It never adds an allow-list entry for a player-facing literal.
- [Reason labels oversimplify, for example many vision codes reading "Item reader error"] → The raw code is always one click away in Details.
- [Wording is subjective] → The exit criterion's read is user-verified. The table in D7 is the proposal, and the user's read may adjust wording without a spec change.

## ADRs

- **In force, constraining this change:** ADR-0001 (the evidence panel never shows a recommendation, and labels do not touch the decision engine), ADR-0002 (no new controller for view state), ADR-0013 (failure code names unchanged), ADR-0020 (timing log v3 keeps the raw codes), ADR-0017 (`ActivitySource` stays stored by name; only its display gets a label).
- **To record during apply:** none. The label and Details pattern is a UI convention, not a binding boundary decision.

## Open Questions

- The exact wording of each reason and failure label is settled during apply against the D7 table and the banned-term check. The user's live read may adjust it later without changing specs.
