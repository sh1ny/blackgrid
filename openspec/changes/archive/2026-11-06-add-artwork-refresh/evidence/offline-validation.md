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

## CI PNG inspection follow-up

Hosted run `42079915995` at `b43ba95` exceeded the existing two-minute limit in `unchangedAndEvidenceOnlyStage`, `retainsSixAndSelectsReviewedCalibration` and `artworkReproducesWithoutRawStage`. Subsequent missing-file and cleanup errors followed timed-out test teardown.

Staging now reuses successful PNG inspections by acquired SHA-256 within that stage, matching the builder's content-identity strategy. Every tile is still fetched, hashed and recorded. Distinct content is inspected before entering the successful-inspection set. Shared fixtures, assertions and timeouts were not relaxed.

The resumed mounted run of `test/maps/artwork_refresh_test.dart`, with concurrency 1 and no timeout override, completed with 13 passing tests, zero errors and terminal success in 195.787 seconds. This includes rejection of a distinct invalid tile after valid tiles without producing a ready candidate or changing active state. The three formerly timed-out cases completed locally as follows; these are local measurements, not hosted-run measurements:

| Test | Seconds |
| --- | ---: |
| `unchangedAndEvidenceOnlyStage` | 30.531 |
| `retainsSixAndSelectsReviewedCalibration` | 15.048 |
| `artworkReproducesWithoutRawStage` | 32.914 |

`mise run analyze && mise run test -- --concurrency=1 && mise run maps:check` passed: analyzer clean, 2,559 fast tests passed, and generation `cefe97a6658f56550ca9466c9e261d8cbd57b044705e5ca453999d9903aa0993` reproduced byte-identically. Serial validation is the owner's approved local override for the remaining PR pushes; repository configuration is unchanged.

The actual optimized CLI also passed, using current authored source admission against a disposable copy:

```text
mise exec -- dart run tool/maps/prepare.dart artwork-refresh --packs .dart_tool/artwork-refresh-ci-smoke-9c224fe08c/packs --pubspec .dart_tool/artwork-refresh-ci-smoke-9c224fe08c/pubspec.yaml --stage .dart_tool/artwork-refresh-ci-smoke-9c224fe08c/candidate
```

Exit 0 in 69.75 seconds; candidate manifest SHA-256 `9d03eee02129f83b0cca7ec0527376fadcd65af80fdf160349201812f2e4f260`. It reported artwork and manifest/evidence differences without publishing. Repository assets, pointer and pubspec and the disposable baseline remained byte-identical; acquisition scratch was absent on return. The task-owned disposable root was deleted afterward. No desktop app, companion or game was launched or inspected. The interrupted run before the owner's stop request is not counted as a pass.

## Independent staging scenario lifecycles

Hosted run `42117085884` at `7d0f8dd` passed 137 qualification tests, with four accepted skips, but the combined `unchangedAndEvidenceOnlyStage` case still exceeded two minutes. The other two former timeout cases passed. The remaining case performed two complete real stages and promotion within one timed test.

That case is now a scoped group with an immutable candidate from one real stage in `setUpAll`. `evidenceOnlyStage` checks its actual evidence-only report, exact noncanonical calibration bytes and unchanged active state. `unchangedStage` promotes that real candidate into a separate private harness and performs one real stage, retaining all no-change report, pointer, manifest, pubspec and committed-id assertions. The tests do not mutate the shared candidate or depend on each other. Production code, timeouts, fixture source admission and compilation/validation gates are unchanged by this lifecycle split.

Mounted verification of the complete artwork-refresh file, concurrency 1 with randomization seed 91 and no timeout override, passed all 14 tests with zero errors and terminal success in 184.084 seconds. The scoped real-stage setup took 15.992 seconds, the evidence-only assertions 0.091 seconds and the independent no-change case 16.684 seconds. A separate run selecting only `unchangedAndEvidenceOnlyStage unchangedStage` also passed with zero errors in 48.421 seconds, proving it does not require the evidence-only test to run first.

`mise run analyze && mise run test -- --concurrency=1` passed again: analyzer clean and all 2,559 fast tests passed. The scenario mappings name both independent cases; tracked task completion and the accepted behavior contract are unchanged.

## Trailing-directory staging fix

Codex finding `4487155051` reproduced before the fix: both native-supported trailing-separator caller cases failed to refuse an existing raw sibling before reading inputs, and `changedArtworkStages` failed with `Rebuild requires an empty fresh candidate`. Scratch had incorrectly been created inside the candidate.

The raw sibling is now derived from the SDK directory URI's file path with trailing native separators removed. The existing safety and freshness guards still check both outputs before input reads. The real staging qualification exercises a trailing separator.

Verification after the fix:
- Mounted Dart runner, `artwork_stage_path_test.dart` and `artwork_refresh_test.dart`, serial execution: 23 tests passed, zero errors; terminal `success: true`, 202.517 seconds.
- Actual CLI: `mise exec -- dart run tool/maps/prepare.dart artwork-refresh --packs .dart_tool/artwork-refresh-trailing-smoke-6f0993b25b/packs --pubspec .dart_tool/artwork-refresh-trailing-smoke-6f0993b25b/pubspec.yaml --stage .dart_tool/artwork-refresh-trailing-smoke-6f0993b25b/candidate/`. Exit 0 in 66.38 seconds. Candidate manifest SHA-256: `9d03eee02129f83b0cca7ec0527376fadcd65af80fdf160349201812f2e4f260`. Repository assets, pointer and pubspec, and the disposable baseline remained byte-identical. No nested `.raw` remained; the raw sibling was removed. The exact task-owned smoke directory was deleted afterward.
- `mise run analyze && mise run test -- --concurrency=1 && mise run maps:check`: passed in 453.88 seconds; analyzer clean, 2,561 fast tests passed, committed map pack reproduced byte-identically.
- No desktop app, companion or game was launched or inspected. No live-game verification is claimed.

## Separator-only stage refusal

Kody finding `4487359348` exposed a Windows boundary case. `/` was already refused by freshness checks, but `//` reached a missing pubspec with an empty derived scratch stem. The new caller regression failed before the fix with `PathNotFoundException` instead of preflight refusal.

An empty stem is now refused before scratch construction or input reads. Mounted path/staging verification passed all 24 tests with zero errors and terminal `success: true` in 180.203 seconds. A disposable direct probe confirmed `/`, `//` and the native separator fail before fetching and leave the working-directory `.raw` type unchanged. Actual CLI `artwork-refresh --packs assets/maps --pubspec .dart_tool/artwork-refresh-root-missing-pubspec.yaml --stage //` exited 1 with directory-name refusal rather than reading the missing pubspec. The probe and its exact temporary directory were removed.

`mise run analyze && mise run test -- --concurrency=1` passed in 427.67 seconds: analyzer clean and all 2,562 fast tests passed. No desktop app, companion or game was launched or inspected.
