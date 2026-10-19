# Review

## Metadata

- **Round:** 1
- **Prior round:** none
- **Re-check (round 1, Required Changes only):** re-read the revised design.md (D5, D6, D10, Failure & Visibility, Flow & State Gaps) and the three delta specs against Required Changes 1-3 and the S1-S5 edits. Required Changes 1-3 are applied as written. Two of the suggestion edits introduce new inconsistencies, listed as Required Changes 4 and 5 below.
- **Re-check 2 (Required Changes 4 and 5 only):** re-read the `scan-pipeline` "The pipeline publishes the hotkey state" requirement and its "Hook thread does not stop" scenario, D5 "Abandoned requests", and the `scan-triggers` scenario "Late answer after a timeout". Both changes are applied, and they resolve the partial acceptances of S2 and S4.
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer). Project skills loaded: dart-use-pattern-matching, dart-write-documentation, dart-add-unit-test, dart-run-static-analysis, flutter-add-widget-test.
- **Reviewed:** proposal.md, design.md, specs/scan-triggers/spec.md, specs/scan-pipeline/spec.md, specs/scanner-evidence/spec.md; main specs openspec/specs/scan-triggers, scan-pipeline, scanner-evidence; ADR-0010, 0013, 0014, 0016, 0017 (hotkey, schema and wait passages); source windows/capture/capture.h, capture_internal.h, hook.cpp; lib/data/capture/mouse_release_trigger_source.dart, capture_native.dart, capture_geometry.dart; lib/application/scan_coordinator.dart (trigger port, platform, `_onTrigger`, `_runStart`, `_waitUntil`, `setLiveScan`/`_save`/`_savesLanded`/`_dispose`, log line); lib/application/settings_controller.dart; lib/domain/settings.dart; lib/ui/live_scan_panel.dart; test/data/capture/capture_source_audit_test.dart; test/data/capture/support/fake_hook_platform.dart.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. D10's audit ban on `WH_KEYBOARD` does not catch `WH_KEYBOARD_LL`.**
D10 says adding `WH_KEYBOARD` "also catches `WH_KEYBOARD_LL`". The audit matches with `RegExp(r'\b(' + _banned.join('|') + r')[AW]?\b')` (`test/data/capture/capture_source_audit_test.dart:66`). In `WH_KEYBOARD_LL`, the character after `WH_KEYBOARD` is `_`, which is a word character, so the trailing `\b` fails and nothing matches. The result is that a later change could install the exact keystroke-seeing hook D10 exists to prevent, and the audit would still pass. This is the mechanism-ledger row "Exceeding the ban-risk ceiling is irreversible". The gate fails silently on the one case it is meant to catch.

**M2. "Restore after a failed save" can leave the new key registered while the state says it is not.**
D5 restores with `setHotkey(old)`, and the native swap is transactional: a refused key "leaves the old registration in place". The Failure table says a refused restore makes the state `unavailable(old, reason)`. But the "old registration" the native side keeps at that point is the new key.
- Example: from `registered(F9)`, F10 registers and F9 is released. The save then fails, and `setHotkey(F9)` is refused because F9 was taken in the meantime. F10 stays registered by the OS: it swallows F10 system-wide and produces triggers. Meanwhile Scanner shows "F9 unavailable" and F9 is saved.
- Example: this is not only a race. From `unavailable(F9)`, which is the scenario "Rebind out of an unavailable state", the user picks F10, F10 registers, and the save fails. Restoring to F9 is refused again because F9 is still held, so F10 stays registered every time.
- The restore must target the previous registration, not the previous binding. From `unavailable` or `disabled` that means `setHotkey(off)`. If restoring a real old key is refused, the coordinator must release the new key, or report the state truthfully as `registered(new)` with the not-saved error.

**M3. Hotkey saves are not serialized with the coordinator's live-scan saves.**
`SettingsController.save` refuses while `busy` (`settings_controller.dart:26`). The coordinator only waits for its own live-scan saves: `_savesLanded` loops on `_saving`, which only `_save(on:)` sets (`scan_coordinator.dart:1696-1712`). D5 adds a second coordinator-driven save without saying it joins that tracking. Three things follow from the current code:
- Picking a key and then switching live scan off before the hotkey save lands makes `_persistOff`'s save return busy-refused. The user then sees "preference was not saved and may return on the next launch". The scenario "Switching off during a rebind" does not cover this.
- Picking a key while live scan is `off` (the picker is enabled) and then switching it on refuses the on-save as busy, so "Live scan was not switched on" appears. If the hotkey save lands after the on-save instead, activation can register the old binding while F10 ends up saved.
- `_dispose` waits only on `_offPersist` and `_savesLanded()` before the database is torn down (`scan_coordinator.dart:1722-1730`), so a hotkey save still in flight is not awaited.

