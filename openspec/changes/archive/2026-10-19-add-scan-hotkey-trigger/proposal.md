# Proposal

## Why

Today a scan starts only when the left mouse button is released over the game. An inspect window that is already open can't be scanned again without clicking, and the reference companion's F9 "scan at the cursor" key has no equivalent. This change serves **M4 - complete raid-time Scanner slice** (roadmap change 5). It advances this exit criterion:

> The global hotkey runs the same pipeline as the mouse trigger; a registration conflict shows the trigger as unavailable and allows rebinding; the hotkey is unregistered on rebinding and shutdown. (agent for state and registration fakes; user for a live hotkey scan)

It must also hold the race criterion. Latest-wins bursts, late completions and mode or session changes must never publish a stale decision, and must never record a scan twice. This holds whichever trigger started the scan.

## What Changes

- **Hotkey trigger.** A global scan hotkey, registered with the OS hotkey service (no keyboard hook), runs on the capture boundary's existing input thread. It is registered only while live scan is on, and unregistered when live scan stops, when the user rebinds it and at shutdown.
  - A key press while the game window is in front produces one trigger. It carries the same target facts as a mouse release: the cursor position, the foreground window and its ids, and the monotonic timestamp.
  - It joins the same bounded queue and the same latest-wins scan flow.
  - A key press over any other window produces no trigger.
- **Binding.** The hotkey defaults to **F9** with no modifier, which matches the reference companion. It can be rebound to any of **F1-F24** or turned **Off**.
  - Holding the key does not repeat scans.
  - The binding is a persisted setting. A missing or malformed value falls back to F9 without failing the settings load.
- **Conflicts.** When another application already holds the key, only the hotkey is reported as unavailable, with the OS reason. Live scan stays `ready` and mouse releases keep scanning. The user can pick another key.
  - A rebind while live scan is on is transactional: the new key is saved only after the OS accepts it, and a refused key keeps the previous binding active.
- **Waits by trigger.** A hotkey scan skips the 50 ms settle wait and the 200 ms fallback wait, because the inspect window is already open when the key is pressed. Mouse scans keep both waits. ADR-0014 and ADR-0016 left this decision to M4.
- **Visibility.**
  - Scanner shows the hotkey's binding and state (`registered`, `unavailable` with its reason, `off`, or inactive while live scan is off), next to a control to rebind it.
  - Each scan records which trigger started it, and Scanner's recent scans list labels hotkey scans.
  - The timing log line gains a `trigger` field. Its schema version goes from 1 to 2.
- **Native interface.** The capture ABI goes from version 1 to 2: trigger events carry their source, and there is a call to set the hotkey. The source audit now also rejects keyboard hooks, key-state polling and synthesized keyboard input.

Non-goals:
- importing the reference companion's saved `Scanner.ScanHotkey` (legacy import keeps excluding it);
- hotkeys with modifiers, or keys outside F1-F24;
- registering the hotkey while live scan is off;
- an overlay or any other shortcut.

## Capabilities

### New Capabilities

None. ADR-0010 and the `scan-triggers` spec already reserve this capability for hotkey triggers.

### Modified Capabilities

- `scan-triggers`: adds the hotkey trigger. It covers the hotkey's target facts and foreground filter, explicit registration, unregistration with reported conflicts, transactional rebinding, no repeat, and a queue shared in order with mouse releases. The hook lifecycle now includes unregistering the hotkey on stop.
- `scan-pipeline`: activation registers the saved hotkey after the hook, and a refused registration does not make live scan unavailable. Stop unregisters it. The settle and fallback waits apply to mouse triggers only. Rebinding while live scan is on goes through the pipeline. The timing log line becomes version 2 with the trigger source.
- `scanner-evidence`: Scanner shows the hotkey's binding and state with a rebind control, and labels each recent scan with its trigger.

## Impact

- **Native:**
  - `windows/capture/`: `capture.h` (ABI 2, the trigger source field, the hotkey call and its status codes), and `hook.cpp`, where the thread loop handles hotkey messages and the hotkey is unregistered before the thread exits.
  - The self-test covers the hotkey filter and the rebinding swap.
- **Dart capture layer:**
  - `lib/data/capture/capture_native.dart`: ABI 2 bindings and the event layout.
  - The trigger source surfaces hotkey registration results.
  - The `TriggerEvent` source field.
- **Application:**
  - `lib/application/scan_coordinator.dart`: hotkey state and rebinding, waits chosen by trigger source, the report's trigger, and log v2.
  - `lib/domain/settings.dart`: the `scanHotkey` setting.
- **UI:** `lib/ui/live_scan_panel.dart` (hotkey row and rebind control), and the recent scans list.
- **Tests:**
  - capture fakes such as `fake_hook_platform.dart` and `fake_scan_ports.dart`;
  - new trigger-source, coordinator and settings tests;
  - `capture_source_audit_test.dart`, which gains the keyboard bans and the new trigger source name.
- **Docs:**
  - a new ADR for the hotkey trigger (it settles the M4 wait question that ADR-0014 and ADR-0016 deferred);
  - `openspec/architecture.md` (the capture DLL and coordinator rows, and the "hotkeys do not exist" notes);
  - README.
- **Game interaction:**
  - The OS hotkey service sends nothing to the game and reads nothing from it.
  - The press is consumed system-wide while the hotkey is registered, as in the reference companion.
  - No process handle, memory access or input injection is added, so this stays within the reference companion's profile.
  - A live hotkey scan is checked by the user only.
