# vision-worker Specification

## Purpose

Runs item-vision work in one warm, dedicated worker off the UI isolate, so that slow or blocked native vision calls never freeze the UI, never overlap on the OCR engine, never publish stale results and always release their inputs.

## Requirements

### Requirement: Worker opens the vision runtime once and keeps it warm
Starting the vision service SHALL spawn one dedicated worker isolate that verifies and opens the vision runtime once, takes ownership of the marker templates it is given, and reports `ready` or the runtime's typed failure. A ready worker SHALL reuse that runtime, OCR engine and templates for every request until shutdown. The UI isolate SHALL NOT open the vision runtime.

#### Scenario: Warm start
- **WHEN** the service starts against an intact bundle with two valid templates
- **THEN** the service reports `ready`, the runtime was opened exactly once in the worker isolate, and three later requests all run against that one OCR engine

#### Scenario: Runtime unavailable at start
- **WHEN** the service starts and the runtime reports `missingFile` for the OCR model
- **THEN** the service reports `unavailable` carrying that failure, every request is answered `unavailable` without running, and the worker is not respawned

#### Scenario: Invalid template at start
- **WHEN** a template given at start is malformed or has zero variance
- **THEN** the service reports `unavailable` with failure `invalidTemplate` naming that template, and the runtime it opened is disposed

#### Scenario: Caller mutates its template bytes after start
- **WHEN** the caller changes the bytes of a template list after starting the service
- **THEN** requests still run against the templates as they were at start

### Requirement: Native vision calls never overlap
The worker SHALL run at most one request at a time and SHALL start the next request only after the previous request's job, including every native call it made, has returned. No timeout, supersession, invalidation or close SHALL start a second native call while one is running.

#### Scenario: Requests run one after another
- **WHEN** two requests are submitted back to back and the first is held inside a native call by a test barrier
- **THEN** the second job has not started while the barrier holds, and it starts only after the first native call returns

#### Scenario: Deadline passes during a held call
- **WHEN** the active request's deadline passes while its native call is still held
- **THEN** no further native call is started until the held call returns, as observed by the fake engine's concurrent-call counter staying at most 1

### Requirement: One active and one replaceable pending request
The service SHALL hold at most one active request and at most one pending request. A request submitted while one is active SHALL become pending. A request submitted while another is pending SHALL replace it, and the replaced request SHALL be answered `superseded` without running.

#### Scenario: Pending request runs after the active one
- **WHEN** request A is active and request B is submitted
- **THEN** B is pending, and B runs after A is answered

#### Scenario: Newer request replaces the pending one
- **WHEN** request A is active, request B is pending, and request C is submitted
- **THEN** B is answered `superseded` at once and never runs, C is pending, and the pending count never exceeds 1

### Requirement: Results are fenced by generation
Each request SHALL carry the service generation current at submission. Invalidating the service SHALL advance the generation and answer both the pending and the active request `invalidated` at once. The pending request never runs. The active request's late result SHALL be discarded when its job returns, and it SHALL NOT be answered again. A result SHALL be delivered only if its generation is still current.

#### Scenario: Current result is delivered
- **WHEN** a request completes with no invalidation since it was submitted
- **THEN** the caller receives the job's result

#### Scenario: Invalidation during an active job
- **WHEN** the service is invalidated while a request's job is held in a native call, and the call returns a result after the request's deadline
- **THEN** that request is answered `invalidated` at the moment of invalidation and is not answered again (no `visionTimeout`), the service reports `overrun` from the deadline until the call returns, the result is not delivered, and the input is released

#### Scenario: Invalidation with a pending request
- **WHEN** the service is invalidated while a request is pending
- **THEN** the pending request is answered `invalidated` at once and never runs

### Requirement: Requests have a deadline
Each request SHALL have a deadline measured from its submission, 1.5 s by default and set when the service is constructed. When the deadline passes before the request is answered, the caller SHALL be answered `visionTimeout` at once. An active request whose deadline passes, whether timed out or already invalidated, SHALL leave the service `overrun` until its native call returns. Its late result SHALL be discarded, never delivered.

#### Scenario: Request finishes in time
- **WHEN** a request's job returns before its deadline
- **THEN** the caller receives the result and the service is not `overrun`

#### Scenario: Active request overruns
- **WHEN** the active request's job is held past its deadline
- **THEN** the caller is answered `visionTimeout` at the deadline, the service reports `overrun`, and when the held call returns, the late result is discarded and the service returns to `ready`

#### Scenario: Pending request expires while waiting
- **WHEN** a pending request's deadline passes while the active request is still held
- **THEN** the pending request is answered `visionTimeout`, its input is released, and it never runs

