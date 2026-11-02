# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** n/a for SKIPPED_LIGHT
- **Reviewed:** design.md triage re-checked against `lib/ui/map_workspace.dart` (painter, selection state, toolbar, semantics), `lib/application/map_controller.dart` (`hitTestMarker`, `setSelectedMarker`, projection cache), `lib/maps/map_marker_icons.dart` (`colourFor`, fallback colours), `lib/maps/prepared_map.dart` (extract faction to filter key) and the active pack's marker counts.

## Findings

### Critical (blocking)

### Moderate

### Suggestions

## Verdict

LIGHT tier confirmed: the change is painter, hover and dialog work. It adds no persisted state, cache, async work, stored format or shared contract, and its work is bounded by the visible markers.

VERDICT: SKIPPED_LIGHT

## Required Changes

CHANGES_APPLIED: n/a

## Rebuttals
