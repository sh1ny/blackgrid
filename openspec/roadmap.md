# Blackgrid Roadmap

Strategy: [STRATEGY.md](../STRATEGY.md) · Architecture: [architecture.md](architecture.md) · Historical source: [implementation strategy §11–§12](../docs/IMPLEMENTATION_STRATEGY.md#11-migration-plan)

<!-- Status is derived: a change is done when archived; a milestone is done when its changes are done and its exit criteria pass. Do not add status checkboxes for changes. -->

Milestone IDs keep the implementation strategy's numbering (M0–M6), so they match the CE-era plans and qualification evidence. M2 and M3 were planned as independent after M1; M5 was explicitly authorized before the Scanner milestones ([§11](../docs/IMPLEMENTATION_STRATEGY.md#11-migration-plan)). "(user)" marks a criterion only the user can verify: anything that needs the game running, a real saved game screenshot, or a clean Windows machine. Agents never run those checks ([AGENTS.md](../AGENTS.md)). Until the user reports a result, it is unverified, never passed.

## Now: M2 - capture/recognition proof

**Outcome:** A real Windows mouse release over an item inspection captures a direct physical-pixel ROI, recognises marker, title, OCR text and catalog identity in a worker off the UI isolate, falls back to a full-viewport pass when the targeted pass is not accepted, and shows that evidence in Scanner while the UI stays responsive. Decisions, correction, history and the accepted Map snapshot stay M4.

Retires risks 1 (recognition coverage, wrong identities, ROI/DPI drift) and 2 (FFI packaging, buffer lifetime, long native calls) from [§12](../docs/IMPLEMENTATION_STRATEGY.md#12-risks-and-prototypes) and proves the [§7](../docs/IMPLEMENTATION_STRATEGY.md#7-windows-integration-strategy) capture contract.

**Exit criteria:**
- The OpenCV and Tesseract binaries and the traineddata chosen for item recognition have source, version and terms recorded in `THIRD_PARTY_NOTICES.md` before they enter a build. (agent)
- The Release bundle contains every native DLL and model it needs; each is hash-bound and loaded from the bundle; no system installation is used. Offline bundle integrity check passes. (agent)
- The same bundle launches and recognises on a clean Windows machine. (user)
- A blocked or slow native call cannot freeze the UI isolate, cannot start a second call on the same OCR handle, and cannot publish after supersession or shutdown. Fixture tests use controlled native barriers. (agent)
- Deterministic capture-geometry fixtures cover all 16 resolution/scaling cells, signed negative monitor origins and clipped ROIs, and produce typed failures for changed, minimised or wrong targets. (agent)
- The fixed positive/negative screenshot corpus has expected item IDs or rejections labelled independently of the reference. (user)
- On that corpus, offline recognition reports marker score, title crop, OCR text, candidate scores and the accepted ID or rejection per case, with coverage and false positives compared against the reference baseline. (agent, once the corpus and baseline exist)
- Live cursor-triggered capture over the game produces evidence for real items at the user's resolution and DPI, falls back visibly, and the UI stays responsive, with stage timings recorded. (user)

**Changes** (in order; each about one PR):
1. `add-native-vision-runtime` - select, rights-check and package OpenCV (dartcv4/opencv_dart candidate) and an owned minimal Tesseract C-API binding with traineddata; hash-bound loading from the bundle, as the panel OCR DLL already does.
2. `add-windows-capture-boundary` - a dedicated-thread low-level mouse-release hook with a bounded queue, foreground HWND/process identity, signed physical client geometry and DPI, direct ROI BitBlt plus full-client fallback capture, and an immutable owned-buffer contract with typed failures. Independent of change 1.
3. `add-vision-worker` - a warm dedicated isolate owning templates, OCR handles and scratch buffers; explicit buffer ownership and release; one active plus one replaceable pending request; generation fences; drain on shutdown. Needs change 1.
4. `add-inspection-recognition-pipeline` - marker correlation, scaled title ROI, threshold, OCR, FormKC normalisation and guarded Levenshtein matching against the immutable catalog, with the baseline gates (.82 / .55 / length 3 / margin .05) and quantity and UI-chrome safeguards; offline corpus tests. Needs change 3.
5. `add-scanner-evidence-slice` - wire trigger → capture → worker → evidence into the Scanner area, with stage timing instrumentation and visible fallback state; no recommendation is shown from unaccepted evidence. Needs changes 2 and 4.

## Next: M4 - complete raid-time Scanner slice

Mouse and hotkey (`RegisterHotKey`) triggers drive recognition through the mode-correct catalog, session progress and the existing shared decision engine into Scanner advice, correction and history, usable while Map is open; accepted scans feed the passive Map snapshot (`lib/application/session_scan_state.dart` has no producer yet). Retires risk 6 (input/mode/map/refresh races) and closes the latency gate: targeted ≤300 ms p95, fallback visibly underway by about 300 ms, ≤1.5 s p95 total from the original trigger, with coverage at least the reference and false positives no worse. The reference timing baseline that M0 left unverified must be recorded on the named Windows setup first. (user)

## Later

- M6 - replacement qualification: clean-machine release bundle with packaged DLLs/models/artwork and notices; full display and mixed-monitor matrix; offline, refresh and auth failures; restart, import and history correctness (risks 3 and 7); [§14](../docs/IMPLEMENTATION_STRATEGY.md#14-definition-of-done) definition of done. Also closes the user-only checks M3 waived and M5 left pending (real saved panels, extract/transit highlights, automatic floors).

## Done

- M0 - reference qualification and provenance - 2026-10-06 ([PR #1](https://github.com/sh1ny/blackgrid/pull/1), [PR #2](https://github.com/sh1ny/blackgrid/pull/2)) - [plan](../docs/plans/2026-10-05-1006-test-m0-reference-qualification-plan.md), [evidence](../docs/qualification/m0/) - Delivered the rights-gated dossier, protocol and validators. The reference baseline, labelled corpus and display matrix remain unverified or blocked; that did not block authoring new code, and the remaining checks now sit in M2, M4 and M6.
- M1 - shared shell and decision foundation - 2026-10-06 ([PR #3](https://github.com/sh1ny/blackgrid/pull/3)) - [plan](../docs/plans/2026-10-06-0242-feat-m1-manual-item-decisions-plan.md), evidence: no `docs/qualification/` record; offline tests and [`integration_test/m1_windows_smoke_test.dart`](../integration_test/m1_windows_smoke_test.dart) - The conservative decision engine, mode-scoped catalog, read-only Tracker and DPAPI credentials landed as pure, testable layers that Scanner can reuse.
- M3 - native map proof - 2026-10-06 ([PR #4](https://github.com/sh1ny/blackgrid/pull/4)) - [plan](../docs/plans/2026-10-06-1026-feat-m3-native-map-proof-plan.md), [evidence](../docs/qualification/m3/STATUS.md) - The native renderer was proven on Interchange, Labs and Icebreaker and chosen over a WebView. Delivered under the user's explicit verification waiver: full qualification is not claimed.
- M5 - complete useful native Map - 2026-10-07 ([PR #7](https://github.com/sh1ny/blackgrid/pull/7)) - [plan](../docs/plans/2026-10-07-0050-feat-m5-independent-useful-map-plan.md), [evidence](../docs/qualification/m5/STATUS.md) - All 13 maps were promoted and the user's live map/position check passed. Functional parity with the user's reference companion replaced stricter blocking gates (publisher-deleted `<use>` ids, Windows.Media.Ocr for raid panels). The real saved-panel check is still pending. (user)
