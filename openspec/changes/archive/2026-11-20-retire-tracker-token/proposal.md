# Proposal

## Why

M9 (local progress tracker) ends with Blackgrid owning the player's progress. The event store, task catalog, availability rules, log ingestion, manual entry and quest checklist are all on main. Keep/sell advice, the scav cooldown's hideout bonuses and task state still read a 15-minute snapshot fetched with a Tracker token, though. Users therefore still need a token, a network call and a third-party account for advice, while the progress Blackgrid records itself goes unused. This change serves the M9 exit criterion "Keep/sell advice, the scav cooldown's hideout bonuses and task state come from local progress, and the token integration is removed" (agent-verified). It is the last switch before the user-verified play check ("a replay of the player's real log folders matches their in-game quest state, and the checklist and manual progress entry work in play"). That check is judged at the M9 close, after `polish-ember-ui`, because it covers the whole tracker and not this change alone.

## What Changes

- Keep/sell advice (Scanner, Map last scan, history recomputation, requirement rows, Flea eligibility) reads the active wipe's local progress for the effective mode instead of the Tracker snapshot. A task, objective or station level with nothing recorded counts as not started, zero or not built. Unset level, faction or edition leaves only the gates that need it unknown. An unbuilt hideout level needs its full item count, and a built level's items are satisfied.
- Local progress has no 15-minute age window. It counts while the mode's active wipe can be read; when it cannot be read, advice says progress is unavailable, as it does today when progress is missing.
- The scav cooldown counts a hideout bonus when the local built level of that station reaches the bonus level.
- **BREAKING:** the Tracker integration is removed: the token field, Save/Remove token, Refresh progress, the Use Tracker progress switch, the Settings Tracker progress section, the status bar's Tracker item, the Tracker HTTP client, the progress controller and its snapshot type. Blackgrid makes no request to the progress site.
- **BREAKING:** on first launch after the upgrade, saved tokens (`%LOCALAPPDATA%\Blackgrid\credentials\*.dpapi`) and the credentials folder are deleted. The runner's DPAPI protect, unprotect and atomic-replace methods are removed. Only the local-data-path method stays.
- The status bar shows a Progress item for the effective mode ("Progress local" or "Progress unavailable"). Activating it opens Settings at Local progress.
- Wording moves from "Tracker progress" to "progress": the open-input reason, evidence and Diagnostics lines. Saved settings and legacy imports that still carry the Tracker switch load without error and ignore it.
- No one-time import of progress from the site is offered (owner decision, 2026-11-19).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `progress-authority`: the Tracker refresh, retry, selection and malformed-response requirements are removed. New requirements make the active wipe's local progress the progress authority for advice and timers, with its unset semantics, hideout counting and unavailable state.
- `raid-timers`: built hideout levels for the scav cooldown come from local progress for the cooldown's mode.
- `local-data-durability`: the damaged-token requirement is removed, and the saved-token clean-up on first launch is added.
- `settings-page`: the Tracker progress section and its token save exception are removed; the section list changes, and the section-link requirement is replaced under a new name for the Progress item.
- `workspace-shell`: the status bar's Tracker item becomes the Progress item, which opens Local progress.
- `settings-diagnostics`: the two requirements naming Tracker errors, update time and cooldown are replaced, under new names, by local progress state.
- `verdict-presentation`: the open-input reason for progress reads "Progress unavailable".
- `player-facing-text`: Tracker progress status labels give way to local progress labels.
- `scanner-evidence`: the Scanner no longer names Tracker controls among those reachable from the status bar or Settings.
- `scan-frame-recording`: case lines hold no progress data; the requirement is replaced under a new name without the Tracker-connected scenario.
- `legacy-import`: an imported Tracker switch is ignored.
- `local-progress`, `manual-progress`, `quest-checklist`, `task-catalog`: their "advice stays on the Tracker" requirements are removed, since this change is the cutover they deferred to.

## Impact

