# Design

## Triage

| Trigger | Applies? | Evidence |
|---|---|---|
| T1 Components | No | One marker calibration and its existing normalizer guard change; the controller and pack publisher already consume the result (`lib/application/map_controller.dart:230-246`, `tool/maps/pack.dart:2947-2974`). |
| T2 State | No | Regenerates a static bundled asset; no change to application state, caches or persistence (`lib/maps/prepared_map.dart:419-436`). |
| T3 Concurrency | No | No new background work, timing or ordering; reuse the existing offline build and publish operations (`tool/maps/pack.dart:965-981,2947-2974`). |
| T4 Boundaries | No | Uses the existing `markerFloorAssignments` and `floorId` in the unchanged v5 pack, not a schema or installed-data migration (`lib/maps/live_map_normalizer.dart:245-253,295-324`). |
| T5 Volume | No | One exact marker entry, with no new inventory or scan (`lib/maps/live_map_normalizer.dart:287-302`). |
| T6 Risk | No | Only repository-generated data changes; publication retains existing verification (`tool/maps/pack.dart:2947-2974`). |

TIER: LIGHT

## Context

- The current bundled Shoreline second-floor extent is height-only at `[-1, 2)`, not bounded as the issue describes; Climber’s Trail is at its lower edge, height `-1` (`assets/maps/versions/2cc3a1cf4ab49250e9df8aa67438cbf3a3fcb53cb34288bf9a41c789f99b5bb5/manifest.json:335574-335583,336000-336027`). Admin Basement and Transit to Labyrinth fall in the existing underground extent (same manifest, lines 335648–335670, 336077–336105 and 337621–337649).
- `MapController` prefers the prepared `floorId` to spatial inference (`lib/application/map_controller.dart:230-246`). The shared normalizer looks up an exact category/source ID/occurrence and applies the annotation only if the placement guard succeeds; Interchange already compares the complete source volume (`lib/maps/live_map_normalizer.dart:287-324,829-843`). Runtime refresh gets that same calibration from the prepared pack (`lib/maps/prepared_map.dart:70-79,419-436`).
- The ordinary rebuild uses the incumbent’s own frozen calibration (`tool/maps/pack.dart:2696-2698,2728-2734`); it cannot introduce a reviewed annotation by itself. The existing exact-candidate publisher verifies the baseline, candidate, and reviewed source admission before updating assets (`tool/maps/pack.dart:2947-2974`).
- No overlap with PR #136: it changes the raid-panel parser/matcher and their tests/spec; the other worker confirms there is no separate Reserve floor work in flight. Map normalizer, calibration and pack data are independent of that PR.
- Manual branch gate for Orca’s pre-created worktree (sh1ny/specwright#258): code and planning resolve to this same worktree; pinned `sw` 0.39.1 reports interface 3 and a clean assigned branch; its HEAD, local `main`, and fetched `origin/main` are all `28f6f4d`; neither main archive contains this change name. The normal on-main check does not apply to this pre-created branch; no branch switch, bootstrap or shared configuration edit was needed.

## Decisions

### D1: Reuse exact reviewed marker ownership, not a spatial exception

- **Choice:** Add one `Ground_Level` assignment to Shoreline’s reviewed calibration for `extracts:f7da3681df4ae3bd7b3d5ba0e0f960dc1722d23f:0`, tied to its full frozen position, height band and outline. Reuse the Interchange source-volume comparison for Shoreline; if source identity or placement drifts, normal inference applies. Preserve the existing Icebreaker guards unchanged.
- **Rejected:** Edit Shoreline’s extents or globally reinterpret extract height/volume. Either changes unreviewed markers or player Auto; neither is needed for the known outdoor exit.
- **Reversal cost:** Low; remove one entry and regenerate the bundle.
- **Important:** No additional behavioral or format decision beyond S1; uses the existing ownership and drift contracts in ADR-0035 and ADR-0050.
- **Chosen by:** agent.

### D2: Stage one offline generation through the existing builder and publisher

- **Choice:** From a verified baseline, use a disposable staged copy with only the exact reviewed calibration change and its source-index hash updated. Build a candidate from the staged frozen view and incumbent source lock and notices. Before publication require every output hash except `evidence/calibration.json` and `evidence/sources.json` to match the baseline; require map records to be unchanged apart from Shoreline’s single assignment and its marker’s ownership/evidence. Use the existing validated candidate publisher, remove staging inputs, and run `maps:check` on the promoted generation.
- **Rejected:** Edit the active manifest by hand, refresh upstream content, or add a permanent pack migration/CLI option for the one entry. These respectively bypass reproducibility, add unrelated content, or leave a new mechanism behind.
- **Reversal cost:** Low; revert the immutable generation and pointer together with the calibration change.
- **Important:** No — no new published contract or command.
- **Chosen by:** agent.

### Decision summary

| # | Decision | Choice | Rejected | Reversal cost | Important | Chosen by |
|---|---|---|---|---|---|---|
| S1 | Fix the outdoor extract only | Ground-level Climber’s Trail, unchanged indoor routes | Blanket floor rule or parser workaround | Low | Yes | user |
| D1 | Floor ownership | Exact reviewed marker and volume | Extent or global extract rule changes | Low | No | agent |
| D2 | Pack generation | Disposable offline stage and existing publisher | Hand edit, upstream refresh, permanent migration | Low | No | agent |

## Assumptions

None. Before merge, only the owner can confirm live visibility; the bundled regression and reproducibility check are offline evidence, not live proof.

## Carried constraints

- **C1:** Explicit marker ownership wins; unassigned markers and player Auto still use the same position classifier. Kind: invariant. Destination: spec: specs/map-controls/spec.md → Requirement: Unassigned markers use the prepared floor extents.
- **C2:** Live marker identities or placements may drift; a stale annotation does not force ownership or reject an otherwise valid snapshot. Kind: invariant. Destination: ADR 0035.
- **C3:** Generated pack changes must remain reproducible from their own frozen inputs. Kind: invariant. Destination: ADR 0033.
