# Offline evidence: title crop width

Collected 2026-10-17 on `main` at `5a1fe08`, after process-list checks found neither `EscapeFromTarkov.exe` nor `EscapeFromTarkov_BE.exe`. No game or app window was opened or captured.

## Inputs and reproducible baseline

- Recording: `20261014-122522`, supplied and reviewed by the user.
- Corpus: `F:\Dev\Dart\blackgrid-corpus\inspection`, 50 cases at 3440 x 1440: 35 expected items and 15 rejects. The user confirmed scans 0012 and 0013 as no-flea Weapon case `6a997c6e21aaf68dc6045d88` in this thread; those cases have now been added.
- Catalog: the existing seasonal snapshot; no catalog refresh was performed.
- Bundle: `build/windows/x64/runner/Release`, the previously built release. The runner executes the current Dart recognition source against its packaged native libraries/model.
- Command: set `BLACKGRID_RELEASE_BUNDLE` and `BLACKGRID_CORPUS_DIR`, then `mise exec -- flutter test --tags qualification test/qualification/inspection_corpus_test.dart`.
- Result: 26/35 correct item cases (74.29% coverage), four false positives, and all 15 reject cases rejected. The test completed successfully; without a reference baseline its success means the report was generated, not that recognition quality passed M2.
- Preserved report: local `out/before-fix-title-crop.json`. The reference companion baseline remains absent. Do not create `baseline.json` from Blackgrid outcomes and describe it as a reference result.

The five ambiguous failures are 0007 (ANA M1 OD Green), 0031 (Olight Baldr Pro), 0034 (Lancer L7AWM 25-round), 0037 (BS ammo pack) and 0051 (M855A1 ammo pack). Existing false positives are 0012/0013 (flea-listable Weapon case instead of no-flea) and 0016/0017 (MDR HCO preset instead of base rifle).

## Controlled width comparison

Inspected all five reported thresholded crops. They are 999 x 33 pixels, with readable black title text and a white right margin. The suspected close-button/chrome pixels are not visible in those crops.

A temporary Python/ctypes probe loaded the same bundle's `tesseract50.dll` and `eng.traineddata`, with the application's OEM 1 and PSM 13. For each saved crop it compared the original buffer with a copy ending eight pixels after its rightmost non-white pixel. All other pixels, height, model and OCR configuration were held constant. Each OCR operation cleared the engine image afterwards. Raw results are local `out/title-crop-probe.json`; the probe is local `%TEMP%\blackgrid-title-crop-probe.py`.

| Scan suffix | Original width | Trimmed width | Text from trimmed buffer |
| --- | ---: | ---: | --- |
| 0007 | 999 | 534 | ANA Tactical M1 plate carrier (OD Green) |
| 0031 | 999 | 595 | Olight Baldr Pro tactical flashlight with laser |
| 0034 | 999 | 647 | AR-10 762x51 Lancer L7AWM 25-round magazine |
| 0037 | 999 | 506 | 5.45x39mm BS gs ammo pack (38 pcs) |
| 0051 | 999 | 548 | 5.56x45mm M85SA1 ammo pack (188 pcs) |

Original buffers reproduced the report's trailing symbols. Trimming removed the suffix in all five. This supports the chain: the 500 x scale cap leaves excessive whitespace after short titles; raw-line OCR invents a suffix; that corrupts the matcher input. Remaining character/quantity misreads demonstrate why improved OCR text alone is not proof of a correct catalog identity. The full pipeline must still be requalified after implementation; this probe did not run title matching on its edited buffers.

The probe also removed a suffix from MDR 0016 and inserted the missing space in Weapon case 0012. Their identity outcomes after a crop fix are unverified. They must remain in the full comparison so that rejecting an existing wrong identity is distinguished from introducing a new one.

## Limits

- The corpus runner reconstructs a targeted strip from each saved full frame, which was captured later than the actual recorded strip. This replay does not establish live targeted-pass success or trigger latency.
- No reference companion comparison, clean-machine test or live-game retest has been performed in this session.
- The original handoff was copied beside the local corpus as `HANDOFF-20261014.md`, then removed from the repo to satisfy the clean-main branch gate.

## Qualification result after the fix

Run 2026-10-17 on `bugfix/fix-title-crop` at `61029e2` (recognition code last changed in `648120c`), with the same release bundle as the baseline (`build/windows/x64/runner/Release`: `blackgrid_vision.dll` built 2026-10-10, runtime manifest 2026-10-14) and the same corpus, labels and catalog. The process list showed neither Tarkov process in the shell call that then ran the command above. No app, companion or game was launched.

- Result: 31/35 correct item cases (88.57% coverage), two false positives, all 15 reject cases rejected.
- Local reports, outside Git: `out/before-fix-title-crop.json` (unchanged), `out/after-fix-title-crop.json` and the per-case comparison `out/comparison-fix-title-crop.json`.
- Comparison: every check passed. Case sets and labels are identical. All 26 previously correct items are retained, no case gains a false positive, and no already wrong case changes its wrong ID.

| Case | Before | After | After text, trimmed |
| --- | --- | --- | --- |
| 0007 ANA M1 OD Green | ambiguous | ambiguous: expected ID best at 1.0, runner-up 0.974 | ANA Tactical M1 plate carrier (OD Green) |
| 0031 Olight Baldr Pro | ambiguous | correct | Olight Baldr Pro tactical flashlight with laser |
| 0034 Lancer L7AWM 25-round | ambiguous | correct | AR-10 762x51 Lancer L7AWM 25-round magazine |
| 0037 BS ammo pack | ambiguous | correct | 5.45x39mm BS gs ammo pack (38 pcs) |
| 0051 M855A1 ammo pack | ambiguous | ambiguous: tie at 0.893 after a quantity misread | 5.56x45mm M85SA1 ammo pack (188 pcs) |
| 0016/0017 MDR | wrong (HCO preset) | correct (base rifle) | Desert Tech MOR 762x51 assault rifle |
| 0012/0013 Weapon case | wrong (flea-listable case) | wrong, same ID | Weapon case |

The remaining failures concern matcher ambiguity and catalog identity, not the crop margin. They stay visible in qualification and are outside this change.

**Unverified:** reference companion comparison (no reference baseline exists), accuracy at other resolutions (the corpus is 3440 x 1440 only), clean-machine check and live-game retest. Each needs the user or a later change.
