# Proposal

## Why

The existing offline map rebuild reproduces bundled sources; it cannot prepare a fresh artwork generation when upstream artwork changes. Provide a repeatable, reviewable way to stage such a generation without changing the active pack until an operator explicitly publishes it.

## What Changes

- Fetch fresh artwork and required interactive metadata and terms for the supported inventory, retain the verified baseline's six regular-mode marker/task/trader and English snapshots and calibration by default, then build and validate a frozen candidate and print the existing map/floor change report. Staging does not publish.
- Keep source locks and calibration under reviewed repository configuration. Locked primary sources and every required terms document need explicit URL and expected-hash locks, repository revisions where available, and recorded provenance. Raster tiles are admitted by reviewed calibration and exact configured URL identities; acquired hashes establish frozen integrity, not prior byte approval. Incompatible source frames, floors, dependencies or reviewed marker ownership require a reviewed correction rather than automatic calibration.
- Publish the exact staged candidate only through a separate explicit command using the existing validated promotion, asset-declaration, pruning and recovery transaction. Report the current verified baseline-to-candidate changes; do not rebuild the candidate.
- Preserve generation-owned offline reproduction and ADR-0034's six-source metadata-only preservation gates, even while newer configuration is pending. Unsupported newly discovered identities receive an actionable diagnostic; integrating a new map remains separate authored work.
- No generated onboarding package, native PNG exporter, image index, checklist protocol, hash acknowledgement, runtime UI or painter changes. No automatic owner-review assertion. Live data, location labels and classification remain separate.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `prepared-map-packs`: fresh-artwork staging and explicit exact-candidate publication while preserving existing reproduction and metadata-only contracts.

## Impact

Build-time `tool/maps/prepare.dart`, `pack.dart`, calibration and inventory configuration, map-tool tests, `mise.toml` and existing command documentation. No intended runtime or pack-format change. ADR-0005 as amended by ADR-0033 and ADR-0034 remains in force; a supplementary ADR during apply is warranted only if a durable boundary needs recording.

## Decision Making

DECISION_MAKING: important
Source: setting

The user revised the previous onboarding, native-preview and checklist choices with “yes, go ahead” and confirmed rewriting all five planning artifacts. This also refines the roadmap's planned new-map scope: generated calibration and checklist onboarding are removed, not delivered or merely deferred; a newly unsupported identity gets an actionable diagnostic and needs separate authored integration. The roadmap itself is unchanged. The prior review and tasks do not apply to this revision and must be replaced after a fresh review.

### S1 — Supported inventory
- Choice: Diagnose newly discovered unsupported identities relative to the baseline; new-map integration is separate authored work, not a generated onboarding package.
- Rejected: Generate onboarding artifacts or automatically make upstream maps selectable.
- Reversal cost: medium.
- Important: yes — binds the supported-map boundary.
- Chosen by: user.

### S2 — Stage and publication
- Choice: Stage a validated candidate and report; a separate explicit publication publishes those candidate bytes through the existing transaction without a checklist, preview exporter or hash-acknowledgement protocol.
- Rejected: Automatic publication or a machine-enforced image/checklist acceptance protocol.
- Reversal cost: medium.
- Important: yes — changes operator-visible behavior and the publication boundary.
- Chosen by: user.

### S3 — Source and calibration authority
- Choice: Existing reviewed source configuration admits locked primary identities and hashes; add explicit reviewed locks and provenance for every required terms document. Raster tile admission uses reviewed calibration and exact configured URLs, with observed hashes used only for frozen integrity. Retain baseline calibration unless an explicit reviewed configuration update is selected and reconciled. Preserve the six baseline metadata snapshots.
- Rejected: Treat observed upstream bytes or derived calibration as approved, or refresh marker metadata along with artwork.
- Reversal cost: medium.
- Important: yes — binds source trust and preservation boundaries.
- Chosen by: user.

### S4 — Raster and terms admission authority
- Choice: Admit raster tiles through reviewed calibration and exact configured URL identities, then freeze and verify acquired hashes; add reviewed URL/hash locks and provenance for the three previously unpinned required terms documents, with repository revisions where available.
- Rejected: Require pre-reviewed per-tile byte hashes; treat newly observed hashes as prior approval; retain stale baseline terms instead of fresh acquisition.
- Reversal cost: medium.
- Important: yes — resolves the distinction between reviewed source identity and frozen byte integrity.
- Chosen by: user.

## Release Notes

Prepare fresh map artwork for review without automatically changing the active map pack.

### Added

- Stage fresh artwork with source and calibration checks and a per-map change report; publish the exact staged candidate separately with interrupted-publication recovery diagnostics.

### Changed

- Keep offline map checks, rebuilds and metadata-only renewal tied to the active generation's frozen calibration, source locks and notices while newer artwork configuration is pending.
