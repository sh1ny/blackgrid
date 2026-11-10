# Proposal

## Why

The Scanner that M8.5 shipped does not match the approved B view of `.impeccable/preview/ember-directions.html` (owner review, 2026-11-10). `add-answer-strip` put a new shell around the old Scanner widgets. `move-scanner-diagnostics` then emptied the Scan evidence card. The result:

- The main column is one bordered card that names the item and leaves about 70% of the window empty.
- Prices and requirements are hidden in inspector accordions. "Inspection details" repeats the strip's verdict and name, then shows prices in boxed cards in a 352px column.
- The recent-items card has a fixed height that cuts a row off mid-word.
- Found in raid sits at the far end of the strip, away from the verdict it changes, and the Check reason, "Found in raid unknown for this item", repeats the control.
- The top bar stretches the search field across half the window and shows Settings, Stats and Import as outlined pills, with Settings first.

This change serves **M8.5 - Ember interface**, change 7. It advances two exit criteria:
- the new agent criterion that the Scanner matches the B view, proved by geometry widget tests;
- the new user criterion that the owner signs off the Scanner design against the B view. The owner extended the milestone for this change and does not count it finished until the design is ironed out. That check is a `[user]` task in tasks.md.

It also keeps the existing criteria true: answer first at every width, Found in raid still working, and no debug information on Scanner.

## What Changes

- **Answer strip:**
  - Found in raid becomes one segmented control directly beside the verdict plate, with the reason line under both.
  - The price block on the right shows the Flea price with its per-slot price, the best trader's price and name, and the freshness tag, in aligned label/value rows.
  - Under the item name, a provenance line says where the item came from and how long ago, e.g. "Accepted scan · 12 s ago" or "Current advice · saved 3 min ago".
  - The control has room for a value-source label, which `detect-found-in-raid` fills next. This change adds no detection.
- **Check reason:** when found in raid is the open question, the reason names the need that requires it, e.g. "Found in raid unknown: Medstation level 1 needs it found in raid". Every other reason keeps its wording.
- **Scanner main column:** rebuilt as flat sections with hairline dividers, no bordered cards:
  - **Why:** a one-line needed summary (found in raid / any), then the requirement rows as dense rows, with the optional uses collapsed as today.
  - **Prices:** Flea, Trader, Per slot and Updated rows.
  - These two sit side by side on a wide window and stack on a narrow one. **Scan evidence** follows below them.
- **Scanner inspector:**
  - a flat Recent items list (X14 rows: picture, name, recorded-verdict dot, relative age such as "3 min", and a tag for another mode or an imported scan), whose rows are never clipped;
  - a short Live scan note that points to the status bar and Settings.
  - The Inspection details, Requirements and Sources accordions are removed.
- **Top bar (shared with Map):** Map/Scanner as one segmented control, a search field of bounded width, then the timers, the inspector toggle, and Stats, Import and Settings as quiet buttons, Settings last.
- **Removed from Scanner:**
  - the data-sources panel, whose freshness now lives in Prices and the status bar; the progress refresh stays in Settings → Tracker progress, the catalog error moves to Settings → Item and map data and the Tracker error stays in Settings → Tracker progress, both reached from the status bar;
  - the item's size line;
  - the old decision card. Its correction offer stays in the strip.
- **Recorded, not added:** the B view's "Clear" link on Recent items is left out. History has no clear action, and adding one would delete data that Stats uses.

## Capabilities

### New Capabilities
- `scanner-workspace`: what the Scanner's main column and inspector show and where: the Why, Prices and Scan evidence sections, their order and placement at wide and narrow widths, the flat Recent items list and the Live scan note.

### Modified Capabilities
- `workspace-shell`:
  - Found in raid sits beside the verdict, and the strip carries the Flea, per-slot and trader price block.
  - The top bar uses a segmented area switch, a bounded search and quiet text actions with Settings last.
  - The Scanner inspector holds Recent items and the Live scan note, with no details, requirements or sources panels.
  - The strip shows a provenance line with the source and relative age of the shown item.
  - History rows show a relative age, and a tag for another mode or an imported scan.
- `verdict-presentation`:
  - The plate and freshness-tag requirements name the answer strip and the Scanner's Prices section instead of the decision card.
  - The Check reason for an unknown found-in-raid state names the need that requires found in raid.
- `scanner-evidence`:
  - The desktop layout requirement moves from a scan evidence panel that fills the window to a Scan evidence section in the main column, which scrolls with the column.
  - The unaccepted-scan rule names the strip and the Why and Prices sections instead of the decision card and panels.
  - The plain-language summary rules are unchanged.
- `catalog-authority`: the catalog error, and item names that could not be loaded, move from the Data sources panel to Settings → Item and map data.
- `player-facing-text`:
  - The Data sources panel requirement is removed, with a migration note.
  - History rows show relative ages instead of clock times.
  - The missing price time is reported in the strip and Prices.
