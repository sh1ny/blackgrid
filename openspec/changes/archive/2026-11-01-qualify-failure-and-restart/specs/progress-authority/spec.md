# Spec Delta

## ADDED Requirements

### Requirement: A malformed Tracker response keeps the session's last good progress
When a progress refresh fails because the Tracker response cannot be read, the app SHALL keep the progress already loaded in this app session for that mode, with status `stale` and the error "Tracker response invalid". With no progress loaded yet, the status SHALL be `failed`. A rejected token, a missing read permission, a mode mismatch or an account mismatch SHALL still discard the loaded progress.

#### Scenario: Malformed response after a good refresh
- **WHEN** a refresh has published progress for a mode, and the next refresh for that mode returns a body that is not valid progress
- **THEN** the earlier progress is still published, the status is `stale` and the error is "Tracker response invalid"

#### Scenario: Malformed response with no progress yet
- **WHEN** the first refresh for a mode returns a body that is not valid progress
- **THEN** no progress is published and the status is `failed` with "Tracker response invalid"

#### Scenario: Rejected token still discards progress
- **WHEN** a refresh has published progress for a mode, and the next refresh is answered HTTP 401
- **THEN** no progress is published and the status is `failed` with "Tracker credential denied"

#### Scenario: Account mismatch still discards progress
- **WHEN** a refresh has published progress for a mode, and the next refresh returns progress for a different account
- **THEN** no progress is published and the status is `failed` with "Tracker account mismatch"