- **Code removed:** `lib/data/tracker_client.dart`, `lib/application/progress_controller.dart`, `lib/domain/progress.dart` (`ProgressSnapshot`), `lib/data/credential_store.dart`, `lib/domain/credential_store.dart`, the Tracker parts of `lib/ui/settings/settings_page.dart`, `settings_section.dart`, `shell.dart`, `labels.dart` and `evidence_panels.dart`, and `trackerEnabled` in `lib/domain/settings.dart` and `import_preview.dart`. The protect, unprotect and atomic-replace methods go from `windows/runner/credential_protector.cpp`, and their tests go too.
- **Code changed:** `DecisionEngine`, `InspectionContext`, `SelectionController`, the raid timers' progress source, `AppServices` wiring, and the local-progress read path (`TaskLogProgressController.readCurrent`, `LocalProgressAccess`).
- **Data:** no schema migration. Saved tokens are deleted. `settings.json` drops `trackerEnabled` on its next save, and old files still load.
- **Network:** `api.tarkovtracker.org` is no longer contacted. json.tarkov.dev is unchanged.
- **Architecture:** `openspec/architecture.md` loses the Tracker boundary, component, state and resource rows. The runner channel shrinks to the local-data path. ADR-0007's DPAPI token use and the "Tracker coexists" clauses of ADR-0041 and ADR-0044 are superseded by a new ADR.
- **Tests:** Tracker client, progress controller, credential store and token UI tests are removed. Decision, raid timer, selection, shell and settings tests move to local-progress fixtures.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: No import from the progress site

- **Choice:** remove the token integration outright; log replay and manual entry rebuild progress.
- **Rejected:** a one-time opt-in "import my progress" that reads the site once and stores events (more code, one more site contact, mapping work for a short-lived path).
- **Reversal cost:** medium
- **Important:** yes: changes behaviour users see.
- **Chosen by:** user

### S2: Unrecorded facts count as not started, zero or not built

- **Choice:** advice treats an unset task as not started, an unset objective as count 0 and not done, and an unset station level as not built, as the availability rules do (ADR-0043). Following those rules, a started task's needs skip its gates, and a failed task counts as done unless it is restartable (owner agreed after design review round 1, 2026-11-19). Unset faction or edition, and an unset level where a gate needs more than level 1, leave only that gate unknown. Advice has progress whenever the mode's active wipe can be read.
- **Rejected:** keeping advice at "progress unknown" until the player records something for the mode. That adds a second notion of "known", and a fresh install would show Check until the player acts.
- **Reversal cost:** low
- **Important:** yes: changes behaviour users see.
- **Chosen by:** user

### S3: Hideout items count in full until the level is built

- **Choice:** an unbuilt station level needs its full item count; a built level's items are satisfied. Partial hand-ins are not tracked.
- **Rejected:** an unknown amount that drops the verdict to Check (most hideout items would read Check); per-requirement hand-in counters in manual progress (more scope, for M12 hideout).
- **Reversal cost:** low
- **Important:** yes: changes behaviour users see.
- **Chosen by:** user

### S4: Saved tokens are deleted and the DPAPI methods removed

- **Choice:** on first launch, delete the token files and the credentials folder. Remove protect, unprotect and atomic replace from the runner, keeping the local-data path.
- **Rejected:** keeping the DPAPI code for a later use (dead native code with no consumer); leaving the files (encrypted tokens linger with nothing to remove them).
- **Reversal cost:** medium
- **Important:** yes: high reversal cost (native boundary) and visible to users.
- **Chosen by:** user

### S5: A Progress item replaces the Tracker item in the status bar

- **Choice:** "Progress local" or "Progress unavailable" for the effective mode, which opens Settings at Local progress.
- **Rejected:** dropping the item (an unreadable wipe would then be visible only in Settings).
- **Reversal cost:** low
- **Important:** yes: changes what users see.
- **Chosen by:** user

### S6: Old settings with the Tracker switch still load

- **Choice:** `trackerEnabled` in `settings.json` and `TrackerProgressEnabled` in legacy imports are read and ignored. The key is dropped on the next save.
- **Rejected:** a settings format version bump (no other field changes).
- **Reversal cost:** low
- **Important:** no
- **Chosen by:** agent

## Release Notes

Advice now comes entirely from the progress Blackgrid keeps on your PC. Keep/sell verdicts, requirement rows and the scav timer's hideout bonuses use the quests, objectives and hideout levels recorded from your game logs or entered by hand. The progress-site token is gone: Blackgrid no longer contacts that site and deletes any saved token on first launch.

### Changed

- Keep/sell advice, requirement rows and Flea eligibility use your local progress for the current game mode. Anything not recorded counts as not started, and hideout items count in full until the level is built.
- The scav timer's hideout bonuses use the station levels in your local progress.
- The status bar shows Progress for the current mode and opens Settings at Local progress.

### Removed

- The progress-site token, its Settings section, Refresh progress and the Use Tracker progress switch. Saved tokens are deleted on first launch.
