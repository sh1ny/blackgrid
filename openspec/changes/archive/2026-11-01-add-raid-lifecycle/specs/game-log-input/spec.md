# Spec Delta

## Purpose

Reads the game's own log files, read-only, and turns them into typed, timestamped events that the raid state machine, timers, stats and task progress can trust, without ever touching the game's process.

## ADDED Requirements

### Requirement: Session log files are read from the newest session folder
Blackgrid SHALL read the application, backend and push-notifications logs of the newest `log_<date>_<time>[_<version>]` folder in the configured log root, read-only. When a newer session folder appears, Blackgrid SHALL switch every file to it. A missing file SHALL leave the other files readable.

#### Scenario: Three files of the newest folder
- **WHEN** the log root holds `log_2026.10.30_20-27-43_1.3.0.0.48484` and `log_2026.10.31_21-21-11_1.3.0.0.48484`, each with `application_000.log`, `backend_000.log` and `push-notifications_000.log`
- **THEN** events come only from the three files of `log_2026.10.31_21-21-11_1.3.0.0.48484`

#### Scenario: A newer folder replaces the current one
- **WHEN** events are being read from one session folder and a newer session folder with an `application_000.log` appears
- **THEN** the next events come from the newer folder, and no further event comes from the older one

#### Scenario: Missing push-notifications log
- **WHEN** the newest session folder has `application_000.log` and `backend_000.log` but no `push-notifications_000.log`
- **THEN** application and backend events are still produced, and the "Raid logs:" line says the notifications log has not been written yet

#### Scenario: No log folder
- **WHEN** the configured log root holds no session folder
- **THEN** no event is produced and the log status says no current log was found

### Requirement: Backend and push-notification problems never change the Map's log state
The Map's log status, detected map, detected mode and session incarnation SHALL depend on the application log only. A missing, unreadable, replaced or rejecting backend or push-notifications log SHALL be reported on a separate "Raid logs:" line in Map saved-file inputs and SHALL NOT change the Map's "Logs:" line, its screenshot labels or its saved evidence.

#### Scenario: Push log missing during a raid
- **WHEN** the application log is watched, a screenshot is being followed, and the push-notifications log does not exist
- **THEN** the "Logs:" line still says the folder is being watched, the screenshot is not labelled assumed, and the "Raid logs:" line names the missing notifications log

#### Scenario: Rejected push record
- **WHEN** a push-notifications record is rejected as malformed
- **THEN** the "Raid logs:" line says a notifications record was rejected, and the detected map, mode and "Logs:" line are unchanged

#### Scenario: Backend log rewritten
- **WHEN** the backend log is rewritten and read again from its start
- **THEN** the detected map stays and no Map evidence is invalidated

### Requirement: A record is decoded only when it is complete
Blackgrid SHALL decode a line only after its terminating newline has been read, so a line split across reads or a multi-byte UTF-8 character split across reads SHALL be decoded exactly once, whole. A trailing carriage return SHALL be dropped.

#### Scenario: Line split across two reads
- **WHEN** the application log gains `2026-10-28 19:41:06.991|1.2.5.0.48146|Info|application|GameSt` in one read and `arted:161.35(10.98) real:176.48(12) diff:15.12` plus a newline in the next
- **THEN** exactly one raid-started event is produced, after the second read, and none after the first

#### Scenario: Multi-byte character split across reads
- **WHEN** a push-notifications record contains `Сёма` and a read boundary falls between the two bytes of `ё`
- **THEN** the record is decoded once with `Сёма` intact and no malformed-UTF-8 error is reported

#### Scenario: Unfinished last line
- **WHEN** the file ends without a newline after its last line
- **THEN** that line produces no event until its newline is written

### Requirement: A record spans its header and continuation lines
A record SHALL start at a line that begins with a log timestamp (`YYYY-MM-DD HH:MM:SS.mmm|`) and SHALL include the following lines up to the next such line. A push notification's JSON body SHALL belong to its header's record, which SHALL be complete at the body's closing line (`}` alone) or at the next header line, whichever is read first.

#### Scenario: Notification with a JSON body
- **WHEN** the push-notifications log holds a `Got notification | ChatMessageReceived` header and its multi-line JSON body with `"type": 12` and `"templateId": "<task id> successMessageText"`, ending with a line holding only `}`
- **THEN** one task-finished event is produced for that task ID, with the header's time, without waiting for another header line

#### Scenario: Body not yet complete
- **WHEN** a notification header and half of its JSON body have been written
- **THEN** no event is produced for it, and it is produced once its closing `}` line is read

#### Scenario: Body cut off by the next header
- **WHEN** a notification body has no closing `}` line before the next header line
- **THEN** the record ends at that header, its body is parsed as written, and the next header starts a new record

#### Scenario: Body that is not valid JSON
- **WHEN** a notification record's body is not valid JSON
- **THEN** that record produces no event, the following records still produce theirs, and the "Raid logs:" line reports a rejected record

### Requirement: Malformed and over-long records are rejected visibly
A line longer than the line limit or not valid UTF-8 SHALL be rejected, SHALL produce no event and SHALL be reported until later bytes of the same file read cleanly: on the "Logs:" line for the application log, on the "Raid logs:" line for the others. A push-notification record larger than the record limit SHALL be rejected the same way. Rejection SHALL NOT stop later records from being read.

#### Scenario: Malformed UTF-8 line
- **WHEN** an application log line contains bytes that are not valid UTF-8
- **THEN** that line produces no event, the log status says a malformed record was rejected, and the next valid line produces its event

#### Scenario: Over-long line
- **WHEN** a line is longer than the line limit
- **THEN** that line produces no event, the log status says an over-limit record was rejected, and reading continues with the next line

