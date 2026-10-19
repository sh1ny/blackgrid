# scan-triggers Specification

## Purpose

Detects the global user input that starts a scan (a left mouse-button release over the target game window) and delivers it as a bounded stream of trigger events without blocking system input or the UI isolate.

## Requirements

### Requirement: Mouse-release trigger records cheap target facts
While started, the trigger source SHALL emit one trigger per left-button release whose foreground window title equals the configured target title. Each trigger SHALL carry the signed physical screen point, the foreground window handle, its process and thread ids, and a monotonic timestamp from the same clock that capture timestamps use. Other buttons, button presses and releases over other windows SHALL NOT produce triggers.

#### Scenario: Release over the target window
- **WHEN** the trigger source is started with target title `EscapeFromTarkov` and a left-button release occurs at physical screen point (-1200, 340) while a window titled `EscapeFromTarkov` is foreground
- **THEN** exactly one trigger is emitted with point (-1200, 340), that window's handle, process id and thread id, and a monotonic timestamp no earlier than the source's start time

#### Scenario: Release over another window
- **WHEN** a left-button release occurs while a window titled `Notepad` is foreground
- **THEN** no trigger is emitted

#### Scenario: Press, right button and wheel
- **WHEN** a left-button press, a right-button release and a wheel event occur over the target window
- **THEN** no trigger is emitted for any of them

#### Scenario: No foreground window
- **WHEN** a left-button release occurs while there is no foreground window
- **THEN** no trigger is emitted

### Requirement: Hook callback never does capture, recognition or UI work
The input callback SHALL only filter the event, read the foreground window's handle, ids and title, append to the native queue and request a drain. Its title read SHALL NOT send a window message. The callback SHALL always pass the event on to the next hook, and SHALL NOT capture pixels, run recognition, query process listings or call into Dart synchronously.

#### Scenario: Event passed on
- **WHEN** any mouse event reaches the callback, whether or not it becomes a trigger
- **THEN** the callback passes it to the next hook and returns without consuming it

#### Scenario: Dart isolate is busy
- **WHEN** the receiving isolate is blocked for 2 s while 5 target releases occur
- **THEN** each callback still returns without waiting for the isolate, and the 5 triggers are delivered in order once the isolate resumes

#### Scenario: Blackgrid's own window is foreground with a blocked UI thread
- **WHEN** a left-button release occurs while a Blackgrid window is foreground and its UI thread is blocked
- **THEN** the callback returns without waiting on that thread, and no trigger is emitted

### Requirement: Trigger queue is bounded
Undelivered triggers SHALL be held in a native queue of at most 16 events. When the queue is full, the oldest event SHALL be dropped and counted. The next delivered trigger SHALL carry the number of events dropped before it. Delivery signals SHALL be coalesced, so that at most one undrained signal is pending for the receiving isolate.

#### Scenario: Queue overflow
- **WHEN** 20 target releases occur while the receiving isolate cannot drain
- **THEN** the isolate later receives the newest 16 triggers in order, and the first of them reports 4 dropped events

#### Scenario: Coalesced signal
- **WHEN** 3 target releases occur before the isolate drains once
- **THEN** a single drain returns all 3 triggers, and no further empty drains are signalled for them

#### Scenario: Release during a drain
- **WHEN** a target release is appended while a drain is copying the queue
- **THEN** the release is delivered either in that drain or by a later signal, with no further click needed

### Requirement: Hook lifecycle is explicit
The hook SHALL be installed only by an explicit start, and only one installation SHALL exist per process. Stop and dispose SHALL unregister any hotkey, remove the hook and end its thread before returning success. After stop returns, no trigger SHALL be delivered, from either source. Starting the application normally SHALL NOT install the hook or register a hotkey unless a trigger consumer starts it.

#### Scenario: Start then stop
- **WHEN** the source is started, one trigger is delivered, and the source is stopped
- **THEN** stop reports success, the hook thread has ended, and a target release after that produces no trigger

#### Scenario: Stop with a hotkey registered
- **WHEN** the source is started with F9 registered and is then stopped
- **THEN** stop reports success, F9 is no longer registered by the process, and an F9 press after that produces no trigger

#### Scenario: Second start
- **WHEN** the source is already started and start is called again
- **THEN** the second start fails with a typed `alreadyStarted` result, and the existing installation is unchanged

#### Scenario: Installation refused by the OS
- **WHEN** the OS refuses to install the hook
- **THEN** start returns a typed `unavailable` result carrying the OS error code, and no hook thread is left running

#### Scenario: Hook thread does not end in time
- **WHEN** stop is called and the hook thread does not end within 1 s
- **THEN** stop returns a typed `stopTimedOut` result, the delivery callback is kept alive rather than freed, so that a late delivery cannot call freed code, and a later start returns `alreadyStarted` because the installation is still held

#### Scenario: Normal startup
- **WHEN** the application starts normally and no trigger consumer has started the source
- **THEN** no global mouse hook is installed and no hotkey is registered by the process

### Requirement: Hotkey trigger records the same target facts
While the source is started and a hotkey is registered, each press of that hotkey SHALL emit one trigger if the foreground window's title equals the configured target title. The trigger SHALL carry the same facts as a mouse release, with the cursor's physical screen point as its point, and SHALL name the hotkey as its source. A press over another window, over Blackgrid's own window, or with no foreground window SHALL NOT produce a trigger.

