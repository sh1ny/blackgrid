# Design

## Triage

| Trigger | Applies? | Evidence |
|---|---|---|
| T1 Components (new component, or 3+ with directed relationships) | No | No file under `lib/`, `test/`, `assets/`, `windows/` or `tool/` changes; the change adds documents, a copied brand kit and screenshots. `brand/flutter/*.dart` is outside `lib/` and is not compiled or imported. |
| T2 State (persistent state, caches, 3+ state machine) | No | No app state, preference key or database table is added. The theme switch and its saved setting are design intent for `adopt-ember-theme`, not built here. |
| T3 Concurrency (background work, workers/isolates, async, retries) | No | No code runs. |
| T4 Boundaries (data format, migration, shared interface, IPC, external) | No | `DESIGN.md` and `.impeccable/design.json` are design documents read by the impeccable skill, not by the app or its build. The shared kit in `brand/` is a copy; the Mythspine repository is not touched. |
| T5 Volume (grows without a fixed bound) | No | A fixed set of files: about 0.5 MB in `brand/` and 17 screenshots. |
| T6 Risk (security, money, data loss, unrecoverable user data) | No | The screenshots were taken read-only against the owner's profile; two local folder paths are blacked out and no token is visible (`.impeccable/review/current/PROVENANCE.md`). Nothing writes user data. |

TIER: LIGHT

## Context

See `proposal.md` for the scope. The design authority this change creates is `DESIGN.md`. Its shared part is `brand/BRAND.md` unchanged apart from the name, description and one Overview paragraph. Its Blackgrid part is the "Blackgrid extensions" section (X1–X14) and the "Owner decisions (2026-11-06)" table. The before state is `.impeccable/review/current/DESIGN.before.md` with `PROVENANCE.md` and the screenshots.

Today's styling lives in `lib/ui/theme.dart` (`GridColors`, one gold accent for about 12 roles, Segoe UI). The map's colours are fixed by ADR-0023 (`docs/adr/0023-project-authored-map-marker-icons.md`): a cyan highlight band of 170–190°, a gold quest role `#dcc05a`, an amber loot role `#e8a04a`, a `#090f0d` badge background and an at-least-3:1 contrast check. D3 below decides to change parts of that. The ADR stays in force until `restyle-map-workspace` supersedes it during apply. Until then, nothing in this change contradicts the running app.

The owner answered the open questions on 2026-11-06. Every decision below except D2's values, D10 and D12's colour proposal is the owner's. D11–D15 come from the owner's second review of Direction B the same day, on the mock-up `.impeccable/preview/ember-directions.html`; the owner approved its round 2 B view as settled.

## Decisions

### D1: Verdict text gets its own 22px role

- **Choice:** Add a Verdict type role (Geist 600, 22px, line height 1.2) used only for the verdict word and its price on a verdict plate. The plate grows from 34px to 44px. This is an approved exception to Ember's 13px Flat Chrome Scale Rule, for Blackgrid only.
- **Rejected:** Keep the 13px cap and rely on the plate's fill, because the verdict has to be read at a glance from a second monitor or right after an alt-tab. Setting the verdict in Literata Headline was also rejected, because the verdict is the tool speaking, not the subject.
- **Reversal cost:** low (one token, in documents only)
- **Important:** yes (changes what users see; widens a shared rule)
- **Chosen by:** user

### D2: Keep is green, through a new green set in both rooms

