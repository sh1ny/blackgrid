# 0050 - Floor extents are pack-owned

- Status: accepted
- Date: 2026-11-24
- Partly supersedes: [ADR-0036](0036-place-labels-are-pack-owned.md), its preparation-version-4 statements only
- Source: `add-generic-floor-detection` (D1, D2; [#131](https://github.com/sh1ny/blackgrid/issues/131))

## Context

The pack carries interactive layer extents, but the old runtime followed heights only on Labs and Icebreaker. Reserve overlaps height ranges at different X/Z positions. Markers without explicit floor ownership used the same old player classification.

## Decision

- Preparation version 5 requires an `extents` list per floor. The offline builder links only the frozen interactive layers to the reviewed floor inventory, using their SVG or tile identity. An extent-bearing layer that does not match exactly one floor, or has malformed extents, fails preparation. Root-level height ranges do not fill gaps. Validation re-derives extents from candidate evidence. Reviewed place-label ownership is unchanged.
- The pack is the only extent authority. The runtime's six-source marker refresh cannot change prepared floor rules. Auto and unassigned markers classify game-space X/Z/height using the same immutable policy. Explicit marker ownership wins; marker activation bands remain distinct. A known unmatched position is base; an unknown height stays unresolved. Manual selection overrides Auto for that map.
- The offline rebuild of a verified v4 active generation removes only obsolete direct floor `heightBand` calibration fields and rebinds their evidence hashes. It preserves nested marker evidence, other inputs and exact artwork admission. Ordinary v5 validation rejects obsolete floor fields; the app loads only the active v5 generation.

## Consequences

The runtime does not parse network metadata or keep a fallback pack. Changes to frozen extents affect Auto and unassigned-marker eligibility on the next generation. Community metadata may be incomplete; manual selection remains available. Restoring an earlier generation requires reverting the matching tool and app code, not adding a second reader.
