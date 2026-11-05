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

All fourteen tracked tasks are complete, including the separately attributed owner acceptance of task 4.4 below. No archive, PR or merge is implied by recording that acceptance; the applicable workflow gates remain separate.

## Owner result and safety boundary

**Owner accepted on 2026-11-05:** after receiving local Windows bundle `0.7.0+406`, the owner reported "OK it's identical to tarkov.dev" and "as far as this change is concerned, we're good." This completes task 4.4 for generation `cefe97a6658f56550ca9466c9e261d8cbd57b044705e5ca453999d9903aa0993`. The result is user-reported, not agent-performed UI verification.

The local build used the pinned Flutter toolchain with build name `0.7.0`, build number `406` and `BLACKGRID_VERSION=0.7.0+406`. The official release command had refused the uncommitted roadmap entry authored during planning; that release guard was not changed. A direct local Release build then succeeded, followed by `mise run bundle:check -- build/windows/x64/runner/Release`; all eight offline bundle-check groups passed. The built bundle's `data/flutter_assets/assets/maps/active.json` was verified to name the exact generation above.

Built artifact binding (SHA-256):
- `build/windows/x64/runner/Release/blackgrid.exe`: `1489872f9ee40405b86ec269fc9200851a6a3b9b5a0e9bfcf2cd6b0d977f6410`.
- `build/windows/x64/runner/Release/data/app.so`: `c7972ade3471777c5432fdc47e74f80440deb959d9d81c8d77f3443da588e20e`.

The owner's requested classification follow-up is [issue #89](https://github.com/sh1ny/blackgrid/issues/89): separate Raiders, Rogues and other non-boss AI from boss spawns. It does not block this accepted metadata correction.

Before building, a name-only process inventory confirmed Tarkov and BEService were absent. Agents did not launch or inspect the app or game, and `BLACKGRID_NO_GAMES_RUNNING` was not set. No agent-performed application-runtime check, source-versus-game accuracy or M8-wide readability acceptance is claimed. No release or source-version bump occurred.

Disposable acquisition/audit scripts and reporter files are scaffolding, not permanent CLI interfaces. Their observed results are captured in these generation-bound evidence files; owned scratch files are removed after recording the verification.
