# Offline FIR qualification

## Boundary and build

All agent checks use saved images, synthetic buffers or offline fixtures. No game was launched, driven, captured or inspected. Process-name-only checks confirmed that EscapeFromTarkov, EscapeFromTarkov_BE and BEService were absent before native build work. Task 7.3 remains owner-only and unticked; this record does not establish live-game acceptance.

The existing running Blackgrid instance was left untouched. The standard build was blocked by its locked executable; Flutter's flavor migration also encountered the old output. A disposable, process-local Flutter configuration selects `build/fir-qualification` instead. No user Flutter setting was changed.

## Template reproduction

The owner source remains private under `.qualification/found-in-raid/`. The committed fixture manifest pins all twelve source identities. The FIR template uses the unresampled 28×28 crop at (1199, 732) from the 3440×1440 AFAK Yes image, with the specified integer grayscale conversion.

Two generator runs to separate outputs produced byte-identical files:

| Artifact | SHA-256 |
|---|---|
| Source JPEG | `0d5fbdccd97c07c5b9a82c97633059325c9142cbab27953c024c868c93e2169b` |
| FIR grayscale | `da803a9836846ede25ca471d693e66d7421397f8ae2517a2e38879f450ddb42a` |
| FIR metadata | `1d5666f0c966df1ea943ec72bf761fdcab57fead16e28db9d49a26bf1c8df23e` |
| Unchanged marker grayscale | `3b6771a1028cb438c14daf252e78fc9c1fe0cf8af79af5800b15681713c8e72f` |
| Unchanged marker metadata | `60321abd52ad2070508930b28c3c1c9b8fa724b3dc7af2fa260db2497ee162e3` |

## Logic and UI checks

- Capture regression tests first exposed nine old-height failures, then passed all 136 focused capture tests after the physical lower-band change and fixture migration.
- All 46 focused detector/job tests passed: thresholds, clipping, unreadable corners, residual-gold rejection, native failures, cache ownership and worker propagation.
- All 140 focused application tests passed: winning evidence only, initial advice/history, manual overrides, refresh/age stability, selection resets and epoch fences.
- All 11 focused FIR widget tests passed, covering Map and Scanner, selected-value manual taps, explicit Unknown, refresh and keyboard input.
- Offline `BlackgridApp` widget renders were inspected at widths 960 and 1672 in dark and light themes. The source caption remains visible and the narrow decision row wraps. Generated renders are local under `build/fir-ui/`; they are not live-window or live-game evidence. The throwaway render harness was removed.
- `mise run analyze`: no issues.
- `mise run test`: **3,081 tests passed**, excluding qualification-tagged tests. An incidental allowlist-inventory snapshot assertion was deleted rather than re-pinned; the behavior and safety-policy audit tests remain and pass.
- `openspec validate detect-found-in-raid --strict`: valid.
- `mise run release-notes -- --check openspec/changes/detect-found-in-raid/proposal.md`: accepted.

## Saved replay inputs

The existing targeted-region replay recordings and catalog are available outside the repository. Originals and their prior report are preserved.

| Input | SHA-256 |
|---|---|
| `blackgrid-replay/catalog.json` | `51a5e62dc232c8a73b9cccf012e8210f47c9db4bf06ae93be7203070993674c5` |
| `rec/20261014-122522/frames.jsonl` | `9a9574e822689dccc48252d4ab25c33724c68db433d2851f0398b5a61c9ff8d4` |
| `rec/20261017-130909/frames.jsonl` | `818bfcf81c6eaaea146a2b448212f5340191dc3ff81235e41a8270ad51035637` |

The preserved pre-FIR run used 70 frames: 39 full/targeted accept agreements, 31 both-rejected frames, zero hard conflicts and zero targeted misses. Its targeted latency was p50 51 ms / p95 74 ms / max 81 ms; full latency was p50 171 ms / p95 286 ms / max 305 ms. This is a historical baseline, not a controlled same-build A/B measurement.

## Built-bundle native FIR results

The isolated Windows Release build completed as **0.8.5+437** at `build/fir-qualification/windows/x64/runner/Release/`. The disposable build configuration was removed afterward. `mise run bundle:check -- build/fir-qualification/windows/x64/runner/Release` passed inventory, bindings, pins, imports, runtime versions, notices and both icon checks.

After confirming game/service absence again, the saved-image qualification ran against that bundle:

```sh
BLACKGRID_RELEASE_BUNDLE=F:/Dev/Dart/blackgrid/build/fir-qualification/windows/x64/runner/Release \
  mise run test:qualification -- test/qualification/inspection_fir_test.dart
```

Both tagged tests passed, including all nineteen native cases. Source identities and frozen annotations are in [`manifest.json`](../../../../test/fixtures/vision/fir/manifest.json). No labels or detector thresholds were changed after the run.

