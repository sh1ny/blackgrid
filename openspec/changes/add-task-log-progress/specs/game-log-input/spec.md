# Spec Delta

## ADDED Requirements

### Requirement: Older session folders can be read once on request
On request, Blackgrid SHALL list the session folders of the log root in folder-date order and read a chosen folder's application and push-notifications logs once, from start to end, read-only. It SHALL use the same framing, limits, parsers and event order as the live reader, so each event gets the same record identity and time as a live read of that folder. A one-shot read SHALL NOT change the live reader's folder, status or "Raid logs:" line.

#### Scenario: Same identities as a live read
- **WHEN** a folder that was read live is later read once on request
- **THEN** each task and session-mode event of the one-shot read has the same record identity and time as in the live read

#### Scenario: Folder-date order
- **WHEN** the log root holds `log_2026.11.02_10-00-00_1.3.0.0.48484`, `log_2026.10.30_20-27-43_1.3.0.0.48484` and a directory named `screenshots`
- **THEN** the listing names the two session folders, 2026-10-30 first, and leaves out `screenshots`

#### Scenario: One-digit hour
- **WHEN** the log root holds `log_2026.11.02_10-00-00_1.3.0.0.48484` and `log_2026.11.02_9-00-00_1.3.0.0.48484`
- **THEN** the listing names the 9:00 folder before the 10:00 folder, ordered by folder date and time, then by name

#### Scenario: Folder without an application log
- **WHEN** a requested folder has a push-notifications log and no application log
- **THEN** its task events are read without any session mode before them

#### Scenario: Folder cannot be opened
- **WHEN** a requested folder's files cannot be opened for reading
- **THEN** the read reports that folder unreadable, produces no event from it, and the live reader's status is unchanged

#### Scenario: Malformed record in an older folder
- **WHEN** an older folder's push-notifications log holds one record whose body is not valid JSON among valid task messages
- **THEN** the valid task events are produced and that record is counted as rejected for the read

### Requirement: One-shot folder reads never touch the game process
A one-shot folder read SHALL only open log files for reading. It SHALL NOT write, move or delete any file in the log root, and SHALL NOT find, open, read from or send input to any game process.

#### Scenario: Offline audit covers the one-shot reader
- **WHEN** the offline audit test scans the log-input code
- **THEN** the one-shot folder reader's source is in the scanned set, and it holds no process call and no file write, rename or delete call
