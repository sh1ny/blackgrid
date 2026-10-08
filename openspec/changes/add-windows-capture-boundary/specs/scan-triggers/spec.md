# Spec Delta

## Purpose

Detects the global user input that starts a scan (a left mouse-button release over the target game window) and delivers it as a bounded stream of trigger events without blocking system input or the UI isolate.

## ADDED Requirements

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
The hook SHALL be installed only by an explicit start, and only one installation SHALL exist per process. Stop and dispose SHALL remove the hook and end its thread before returning success. After stop returns, no trigger SHALL be delivered. Starting the application normally SHALL NOT install the hook unless a trigger consumer starts it.

#### Scenario: Start then stop
- **WHEN** the source is started, one trigger is delivered, and the source is stopped
- **THEN** stop reports success, the hook thread has ended, and a target release after that produces no trigger

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
- **THEN** no global mouse hook is installed by the process
