# Blackgrid Roadmap

Strategy: [STRATEGY.md](../STRATEGY.md) · Architecture: [architecture.md](architecture.md) · Historical source: [implementation strategy §11–§12](../docs/IMPLEMENTATION_STRATEGY.md#11-migration-plan)

<!-- Status is derived: a change is done when archived; a milestone is done when its changes are done and its exit criteria pass. Do not add status checkboxes for changes. -->

Milestone IDs keep the implementation strategy's numbering (M0–M6), so they match the CE-era plans and qualification evidence. M2 and M3 were planned as independent after M1; M5 was explicitly authorized before the Scanner milestones ([§11](../docs/IMPLEMENTATION_STRATEGY.md#11-migration-plan)). "(user)" marks a criterion only the user can verify: anything that needs the game running, a real saved game screenshot, or a clean Windows machine. Agents never run those checks ([AGENTS.md](../AGENTS.md)). Until the user reports a result, it is unverified, never passed.

A change that names a GitHub issue resolves it through its PR: the PR description links the issue with a closing keyword (`Closes #41`), so merging the PR closes the issue, and the PR's body says what of the issue it delivers. If the PR delivers only part of the issue, it links it with `Refs #N` instead, and the issue says what is left.

## Now: M10 - alerts

Planned with the user on 2026-10-30. The split below was agreed at the M8.5 close on 2026-11-10 and kept at the M9 close on 2026-11-20.

**Exit criteria** (drafted at the M9 close):
- Each alert (match found, raid starting, run-through over, scav ready, air filter on and off, quest-items reminder, restart-failed-tasks) fires once from its raid lifecycle, timer or progress event, has its own switch, plays the default or the player's custom sound, and has a test button. Proved by fake-clock and fixture tests with a fake audio port. (agent)
- Screenshot cleanup is off by default; when switched on it deletes only that raid's screenshots, only after the raid ends, and never touches other files. Proved by offline tests on a temp folder. (agent)
- The alerts sound right and fire at the right moments in play, and screenshot cleanup removes a real raid's screenshots. (user)

**Changes** (in order):
1. `add-audio-alerts` - match found, raid starting, run-through over, scav ready, air filter on and off, quest-items reminder and restart-failed-tasks, each with a switch, a custom sound and a test button. The user decides how the default sounds are recorded before this starts.
2. `refactor-shared-objective-rules` - one "objective done" rule in `lib/domain` for the quest checklist and the alerts, and one timer-deadline function for the timer strip and the alerts; behaviour unchanged. Added by the owner on 2026-11-21 from the weekly architecture review (candidates 2 and 3, narrow parts only).
3. `add-screenshot-cleanup` - opt-in, off by default: delete a raid's screenshots after it ends.
4. `update-map-toolchain` - `vector_graphics_compiler` 1.3.4 to 1.3.6 and `xml` 6.6.1 to 7.0.1, the two updates the weekly dependency runs keep skipping. Run `maps:check` and rebuild only if the pack no longer reproduces. The owner approved compiler-supported filters for app-icon sources on 2026-11-26. Marker icons still forbid filters. `xml` 7.1.0 stays out until `vector_graphics_compiler` lifts its `<=7.0.1` cap. Added by the owner on 2026-11-23 from the weekly dependency run (#125).
5. `upgrade-flutter-3-50` - Flutter 3.47.9 to 3.50.1, which pins `test_api` 0.7.14 and so lets `test` move to 1.32.0 (root and `blackgrid_progress`) and `build_runner` to 2.17.1 (needs `analyzer` 14.3 or later). Includes the toolchain lines in the README, notices and `openspec/config.yaml`, the qualification tier and an install check (user). `test` 1.33.0 waits for a Flutter release that pins `test_api` 0.7.15. Added by the owner on 2026-11-23 from the weekly dependency run (#125).
6. `fix-terminal-transit-map` - corrective entry from #129, added by the owner on 2026-11-24. Transit raids on Terminal counted as "Unknown map": the transit table had no Terminal or Labyrinth location, the scene table did not know `terminal_preset`, and an unsupported scene erased a known map while loading. Both tables now cover every supported map, and an unsupported scene keeps the known map. Advances no M10 exit criterion.
7. `fix-future-log-freshness` - use one freshness rule for alerts and screenshot cleanup. Reject log times in the future in `isFreshLogTime` and remove cleanup's separate check, as [ADR-0048 D8](../docs/adr/0048-screenshot-cleanup-recycles-a-raids-screenshots-through-a-runner-channel.md) calls for the existing alerts rule. Advances no M10 exit criterion. Added by the owner on 2026-11-28 from the weekly architecture review.

## Next: M11 - quest planning

**First change:** `refactor-map-floor-state` - one pure module in `lib/domain` holds the selected floors, the Auto flag and the resolved player floor. `MapController` keeps one state per map; the workspace and floor rail read it. Behaviour stays the same except that, with Auto on, a player position received before the map loads applies as soon as the map binds. Expose one public function for marker ownership: an explicit floor owner wins; otherwise classify by position. Use or remove the unused `MapFloorSelection` members `followPosition`, `selectableFloors`, `overlays` and `select()`. Floor keys and focus stay where they are. Added by the owner on 2026-11-28 from the weekly architecture review.

The player sees how to reach the quests they want. A quest tree draws each trader's quests as a prerequisite graph: selecting a quest traces the path that unlocks it, a search finds which quest rewards an item, and right-click sets a quest's state by hand. A next-quest suggestion gives its reasons: what the quest unlocks, whether it counts toward Kappa or Lightkeeper, and whether it can be finished now. The milestone also shows Kappa, Lightkeeper and trader loyalty progress. Builds on M9's rules.

## Later

The milestones below run in this order after M11, starting with M12. M11–M19 were added on 2026-11-01 from the user's future-ideas list.

**Rules for M9 and everything below** (user decisions 2026-11-01): nothing is drawn over the game. "Stay on top" for Blackgrid's own opaque window is allowed; a transparent, borderless or click-through map is not. No global in-game hotkeys whose only job is to drive such a map. There are no squad features (shared positions, item needs or raid planning) and no live position on a phone. The desktop app needs no server and no account. Features use only the game's log files, the screenshot folder, the player's own input and public tarkov.dev data.

### M12 - hideout

- An overview of all stations with their levels and upgrade requirements, the bonuses scaled by Hideout Management, and a history of finished crafts.
- Every craft the built stations can run, ranked by profit per craft and per hour, with favourites and an item filter. Inputs are costed by the cheapest cash or barter route, and outputs at the Flea price after fees. The Flea fee is one shared calculation: tarkov.dev's current fee rates and base prices, scaled by the Intelligence Center level and Hideout Management. The M15 sales ledger reuses it ([#87](https://github.com/sh1ny/blackgrid/issues/87)).
- Timers the player starts by hand for crafts, the Bitcoin Farm, the Water Collector filter and the Scav Case, with a "ready to collect" alert. The game logs no craft events: craft actions go out as the generic `items/moving` request with no body in the logs, and there are no hideout notifications (checked in the user's logs on 2026-11-01). Trader restocks are not logged either.

Builds on M9's hideout levels.

### M13 - map comfort

- `refactor-settings-write-path` - before the map comfort work, give Settings one write path and put each section behind its own interface. Queue a second edit while a save is running instead of refusing it; update the refusal test in `test/application/app_services_test.dart`. The owner first chose this for `add-screenshot-cleanup` on 2026-11-21, but it did not land there. Added by the owner on 2026-11-28 from the weekly architecture review.
- Each map keeps its own marker filters and sizes, restored when it opens, with a reset button. The player and quest markers get their own sizes.
- A few one-click temporary markers that clear at raid end.
- Rebindable "jump to player" and "fit map" keys that work only when Blackgrid's window has focus.
- A setup and troubleshooting guide in the app and the README, extending M8's help button. It covers the screenshot key (Steam players should avoid F12), the logs folder, OneDrive moving screenshots, the launcher's "Clear Cache" deleting old logs, and the Windows "unknown publisher" warning.

Small and independent, so it can move earlier if wanted.

### M14 - loot, extracts and keys

- A loot filter by item, showing only the places a chosen item can spawn and combining with the container filters, plus the items each container type can hold. How much of this is possible depends on tarkov.dev's spawn data.
- Each extract's requirements: time of day, faction, required items and switches. Extracts the player cannot use now are drawn differently, and a filter shows only PMC, Scav or co-op exits. Builds on M8's popups and faction colours.
- The player marks the keys they own, stored with their progress, and the Locks list and the map highlight the doors those keys open.

### M15 - stats and traders

- A wipe summary: quests over time and per trader, quest XP and roubles earned, craft profit, and the found-in-raid items the hideout still needs. It can be exported as an image.
- Raid history from the logs: raids per map and per week, the most played map and the busiest day. Queues that never became raids can be removed. Extends M7's local stats.
- A trader browser with stock, prices, resale profit per unit and per restock, favourites, hidden items and restock timers started by hand.
- A Flea sales ledger ([#87](https://github.com/sh1ny/blackgrid/issues/87)), its own change: every sale with time, item, count, buyer, roubles received, the listing fee and net profit. The fee comes from M12's calculation and is shown as an estimate. A posted offer's whole fee counts once, even when only part of the offer sells. Stats from the player's own sales only: their best items and periods per wipe, and their top items in each period (week of wipe, day of week, time of day). Reading the exact fee from the offer screen is a possible later addition. Extends M7's local stats.

### M16 - portable progress

Progress moves between machines without a server. First comes export and import of a progress file, then sync through a folder the player already has (OneDrive, Dropbox). Conflicts are settled by M9's newest-change-wins rule.

### M17 - Blackgrid Service

An optional hosted service that holds only the progress event history, for players who want the web and mobile apps. The desktop app keeps working fully without it. It needs before launch:

- sign-in with passkeys or a trusted identity provider so we store no passwords if we can avoid it, two-factor sign-in if passwords are used, and a separate revocable sign-in per device, kept in Windows' protected storage;
- encryption in transit and at rest, with per-account access enforced on the server;
- rate limits and abuse protection, and security logging that stores no more personal data than needed;
- account export and deletion (GDPR);
- dependency and secret scanning in CI, and a security review;
- a plan for hosting, domain, email, backups, monitoring, support and running costs (donations or supporter tiers).

It never holds game logs, screenshots, scan images or anything else from the player's PC.

Starts only once the desktop features are solid and the cost plan exists.

### M18 - Blackgrid Web

A Flutter web app built on M9's rules package. It covers quests, objectives and counters, hideout levels, needed items and keep/sell lists, Kappa and Lightkeeper progress, the quest tree, owned keys and timers started by hand. It has no live position, no scanner and no log reading. Whether it gets a planning map without position is still open. Needs M17.

### M19 - Blackgrid Mobile

A Flutter phone app with the web app's scope and small-screen layouts, built after the web app proves the sync. Needs M17.

### Other

- `add-window-behaviour` - tray, stay on top and start minimized. Moved out of M10 by the owner on 2026-11-26.
- Goons reports to tarkov.dev (a one-click, confirmed report that sends the map, mode, raid time and account ID). Deferred by the user on 2026-10-30.
- After 1.0: the issues the M4.6 sweep defers to after 1.0.
- Needs testers besides the user (moved out of M6 on 2026-10-30):
  - Clean-machine qualification of the release bundle: packaged DLLs, models, artwork and notices on a fresh Windows machine.
  - The full display and mixed-monitor matrix. The M2 corpus covers 3440×1440 only.
  - The user-only checks M3 waived and M5 left pending: real saved panels, extract and transit highlights, and automatic floors.
  - The [§14](../docs/IMPLEMENTATION_STRATEGY.md#14-definition-of-done) definition of done, which depends on the checks above.

## Release versioning (`add-release-versioning`)

Decided with the user on 2026-10-08 and recorded in [ADR-0009](../docs/adr/0009-release-versioning.md): SemVer `v` tags, `-beta.N` prereleases for user-only checks, and a commit-count build number. Its changelog with one entry per merged PR was replaced by release notes taken from each change's proposal ([ADR-0029](../docs/adr/0029-release-notes-come-from-each-proposal.md)). Its one minor version per milestone close was dropped on 2026-11-25: the owner decides when to release, and a release can come in the middle of a milestone ([ADR-0051](../docs/adr/0051-releases-are-timed-by-the-owner.md)).

Release flow (local steps; details in the [README](../README.md)):

- `mise run release:prepare -- <version>` - checks a clean, current `main`, runs the offline gates, then commits `chore(release): v<version>` on `release/v<version>`.
- `mise run release:tag` - after the release PR merges, tags the merge `v<version>` and pushes the tag as the configured GitHub login.
- `mise run build:release` - builds the Windows Release bundle with the version and build number, then runs `bundle:check`.
- `mise run release-notes` - previews the next release's notes, built from the archived proposals' `## Release Notes` sections ([ADR-0029](../docs/adr/0029-release-notes-come-from-each-proposal.md)); `release:prepare` then needs a release summary.

M6 moved the builds to CI: a pushed `v` tag publishes a GitHub Release with a zip and an installer ([ADR-0024](../docs/adr/0024-hosted-ci-runs-every-offline-gate.md), [ADR-0025](../docs/adr/0025-release-packaging.md), [ADR-0026](../docs/adr/0026-releases-published-by-a-tag-workflow.md)). Code signing waits on [#66](https://github.com/sh1ny/blackgrid/issues/66).

## Done

- M0 - reference qualification and provenance - 2026-10-06 ([PR #1](https://github.com/sh1ny/blackgrid/pull/1), [PR #2](https://github.com/sh1ny/blackgrid/pull/2)) - [plan](../docs/plans/2026-10-05-1006-test-m0-reference-qualification-plan.md), [evidence](../docs/qualification/m0/) - Delivered the rights-gated dossier, protocol and validators. The reference baseline, labelled corpus and display matrix remain unverified or blocked; that did not block authoring new code, and the remaining checks now sit in M2, M4 and M6.
- M1 - shared shell and decision foundation - 2026-10-06 ([PR #3](https://github.com/sh1ny/blackgrid/pull/3)) - [plan](../docs/plans/2026-10-06-0242-feat-m1-manual-item-decisions-plan.md), evidence: no `docs/qualification/` record; offline tests and [`integration_test/m1_windows_smoke_test.dart`](../integration_test/m1_windows_smoke_test.dart) - The conservative decision engine, mode-scoped catalog, read-only Tracker and DPAPI credentials landed as pure, testable layers that Scanner can reuse.
- M3 - native map proof - 2026-10-06 ([PR #4](https://github.com/sh1ny/blackgrid/pull/4)) - [plan](../docs/plans/2026-10-06-1026-feat-m3-native-map-proof-plan.md), [evidence](../docs/qualification/m3/STATUS.md) - The native renderer was proven on Interchange, Labs and Icebreaker and chosen over a WebView. Delivered under the user's explicit verification waiver: full qualification is not claimed.
- M5 - complete useful native Map - 2026-10-07 ([PR #7](https://github.com/sh1ny/blackgrid/pull/7)) - [plan](../docs/plans/2026-10-07-0050-feat-m5-independent-useful-map-plan.md), [evidence](../docs/qualification/m5/STATUS.md) - All 13 maps were promoted and the user's live map/position check passed. Functional parity with the user's reference companion replaced stricter blocking gates (publisher-deleted `<use>` ids, Windows.Media.Ocr for raid panels). The real saved-panel check is still pending. (user)
- M2 - capture/recognition proof - 2026-10-17 ([PR #9](https://github.com/sh1ny/blackgrid/pull/9), [PR #18](https://github.com/sh1ny/blackgrid/pull/18), [PR #22](https://github.com/sh1ny/blackgrid/pull/22), [PR #26](https://github.com/sh1ny/blackgrid/pull/26), [PR #27](https://github.com/sh1ny/blackgrid/pull/27), [PR #31](https://github.com/sh1ny/blackgrid/pull/31), [PR #32](https://github.com/sh1ny/blackgrid/pull/32), [PR #35](https://github.com/sh1ny/blackgrid/pull/35)) - [corpus runner](../docs/qualification/m2/CORPUS.md), evidence in the archived [`fix-title-crop`](changes/archive/2026-10-17-fix-title-crop/evidence.md) - Agent checks passed on `0.1.0+301` (bundle check, native barrier and capture-geometry fixtures, notices). The user passed the clean-machine check, the independently labelled 50-case 3440×1440 corpus and the live retest (session `20261017-130909`: 7 live accepts, no false positives, no dropped triggers). Corpus result: 31/35 items, 2 false positives, 15/15 rejects; the user waived the reference comparison because no reference baseline exists. Learned: recording live scans finds failures that hand screenshots missed (it exposed the trigger timing and title crop bugs), and every accept still comes from the full-client fallback, so placing the targeted region is M4's first change.
- M4 - complete raid-time Scanner slice - 2026-10-20 ([PR #37](https://github.com/sh1ny/blackgrid/pull/37), [PR #39](https://github.com/sh1ny/blackgrid/pull/39), [PR #42](https://github.com/sh1ny/blackgrid/pull/42), [PR #44](https://github.com/sh1ny/blackgrid/pull/44), [PR #45](https://github.com/sh1ny/blackgrid/pull/45), [PR #46](https://github.com/sh1ny/blackgrid/pull/46), [PR #47](https://github.com/sh1ny/blackgrid/pull/47)) - [evidence](../docs/qualification/m4/EVIDENCE.md) - Agent checks passed. The user's live session on `0.1.0+323` passed the targeted-share, latency, live hotkey and Map checks: with the mouse, 74.6% of accepts came from the targeted pass, targeted trigger to decision was 139.6 ms p95 and the total was 572.4 ms p95. The hotkey figures were below 20 samples and the user accepted them. The user waived the reference timing baseline and the reference corpus comparison: Blackgrid feels responsive and uses less CPU and memory than the reference companion, which they no longer run. Learned: centring the targeted region on the inspect window made the targeted pass the common path, and shared display names now end `ambiguous` instead of being false positives (ADR-0021). Some targeted passes still read the stash's filter button ([#48](https://github.com/sh1ny/blackgrid/issues/48)).
- M4.5 - player-facing polish, item icons and own map markers - 2026-10-29 ([PR #50](https://github.com/sh1ny/blackgrid/pull/50), [PR #51](https://github.com/sh1ny/blackgrid/pull/51), [PR #53](https://github.com/sh1ny/blackgrid/pull/53), [PR #54](https://github.com/sh1ny/blackgrid/pull/54), [PR #56](https://github.com/sh1ny/blackgrid/pull/56), [PR #57](https://github.com/sh1ny/blackgrid/pull/57), [PR #58](https://github.com/sh1ny/blackgrid/pull/58), [PR #59](https://github.com/sh1ny/blackgrid/pull/59)) - Agent checks passed on `main` `da08fdd` (marker provenance check: 19 icons valid; full offline suite and analyze). The user passed the map rail, item icon, requirements & uses and plain-language reads, and the Marker preferences look on re-check after `fix-marker-tile-centering`. Learned: tests that pinned tile size but not position let an off-centre layout through until the user looked, so layout criteria marked "user for the look" also get a geometry widget test where one can prove the invariant.
- M4.6 - open-issue sweep - 2026-10-30 ([PR #60](https://github.com/sh1ny/blackgrid/pull/60)) - The sweep judged all 18 open issues against `main`: #30 was closed as no longer applying, 16 were deferred to after 1.0 with the `post-1.0` label and a recorded reason, and #17 was fixed by `fix-changelog-spec`, which also stopped local `merge:` commits from showing up in the changelog. Learned: judging issues at sweep time, against current `main`, left one fix-now issue out of 18, so review-filed issues are not accepted in advance.
- M6 - Windows CI and releases - 2026-11-01 ([PR #63](https://github.com/sh1ny/blackgrid/pull/63), [PR #67](https://github.com/sh1ny/blackgrid/pull/67), [PR #68](https://github.com/sh1ny/blackgrid/pull/68), [PR #69](https://github.com/sh1ny/blackgrid/pull/69), [PR #70](https://github.com/sh1ny/blackgrid/pull/70), [PR #72](https://github.com/sh1ny/blackgrid/pull/72), [PR #73](https://github.com/sh1ny/blackgrid/pull/73)) - Agent checks passed on `main` `dc636c9`: the `ci` workflow ran every offline gate green on a hosted Windows runner; ADR-0025 records the Inno Setup installer and unsigned builds until #66; the `v0.6.0-beta.1` tag published a prerelease with the zip, the installer and the changelog notes; the committed `.ico` holds all ten sizes from 16 to 256 px; and offline tests prove that failures keep the last good data and that settings, pins, history and imports survive restart. The user picked the `hex_sweep` icon on 2026-10-31 and installed beta.1 from both the installer and the zip on 2026-11-01. Learned: with every gate on a hosted runner, a release no longer depends on the developer's machine, and the restart tests showed that one unreadable row could block startup, so stored data is now decoded one row at a time.
- M7 - raid lifecycle, timers and local stats - 2026-11-02 ([PR #76](https://github.com/sh1ny/blackgrid/pull/76), [PR #77](https://github.com/sh1ny/blackgrid/pull/77), [PR #79](https://github.com/sh1ny/blackgrid/pull/79)) - Agent checks passed on `main` `c2b28f7`: offline fixture tests prove lines and multi-byte text split across reads, both log orders and reconnects; fake-clock tests prove the timers; restart and clear tests prove settings and stats survive. The user reported the raid state line working on `0.6.0+384` (2026-11-01) and the timers and local stats on `0.6.0+386` (2026-11-02, a short test). Learned: reconnects make "the same raid" a cross-cutting rule (lifecycle, timers and stats each had to agree on it), and a mid-raid clear followed by a reconnect and a restart can still recount one raid, accepted as [#80](https://github.com/sh1ny/blackgrid/issues/80).
- M8 - map labels and popups - 2026-11-08 ([PR #84](https://github.com/sh1ny/blackgrid/pull/84), [PR #86](https://github.com/sh1ny/blackgrid/pull/86), [PR #88](https://github.com/sh1ny/blackgrid/pull/88), [PR #90](https://github.com/sh1ny/blackgrid/pull/90), [PR #91](https://github.com/sh1ny/blackgrid/pull/91), [PR #94](https://github.com/sh1ny/blackgrid/pull/94), [PR #95](https://github.com/sh1ny/blackgrid/pull/95)) - Agent checks passed in CI on the merged tree of `main` `7559767` (offline suite, map pack check and qualification), covering the extract label and outline painter tests, the marker bubble widget tests and the place label pack and painter tests. The user reported extract names, outlines and the map help working on `0.7.0+399` (2026-11-02), and the place labels and marker bubbles reading correctly on real maps (2026-11-08). Learned: the generation-backed rebuild with its per-map change report turned each pack change (toolchain, metadata, labels) into a reviewable regeneration, and the owner checks only the maps it lists; the full-rebuild qualification tests needed their own 10-minute timeout on CI.
- M8.5 - Ember interface - 2026-11-10 ([PR #93](https://github.com/sh1ny/blackgrid/pull/93), [PR #97](https://github.com/sh1ny/blackgrid/pull/97), [PR #98](https://github.com/sh1ny/blackgrid/pull/98), [PR #100](https://github.com/sh1ny/blackgrid/pull/100), [PR #102](https://github.com/sh1ny/blackgrid/pull/102), [PR #103](https://github.com/sh1ny/blackgrid/pull/103), [PR #104](https://github.com/sh1ny/blackgrid/pull/104), [PR #105](https://github.com/sh1ny/blackgrid/pull/105)) - Agent checks passed on `main` `0af350f`: the offline suite (3023 tests) covers the Ember rooms and theme switch, the six verdict plates, the strip geometry at wide and 960 px, the Settings page, the diagnostics moved off Map and Scanner, and the B-view Scanner. ADR-0039 covers the map role colours, and Geist and Literata are bundled with their OFL texts in the third-party notices. The owner signed off the Scanner against the B view and checked both rooms on a second monitor and alt-tabbed (2026-11-10), with follow-up fixes queued as `polish-ember-ui`. Learned: the Scanner shipped with its old inspector until the owner compared it with the mockup, so the milestone grew a seventh change. Widget tests draw text in the Ahem font, which overstates width, so layout checks that depend on width now load the real fonts.
- M9 - local progress tracker - 2026-11-20 ([PR #109](https://github.com/sh1ny/blackgrid/pull/109), [PR #110](https://github.com/sh1ny/blackgrid/pull/110), [PR #111](https://github.com/sh1ny/blackgrid/pull/111), [PR #112](https://github.com/sh1ny/blackgrid/pull/112), [PR #113](https://github.com/sh1ny/blackgrid/pull/113), [PR #114](https://github.com/sh1ny/blackgrid/pull/114), [PR #116](https://github.com/sh1ny/blackgrid/pull/116), [PR #117](https://github.com/sh1ny/blackgrid/pull/117), [PR #118](https://github.com/sh1ny/blackgrid/pull/118)) - Agent checks passed in CI on `main` `38aa0f3` and locally (analyze clean, offline suite of 3310 tests): model tests prove the event store's idempotent replay and newest-change-wins merge; `packages/blackgrid_progress` is plain Dart with fixture and gate tests on frozen tarkov.dev data; offline log fixtures prove task events, wipe replay and its refusal during a raid; found-in-raid fixture tests cover the owner's screenshot set; and no tracker token code remains in `lib`. The owner reported on 2026-11-20 that the log replay matches their in-game quest state, the checklist and manual entry work in play, Found in raid reads correctly on live scans, and the `polish-ember-ui` fixes look right. Learned: building the tracker locally first, with the rules as a plain Dart package, let the token integration go in one last change with nothing left depending on it.
