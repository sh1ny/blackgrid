# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer)
- **Reviewed:** `proposal.md`, `design.md` (TIER: FULL), `specs/scan-pipeline/spec.md`, `specs/scanner-evidence/spec.md`; main specs `openspec/specs/scan-pipeline/spec.md`, `openspec/specs/scanner-evidence/spec.md`; `openspec/architecture.md`; ADR-0010, ADR-0013; source `lib/application/scan_coordinator.dart`, `lib/application/app_services.dart`, `lib/ui/scanner_screen.dart`, `lib/ui/scan_evidence_panel.dart`, `lib/ui/shell.dart`, `lib/data/capture/capture_policy.dart`; tests `test/ui/shell_test.dart`, `test/ui/scan_evidence_panel_test.dart`, `test/ui/support/scan_ui_support.dart`, `test/application/support/fake_scan_ports.dart`, `test/application/scan_coordinator_flow_test.dart`; fork `Services/ScannerOrchestrator.cs`, `MainWindow.xaml.cs`, `Services/ScannerStateStore.cs`; `docs/IMPLEMENTATION_STRATEGY.md:35,196`. Nothing was built, run or tested.
- **Re-check (round 1):** the same reviewer, in a new run, re-checked Required Changes 1-4 against the updated `specs/scan-pipeline/spec.md` (MODIFIED "One scan in flight, latest trigger wins"), `specs/scanner-evidence/spec.md` (MODIFIED "Scan phase is visible, including fallback", plus the scenario "Crop and timings after a rejection"), design.md D1 (Wiring, Tests) and D3 (Crop, Timings), and the proposal's Impact. All four hold. One leftover, which does not affect the verdict: design.md D1 still says "The fork measures from enqueue" in its second Rejected bullet, while its Scope bullet and the ADR-0014 note now say the fork's settle starts at dequeue.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

The core mechanism holds up against the code. The waits go into `_flow`. `_dead` is checked after each wait. `_onTrigger` starts a new scan right away when the old one is waiting. `_abandonScans` completes the scan's `cancelled`. The cap on the wait covers the missing-clock case. Ownership is clean: `_lastAccepted` has one writer, `_publish`, and is bounded at one report. I found no Critical issue. Each finding below is a gap between the design and code or specs that already exist.

### Critical (blocking)

None.

### Moderate

1. **The delta contradicts two main requirements it leaves unchanged.**
   - `openspec/specs/scan-pipeline/spec.md:115-117` ("One scan in flight, latest trigger wins") says: "A trigger arriving during a scan SHALL supersede that scan and take the pending slot. ... The pending trigger SHALL start once the superseded scan's native stage returns or its vision request is invalidated."
   - The new requirement "A trigger during a wait supersedes the scan at once" says the new scan "SHALL start right away, without the pending slot". The proposal says the existing requirements stay unchanged, so both SHALLs would be in force and contradict each other.
   - `openspec/specs/scanner-evidence/spec.md:28` ("Scan phase is visible, including fallback") says Scanner shows `fallback underway` "from the fallback capture request until the scan ends". The new fallback requirement publishes the phase before a wait of up to about 200 ms that comes before that request. That is what this change intends, but it no longer matches the main text.
   - Consequence: the archived specs would state two incompatible rules for a trigger during a wait. A test written from the old requirement would fail against the new behaviour, or the other way round.

2. **The panel's crop and timings are tied to `latest`, and D3 does not rebind them.**
   - `_syncImage` decodes the crop of `widget.scanner.latest`, keyed by report id (`lib/ui/scan_evidence_panel.dart:70-72`).
   - `_report` draws the TIMINGS block inside the evidence view of the report it is given (`:160-177`).
   - D3 only says the panel shows `lastAccepted ?? latest` and that "timings ... keep reading `latest`". Once a rejected scan follows an accepted one, there are two outcomes:
     - If the image sync is left as it is, the accepted view shows the rejected scan's crop, or no crop at all. The modified "Accepted scan" scenario requires the accepted scan's crop.
     - If `_report(lastAccepted)` is reused as it is, the timings shown belong to the accepted scan, which breaks the new "timings SHALL still follow the latest published scan".
   - Neither case is caught by the planned test ("accepted view with a later rejection") unless it checks the crop and the timings' scan id.

