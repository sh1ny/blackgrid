# 0034 - Metadata refresh preserves prepared artwork and calibration

- Status: accepted
- Date: 2026-11-05 (change `fix-frozen-map-metadata`)
- Supplements: [ADR-0033](0033-map-packs-proven-by-reproduction.md), without changing its decisions about immutable generations, reproduction, promotion, or runtime loading
- Source: change `fix-frozen-map-metadata` (design D1-D2)

## Context and problem

The prepared map generation carries both marker metadata and the artwork, geometry, calibration, and rendering evidence used to build each map. A metadata refresh is needed to replace stale marker-source snapshots without downloading or silently changing prepared artwork, recalibrating reviewed markers, or creating a separate pack-building and promotion path. The refresh must remain reproducible from the complete frozen inputs and must not publish a candidate whose non-metadata properties drift from the active generation.

## Decision

- **Replace only six carried REST inputs (D1).** Start from the active generation's complete, verified raw input closure. Replace only these files, acquiring regular-mode JSON over HTTPS from the listed existing URLs and recording the exact acquired bytes and hashes in the canonical source index:

  | Staged path | Source URL |
  |---|---|
  | `markers/maps.json` | `https://json.tarkov.dev/regular/maps` |
  | `markers/maps_en.json` | `https://json.tarkov.dev/regular/maps_en` |
  | `quests/tasks.json` | `https://json.tarkov.dev/regular/tasks` |
  | `quests/tasks_en.json` | `https://json.tarkov.dev/regular/tasks_en` |
  | `quests/traders.json` | `https://json.tarkov.dev/regular/traders` |
  | `quests/traders_en.json` | `https://json.tarkov.dev/regular/traders_en` |

  The staged source index must have exactly the baseline's path inventory and URLs. Only the six listed byte hashes may differ; every other input byte and source record remains unchanged. Verify the staged closure through the existing `FrozenInputs` boundary. Do not use broad acquisition, change artwork or calibration, introduce runtime datasets, or patch prepared markers directly.
- **Extend the existing refresh transaction (D2).** Add the optional metadata-input route to the existing refresh function; omission retains its existing behavior. In the metadata branch, verify the active baseline first, admit only the exact six permitted source replacements, rebuild every supported map through the existing builder, validate the candidate through existing validation, then run the preservation and reviewed-ownership checks before the existing promotion point. Reuse the existing report, asset replacement, pruning, and failure/recovery path. Keep acquisition in disposable apply-time orchestration; do not add a permanent acquisition command, duplicate refresh subsystem, or generic candidate-writer callback.
- **Preserve the complete non-metadata baseline.** Compare every candidate map record after excluding `markers` with its baseline counterpart. Preserve the complete non-metadata output path/hash inventory, including notices, vectors, compiler inputs, raster outputs, and witnesses. Among output files, only the six carried metadata files and `evidence/sources.json` may differ; the manifest may change to bind the changed outputs, source generation, and marker lists. Preserve `sourceLock`, format and preparation versions, and the supported map inventory. Preserve artwork bytes, notices, calibration bytes and historical evidence annotations, map geometry, artwork frames, display crops, floor inventory, and rendering metadata. The pre-promotion gate must reject any such drift without changing the active generation, pointer, or asset declarations.
- **Retain reviewed marker ownership and owner checking.** Every reviewed floor-assignment key must still resolve to the same prepared marker identity, floor, and source volume. A missing, changed, or lost reviewed assignment blocks promotion; do not loosen assignment checks or silently change calibration. Metadata changes continue to use the existing per-map report and require the owner to check changed maps before merge.

## Rejected alternatives

- Broadly reacquire artwork and all sources: this expands the boundary, risks changing artwork, and does not preserve the verified input closure.
- Patch prepared markers or introduce mode-specific runtime data: this bypasses source reproducibility and changes the offline runtime boundary.
- Duplicate refresh/promotion orchestration, add a permanent acquisition command, or introduce a new subsystem: this duplicates failure handling and exceeds the corrective scope.
- Rely on an operator report alone for preservation: the preservation comparison belongs inside the metadata branch before promotion.

## Consequences

- Every metadata generation remains bound to the exact acquired six-source snapshot and the unchanged remaining source closure.
- Artwork, calibration, geometry, floor and rendering properties are proven unchanged before promotion; drift cannot be published by a metadata-only refresh.
- Existing refresh behavior and lifecycle ownership remain in place, and existing reviewed-marker and owner-check responsibilities remain mandatory.
- The manifest and marker outputs may change as required to bind the new metadata, but the prepared-pack format, preparation version, source lock, runtime loader, and artwork do not change.
- Reversal cost: medium; the restriction and gate are narrow additions to the existing refresh path, while a revert restores its prior metadata behavior.

Related: [ADR-0005](0005-native-map-prepared-packs.md), [ADR-0033](0033-map-packs-proven-by-reproduction.md).
