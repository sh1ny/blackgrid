# Spec Delta

## MODIFIED Requirements

### Requirement: Database upgrade preserves existing application behavior
Upgrading storage SHALL preserve settings, pins, activity, caches, statistics and their existing semantics while adding empty local-progress storage. A newer unsupported database SHALL still be refused without mutation. Upgrading SHALL NOT initiate progress ingestion or synchronization.

#### Scenario: Upgrade and reopen
- **WHEN** an existing database with user records is upgraded and reopened
- **THEN** existing records retain their values, and local progress starts empty

#### Scenario: Newer database
- **WHEN** the database has a schema newer than the supported version
- **THEN** opening fails with the existing newer-database error and leaves its bytes unchanged