The design should route the hotkey save through the same tracked-save path, so that live-scan saves, activation and dispose wait for it, and the reverse.

### Suggestions

**S1. The spec omits worker loss as a cause of hotkey state change.**
The pipeline delta says the hotkey state "SHALL change only through activation, rebinding and stop". However, worker loss (`_fail` → `_unhook`, `scan_coordinator.dart:1876-1883`) releases the hotkey, and D3 and the T2 state diagram both list "loss". Add loss and dispose to that sentence. Also consider extending the main "Worker loss makes live scan unavailable" requirement so it says the hotkey is unregistered and the state becomes `inactive`.

**S2. A late answer after `hotkeyTimedOut` desynchronises the OS and the coordinator.**
After a 1 s timeout the input thread may still complete the swap later, leaving F10 registered while the coordinator shows and saves F9. Options:
- have the thread roll the swap back when it finds the request abandoned (a flag in the static slot);
- or state that a timeout leaves the state undefined until the next activation.

Also specify the hotkey state when the activation-time registration itself returns `hotkeyTimedOut` or `notStarted`.

**S3. D6's result set does not match the spec.**
The spec requires `invalidArgument` for a key outside F1-F24 and a success result for off. D6's typed results list only `HotkeyRegistered`, `HotkeyUnavailable`, `HotkeyTimedOut` and `HotkeyNotStarted`. Add the missing cases, or say they are native-only and unreachable through the closed `ScanHotkey` enum, so the sealed switch stays exhaustive and honest.

**S4. A stop that times out leaves the hotkey registered with no notice.**
On `stopTimedOut` the stuck thread still holds its registration. The key stays swallowed system-wide while Scanner shows `inactive`. The existing `stopTimedOut` warning could say the hotkey may still be held until the thread ends.

**S5. Keyboard-input APIs are still allowed outside D10's ban list.**
Raw input (`RegisterRawInputDevices`, `GetRawInputData`) is another way to see every keystroke, and D10 does not ban it. Adding both to the audit costs nothing and closes the remaining keystroke-seeing route in `windows/capture/`.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

Re-check status: all five are applied. 1-3 were confirmed in re-check 1, and 4 and 5 in re-check 2.

Implementation note, not blocking: the thread's final abandoned check and the slot's completion must be atomic with the caller's timeout marking. Use one lock over the slot: the caller sets `abandoned` under it, and the thread checks the flag and completes under it. Otherwise a timeout that lands between the check and the completion would report `hotkeyTimedOut` for a swap that was kept.

1. **D10 (design.md) and the audit plan.** Replace the claim that `WH_KEYBOARD` "also catches `WH_KEYBOARD_LL`". List `WH_KEYBOARD_LL` and `WH_KEYBOARD` as separate banned identifiers, or ban the `WH_KEYBOARD\w*` prefix. Require the audit's non-vacuous test to assert that a source containing `SetWindowsHookExW(WH_KEYBOARD_LL, ...)` is reported.
2. **D5 (design.md), the Failure & Visibility row "Restore after a failed save", and the `scan-pipeline` "Rebinding the hotkey" requirement.**
   - Define the restore target as the previous registration: `off` when the prior state was `unavailable` or `disabled`, otherwise the prior key.
   - Define the outcome when restoring a prior key is refused: the new key is released with `setHotkey(off)` and the state becomes `unavailable(old, reason)`. The alternative is that the state reports `registered(new)` with the not-saved error. Either way, the published state never disagrees with what the OS holds.
   - Add a scenario: from `unavailable(F9)`, pick F10 → F10 registers → save fails → F10 is no longer registered and the state is `unavailable(F9)`.
3. **D5 and Flow & State Gaps (design.md).**
   - State that the hotkey save runs through the coordinator's tracked save path (`_saving` / `_savesLanded`). Live-scan on and off saves wait for a running hotkey save and a hotkey save waits for a running live-scan save. Activation reads `scanHotkey` only after those saves have landed. Dispose awaits it before teardown.
   - Add a `scan-pipeline` scenario: a rebind's save is still running when live scan is switched off → the off save is not refused as busy, and no "not saved" error is shown.