- `item-icons`: the answer strip, not the decision card, is the item's icon surface.
- `scan-decisions`: an accepted scan shows in the answer strip and the Why and Prices sections; its age is in the strip's provenance line.
- `scan-correction`: the offer and the corrected label live in the answer strip; the correction's age is in the provenance line.
- `latest-accepted-scan`: "Back to latest scan" is the strip's action, and the returned scan's age shows in the provenance line.
- `settings-diagnostics`: catalog and Tracker errors stay reachable through the status bar and Settings instead of an inspector panel; the corrected-scan wording moves to the provenance line.
- `settings-page`: choosing the area Settings came from in the top bar's switch still closes Settings.

## Impact

- **UI code:**
  - `lib/ui/answer_strip.dart`, `lib/ui/shell.dart` (top bar and inspector), `lib/ui/scanner_screen.dart`;
  - `lib/ui/scan_evidence_panel.dart`, `lib/ui/evidence_panels.dart` (`RequirementPanel`, `HistoryPanel`, `SourcePanel`);
  - `lib/ui/item_decision_card.dart` (the card goes; `CorrectionOfferBlock` stays).
- **Domain:** `lib/domain/verdict_reason.dart` (the Check wording), and a shared need-title function also used by `lib/ui/requirement_rows.dart`.
- **Settings:** `lib/ui/settings/settings_page.dart` (catalog error in Item and map data). `DESIGN.md` X11 action order.
- **Tests:** widget tests for the strip, shell, inspector, history, requirement and source panels, and the decision card move or are rewritten. New geometry tests pin the placement.
- **Unchanged:** no data, storage, capture or vision change, and no new dependency. Map's main column is unchanged; only the shared top bar affects it.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Include the shared top bar

- **Choice:** restyle the top bar to the B view in this change, for Map as well.
- **Rejected:** Scanner body only. The top bar was part of the owner's comparison and is the same widget on both areas.
- **Reversal cost:** low
- **Important:** yes, it changes what users see on both areas
- **Chosen by:** user

### S2: Drop the Sources panel from Scanner

- **Choice:** remove the data-sources panel. Price age goes to the Prices "Updated" row; item data and Tracker state stay in the status bar; the progress refresh stays in Settings → Tracker progress; errors the player must act on stay visible.
- **Rejected:** keep it as a flat inspector section. It repeats the status bar, and the B view has no such section.
- **Reversal cost:** low
- **Important:** yes, it changes what users see
- **Chosen by:** user

### S3: No Clear action for Recent items

- **Choice:** leave out the B view's "Clear" link.
- **Rejected:** add a confirmed clear. It deletes history that Stats reads, which is new data behaviour in a layout change.
- **Reversal cost:** low
- **Important:** yes, it changes what users see (the mockup has it)
- **Chosen by:** user

### S4: Needed totals move to Why; item size is dropped

- **Choice:** Why opens with a one-line found-in-raid/any needed summary. The size line ("1 × 1 • 1 slots") is not shown.
- **Rejected:** keep both (the size adds little next to the per-slot price); drop both (the totals answer "how many do I still need" at a glance).
- **Reversal cost:** low
- **Important:** yes, it changes what users see
- **Chosen by:** user

### S5: Richer Check reason for unknown found in raid

- **Choice:** when found in raid is the first open question, the reason names the first need that requires a found-in-raid item. With no such need, it keeps today's wording.
- **Rejected:** list every open question, mockup style (long, likely to wrap); leave the wording as it is (the line repeats the control).
- **Reversal cost:** low
- **Important:** yes, it changes text users see and amends a spec scenario
- **Chosen by:** user

### S6: detect-found-in-raid stays separate

- **Choice:** this change leaves room for a value-source label beside Found in raid but adds no detection. `detect-found-in-raid` is the next change after M8.5 (roadmap, 2026-11-10).
- **Rejected:** fold detection in. It needs an ADR, a capture-band change, measured offsets and an owner-supplied screenshot set, and would hold the layout fix back.
- **Reversal cost:** low
- **Important:** yes, it binds the next change
- **Chosen by:** user

## Release Notes

The Scanner now matches the approved Ember layout. Found in raid sits next to the verdict, the strip shows Flea, per-slot and trader prices, and the main column shows why an item is needed, its prices and the scan evidence, instead of one near-empty card. Recent items is a flat list that is never cut off. The top bar is tidier on both areas.

### Changed
- Scanner: Found in raid beside the verdict, a full price block in the strip, and Why, Prices and Scan evidence in the main column instead of inspector accordions (#105).
- The Check reason now says which need requires a found-in-raid item (#105).
- Top bar: one Map/Scanner switch, a narrower search, and Stats, Import and Settings as quiet buttons (#105).

### Removed
- Scanner's data-sources panel and the item size line. Freshness is in Prices and the status bar, and the progress refresh is in Settings (#105).