| Owner source | Expected | Actual | Reason | Native NCC | Readable negative admitted |
|---|---|---|---|---:|---|
| `afak_fir_yes_no_medal_3440x1440.jpg` | Yes | Yes | iconFound | 1.000000 | false |
| `afak_fir_no_no_medal_3440x1440.jpg` | No | No | iconAbsent | 0.000000 | true |
| `hk416_fir_yes_with_medal_3440x1440.jpg` | Yes | Yes | iconFound | 0.931217 | false |
| `hk416_fir_no_with_medal_3440x1440.jpg` | No | No | iconAbsent | 0.478737 | true |
| `hk416_fir_no_with_medal_1920x1080.jpg` | No | No | iconAbsent | 0.504178 | true |
| `hk416_fir_yes_with_medal_1920x1080.jpg` | Yes | Yes | iconFound | 0.897507 | false |
| `afak_fir_yes_no_medal_1920x1080.jpg` | Yes | Yes | iconFound | 0.960918 | false |
| `afak_fir_no_no_medal_1920x1080.jpg` | No | No | iconAbsent | 0.000000 | true |
| `m4a1_fir_yes_with_medal_cascade_1920x1080.jpg` | Yes | Yes | iconFound | 0.897820 | false |
| `ak308_fir_no_with_medal_cascade_1920x1080.jpg` | No | No | iconAbsent | 0.488068 | true |
| `m4a1_fir_yes_with_medal_cascade_3440x1440.jpg` | Yes | Yes | iconFound | 0.975847 | false |
| `ak308_fir_no_with_medal_cascade_3440x1440.jpg` | No | No | iconAbsent | 0.497923 | true |

The four independent left/top/right/bottom clips of the AFAK 3440 positive each returned `Unknown / cornerCutOff`, with no NCC score and no negative admission. The two partial-check blackouts returned `Unknown / cornerUnreadable`: width 12 scored 0.506396 and width 16 scored 0.365481. Both scores are below 0.60, but neither became No.

The translated 1080 M4A1 cascade placed its marker at (562, 400), with its complete D2 corner below the former 600-pixel targeted-band bottom. The widened 940-pixel band returned `Yes / iconFound`, NCC 0.897820. The 3440×1392 saved captures retained their 3440×1440 client geometry; the 1922×1082 bordered source was border-cropped while retaining 1920×1080 physical client geometry.

## Saved targeted-region replay result

The existing replay test ran with the same isolated bundle, both preserved recording directories and `BLACKGRID_REPLAY_CATALOG=F:/Dev/Dart/blackgrid-replay/catalog.json`, writing a new report to `F:/Dev/Dart/blackgrid-replay/run-fir-20261111/out/replay.json`. Game/service absence was confirmed immediately before the run. The tagged test passed.

All 70 frames were evaluated: **37 full-client accepts, all 37 also accepted by the targeted pass; 33 both-rejected frames; zero conflicts and zero targeted misses**. No winner was outside the new band and no in-band winner was rejected only by the targeted pass.

| Measurement | Historical pre-FIR run | Current 0.8.5+437 |
|---|---:|---:|
| Full/targeted accept agreements | 39 | 37 |
| Both rejected | 31 | 33 |
| Conflicts | 0 | 0 |
| Targeted misses | 0 | 0 |
| Targeted p50, ms | 51 | 72 |
| Targeted p95, ms | 74 | 104 |
| Targeted max, ms | 81 | 108 |
| Full-client p50, ms | 171 | 154 |
| Full-client p95, ms | 286 | 256 |
| Full-client max, ms | 305 | 268 |

The historical report was produced by 0.1.0+321, not this branch's immediate base. Different application versions and run conditions prevent attributing its acceptance-count or latency differences to FIR. This gate proves current targeted/full-client agreement and records the requested timing comparison; it does not establish cross-release recognition parity.

## Remaining owner acceptance

Task 7.3 is unverified and remains unticked. The owner must perform its live-game scenarios and record their observed version/results. No archive or live-game acceptance is implied by the offline passes above.

## PR review round 1

The scale regression first failed in both detection and geometry planning with `UnsupportedError: Infinity or NaN toInt`. The fix rejects non-finite scaled offsets as `ArgumentError` in the planner and returns unreadable evidence when the squared witness scale overflows, before any matching. Finite products are reused rather than recomputed. All **47 focused detector/worker tests passed**, including `double.maxFinite` offset overflow and finite-scale witness-area overflow.

The bordered-source sentence above was also corrected to distinguish its 1922×1082 image from its declared 1920×1080 physical client, matching the frozen manifest and the already-qualified normalization path. No source labels, thresholds, native scores or client geometry were changed.

After the review fix, `mise run analyze` reported no issues and `mise run test` passed all **3,082** fast tests. Owner-only task 7.3 remains unverified.
