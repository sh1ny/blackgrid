# Review

## Metadata

- **Round:** 2
- **Prior round:** 1
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer)
- **Reviewed:** `proposal.md`, `design.md` (TIER: FULL), `specs/scan-pipeline/spec.md`, `specs/scanner-evidence/spec.md`; main specs `openspec/specs/scan-pipeline/spec.md`, `openspec/specs/scanner-evidence/spec.md`; `openspec/architecture.md`; ADR-0010, ADR-0013; source `lib/application/scan_coordinator.dart`, `lib/application/app_services.dart`, `lib/ui/scanner_screen.dart`, `lib/ui/scan_evidence_panel.dart`, `lib/ui/shell.dart`, `lib/data/capture/capture_policy.dart`; tests `test/ui/shell_test.dart`, `test/ui/scan_evidence_panel_test.dart`, `test/ui/support/scan_ui_support.dart`, `test/application/support/fake_scan_ports.dart`, `test/application/scan_coordinator_flow_test.dart`; fork `Services/ScannerOrchestrator.cs`, `MainWindow.xaml.cs`, `Services/ScannerStateStore.cs`; `docs/IMPLEMENTATION_STRATEGY.md:35,196`. Nothing was built, run or tested.
- **Re-check (round 1):** the same reviewer, in a new run, re-checked Required Changes 1-4 against the updated `specs/scan-pipeline/spec.md` (MODIFIED "One scan in flight, latest trigger wins"), `specs/scanner-evidence/spec.md` (MODIFIED "Scan phase is visible, including fallback", plus the scenario "Crop and timings after a rejection"), design.md D1 (Wiring, Tests) and D3 (Crop, Timings), and the proposal's Impact. All four hold. One leftover, which does not affect the verdict: design.md D1 still says "The fork measures from enqueue" in its second Rejected bullet, while its Scope bullet and the ADR-0014 note now say the fork's settle starts at dequeue.
- **Re-check (round 2):** a new fresh-context reviewer checked the two "*Amended during apply:*" bullets in design.md D4 and task 5.2 against `specs/scanner-evidence/spec.md` ("Scan evidence panel is visible without scrolling" and its three scenarios, "Footer shows the live scan state"), the rest of D4 and D5, and the uncommitted diff of `lib/ui/scanner_screen.dart`, `lib/ui/shell.dart`, `lib/ui/manual_controls.dart` and `test/ui/shell_test.dart`. Confirmed in `lib/ui/shell.dart`: the Scanner screen sits in `Padding(padding: EdgeInsets.all(14))` (`:158-160`) between a `66 × scale` header and a `34 × scale` footer, so the 28 px claim is right. Computed by hand, not run: at 1100x720 the screen gets 1072 x 592, `1072 + 28` is not below 1100, so the desktop layout is used. Nothing was built, run or tested.

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

### Round 2

The amendment satisfies the spec. Evidence now sits at the top of the right column, so at 1100x720 its frame spans y 80 to about 492 with the page at rest (`0.6 × (700 − 14)` ≈ 412 px tall). At 1660x870 it spans about 80 to 497. The new breakpoint is right: windows of 1100 to 1127 px get the desktop layout. The inner `SingleChildScrollView` sized `max(available, 760 × scale)` removes the 117 px overflow without hiding any control. `isExpanded: true` on the dropdown is a safe width fix. D5 matches `_liveScanFooter` row for row. The compact order is unchanged.

#### Moderate (round 2)

1. **The amended D4 says "The page itself never scrolls", but at 1100x720 it does.**
   - The desktop branch still wraps the row in `SingleChildScrollView(key: 'scanner-desktop-scroll')` with `height: math.max(constraints.maxHeight, 700 * scale)` (`lib/ui/scanner_screen.dart:89-92`).
   - At 1100x720 the screen gets 592 px of height (`720 − 66 − 34 − 28`), so the row is 700 px and the page has 108 px of scroll extent. The Scanner panel's bottom is at about y 780, 60 px below the window, and only a page scroll reaches it. Its controls therefore scroll in two nested views, the panel's own and the page's. The same holds for any window shorter than about 828 px, and for larger windows at text scale 1.25 and 1.5.
   - The spec is still met, because it asks for the frame to be on screen "without scrolling the page", and the evidence panel is at the top. But the design records a property the code does not have. A later test or change written from D4 ("page never scrolls") would fail or remove the 700 px floor that protects the middle column from overflowing.
   - The tests do not show the gap. The 1660x870 test asserts `page.position.pixels == 0`, which nothing in the test could change, so it proves nothing. At that size the page cannot scroll anyway (742 > 700). The 1100x720 test does not look at the page scroll at all.

#### Suggestions (round 2)

1. **Derive the breakpoint from the window, not from the shell's padding.** `_shellPadding = 28` in `scanner_screen.dart:17` copies `EdgeInsets.all(14)` in `shell.dart:160`, and neither file names the other. The risk is small. If the shell padding grows, the 1100x720 test fails, because the compact layout puts evidence at y 854 or lower. If it shrinks, windows a few px under 1100 get the desktop layout, which does no harm. `MediaQuery.sizeOf(context).width < desktopWindowWidth` measures the window, as the spec says, and removes the coupling. It is not required.
2. **Make the layout tests prove what they claim.**
   - 1660x870: assert `page.position.maxScrollExtent == 0`, not `pixels == 0`.
   - 1100x720: assert `page.position.pixels == 0` before reading the frame (the requirement says "without scrolling the page"), and assert the desktop layout explicitly, for example `evidence.left > scanner.right`. Today the desktop layout is only proven indirectly, because the compact layout would put the frame below 720.
   - The footer tests cover the three spec scenarios. `starting` and `stopping` have no test, and neither does the gold colour for `ready`. The spec has no scenario for them, so this is optional.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

Round 2 verdict. The amended D4 meets the spec and does not break D5 or any other requirement. One design statement is wrong about the code (Moderate round 2, item 1).

## Required Changes

### Round 2

1. In design.md D4, replace "The page itself never scrolls" with what the code does. The desktop page keeps its `700 × scale` minimum height and scrolls when the screen area is shorter (108 px at 1100x720, where the Scanner panel's bottom is reachable only by that scroll). The evidence panel is at the top of the right column, so its frame is fully on screen while the page is unscrolled. Alternatively, remove the 700 px floor and show that the middle column does not overflow at 1100x720. In either case, the 1100x720 test in `test/ui/shell_test.dart` must assert that the page scroll offset is 0 when it reads the evidence frame.

### Round 1 (applied, see Rebuttals)

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
- **Round 2, required change 1:** fixed by correcting D4. The desktop page keeps its `700 × scale` floor (it stops the middle column overflowing); D4 now says the page scrolls on short windows (108 px at 1100x720) and that the Scanner controls are then reached through both scrolls. The 1100x720 test asserts the page offset is 0 when it reads the evidence frame.
- **Round 2 suggestions:**
  - Applied: the 1660x870 test asserts `maxScrollExtent == 0`, and the 1100x720 test asserts the desktop layout directly (evidence right of the Scanner panel).
  - Not applied: measuring the breakpoint with `MediaQuery` instead of the 28 px shell padding allowance. The reviewer rated the coupling a small risk, and `ScannerScreen` measuring its own constraints keeps it correct when hosted in a narrower box.
  - Not applied: tests for the `starting` and `stopping` footer texts and the `ready` gold colour, which have no spec scenario.
