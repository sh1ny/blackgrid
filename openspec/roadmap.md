# Blackgrid Roadmap

Strategy: [STRATEGY.md](../STRATEGY.md) · Architecture: [architecture.md](architecture.md) · Historical source: [implementation strategy §11–§12](../docs/IMPLEMENTATION_STRATEGY.md#11-migration-plan)

<!-- Status is derived: a change is done when archived; a milestone is done when its changes are done and its exit criteria pass. Do not add status checkboxes for changes. -->

Milestone IDs keep the implementation strategy's numbering (M0–M6), so they match the CE-era plans and qualification evidence. M2 and M3 were planned as independent after M1; M5 was explicitly authorized before the Scanner milestones ([§11](../docs/IMPLEMENTATION_STRATEGY.md#11-migration-plan)). "(user)" marks a criterion only the user can verify: anything that needs the game running, a real saved game screenshot, or a clean Windows machine. Agents never run those checks ([AGENTS.md](../AGENTS.md)). Until the user reports a result, it is unverified, never passed.

A change that names a GitHub issue resolves it through its PR: the PR description links the issue with a closing keyword (`Closes #41`), so merging the PR closes the issue, and the PR's body says what of the issue it delivers. If the PR delivers only part of the issue, it links it with `Refs #N` instead, and the issue says what is left.

## Now: M7 - raid lifecycle, timers and local stats

Promoted from Next at the M6 close on 2026-11-01; the user agreed its split then. Planned with the user on 2026-10-30 from a review of [TarkovMonitor](https://github.com/the-hideout/TarkovMonitor) and [tarkov.dev](https://github.com/the-hideout/tarkov-dev)'s map. The goal is useful feature parity, rebuilt independently: no source code is copied and TarkovMonitor's bugs are not repeated. Blackgrid never looks for the game process; everything below comes from the game's log files, the screenshot folder and the user's own actions.

Blackgrid follows the whole raid from the game's logs, not just the map and mode, shows raid timers in its own window and keeps local stats.

**Exit criteria:**
- `application.log` and `notifications.log` feed one raid state machine covering queue, match found, raid starting and started, matching aborted, raid exit, back in menus, profile select and reconnects. Partial lines, multi-byte text split across reads and the two logs arriving in either order are each proved by offline fixture tests. (agent)
- Time in raid, the run-through countdown and the scav cooldown show in Blackgrid's own window, never on the game screen. Their settings survive restart, and the countdowns are proved by fake-clock tests. (agent)
- Total flea sales and raids per map are stored only in the local database, survive restart and are emptied by the clear button, proved by offline tests. (agent)
- During real raids, the raid state, timers and stats follow the game. (user)

**Changes** (in order):
1. `add-raid-lifecycle` - read the rest of `application.log` (queue, match found, raid starting and started, matching aborted, back in menus, profile select) and `notifications.log` (raid exit, flea sales, task started, failed and finished, which are message types 10, 11 and 12, confirmed in the user's logs on 2026-11-01) into one raid state machine that recognises reconnects. Fixes what TarkovMonitor gets wrong: partial lines across reads, multi-byte text split across chunks, and the raid exit and profile select coming from two logs in either order.
2. `add-raid-timers` - time in raid, the run-through countdown (default 7:10) and the scav cooldown countdown (tarkov.dev's base time, the user's Fence reputation and built hideout bonuses from Tracker progress), shown in Blackgrid's window; no overlay. Settings: run-through length, Fence reputation, timers on or off and which ones show.
3. `add-local-stats` - total flea sales and raids per map, stored locally in the Drift database, with a clear button. Nothing leaves the machine.

## Next: M8 - map labels and popups

The native map reads like tarkov.dev's: named places, labelled extracts and a bubble at the marker on click.

**Split agreed:** 2026-11-01

1. `add-extract-labels` - draw each extract's name beside its badge, coloured by faction (PMC, Scav, shared, transit) in colours we choose (ADR-0023), outlines drawn in their category's colour instead of hazard red, and extract outlines shown on hover or selection. Adds a `?` help button on the map: position tracking needs the game's own screenshot key.
2. `add-marker-popups` - replace the details strip under the map with a bubble anchored to the marker that follows pan and zoom, stays in the viewport and closes. It shows the quest name and objective text, an extract's switches and required item, a lock's type and key name, a container's name, or a boss and spawn chance; raw fields move to a collapsed Details section (`player-facing-text`).
3. `add-location-labels` - carry tarkov.dev's place labels (`maps.json`, already frozen in the pack's evidence: 303 labels on 10 maps) into a new pack version, with a rights note (user decision 2026-10-30: use tarkov.dev's data); draw them on the canvas behind the markers at a fixed screen size, with rotation and a halo, hidden on other floors by height band and thinned when zoomed far out.

## Later

The milestones below run in this order after M8. M9 and M10 were planned with the user on 2026-10-30; M9 was replaced and M11–M19 were added on 2026-11-01 from the user's future-ideas list.

**Rules for everything below** (user decisions 2026-11-01): nothing is drawn over the game. "Stay on top" for Blackgrid's own opaque window is allowed; a transparent, borderless or click-through map is not. No global in-game hotkeys whose only job is to drive such a map. There are no squad features (shared positions, item needs or raid planning) and no live position on a phone. The desktop app needs no server and no account. Features use only the game's log files, the screenshot folder, the player's own input and public tarkov.dev data.

### M9 - local progress tracker

Replaces the planned Tarkov Tracker task sync (user decision 2026-11-01). Blackgrid tracks quest and hideout progress itself, on the player's machine. The tracker is built so sync can be added later, but it syncs nothing. The existing read-only progress-site token stays exactly as it is until this milestone's last change replaces everything it provides.

**Exit criteria:**
- Every progress change is stored as an event with a unique ID, device ID, timestamp, game mode, wipe and data format version, and the current state is computed from the events. Replaying an event twice changes nothing. The newest change per task, objective or station wins, and game-log events beat older manual edits. Proved by model tests. (agent)
- The availability rules are a plain Dart package with no Flutter or Windows dependency. For each task they say done, available or locked, and why: level, trader loyalty, a missing or must-be-failed prerequisite, an alternative task, faction or edition. Proved by tests on frozen tarkov.dev fixtures. (agent)
- Task started, failed and finished events from the logs fill the store per mode and wipe. A log-folder replay rebuilds a wipe and is refused during a raid. Proved by offline fixture tests. (agent)
- Keep/sell advice, the scav cooldown's hideout bonuses and task state come from local progress, and the token integration is removed. (agent)
- A replay of the player's real log folders matches their in-game quest state, and the checklist and manual progress entry work in play. (user)

**Changes** (in order):
1. `add-progress-store` - an ADR for the local tracker and its event format, then the event store in the Drift database: device ID, mode and wipe keys, a format version, newest-change-wins merging, counters stored as values rather than increments, and undo from the event history.
2. `add-task-catalog` - keep more tarkov.dev data: tasks, objectives, prerequisites (including must-be-failed and alternatives), trader and level requirements, faction, Kappa and Lightkeeper flags, and hideout stations and levels. Mode-scoped like the item catalog.
3. `add-task-rules` - the availability rules package. We write the edition rules ourselves.
4. `add-task-log-progress` - take task events from M7's raid lifecycle into the store, and replay old log folders.
5. `add-manual-progress` - the player enters their level, trader loyalty levels and built hideout station levels by hand, and can override any task the logs missed.
6. `add-quest-checklist` - active quests with tickable objectives and +/- counters for kill and found-in-raid objectives. Ticking an objective updates the map's quest markers.
7. `retire-tracker-token` - switch keep/sell advice, the scav timer and task state to local progress, and remove the token integration. Before it starts, the user decides whether to keep a one-time "import my progress" from the site.

**Inputs for `add-progress-store`'s ADR** (from the user's future-ideas list, 2026-11-01):
- **Why our own tracker:** showing tasks, availability, needed items and the hideout has to be built in Blackgrid either way, because a third-party API returns only IDs and states. Syncing with someone else's service adds daily request quotas, tokens the user must create, polling, conflict handling and terms of use, and it still cannot write hideout or trader progress. A local tracker has none of these limits and works offline. Blackgrid never writes to the progress site.
- **Sync-ready from the first release:** tarkov.dev IDs in every key, with game mode and wipe; each app downloads tarkov.dev data itself, so a sync service would only ever hold the player's progress; the rules package gives web and mobile the same answers as the desktop. The extra cost now is one or two tasks in this change, and the event history also gives undo, log replay and the wipe summary.
- **Upkeep:** the availability rules are the hardest part (alternatives, must-be-failed prerequisites, faction and edition rules) and need checking every wipe.

### M10 - alerts and window behaviour

1. `add-audio-alerts` - match found, raid starting, run-through over, scav ready, air filter on and off, quest-items reminder and restart-failed-tasks, each with a switch, a custom sound and a test button. The user decides how the default sounds are recorded before this starts.
2. `add-screenshot-cleanup` - opt-in, off by default: delete a raid's screenshots after it ends.
3. `add-window-behaviour` - tray, stay on top and start minimized.

### M11 - quest planning

The player sees how to reach the quests they want. A quest tree draws each trader's quests as a prerequisite graph: selecting a quest traces the path that unlocks it, a search finds which quest rewards an item, and right-click sets a quest's state by hand. A next-quest suggestion gives its reasons: what the quest unlocks, whether it counts toward Kappa or Lightkeeper, and whether it can be finished now. The milestone also shows Kappa, Lightkeeper and trader loyalty progress. Builds on M9's rules.

### M12 - hideout

- An overview of all stations with their levels and upgrade requirements, the bonuses scaled by Hideout Management, and a history of finished crafts.
- Every craft the built stations can run, ranked by profit per craft and per hour, with favourites and an item filter. Inputs are costed by the cheapest cash or barter route, and outputs at the Flea price after fees.
- Timers the player starts by hand for crafts, the Bitcoin Farm, the Water Collector filter and the Scav Case, with a "ready to collect" alert. The game logs no craft events: craft actions go out as the generic `items/moving` request with no body in the logs, and there are no hideout notifications (checked in the user's logs on 2026-11-01). Trader restocks are not logged either.

Builds on M9's hideout levels.

### M13 - map comfort

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

- Goons reports to tarkov.dev (a one-click, confirmed report that sends the map, mode, raid time and account ID). Deferred by the user on 2026-10-30.
- After 1.0: the issues the M4.6 sweep defers to after 1.0.
- Needs testers besides the user (moved out of M6 on 2026-10-30):
  - Clean-machine qualification of the release bundle: packaged DLLs, models, artwork and notices on a fresh Windows machine.
  - The full display and mixed-monitor matrix. The M2 corpus covers 3440×1440 only.
  - The user-only checks M3 waived and M5 left pending: real saved panels, extract and transit highlights, and automatic floors.
  - The [§14](../docs/IMPLEMENTATION_STRATEGY.md#14-definition-of-done) definition of done, which depends on the checks above.

## Release versioning (`add-release-versioning`)

Decided with the user on 2026-10-08 and recorded in [ADR-0009](../docs/adr/0009-release-versioning.md): SemVer `v` tags, one minor version per milestone close (M2 → `0.2.0`), `-beta.N` prereleases for user-only checks, and a commit-count build number. Its changelog with one entry per merged PR was replaced by release notes taken from each change's proposal ([ADR-0029](../docs/adr/0029-release-notes-come-from-each-proposal.md)).

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