3. **The default `Timer` waiter turns existing offline tests into real-time waits, and the widget harness cannot inject a fake.**
   - The coordinator test rigs construct `ScanCoordinator` without the new parameters (`test/application/support/fake_scan_ports.dart`, `test/ui/support/scan_ui_support.dart:276`).
   - `FakeScanClock.now` starts at 0 and the tests fire triggers at qpc 1000 (`fake_scan_ports.dart:439-441`, `scan_coordinator_flow_test.dart:297` and others). With the planned cap, every existing scan waits a real 50 ms, and every fallback path waits a real 200 ms, inside `runAsync` or on real timers.
   - `AppServices` builds the coordinator with a fixed argument list and no waiter or delay parameter (`lib/application/app_services.dart:82-91`). So `pumpM1`-based tests (`shell_test.dart:67,100`, `scanner_screen_test.dart:114`) cannot inject a waiter at all.
   - Consequence: about 45 flow tests plus the panel, shell and scanner-screen tests gain real-time sleeps in `mise run test`. That breaks the AGENTS.md rule "Never wait with arbitrary sleeps ... use ... fake clocks". The proposal's "tests use a fake clock and completers, never real sleeps" holds only for the new tests.

### Suggestions

1. **Correct the fork parity record before it goes into ADR-0014.**
   - Settle wait: the fork waits a full 50 ms after the worker dequeues the request, for every request (`ScannerOrchestrator.cs:182-183`). It does not measure from enqueue. Only the fallback deadline is measured from `EnqueuedAtUtc` (`MainWindow.xaml.cs:727-728`).
   - Fallback wait: the fork applies it only to `ScannerScanSource.Automatic` (`MainWindow.xaml.cs:763-768`). D1's claim that "the M4 hotkey inherits the waits with no extra work" therefore diverges from the fork for the fallback wait on manual scans.
   - Record both facts so M4 makes that choice on purpose.

2. **Add `stopping` to the footer requirement.** D5 maps `stopping` to "Live scan stopping", but the spec lists only `off`, `starting`, `ready` and `unavailable`. While stopping, a capture can still be draining (2 s close drain, ADR-0010). The spec should say that no "no capture" claim is shown in that state either.

3. **Give the settle THEN an upper bound.** "requested no earlier than 50 ms after the trigger, and not before" is met by a wait of any length. Assert as well that the capture is requested once the 50 ms have passed, for example that the injected waiter is asked for the remaining time, so a wrong deadline such as `delay` plus elapsed time fails the test.

4. **State the left-column sizing in D4.** Today the left column is a fixed `760 * scale` inside its own scroll view (`scanner_screen.dart:76-83`). The desktop row's minimum height is `700 * scale` (`:69`). Without the nested scroll view, the Scanner panel shrinks to the row height, and `ManualControls` absorbs the loss. Say whether that is intended, so the 1.25 and 1.5 scale overflow tests in `shell_test.dart:9-28` are not a surprise.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. In `specs/scan-pipeline/spec.md`, add a `## MODIFIED Requirements` entry for "One scan in flight, latest trigger wins". Copy the full main text and narrow the pending-slot sentence to a scan in its capture stage. State that a trigger during a wait or during vision or matching starts the new scan at once. Keep all existing scenarios.
2. In `specs/scanner-evidence/spec.md`, add a MODIFIED entry for "Scan phase is visible, including fallback". Change "from the fallback capture request" to "from the start of the fallback pass, including its wait before the fallback capture request". Keep both existing scenarios.
3. In design.md D3, state that the title crop is decoded for the shown report (`lastAccepted ?? latest`), keyed by that report's id. Also state that the TIMINGS block is drawn apart from the main evidence, for `latest`, and labelled with `latest`'s scan id. Add a scenario to the "A later unaccepted scan is shown as a note" requirement: after the rejection, Scanner still shows item A's crop, and the timings shown are scan 2's.
4. In design.md D1 and the proposal's Impact, add `lib/application/app_services.dart`: it forwards the waiter and the delays to `ScanCoordinator`. State that the test rigs (`test/application/support/fake_scan_ports.dart`, `test/ui/support/scan_ui_support.dart`, `test/support/m1_widget_harness.dart`) default to an immediate waiter. Only the wait tests inject a controllable fake waiter, so no existing test waits in real time.

CHANGES_APPLIED: yes

## Rebuttals
- **Required change 1:** fixed. `specs/scan-pipeline/spec.md` has a MODIFIED "One scan in flight, latest trigger wins": the pending slot applies to the capture stage only, and a trigger during a wait, vision or matching starts the new scan at once. All scenarios are kept, and the vision scenario now says "settle wait starts".
- **Required change 2:** fixed. `specs/scanner-evidence/spec.md` has a MODIFIED "Scan phase is visible, including fallback", worded as requested, with both scenarios kept.
- **Required change 3:** fixed. D3 has "Crop" and "Timings" bullets, and the scenario "Crop and timings after a rejection" is added.
- **Required change 4:** fixed. D1 has "Wiring" and "Tests" bullets, and the proposal's Impact lists `app_services.dart` and the test rigs.
- **Suggestions, applied:**
  - Fork parity: D1 Scope and the ADR-0014 note now record that the fork's settle starts at dequeue and its fallback wait covers automatic scans only.
  - The footer spec lists `stopping`.
  - The settle scenario asserts the exact 49 ms remaining wait.
  - D4 says the left column fills its height and `ManualControls` scrolls.
