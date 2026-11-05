# Proposal

## Why

M8's marker bubbles expose stale frozen map data: the current bundle has no Kollontay records at the three reported Streets positions and no Glukhar records on Reserve, although the current REST source supplies them. This corrective change refreshes every supported map and advances M8's readable, truthful marker-information criterion; offline checks prove source fidelity, while the required owner map check remains a `[user]` task and does not close M8's overall readability criterion.

## What Changes

- Acquire a fresh, hash-recorded regular-mode snapshot of the six existing marker, task, trader and English-translation REST inputs for all 13 supported maps. Derive the complete marker inventory, not hand edits for two bosses.
- Stage six replacement files and construct a generation-backed input view from the active pack's verified carried inputs; preserve artwork and calibration. Extend the existing refresh function with a narrow replacement-metadata input option and preservation checks. Reuse its offline build, validation and promotion machinery; do not edit an active generation in place or reacquire unused historical artwork inputs.
- Prove per-map boss-position coverage, including identity, resolved name, location, position, rate and multiplicity. Report source entries with no positions rather than inventing locations.
- Review the all-map metadata diff, verify unchanged artwork/frames/floors/pin geometry, and ship only after the owner checks the listed changed maps.
- Keep runtime behavior unchanged: bundled data only, no popup-triggered requests, no new cache or mode-specific map dataset. Artwork refresh, runtime live-map data, new maps, location labels, package upgrades and a permanent acquisition-command redesign remain out of scope.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `prepared-map-packs`: refreshed metadata must remain source-bound and complete per supported map, and a metadata-only generation must preserve artwork/calibration while retaining existing validation, promotion and owner-check gates.

## Impact

- Existing preparation APIs in `tool/maps/pack.dart`, fixtures and tests under `test/maps/` and `test/support/`, plus preparation documentation.
- New prepared generation, `assets/maps/active.json`, generated map asset declarations in `pubspec.yaml`, and removal of the superseded generation during apply. No dependency changes or app/runtime schema changes.
- Roadmap: user-approved M8 corrective entry immediately after `add-marker-popups`, before the remaining artwork/live-data/location-label initiatives.

## Decision Making

DECISION_MAKING: important
- **Source:** setting (`openspec/specwright.yaml`).

### S1: Refresh the supported inventory, not individual bosses

- **Choice:** Refresh all existing map-marker source inputs across all 13 supported maps and verify boss source-to-pack coverage; retain the existing regular-mode dataset boundary.
- **Rejected:** Relabel generic Scav spawns or patch only Kollontay/Glukhar; neither repairs the stale snapshot.
- **Reversal cost:** medium.
- **Important:** yes; changes player-visible marker data and spawn rates.
- **Chosen by:** user ("Plan the all-map refresh").

### S2: Keep artwork and runtime boundaries unchanged

- **Choice:** Preserve carried artwork, calibration and floor inventory; keep popups offline and retain current runtime loading. Extend the existing refresh function with a narrow replacement-metadata option and a six-file generation-backed staging view, reusing promotion and recovery without adding a CLI command. The user approved correcting staging to the existing build-read input closure rather than reconstructing every historically indexed source.
- **Rejected:** Broad acquisition of new artwork, runtime downloads, or a new general refresh subsystem; these belong to separate roadmap work. Disposable orchestration alone would duplicate the existing refresh function's promotion and recovery sequencing.
- **Reversal cost:** medium.
- **Important:** yes; preserves the user-visible scope boundary and extends a shared preparation interface.
- **Chosen by:** user ("Extend the existing refresh function").

### S3: M8 corrective placement

- **Choice:** Insert `fix-frozen-map-metadata` after marker popups, without starting the remaining M8 initiatives.
- **Rejected:** A standalone bugfix outside the milestone sequence.
- **Reversal cost:** low.
- **Important:** yes; changes the agreed milestone sequence.
- **Chosen by:** user ("M8 corrective change").

## Release Notes

Refresh the bundled map metadata across supported maps so boss markers and spawn chances reflect the reviewed source snapshot. Maps and marker popups remain available offline.

### Fixed

- Refresh boss and non-boss metadata across all 13 supported maps, restoring the reported Kollontay locations on Streets and Glukhar locations on Reserve with independently audited source-to-pack coverage.
- Reject malformed boss source facts and missing or ambiguous supported-map identities with source and map diagnostics, while preserving repeated positions and explicit empty coverage.
- Prevent metadata-only renewal from changing prepared artwork, calibration or reviewed marker floor ownership; keep normal rebuilds offline.
