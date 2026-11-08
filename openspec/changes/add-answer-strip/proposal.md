# Proposal

## Why

M8.5's Ember interface puts the keep/sell answer first. Today Scanner places controls before the answer at narrow widths, and Map buries it below the workspace. This change advances the answer-first geometry and control-preservation exit criteria. The second-monitor and alt-tab visual criterion will be judged by the owner at milestone close, after map and dialog restyling complete.

## What Changes

- Build Direction B's shared top bar, answer strip, inspector and clickable status bar in both Ember rooms (DESIGN.md X7, X10, X11, X14).
- Put item identity, verdict, reason, freshness and per-item Found in raid together directly under the top bar on Map and Scanner.
- Keep raid timers in the top bar; retain labelled Settings, Stats and Import actions with tooltips when labels collapse.
- Move work-area configuration into the existing Settings dialog, with section targets for status links. The full Settings page remains in `restyle-dialogs`.
- Put detailed inspection, requirements, sources and history in the inspector; show pictures in history rows and remove raw item IDs below item names.
- Persist the displayed verdict with each newly recorded activity; older records show an unknown indicator, never a recomputed historical verdict.
- Preserve map controls and filters until `restyle-map-workspace` gives them their final placement and styling.

## Capabilities

### New Capabilities
- `workspace-shell`: answer-first shared shell, responsive inspector and status navigation.

### Modified Capabilities
- `map-rail`: replace the obsolete decision-in-rail ordering with the shared strip and inspector arrangement while preserving map controls.
- `local-data-durability`: retain an optional verdict with activity across migration, import and restart.
- `scanner-evidence`: move scan configuration to Settings and retain evidence below the answer, with session state preserved.

## Impact

Primarily `lib/ui/shell.dart`, Map and Scanner screens, decision and evidence panels, manual controls, timer presentation and Settings dialog. Reuse application controllers, icon loading and saved history; no capture, decision-rule or dependency changes. Adds an optional activity verdict and a Drift migration. AGENTS.md's safety boundary, ADR-0029's release notes and the architecture's state ownership remain constraints; map-role changes under ADR-0023 belong to the next change.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Approved Direction B scope
- **Choice:** Deliver the shell and answer strip described by the agreed M8.5 split and DESIGN.md X7/X10/X11/X14, preserving existing selection and evidence semantics.
- **Rejected:** A new visual direction or moving map-role and dialog redesign into this change; these would rewrite the agreed split.
- **Reversal cost:** medium
- **Important:** yes; changes visible behaviour and binds later milestone work.
- **Chosen by:** user (approved design and roadmap split)

### S2: Settings transition
- **Choice:** Keep the existing Settings dialog, add displaced controls there, and let status links open the relevant section.
- **Rejected:** Bring the full Settings page forward; it remains in `restyle-dialogs`.
- **Reversal cost:** low
- **Important:** yes; changes settings users see.
- **Chosen by:** user (2026-11-08)

### S3: Verdict at history recording time
- **Choice:** Save the displayed verdict when each new activity is recorded; older entries show an unknown indicator. Preserve the existing one-row-per-item-and-mode history and current history-inspection behaviour.
- **Rejected:** Use today's verdict as if historical, or defer the dots.
- **Reversal cost:** medium (stored user data).
- **Important:** yes; stored format and visible behaviour.
- **Chosen by:** user (2026-11-08)

## Release Notes

Blackgrid puts the current item and keep/sell answer directly below the top bar on Map and Scanner.

### Changed
- Activity records now retain the verdict shown at recording time across restart and import; older records retain an unknown verdict.
- Added an answer-first workspace with raid timers in the top bar, a details inspector, pictured history rows and clickable status controls. Configuration remains available in Settings. New history entries retain their verdict; older entries show an unknown indicator.
