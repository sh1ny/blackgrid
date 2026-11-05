# Artwork CLI smoke evidence

## Scope and isolation

All acquisition used the actual Dart CLI and the authored source configuration. No synthetic primary-source hashes, source-admission bypass, generated artwork difference, image gate or owner-approval token was used. Publication targeted a disposable copy at `.dart_tool/artwork-refresh-smoke-867726f96f/packs` and its own `pubspec.yaml`, never repository-active assets.

No Blackgrid desktop app or reference companion was launched or inspected, and no game or game process was inspected, launched or controlled. No live-game qualification ran. After all real CLI checks completed, the exact task-owned disposable root and both candidates were deleted; removal was verified. Identities and observed outcomes are recorded here.

## Identities

| Role | Manifest SHA-256 / generation ID |
|---|---|
| Repository and initial disposable baseline | `cefe97a6658f56550ca9466c9e261d8cbd57b044705e5ca453999d9903aa0993` |
| Direct CLI stage and first published candidate | `d004e7cf1ff12abcd6eca9383c8c98f41fcdd265e8babd318be4acd1d48cb123` |
| Mise stage and subsequently published candidate | `9d03eee02129f83b0cca7ec0527376fadcd65af80fdf160349201812f2e4f260` |

## Commands and observed results

Every command below exited 0. Times are observed wall-clock command durations, not performance budgets.

| Command | Seconds | Result |
|---|---:|---|
| `mise exec -- dart run tool/maps/prepare.dart artwork-refresh --packs .dart_tool/artwork-refresh-smoke-867726f96f/packs --pubspec .dart_tool/artwork-refresh-smoke-867726f96f/pubspec.yaml --stage .dart_tool/artwork-refresh-smoke-867726f96f/candidate-cli` | 228.64 | Real admitted acquisition, build and validation succeeded; staged `d004e7cf…48cb123`; nothing published. |
| `mise exec -- dart run tool/maps/prepare.dart artwork-publish --candidate .dart_tool/artwork-refresh-smoke-867726f96f/candidate-cli --packs .dart_tool/artwork-refresh-smoke-867726f96f/packs --pubspec .dart_tool/artwork-refresh-smoke-867726f96f/pubspec.yaml` | 45.79 | Published the exact staged generation, updated declarations, pruned the old disposable generation, retained the operator-owned candidate. |
| `mise run maps:artwork:refresh -- --packs .dart_tool/artwork-refresh-smoke-867726f96f/packs --pubspec .dart_tool/artwork-refresh-smoke-867726f96f/pubspec.yaml --stage .dart_tool/artwork-refresh-smoke-867726f96f/candidate-alias` | 85.54 | Fresh real acquisition against the now-current disposable baseline succeeded with evidence-only changes; staged `9d03eee0…2e4f260`; nothing published. |
| `mise exec -- dart run tool/maps/prepare.dart check --packs .dart_tool/artwork-refresh-smoke-867726f96f/packs` | 36.33 | The first real published candidate reproduced byte-identically offline after its acquisition scratch had been removed. |
| `mise run maps:artwork:publish -- --candidate .dart_tool/artwork-refresh-smoke-867726f96f/candidate-alias --packs .dart_tool/artwork-refresh-smoke-867726f96f/packs --pubspec .dart_tool/artwork-refresh-smoke-867726f96f/pubspec.yaml` | 63.12 | Published the exact second candidate and pruned the first disposable generation; retained the candidate. |
| The same mise publication command, repeated with the retained second candidate | 43.81 | Genuine no-change replay succeeded. Output: `No changes outside the toolchain record: no owner check is needed.` Pointer, complete pack bytes and pubspec remained byte-identical. |

## Actual reports

The direct stage and its publication compared the initial verified baseline with `d004e7cf…48cb123` and reported:

| Map / floor or scope | Changed output files |
|---|---:|
| Reserve / Fourth_Floor | 3 |
| Ground Zero / dependency Ground_Level | 101 |
| Labyrinth / Main_Level | 1 |
| Other evidence | 2 |

The three Reserve paths were `artwork/reserve/Fourth_Floor/9/10.png`, `9/11.png` and `10/11.png`. The Labyrinth path was `artwork/labyrinth/Main_Level/13/13.png`. Ground Zero changes were under `artwork/dependencies/groundzero/Ground_Level/`. The other paths were `evidence/sources.json` and `evidence/terms/tarkovbot-creator.html`.

Manifest-value differences were attribution records for factory, customs, woods, shoreline, interchange, reserve, lighthouse, streetsoftarkov, groundzero and terminal, plus `sourceGeneration` and `sourceLock`. These were reported as actual manifest/evidence changes, not hidden as toolchain-only changes.

The mise stage and its publication compared `d004e7cf…48cb123` with `9d03eee0…2e4f260`. Their report contained only:

- `pack: manifest values changed`;
- `other: 2 changed file(s)`;
- paths `evidence/sources.json` and `evidence/tile-alpha/65d9b3b64a77c00aec4c582fb2577b101010d970923a129e9760c1edbefe2ea8.png`;
- manifest key `sourceGeneration`.

There were no changed `artwork/` outputs in this second acquisition. Comparison of the frozen indexes found 490 raster-source records with changed acquired hashes across customs, groundzero, labyrinth and reserve. This is an honest evidence-only/no-new-artwork success, not a claim of identical upstream bytes. The subsequent same-candidate publication replay was a true no-change success without any network response or artwork being fabricated to obtain it.

## Byte and transaction checks

Before staging, hashes were recorded for the repository pointer, pubspec and the complete map asset tree. The asset-tree identity is SHA-256 over sorted paths relative to the hashed tree root and their individual SHA-256 digests, separated by NUL/newline; it included 1,323 files and 107,351,241 bytes.

| Repository object | Unchanged SHA-256 |
|---|---|
| `assets/maps/active.json` | `01fb6e074e4941d588b8b76de9171e5209523338a180797deafd9fcd3f088720` |
| `pubspec.yaml` | `1a8be36edcdcb51546e4aa671279295389ea70e8eae21cbf20395b4c58d21ade` |
| Complete `assets/maps/` tree identity | `1f1a51f1c72312bfd9392e0377b88913913955741c08f2699ed40eb135deeb61` |

These identities remained unchanged after the direct stage, direct publication, mise stage and final replay. The disposable baseline and its pubspec were also byte-identical before/after each non-publishing stage. Both adjacent `.raw` acquisition directories were absent on successful return.

For each publication, the resulting version directory's complete file-tree identity matched the named staged candidate, the active pointer named its full manifest hash, the generated pubspec block named the disposable pack root and that generation, and the preceding disposable generation was absent. The candidates themselves remained present after publication.

For the no-change replay, the disposable pack tree identity stayed `5fc925c341d61566b53a7b9cbe376787449c2ace506367a2bbff597e771af0a5` and the pubspec SHA-256 stayed `38072c6804b2b4c9dfe60e8474ad2eebdb48515b6f911c1cca68430f5257fcd4`.

## Owner responsibility and limitations

The changed and evidence-only publication commands printed the existing non-toolchain before-merge owner-check responsibility and did not claim human review. They still succeeded automatically: that message is not a new publication gate. No repository-active assets changed, so this tooling-only/disposable exercise creates no repository-generation owner-check task. No visual-placement or live-game qualification is claimed.

The operator serialized writers to the disposable pack root. The baseline recheck was not treated as a lock or concurrent-writer guarantee. There was no real-source admission blocker in these runs.