### Requirement: Request inputs are owned and released exactly once
A request's image SHALL be either a capture frame or an owned image. The submitter SHALL lose access to it on submission. Each input SHALL be released exactly once on every outcome, including success, failure, supersession, invalidation, deadline, worker failure and close. A frame not yet sent to the worker SHALL keep its finalizer. A malformed owned image SHALL be answered `invalidInput` at submission, without being admitted.

#### Scenario: Frame released after success
- **WHEN** a request with a handed-off capture frame completes
- **THEN** the frame has been released exactly once and the live frame count has returned to its value before the capture

#### Scenario: Superseded frame released at once
- **WHEN** a pending request holding a capture frame is superseded
- **THEN** its frame is released before the superseding request is acknowledged, so the four-frame budget is not held by work that will never run

#### Scenario: Malformed owned image
- **WHEN** an owned image whose stride is smaller than width × channels is submitted while another request is pending
- **THEN** the request is answered `invalidInput`, no job or native call runs, and the pending request is kept

#### Scenario: Service dropped with a pending frame
- **WHEN** a service holding a pending frame request is dropped without being closed
- **THEN** the frame is released by its finalizer, and the live frame count returns to its value before the capture

### Requirement: A failing job does not break the worker
If a request's job throws or reports a native failure, the request SHALL be answered with a typed failure (`jobFailed` with the error description, or the runtime's `VisionFailure`), its input SHALL be released, and the worker SHALL stay `ready` for the next request.

#### Scenario: Job throws
- **WHEN** a job throws an exception
- **THEN** the request is answered `jobFailed`, and the next request runs and succeeds on the same OCR engine

#### Scenario: Native failure inside a job
- **WHEN** a runtime operation inside a job returns `nativeFailure` with status -3
- **THEN** that failure reaches the caller as a typed failure, not as a successful result

### Requirement: Answers carry monotonic stage timestamps
Every answer that ran a job SHALL include the monotonic timestamps of submission, job start and job end, on the same clock as capture and trigger timestamps, so that queueing and run time can be measured.

#### Scenario: Timestamps of a completed request
- **WHEN** a request completes after waiting behind another
- **THEN** its answer reports submission ≤ job start ≤ job end, and job start is not earlier than the previous request's job end

#### Scenario: Request answered without running
- **WHEN** a request is answered `superseded`
- **THEN** its answer reports its submission time and no job start or end

### Requirement: Shutdown drains the worker before releasing handles
Closing the service SHALL stop admission at once, advance the generation, answer the active and pending requests `closed`, and wait up to 2 s for an active native call to return. Only then SHALL it dispose the runtime and end the worker. If the call has not returned, close SHALL report `shutdownIncomplete` without disposing the runtime or ending the worker under the running call. Later submissions SHALL be answered `closed`.

#### Scenario: Close while idle
- **WHEN** a ready, idle service is closed
- **THEN** close completes, the runtime's dispose ran exactly once, the worker has exited, and a later submission is answered `closed`

#### Scenario: Close during warm start
- **WHEN** the service is closed while the worker is still opening the runtime, and the open then succeeds
- **THEN** a request submitted before close is answered `closed`, the opened runtime is disposed exactly once, and the worker exits

#### Scenario: Close during a call that returns in time
- **WHEN** the service is closed while a job is held and the barrier is lifted after 500 ms
- **THEN** the active and pending requests are answered `closed`, their inputs are released, the late result is not delivered, and the runtime is disposed after the call returned

#### Scenario: Close during a call that does not return
- **WHEN** the service is closed while a job stays held past the 2 s drain
- **THEN** close reports `shutdownIncomplete`, the runtime's dispose has not run, and when the call later returns, its input is released and nothing is delivered

### Requirement: Worker failure makes the service unavailable
If the worker isolate exits or reports an uncaught error, the service SHALL answer every outstanding request `unavailable`, release their inputs, and stay `unavailable` without respawning.

#### Scenario: Worker dies during a request
- **WHEN** the worker isolate exits while a request is active and another is pending
- **THEN** both are answered `unavailable`, both frames are released, and later submissions are answered `unavailable`

### Requirement: Normal launch does not start the vision worker
Starting the application SHALL NOT start the vision service or its worker while live scanning is off. Only the scan pipeline SHALL start it in the application, and only while live scanning is on; tests, explicit test harnesses and the self-check may also start it. No other startup or UI source SHALL import or start the vision service.

#### Scenario: No startup path starts the worker
- **WHEN** the application's startup and UI sources are audited
- **THEN** none of them import or start the vision service, except the scan pipeline's source

#### Scenario: Normal launch loads no vision library
- **WHEN** the application starts without the self-check argument and with live scanning off
- **THEN** no vision library is loaded in the process

#### Scenario: Live scanning starts the worker
- **WHEN** live scanning is switched on in the application
- **THEN** exactly one vision service is started, by the scan pipeline