#### Scenario: Press over the target window
- **WHEN** F9 is registered, a window titled `EscapeFromTarkov` is foreground, and F9 is pressed with the cursor at physical screen point (640, 360)
- **THEN** exactly one trigger is emitted with source `hotkey`, point (640, 360), that window's handle, process id and thread id, and a monotonic timestamp from the capture clock

#### Scenario: Press over another window
- **WHEN** F9 is registered and pressed while a window titled `Notepad` is foreground
- **THEN** no trigger is emitted

#### Scenario: Press over Blackgrid
- **WHEN** F9 is registered and pressed while a Blackgrid window is foreground
- **THEN** no trigger is emitted

#### Scenario: Mouse release keeps its source
- **WHEN** a left-button release occurs over the target window
- **THEN** its trigger names `mouse` as its source

### Requirement: Holding the hotkey does not repeat
A hotkey SHALL be registered so that the OS's key repeat does not generate further presses. Holding the key down SHALL produce one trigger; releasing and pressing it again SHALL produce another.

#### Scenario: Key held down
- **WHEN** F9 is held down for 2 s over the target window
- **THEN** exactly one trigger is emitted

#### Scenario: Two separate presses
- **WHEN** F9 is pressed, released and pressed again over the target window
- **THEN** two triggers are emitted, in press order

### Requirement: Hotkey triggers share the bounded queue
Hotkey triggers SHALL be appended to the same native queue as mouse-release triggers, under its bound, drop counting and coalesced delivery, and SHALL be delivered in the order the two sources appended them.

#### Scenario: Mixed sources in order
- **WHEN** a mouse release, then an F9 press, then a mouse release occur over the target window before the isolate drains
- **THEN** a single drain returns the three triggers in that order with sources `mouse`, `hotkey`, `mouse`

#### Scenario: Dart isolate is busy
- **WHEN** the receiving isolate is blocked for 2 s while 3 hotkey presses occur over the target window
- **THEN** the input thread keeps handling presses without waiting for the isolate, and the 3 triggers are delivered in order once the isolate resumes

#### Scenario: Overflow across sources
- **WHEN** 10 mouse releases and 10 hotkey presses alternate over the target window while the isolate cannot drain
- **THEN** the isolate later receives the newest 16 triggers in order, and the first of them reports 4 dropped events

### Requirement: Hotkey registration is explicit and reports conflicts
The hotkey SHALL be registered only by an explicit request while the source is started, with one of F1-F24 and no modifier, or set to off. The input thread SHALL do the registration. A key held by another application SHALL fail with a typed `hotkeyUnavailable` result carrying the OS error code. A request while the source is stopped SHALL fail with `notStarted`. A key outside F1-F24 SHALL fail with `invalidArgument`.

#### Scenario: Register a free key
- **WHEN** the source is started and F9 is requested
- **THEN** the request succeeds and F9 is registered on the input thread

#### Scenario: Key held by another application
- **WHEN** the source is started and F9 is requested while another application holds F9
- **THEN** the request returns `hotkeyUnavailable` with the OS error code, and no hotkey is registered by the process

#### Scenario: Request while stopped
- **WHEN** the source is stopped and F9 is requested
- **THEN** the request returns `notStarted` and no hotkey is registered

#### Scenario: Unsupported key
- **WHEN** a key other than F1-F24 is requested
- **THEN** the request returns `invalidArgument` and the current registration is unchanged

#### Scenario: Turned off
- **WHEN** F9 is registered and off is requested
- **THEN** F9 is unregistered, and a later F9 press produces no trigger

### Requirement: Rebinding keeps the previous key on failure
A request for a different key while one is registered SHALL register the new key before releasing the old one. If the new key is refused, the old key SHALL stay registered and the request SHALL return the refusal. A request for the key already registered SHALL succeed with no change. A request SHALL report `hotkeyTimedOut` if the input thread has not answered within 1 s, and a later request SHALL be refused until that answer arrives.

#### Scenario: Rebind to a free key
- **WHEN** F9 is registered and F10 is requested, and F10 is free
- **THEN** the request succeeds, F10 presses produce triggers, and F9 is no longer registered

#### Scenario: Rebind to a held key
- **WHEN** F9 is registered and F10 is requested while another application holds F10
- **THEN** the request returns `hotkeyUnavailable`, F9 is still registered and its presses still produce triggers

#### Scenario: Same key again
- **WHEN** F9 is registered and F9 is requested
- **THEN** the request succeeds and F9 stays registered without being released

#### Scenario: Input thread does not answer
- **WHEN** a request is made and the input thread does not answer within 1 s
- **THEN** the request returns `hotkeyTimedOut`, and another request before that answer returns `hotkeyTimedOut` without reaching the input thread

#### Scenario: Late answer after a timeout
- **WHEN** a request for F10 with F9 registered returns `hotkeyTimedOut`, and the input thread later completes the swap
- **THEN** the input thread rolls the swap back, F9 is still registered, F10 is not, and the next request reaches the input thread
