# Offline validation evidence

## Scope

The change is build-time Dart map tooling. Validation used offline fixtures, the existing fast suite, mounted Dart qualification runs and actual CLI commands. Real acquisition/publication results are recorded in [artwork-cli-smoke.md](artwork-cli-smoke.md).

No Blackgrid desktop app, reference companion or game was launched or inspected. No game process inspection, live-game qualification, hot reload/restart or local `BLACKGRID_NO_GAMES_RUNNING` override was performed. Those checks are not claimed as passed. Release is disabled; no version was bumped and repository-active map assets/pubspec were unchanged.

## Required commands

Commands ran from the repository root.

| Command | Observed result |
|---|---|
| `mise run analyze` | Passed; final run: `No issues found! (ran in 8.4s)`. |
| `mise run test` | Passed: **2,552 tests**, `04:18 +2552: All tests passed!`; qualification-tagged tests excluded by the existing task. Analyze and test were invoked as `mise run analyze && mise run test`, exit 0, total wall time 283.48 seconds. |
| `mise run maps:check` | Passed, exit 0, 24.09 seconds; committed generation `cefe97a6658f56550ca9466c9e261d8cbd57b044705e5ca453999d9903aa0993` reproduced byte-identically. |
| `openspec validate add-artwork-refresh --strict` | Passed: `Change 'add-artwork-refresh' is valid`. |
| `mise run release-notes -- --check openspec/changes/add-artwork-refresh/proposal.md` | Passed, exit 0; accepted the summary and one Added / one Changed entry. |

The map reproduction command printed the resolved versions: xml 6.6.1, image 4.12.0, vector_graphics_compiler 1.3.4, vector_graphics 1.2.5 and vector_graphics_codec 1.1.13. No network acquisition is part of `maps:check`.

Formatting also passed, with `Formatted 9 files (0 changed)`, using:

```text
mise exec -- dart format --output=none --set-exit-if-changed tool/maps/pack.dart tool/maps/calibration.dart tool/maps/prepare.dart test/support/map_preparation_fixtures.dart test/maps/artwork_compatibility_test.dart test/maps/artwork_refresh_test.dart test/maps/artwork_publication_test.dart test/maps/map_generation_inputs_test.dart test/maps/map_preparation_qualification_test.dart
```

## Mounted Dart test runs

All calls used the mounted `dart.run_tests` tool with this checkout as the project root, not a shell `dart test`/`flutter test` substitution. Paths and explicit arguments below are the actual execution inputs. Counts are per run and overlap; they must not be added into a unique-test total.

| Paths / selection | Explicit arguments | Terminal outcome |
|---|---|---|
| `test/maps/artwork_compatibility_test.dart`, `test/maps/map_preparation_qualification_test.dart` | `reporter: expanded`, `concurrency: 1`, `file-reporter: json:.dart_tool/artwork-refresh-verification/group1-final.jsonl` | 42 passed, zero errors; `done.success: true`, 446.867 seconds. |
| `test/maps/artwork_refresh_test.dart`, `test/maps/map_generation_inputs_test.dart`, `test/maps/artwork_compatibility_test.dart` | `reporter: expanded`, `concurrency: 1`, `timeout: 3m`, `file-reporter: json:.dart_tool/artwork-refresh-verification/group2-final.jsonl` | 35 passed, zero errors; `done.success: true`, 254.886 seconds. |
| `test/maps/artwork_publication_test.dart` | `reporter: expanded`, `timeout: 3m`, `file-reporter: json:.dart_tool/artwork-refresh-verification/group3-final-publication2.jsonl` | 5 passed, zero errors; `done.success: true`, 81.019 seconds. |
| `test/maps/map_preparation_qualification_test.dart`, `name: [refresh]` | `reporter: expanded`, `timeout: 3m`, `file-reporter: json:.dart_tool/artwork-refresh-verification/group3-final-refresh.jsonl` | 15 passed, zero errors; `done.success: true`, 497.661 seconds. |

`artworkReproducesWithoutRawStage` is qualification-tagged in `artwork_refresh_test.dart`, next to its shared staging fixture, rather than the planning map's originally proposed `map_preparation_qualification_test.dart` location. The execution test map records the actual path. It stages through admitted fixture transport, removes only private acquired inputs, then reproduces from the staged generation's carried closure.

The final publication suite includes the named publication scenarios, changed-current-baseline ownership rejection and sequential baseline-change rejection. Its fast transaction permutations inject typed filesystem operations over minimal files; the admitted-candidate service cases are qualification-tagged. The existing refresh selection exercises the offline/metadata transaction after extraction, including prechecks and failure behavior.

## Failing-before evidence and corrections

Meaningful RED runs were observed before the corresponding implementation/fixes:

- Frozen-generation compatibility failed with `Calibration revision mismatch for icebreaker` in the old builder, proving the pending-global dependency. Preservation cases already supported by existing gates stayed green.
- Locked-source mismatch, required terms identity and supported/new identity diagnostics failed before admission implementation.
- Fresh staging and frozen-candidate reproduction failed against unimplemented staging declarations before production behavior was written.
- A valid noncanonical frozen calibration lost trailing bytes on default staging; the corrected path preserves the original bytes rather than reserializing them.
- Fresh reviewed notice bytes were incorrectly replaced by baseline notice bytes; the corrected fresh context uses reviewed notices.
- Ownership-rejected staging left a ready manifest; the corrected failure path invalidates the manifest while retaining diagnostic partial files.
- Publication accepted a candidate conflicting with current-baseline reviewed ownership; the corrected publisher calls the existing ownership gate before writes.
- Recovery tests exposed literal escaped line breaks and missing target-scoped guidance. The corrected diagnostics identify actual pointer/pubspec/pruning/candidate state and the actual pack/pubspec targets; they do not direct a custom-root operation to the default repository alias.

Initial test-fixture syntax/setup mistakes and an incidental diagnostic-phrase assertion were corrected rather than counted as behavior RED evidence. The publication success fixture deliberately changed its current baseline; its owner-duty expectation was corrected to match that non-toolchain change, and a separate replay within the same test proves no-change/no-owner behavior. Production classification was not weakened to satisfy a mistaken assertion.

## Tool transport and blockers

Several mounted test calls exceeded the MCP receive timeout after 30 seconds. A transport timeout was not counted as a failed or passed test. Unique JSON reporters preserved outcomes; the exact Dart runner PID from each reporter was awaited, then terminal `type: done` events with `success: true` and test/error counts were read. No passing result was inferred from an incomplete reporter.

One attempted `name` regex containing `|` was misquoted by the mounted Windows runner and launched no tests. The tool issue was reported; verification was rerun without that filter. This is not an application regression or a qualification pass.

No final validation blocker remains. No desktop/game qualification or human visual-placement approval is implied by these results.