- **Choice:** Keep and Keep for later use a new green set built on Ember's Saved Green hue: `ok-fill`, `ok-on-fill`, `ok-bg`, `ok-line`, `ok-ink` and `ok-strong`, each with a light value. Keep is a solid plate (dark `#6fcf8e` with `#0c0c0e`, 10.2:1; light `#1f6b3b` with white, 6.5:1). Keep for later uses the tinted set (`ok-strong` on `ok-bg`: dark 12.6:1, light 8.8:1). The values and contrast figures are the agent's; the owner chose green.
- **Rejected:** Keep as an inverted Ink plate with no hue, the first draft, because green is the signal players expect and the owner approved widening Saved Green's role. Reusing the single `ok` token for every green surface was also rejected, because it gives no tinted fill or readable text tone in the light room (`#2f9a57` on white is 3.6:1).
- **Reversal cost:** low
- **Important:** yes (changes what users see; widens a shared token's role)
- **Chosen by:** user (green); agent (values)

### D3: Selection on the map is Ember, and the amber map roles move

- **Choice:** The selected marker, extract or pin is drawn in Ember instead of ADR-0023's cyan band. The quest and loot roles move off the amber band, so amber on the map means only "selected". The badge background, the other roles and the 3:1 check stay. `restyle-map-workspace` writes a new ADR superseding these parts of ADR-0023 and picks the new role values.
- **Rejected:** Treating the map canvas as subject content with its own palette, because then Ember would mean "selected" in the chrome and "loot" on the map, and the family would read inconsistently. Writing the superseding ADR in this change was also rejected: ADRs are written during apply, alongside the code they govern, and this change has no map code.
- **Reversal cost:** medium (marker colours, a pack-independent painter change and an ADR)
- **Important:** yes (binds a future change; changes what users see; supersedes an accepted ADR)
- **Chosen by:** user

### D4: Item and map names use the serif

- **Choice:** The item being judged and the map being read are Ember's "subject on screen", so their names take Literata's Display, Headline and Title roles. Tool output stays Geist, and the player's own words (pin labels and notes) are Literata.
- **Rejected:** All-Geist apart from pin labels and notes, which would leave the serif almost unused and weaken the family resemblance to Mythspine.
- **Reversal cost:** low
- **Important:** yes (changes what users see)
- **Chosen by:** user

### D5: The brand lockup is exempt from the sentence-case rule

- **Choice:** The hex logo, the "BLACKGRID" wordmark and the "TRACK. PLAN. SURVIVE." tagline form one brand asset and keep their tracked capitals, in the top bar and on the startup screen only (DESIGN.md X9).
- **Rejected:** Recasting the wordmark as "Blackgrid" in sentence case and dropping the tagline from the chrome. That would change an established brand mark to satisfy a chrome rule.
- **Reversal cost:** low
- **Important:** yes (changes what users see)
- **Chosen by:** user

### D6: Both rooms ship, with a System/Dark/Light switch

- **Choice:** The redesign ships Ember's dark and light rooms, plus a three-option switch in Settings that defaults to System. The map ground stays dark in both (DESIGN.md X6, X8).
- **Rejected:** Designing both rooms but shipping only dark, which would leave the light room unproven and still a separate piece of work later.
- **Reversal cost:** medium (a saved setting and a second set of colour checks in every later UI change)
- **Important:** yes (changes what users see; binds future changes, which must work in both rooms)
- **Chosen by:** user

### D7: Direction B, "Answer strip"

- **Choice:** Keep Map and Scanner, switched from the top bar, and put one answer strip under the top bar on both: the item, verdict, reason, price and freshness. Details, settings, marker preferences, pins and history open on demand (DESIGN.md X10, with the Answer First Rule, X7).
- **Rejected:** A, "Workbench": Ember's full frame with an icon rail, sidebar and docked inspector. It looks most like Mythspine but is the costliest and puts more chrome between the player and the answer. C, "Split companion": Map and Scanner side by side. It is the densest, but it shrinks the map and doubles what the eye has to search.
- **Reversal cost:** medium (shell layout across both areas)
- **Important:** yes (binds the M8.5 changes; changes what users see)
- **Chosen by:** user

### D8: The widenings live in Blackgrid's DESIGN.md only

- **Choice:** The widenings approved in D1, D2, D3 and D5 are recorded in this repository's DESIGN.md as approved family extensions. `brand/` stays an unchanged copy of the kit, and the Mythspine repository is not touched.
- **Rejected:** Adding the widenings to the shared kit now, which would change Mythspine without a change of its own.
- **Reversal cost:** low (they can be moved into the kit later)
- **Important:** yes (binds future changes: later kit refreshes must keep the extensions)
- **Chosen by:** user

### D9: PRODUCT.md keeps `## Platform: web`

- **Choice:** Keep `web`, the nearest value impeccable's platform field accepts, with a note that Blackgrid is native Windows Flutter. `impeccable doctor`'s `platform-native-evidence` mention stays open as a known exception.
- **Rejected:** `adaptive`, which loads iOS and Android guidance that does not apply to a Windows desktop app.
- **Reversal cost:** low
- **Important:** no
- **Chosen by:** user

### D10: The plan edits travel in this change

- **Choice:** The M8.5 roadmap entry and the STRATEGY.md brand line are edited on this change's branch and land with its PR.
- **Rejected:** A separate plan-only commit merged to `main` locally. This worktree is not the main checkout, and the milestone, its first change and the brand line it replaces belong together for review.
- **Reversal cost:** low
- **Important:** no
- **Chosen by:** agent

### D11: Direction B keeps every working control of today's app

- **Choice:** The owner's review of the first B mock-up found seven things it had lost. They all come back in B's idiom (DESIGN.md X11–X14, rows R1–R7): the project's marker icons on the map and in the marker list, with a switch per marker type; a map picker on the map; all three raid timers; item pictures in history; labelled Settings, Stats and Import buttons; a home for every setting that leaves the rails; and the marker, quest and trader filters.
- **Rejected:** The first mock-up's colour dots, its four quick marker groups and its hidden settings. They read cleaner but drop features players use every raid.
- **Reversal cost:** low (documents only)
- **Important:** yes (binds the M8.5 changes; changes what users see)
- **Chosen by:** user

### D12: Raid timers sit in the top bar

- **Choice:** Time in raid, run-through and scav cooldown sit in the top bar beside the Settings, Stats and Import buttons, with the run-through value in the warning colour while it counts down (X11).
- **Rejected:** The status bar, which is quieter but easy to miss on a second monitor.
- **Reversal cost:** low
- **Important:** yes (changes what users see)
- **Chosen by:** user

### D13: Marker switches only in the Map inspector

- **Choice:** Every marker type is switched on and off in the Markers section of the Map inspector, with its icon, name, count and a switch, and Show all / Hide all (X13). The map itself has only the map picker, the floor control and zoom. The quest and loot colours in the mock-up (`#8cb4ff`, `#7ed9c6`) are the agent's proposal for D3's ADR, not a decision.
- **Rejected:** Also keeping four or five quick marker buttons on the map for when the inspector is closed: they cover the map and repeat the list.
- **Reversal cost:** low
- **Important:** yes (changes what users see)
- **Chosen by:** user (layout); agent (colour proposal)

### D14: Marker and quest filters stay separate from item search

- **Choice:** The top-bar search finds items on both areas. The Map inspector has its own "Find markers", "Quest name contains" and trader chips above the marker list (X13).
- **Rejected:** One search box that also finds markers and quests on the Map area. It would mix two kinds of results and weaken "find an item" as the first action.
- **Reversal cost:** low
- **Important:** yes (changes what users see)
- **Chosen by:** user

### D15: Settings is a full page

- **Choice:** Settings opens as a page with a section list (General, Live scan, Item data, Tracker progress, Game files, Raid timers, Map) in place of the strip and main column, keeping the top and status bars (X12). Found in raid stays beside the verdict, and the marker controls stay in the Map inspector. Game mode and live scan can also be changed from the status bar. Stats and Import stay dialogs.
- **Rejected:** The current Settings dialog made larger: seven sections would scroll inside a dialog.
- **Reversal cost:** medium (a new page and navigation state)
- **Important:** yes (changes what users see; binds `restyle-dialogs`)
- **Chosen by:** user

### Decision summary

| # | Decision | Choice | Rejected | Reversal cost | Important | Chosen by |
|---|---|---|---|---|---|---|
| S1 | Setup only, no app code | Documents, kit, record; `lib/` untouched | Wire `ember_theme.dart` now | low | yes | user |
| S2 | Shared tokens unchanged; owner-approved widenings | Extensions plus four approved widenings, Blackgrid only | Change the shared kit; refuse every widening | medium | yes | user |
| S3 | New milestone M8.5 | After M8, before M9; this change carries the entry | Fold into M8; after M9; unplanned | low | yes | user |
| S4 | Ember supersedes STRATEGY's brand line | Replace the line in this change | Keep both lines | low | yes | user |
| S5 | Before record beside the screenshots | `.impeccable/review/current/DESIGN.before.md` | Overwrite DESIGN.md; put it in `docs/` | low | no | agent |
| D1 | Verdict type role | Geist 600 22px on a 44px plate | 13px cap; Literata Headline | low | yes | user |
| D2 | Green for Keep | Green set in both rooms; Keep solid, Keep for later tinted | Hue-less inverted Keep; single `ok` token | low | yes | user (values: agent) |
| D3 | Map selection | Ember selection; quest and loot off amber; ADR in `restyle-map-workspace` | Map keeps its own palette; ADR now | medium | yes | user |
| D4 | Item and map names | Literata title roles | All-Geist | low | yes | user |
| D5 | Brand lockup | Exempt, top bar and startup only | Sentence-case wordmark | low | yes | user |
| D6 | Light room | Ship both, System/Dark/Light switch | Dark only | medium | yes | user |
| D7 | Redesign direction | B, Answer strip | A Workbench; C Split companion | medium | yes | user |
| D8 | Where widenings live | Blackgrid DESIGN.md only | Shared kit now | low | yes | user |
| D9 | Platform field | Keep `web`, doctor note open | `adaptive` | low | no | user |
| D10 | Plan edits | In this change's PR | Separate local merge to `main` | low | no | agent |
| D11 | B keeps today's working controls | Marker icons and switches, map picker, timers, history pictures, labelled tools, Settings home, filters | First mock-up's dots, quick groups, hidden settings | low | yes | user |
| D12 | Raid timers | Top bar | Status bar | low | yes | user |
| D13 | Marker switches | Map inspector only; colours proposed for the ADR | Also quick buttons on the map | low | yes | user (colours: agent) |
| D14 | Marker and quest search | Own filters in the Map inspector | One shared search box | low | yes | user |
| D15 | Settings | Full page with sections | Larger dialog | medium | yes | user |
