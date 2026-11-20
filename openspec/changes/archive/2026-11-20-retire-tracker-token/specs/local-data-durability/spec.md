# Spec Delta

## ADDED Requirements

### Requirement: Saved progress-site tokens are deleted at startup
At each launch, the app SHALL delete the saved progress-site token files `pvp.dpapi`, `pve.dpapi` and `seasonal.dpapi`, and the app's own temporary token files `<mode>.dpapi.*.tmp` for those modes, in the local data folder's `credentials` folder, and then that folder when it is empty, without reading, decrypting or sending the files. A failed delete SHALL NOT block startup and SHALL be retried at the next launch. Nothing else in the local data folder SHALL be deleted.

#### Scenario: Upgrade with saved tokens
- **WHEN** the app starts with `credentials\pvp.dpapi` and `credentials\pve.dpapi` in its local data folder
- **THEN** both files and the `credentials` folder are gone, and the database, logs and item icons are unchanged

#### Scenario: Temporary token file left by a crash
- **WHEN** the app starts with `credentials\pvp.dpapi.4242.1700000000.tmp` and no other file in `credentials`
- **THEN** the temporary file and the `credentials` folder are gone

#### Scenario: Nothing saved
- **WHEN** the app starts with no `credentials` folder
- **THEN** startup completes and no folder is created

#### Scenario: A file cannot be deleted
- **WHEN** `credentials\pvp.dpapi` is locked by another process at startup
- **THEN** startup completes, the file is still there, and the next launch deletes it once it is unlocked

#### Scenario: Unexpected file in the folder
- **WHEN** the `credentials` folder also holds a file the user put there
- **THEN** the token files are deleted, the user's file and the folder are kept

## REMOVED Requirements

### Requirement: A damaged saved token reports the token as unavailable
**Reason**: The app no longer reads or saves progress-site tokens.
**Migration**: Saved token files are deleted at startup (see "Saved progress-site tokens are deleted at startup").
