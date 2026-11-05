# Final offline verification

## Generation binding

- Change: `fix-frozen-map-metadata`, branch `bugfix/fix-frozen-map-metadata`.
- Active generation: `cefe97a6658f56550ca9466c9e261d8cbd57b044705e5ca453999d9903aa0993`.
- Superseded generation: `ed26414539f458929025f4ef2c3413d3457c7b3e5b9f2e2adfb4dc20c24bba5f`, removed by the existing refresh transaction.
- The final active pointer still names the audited generation above. The pointer, generated asset declarations and pruning were verified by the real refresh/audit operation.
- Acquisition hashes, all-map changes, independent boss-fact multiset comparison, empty source coverage and unchanged-artwork proof are recorded in [metadata-refresh.md](metadata-refresh.md).

## Exercised integration gates

| Check | Observed terminal outcome |
|---|---|
| `mise run analyze` | Passed; no issues found |
| `mise run test` | Passed; 2,546 tests, qualification tag excluded |
| Mounted Dart `run_tests`, `test/maps/map_preparation_qualification_test.dart`, qualification tag enabled | Passed; 40 nonhidden tests, zero skips, zero errors |
| `mise run maps:check` | Passed; exact active generation reproduced byte-identically |
| `openspec validate fix-frozen-map-metadata --strict` | Passed; change is valid |
| `mise run release-notes -- --check openspec/changes/fix-frozen-map-metadata/proposal.md` | Passed; three Fixed items |

The mounted qualification reply exceeded its transport receive deadline. The owned runner completed normally; its durable JSON reporter ended with `{"success":true,"type":"done","time":469920}`. The outcome above comes from that terminal event and successful test events, not from the receive timeout.

Exact reproduction line:

```text
Map pack cefe97a6658f56550ca9466c9e261d8cbd57b044705e5ca453999d9903aa0993 reproduced byte-identically with xml 6.6.1, image 4.12.0, vector_graphics_compiler 1.3.4, vector_graphics 1.2.5, vector_graphics_codec 1.1.13.
```

## Contract and task completeness

All twelve scenario rows in `tasks.md` have observed green checks. These cover source inventory and identity, malformed dictionaries and boss facts, altered evidence, independent boss projection and multiplicity, same-count corruption, explicit empty coverage, preserved map/output properties, reviewed marker ownership, and the corrected generation-backed input closure.

The new closure checks prove that unused uncarried indexed inputs remain listed without blocking a valid metadata renewal. A required uncarried generation input and a changed or missing replacement still fail without promotion and preserve the established candidate-recovery behavior. Ordinary refresh and recovery cases remain in the full qualification suite.

The real preparation API was exercised against the acquired six-source snapshot. Its independent returned-generation audit found zero boss multiset mismatches, zero forbidden source-index changes and zero preserved map/output differences. No fixed live boss totals or rates serve as future acceptance gates.

Agent/evidence tasks 1.1–4.3 and 5.1–5.2 are complete once this evidence is committed with group 5. Task 4.4 remains user-owned and unticked. Completion of automated checks is not archive or merge readiness.

## Owner result and safety boundary

**Waiting on the user:** task 4.4, for generation `cefe97a6658f56550ca9466c9e261d8cbd57b044705e5ca453999d9903aa0993` only. All thirteen maps were reported changed; the owner check includes Reserve Glukhar, Streets Kollontay, names/rates, placement/floors and readable non-boss information. No owner result has been reported.

No application launch, game inspection/control or live-game qualification occurred. `BLACKGRID_NO_GAMES_RUNNING` was not set. No application-runtime check, source-versus-game accuracy, owner presentation approval or M8-wide readability acceptance is claimed. No release or version bump occurred.

Disposable acquisition/audit scripts and reporter files are scaffolding, not permanent CLI interfaces. Their observed results are captured in these generation-bound evidence files; owned scratch files are removed after recording the verification.