4. **New. The state invariant contradicts the stop-timeout scenario (from the M2 and S4 edits).** The `scan-pipeline` "The pipeline publishes the hotkey state" requirement now says the state "SHALL always describe what the OS holds for the process". The revised "Hook thread does not stop" scenario and the design's "Hook stop times out" Failure row say the stuck thread can keep the hotkey registered while the state is `inactive`. The fix: exempt the `stopTimedOut` case explicitly in the invariant (for example "except after a stop that timed out, which the `stopTimedOut` warning reports"), or publish a distinct state for it. Either way, the SHALL and the scenario must agree.
5. **New. The rollback order for abandoned requests is ambiguous (from the S2 edit).** D5 says that when the thread "finishes a swap and finds the request abandoned, it rolls the swap back: it releases the new id and keeps the old one". Once a swap has finished, the old id is already unregistered, so "keeping" it would mean registering it again, and that can fail if another app took it. The OS would then hold no key while the coordinator shows `registered(F9)`, which breaks the "Late answer after a timeout" scenario. The fix: specify that the thread checks `abandoned` after the new key registers and before it releases the old id. If the request is abandoned, it releases the new id, leaves the old registration untouched and completes the slot. The same check applies to an abandoned off request, which must leave the current key registered.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

- **M1:** fixed. D10 now lists `WH_KEYBOARD_LL` and `WH_KEYBOARD` as separate identifiers and adds raw input (S5). It requires the non-vacuous audit test to report a source containing `SetWindowsHookExW(WH_KEYBOARD_LL, ...)`. **Accepted by reviewer:** matches Required Change 1 exactly.
- **M2:** fixed.
  - D5 now names the restore target as the previous registration: `off` from `unavailable` or `disabled`, otherwise the prior key. A refused restore releases the new key with `setHotkey(off)` and publishes `unavailable(old, reason)`. The Failure & Visibility row is updated to match.
  - The `scan-pipeline` "Rebinding the hotkey" requirement says "restore the previous registration" and gains two scenarios: "Save fails after leaving an unavailable key" and "Old key taken during a failed save". The "publishes the hotkey state" requirement now says the state always describes what the OS holds.
  - **Accepted by reviewer:** matches Required Change 2. The new "always describes what the OS holds" wording is what Required Change 4 is about.
- **M3:** fixed. D5 routes the hotkey save through the tracked save path (`_saving`/`_savesLanded`) so that live-scan and hotkey saves wait for each other. Activation reads `scanHotkey` after pending saves land, and dispose awaits a running hotkey save. Flow & State Gaps and the Mechanism Ledger gain rows for this, and `scan-pipeline` gains the scenario "Live scan switched off while a rebind saves". **Accepted by reviewer:** matches Required Change 3.
- **S1:** applied. The state-change sentence now names worker loss and dispose, and there is a new scenario, "Worker loss". A Flow gap row was added. **Accepted by reviewer.**
- **S2:** applied. D5 adds the abandoned flag and the thread-side rollback. `scan-triggers` gains the scenario "Late answer after a timeout", and the Failure and Ledger rows are updated. The activation outcomes for `hotkeyTimedOut` and `notStarted` are specified, with the new scenario "Registration does not answer at activation". **Accepted by reviewer** (re-check 2): the rollback order is fixed by Required Change 5.
- **S3:** applied. D6 lists the full `HotkeyResult` set: `HotkeyApplied` covers both a key and off, and `HotkeyInvalidArgument` is unreachable through the enum but kept so the switch stays exhaustive. **Accepted by reviewer.**
- **S4:** applied. The `stopTimedOut` warning now says the hotkey may stay held, in the "Hook thread does not stop" scenario and in a new Failure row. **Accepted by reviewer** (re-check 2): the conflict with the state invariant is fixed by Required Change 4.
- **S5:** applied. `RegisterRawInputDevices`, `GetRawInputData` and `GetRawInputBuffer` are added to D10. **Accepted by reviewer.**
- **Required Change 4:** fixed. The `scan-pipeline` hotkey state requirement now names the one exception: after `stopTimedOut`, the stuck input thread may hold the key while the state is `inactive`, as the stop warning says. This is consistent with the "Hook thread does not stop" scenario and the Failure row. **Accepted by reviewer:** the SHALL and the scenario now agree.
- **Required Change 5:** fixed. In D5, the thread checks the abandoned flag after the new key registers and before it releases the old id. An abandoned request releases the new id and leaves the old one untouched, so nothing is re-registered. An abandoned off request checks the flag before releasing, and skips the release. **Accepted by reviewer:** nothing is re-registered, and the "Late answer after a timeout" scenario holds. See the non-blocking atomicity note under Required Changes.