### Requirement: Replaced or rewritten files are read again from the start
When a log file is replaced, truncated or its already-read bytes change, Blackgrid SHALL restart that file's read from its first byte and SHALL NOT produce events from the old file's unread bytes.

#### Scenario: Truncated file
- **WHEN** the backend log shrinks below the offset already read
- **THEN** the backend log is read again from its first byte

#### Scenario: Rewritten bytes
- **WHEN** bytes the application log already read are rewritten in place with different content of the same length
- **THEN** the application log is read again from its first byte and no event comes from the replaced bytes before that restart

### Requirement: Events carry their log time and a stable record identity
Every event SHALL carry the time written on its record and a record identity made of the session folder name, the file and the record's starting byte offset. The same record SHALL get the same identity when the app reads it again after a restart.

#### Scenario: Same identity after restart
- **WHEN** Blackgrid reads a session folder, is restarted and reads the same unchanged folder again
- **THEN** each event of the second read has the same record identity and time as the matching event of the first read

#### Scenario: Records with the same text
- **WHEN** the application log holds two identical `Matching with group id: 3515690` lines at different offsets
- **THEN** the two queue-entered events have different record identities

### Requirement: Application log lines become lifecycle events
Blackgrid SHALL turn application log records into session mode, profile selected, queue entered, scene loaded, match found, raid starting, raid started, matching aborted and raid rejoined events, each recognised by its fixed message text. Any other record SHALL produce no event.

#### Scenario: Menu events
- **WHEN** the application log holds `Session mode: PvpSeason` and `PrepareSelectedProfileLocally ProfileId:<id> AccountId:<n>`
- **THEN** a session-mode event for seasonal and a profile-selected event are produced

#### Scenario: Rejoin line
- **WHEN** the application log holds `Transit reconnect status:MatchWait raidMode:Online location:bigmap settingsLocal:False`
- **THEN** a raid-rejoined event is produced with status MatchWait and map Customs

#### Scenario: A full raid in the application log
- **WHEN** the application log holds, in order, `Matching with group id: 6601208`, `scene preset path:maps/lighthouse_preset.bundle rcid:lighthouse.scenespreset.asset`, `MatchingCompleted:89.19 real:97.16 diff:7.97`, `GameStarting:150.37(26.13) real:164.48(26.56) diff:14.11` and `GameStarted:161.35(10.98) real:176.48(12) diff:15.12`
- **THEN** the events are queue entered, scene loaded on Lighthouse, match found, raid starting and raid started, in that order

#### Scenario: Matching cancelled
- **WHEN** the application log holds `Network game matching cancelled.`
- **THEN** one matching-aborted event is produced

#### Scenario: Unknown scene
- **WHEN** the application log holds `scene preset path:maps/unknown_place.bundle`
- **THEN** a scene-loaded event with no map is produced, and the map status says the current scene is unsupported

#### Scenario: Event map presets
- **WHEN** the application log holds `scene preset path:maps/factory_event_preset.bundle` or `scene preset path:maps/laboratory_event_preset.bundle`
- **THEN** the scene-loaded event's map is Factory or The Lab, and Factory or The Lab is the detected map

#### Scenario: Unrelated line
- **WHEN** the application log holds `Reason:PacketsQueue, Position:(62.883, 10.690, -947.049), SpeedLimit:1.0595`
- **THEN** no event is produced

### Requirement: Backend log notification lines become raid-exit events
Blackgrid SHALL turn a backend log record that reports a received notification with `payloadType=userMatchOver` into a raid-exit event. Other payload types SHALL produce no event in this change.

#### Scenario: Raid exit
- **WHEN** the backend log holds `WebSocketSharp - binary message received: type=Notification, trackingId=<id>, payloadType=userMatchOver, payloadLength=393`
- **THEN** one raid-exit event is produced with that record's time

#### Scenario: Other notification
- **WHEN** the backend log holds a received-notification line with `payloadType=groupMatchRaidReady`
- **THEN** no event is produced

### Requirement: Push-notification messages become flea-sale and task events
Blackgrid SHALL turn a push-notifications `ChatMessageReceived` record into an event by its message `type`: 4 with `systemData.soldItem` is a flea sale (item, count and the roubles in its items); 10, 11 and 12 are task started, failed and finished, with the task ID from the first word of `templateId`. Other message types SHALL produce no event.

#### Scenario: Flea sale
- **WHEN** a type 4 message has `systemData` `{"soldItem": "5c94bbff86f7747ee735c08f", "itemCount": 2}` and one item with `_tpl` `5449016a4bdc2d6f028b456f` and `StackObjectsCount` 206792
- **THEN** one flea-sale event is produced for 2 of item `5c94bbff86f7747ee735c08f` with 206792 roubles received

#### Scenario: Task failed
- **WHEN** a type 11 message has `templateId` `"<task id> failMessageText"`
- **THEN** one task-failed event is produced for `<task id>`

#### Scenario: Flea sale paid in another currency
- **WHEN** a type 4 flea-sale message's item is not the rouble template
- **THEN** a flea-sale event is produced with the item and count and no rouble amount

#### Scenario: Message without a task ID
- **WHEN** a type 10 message has an empty `templateId`
- **THEN** no event is produced, and the "Raid logs:" line reports a rejected record

### Requirement: Log input never touches the game process
Reading the game's logs SHALL only open the log files for reading. It SHALL NOT find, open, read from or send input to any game process, and SHALL NOT write, move or delete any file in the log root.

#### Scenario: Offline audit
- **WHEN** the offline audit test scans the log-input code
- **THEN** it finds no `Process.run`, `Process.start`, process enumeration, process handle or memory-read call, and no `openWrite`, `writeAs*`, `FileMode.write`, `FileMode.append`, `rename` or `delete` call in the log-input source files
