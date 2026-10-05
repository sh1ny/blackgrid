# Private reference measurement recipe

This is a developer-only recipe, not a recorded run or authorization to execute the reference. The current intake is not a final source lock. Private-use clearance, an owner-controlled durable archive, effective local catalog/configuration inputs, independently adjudicated eligible fixtures, and resolved native/build inputs are required before materialization or replay. No native oracle or companion was executed during metadata intake.

## Permission and isolation

1. Record use-specific reviewed dispositions for every source, model, binary, catalog and fixture. `private_reference` clearance does not clear repository fixture bytes or report attachments.
2. Declare the complete effective file set and exact configuration. Use `freeze_reference.ps1` in metadata-only `Intake` mode first. Use `Lock`/`Materialize` only with complete categories, scoped permission, and an explicit new private destination. Do not modify the user's reference checkout.
3. Retain the base snapshot, adapter source, instrumentation patch/source, package/native/model closure, and exact build/replay recipe in an owner-controlled durable private archive. Record portable evidence locators and hashes separately from private absolute workspace paths. An ignored local build directory alone is not reproducibility.
4. Rehash the declared source/input closure before and after each run. Changed inputs invalidate that run; never refresh expected labels to make it pass.
5. Before any permitted native/companion execution, obtain a fresh process-name observation confirming Escape from Tarkov is absent. If absence cannot be confirmed, do not execute. Never launch, focus, capture, inspect or automate a game. Every game-dependent acquisition/measurement is user-only.

## Offline profile boundaries

The frozen host targets .NET 10 Windows x64 and references the pinned RatEye project. The saved-image RatEye benchmark is engine prior art, not host acceptance or advice evidence.

| Profile | Existing seam | Required limitation |
| --- | --- | --- |
| `engine_inspection` | `RatEyeInspectionRecognizer.Recognize` with an explicitly supplied saved-image `CapturedInspection` | No desktop capture, input callbacks, WPF startup, HTTP, credential or personal-settings loading |
| `engine_multi` | `RatEyeInspectionRecognizer.RecognizeAllAndDispose` | Associate detections with independently labeled inspection geometry, not list order |
| `host_resolution` | `ScannerItemMatcher.Match`; `ScannerDecisionResolver.ResolveAcquisition` and `Resolve`, using constructed local catalog/progress projections | Engine recognition is not accepted host identity or actionable advice |
| `map_geometry` | `MapGeometryService.TryProject`, `TryUnproject`, floor selection and bearing helpers | Reference math does not create independent landmark truth |
| `exfil_panel` | `ScreenshotExfilParser.ParseAsync` on an authorized local image file | Missing panel is not authoritative present-empty output; Windows panel OCR differs from item Tesseract |

Freeze the host's English/LSTM/RawLine settings, scale calculation, disabled static-icon/cache selections, preprocessing and acceptance settings. Bind exact effective values, not benchmark defaults. Synthetic progress must be explicit and mode-correct; do not load a real account or Tracker token.

Before full characterization, prove a positive, genuine negative and numeric/ambiguous case through the actual frozen native-plus-host path. Preserve errors and missing stages. A source inspection or synthetic comparator test is not this proof. No such native proof is recorded yet.

## Internal clock and event record

Use process-local `Stopwatch.GetTimestamp()` ticks and `Stopwatch.Frequency`; record the frequency, run/clock-domain identity and request generation. UTC is collection metadata only. Each internal interval must have the same frequency and domain at both boundaries. Do not subtract ticks from a recording timestamp.

Instrument existing boundaries in the private copy:

- Physical-trigger software receipt: `hook_receipt` for automatic triggers; `manual_command_receipt` for manual commands. These are not physical actuation timestamps.
- `enqueue`, `worker_dequeue`, capture start/end, targeted completion.
- Fallback deadline, actual fallback work start, and fallback completion as separate events. A reached deadline or displayed timeout is not running fallback.
- Host match completion, decision completion, acceptance/publication, and UI assignment.
- Terminal outcome for every request: identified-correct, wrong identity, rejection, error, canceled, superseded, incomplete. Record one disposition even when the newest pending request replaces it.

Keep callbacks light: append integer events to a bounded buffer and flush after the timed work. No synchronous trace disk writes, formatting, extra screenshots or payload copies on the measured path. Bind instrumentation source/patch/build hashes to the freeze. Measure game-closed tracing-enabled versus tracing-disabled repeats and retain perturbation observations before any user live run. Perturbation is currently unmeasured.

QPC-only publication/assignment intervals are internal observations. WPF property assignment and `DwmFlush` do not establish a generic actionable visible frame.

## User-operated observation clock

The user records physical mouse release/hotkey actuation and the result in one high-frame-rate recording timeline. For each request, annotate the last frame before/first frame after physical actuation, and the last frame without/first frame with correct item, verdict and uncertainty information. Decorative icon completion is not the endpoint. Preserve source frame timestamps and variable frame rate.

Record request ordinal/generation, case ID, trigger kind, recording method/resolution, correctness, linkage, visibility/occlusion and observation overhead. Calculate elapsed bounds within that same recording:

- lower = first-actionable interval lower bound minus physical-actuation interval upper bound;
- upper = first-actionable interval upper bound minus physical-actuation interval lower bound.

An invalid request linkage, unobserved actuation, occluded result or absent actionable endpoint yields an unavailable latency with a reason. Do not estimate it from acceptance/UI assignment. Genuine visible fallback onset is a separate observed running phase linked to actual fallback work, not the final recognized result or a timeout label.

Correlation between video and QPC request IDs is not clock calibration. Only a calibrated cross-clock alignment may support a hook-receipt-to-visible interval; same-video physical-to-visible bounds and QPC-only intervals need no cross-clock subtraction.

## Allocation and reporting

Freeze case order, named setup/native display cell, viewport/UI settings, display mode, cache state and observer configuration before collection. Keep automatic and manual routes separate within each intended path and terminal outcome. Never replace failures until a success quota is reached.

The allocation and finite human handoff are recorded in `docs/qualification/m0/protocol.md` and `planned-checks.json`. Nearest-rank p95 selects sorted sample `ceil(0.95*N)`. Report completed-sample N, all-trigger outcome counts, unique master/source coverage, lower/upper video quantiles and missing-stage counts. Zero eligible samples means null plus a reason. Replays/derived variants do not increase unique master coverage. Slow or wrong faithfully recorded reference output is a defect observation, not invalid evidence.

## Missing prerequisites

No reviewed private-reference grant, final effective source lock/archive, independently labeled 36-master image corpus, 13-map/39-control survey, permitted real panel corpus, native replay proof, trace perturbation result, game-closed companion baseline or user live recording currently exists in this M0 dossier. These are required unverified checks, not not-applicable exclusions. No build/replay command should be inferred from this recipe before the exact permitted adapter and build identities are established.

Sources: inspected reference `TarkovTracker.csproj`, `Services/RatEyeInspectionRecognizer.cs`, `Services/ScannerItemMatcher.cs`, `Services/ScannerDecisionResolver.cs`, `Services/MapGeometryService.cs`, `Services/ScreenshotExfilParser.cs`, `Services/ScannerOrchestrator.cs`, and `MainWindow.xaml.cs`; [Microsoft QPC guidance](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps), [.NET Stopwatch frequency](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.stopwatch.frequency?view=net-10.0), and [DwmFlush scope](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/nf-dwmapi-dwmflush).
