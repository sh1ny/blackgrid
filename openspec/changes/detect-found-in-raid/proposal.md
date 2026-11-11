# Proposal

## Why

M9’s `detect-found-in-raid` change removes a manual input from each accepted scan: Blackgrid can read the check icon in the inspected item’s picture, including its position beside a mastery medal. It advances M9’s fixture-proven FIR detection and override criterion; an explicit `[user]` task checks live found/not-found scans, while the unrelated `polish-ember-ui` check remains for milestone close.

## What Changes

- Read Yes when the check icon is present, No when its complete corner is readable without the icon, and Unknown only when the corner is incomplete or unreadable. Associate evidence with each inspection, not the frame’s first match.
- Extend the existing targeted band downward; keep physical-client scaling, clipping, the full-client fallback, trigger waits, acceptance gates and game-safety boundary.
- Derive one tiny, provenanced, manifest-bound check-icon template from an owner-supplied screenshot, using the existing marker-asset convention. Keep full screenshots private.
- Feed only the winning accepted inspection’s FIR into the shared decision engine. An unreadable corner does not reject a recognised item or cause another screen copy.
- Retain the three-state manual override and show whether the effective value came from the scan or the player. Each new scan discards the previous override; returning to the latest scan restores its detected value, not its old override.
- Keep manual/history selections and picked corrections Unknown until manually set. No FIR persistence, tracker work, new settings, automatic recapture or game interaction.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `inspection-capture`: deeper targeted band that covers the picture corner as well as the title.
- `inspection-recognition`: bounded per-inspection FIR evidence and a bound check-icon template, computed in the existing worker from the same frame.
- `scan-decisions`: detected FIR, scan/manual provenance and per-selection override/reset behavior.
- `latest-accepted-scan`: returning restores immutable detected FIR while discarding any previous manual override.

## Impact

Capture geometry and its fixtures; vision evidence/job/template tooling and bundle verification; accepted-scan/feed/selection contracts; the shared answer-strip FIR controls and existing application/widget tests. No database migration or native ABI change is planned. A new ADR will amend ADR-0016’s band and document the evidence/override contract; accepted ADR files remain unchanged.

Inputs: twelve owner-supplied JPGs, renamed and moved without byte changes into ignored `.qualification/found-in-raid/` (the repository's existing private-evidence area, not disposable Flutter tooling data). They cover both client resolutions (3440×1440 and 1920×1080), positive/negative flags, medals/no medal, direct inspections and inspections opened over a container. File dimensions are not automatically client dimensions: two 3440 images omit the bottom 48 rows and one 1080p capture has a border. Frozen annotations preserve that distinction.

## Decision Making

DECISION_MAKING: important
Source: setting

| # | Choice | Rejected | Reversal cost | Important | Chosen by |
|---|---|---|---|---|---|
| S1 | Three states, manual override, same-copy analysis; only the owner runs live checks | Boolean-only FIR, automatic game interaction | Medium | yes: visible behavior and safety boundary | user (roadmap) |
| S2 | Return to latest scan restores detection, drops the old manual override | Restore the override; reset to Unknown | Low | yes: visible behavior | user |
| S3 | Corrections/manual/history keep their manual-only FIR behavior | Reuse rejected-window FIR for corrections | Low | yes: visible behavior | user |
| S4 | Unreadable FIR leaves title acceptance intact; no extra fallback for FIR | Recapture or force full-client fallback | Low | yes: visible behavior and pipeline boundary | user |
| S5 | Bundle a tiny screenshot-derived check template; keep source screenshots private | Custom geometric detector; commit full screenshots | Medium | yes: artifact boundary and artwork redistribution | user |

## Release Notes

Accepted item scans fill Found in raid from the inspection picture, with a manual override and a visible source. Unreadable or cut-off corners remain Unknown.

### Added

- Automatic Yes/No/Unknown Found in raid evidence for each inspection, including pictures with a mastery medal, computed from the same captured pixels as its title.
- Scan startup verifies the marker and found-in-raid templates together; missing, altered or invalid assets stop recognition explicitly.

### Changed

- The targeted screen region includes more of the inspection picture. Returning to the latest scan restores its detected Found in raid value and clears the old manual override.
