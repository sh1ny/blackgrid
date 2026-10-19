# Proposal

## Why

At every launch the cached catalog loads as `stale`, and progress has no snapshot at all. Nothing refreshes either one automatically ([#41](https://github.com/sh1ny/blackgrid/issues/41)). The decision engine treats a stale catalog or missing progress as unknown, so after each launch or mode switch every manual decision and every accepted scan reads "Catalog authority missing or stale" or "Progress authority missing or stale" until the user presses Refresh. M4's live checks would need that manual workaround.

This change is M4 change 4 (complete raid-time Scanner slice). It serves the exit criterion "Selecting a known mode, at startup or by switching, starts one catalog refresh without blocking startup … A failed refresh keeps the last-good snapshot and does not retry in a loop". It also adds automatic refreshes to the mode and refresh races that the M4 criterion "catalog/progress refresh cannot publish a stale decision" covers.

## What Changes

- When `catalog.setMode` completes for a known mode, `AppServices` starts one `catalog.refresh()` without waiting on it. This happens at launch and on every mode switch. Startup and `AppServices.setMode` still wait only on the local reads, never on the network.
- When `progress.setMode` completes for a known mode, a saved credential was read and the read-only Tracker integration is enabled, `AppServices` starts one `progress.refresh()` the same way. Without a credential, or with the integration disabled, no request is made.
- A failed automatic refresh keeps the last-good snapshot and reports the existing failure. It is not retried: the next attempt is a manual Refresh or the next mode selection. A manual progress refresh during a tracker cooldown makes no request; a new mode selection clears the cooldown, as it does today.
- A refresh started for one mode never publishes after a switch to another mode. `GameMode.unknown` makes no request, and a selection whose catalog is already `current` (a manual refresh won the race) starts no catalog fetch.
- A cached catalog still starts `stale` until a refresh succeeds. The spec now states that the app contacts the catalog source, and the tracker when a credential is saved and the integration is enabled, on launch and on each mode switch without user action.
- Saving a credential does not trigger an automatic progress refresh; that stays manual.

## Capabilities

### New Capabilities
- `progress-authority`: when tracker progress is fetched without user action and which fetch results may be published. This change adds the automatic progress refresh after a mode is selected with a saved credential.

### Modified Capabilities
- `catalog-authority`: adds a requirement that selecting a known mode, at startup or by switching, starts exactly one catalog refresh without blocking startup, keeps the last-good snapshot on failure and never retries in a loop. The "cached snapshot starts `stale`" rule is unchanged.

## Impact

- Code: `lib/application/app_services.dart` (the `_modeChange` wiring in `_syncMapSession`), and possibly small hooks in `CatalogController` or `ProgressController` that report whether a refresh is due (design decides).
- Tests: new service tests with fake `CatalogClient` and `TrackerClient`. Existing `AppServices` tests that call `catalog.refresh()`/`progress.refresh()` by hand after `initialize()`, or count fetches, may need adjustment.
- Network: the app now makes requests to `json.tarkov.dev` on every launch and mode switch, and to the tracker when a credential is saved. No new dependency.
- Closes #41.
