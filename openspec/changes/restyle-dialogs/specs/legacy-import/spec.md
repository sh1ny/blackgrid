# Spec Delta

## ADDED Requirements

### Requirement: The import preview keeps technical detail under Details
The import preview SHALL show the record, pin and history counts, the settings to import, each pin, what was left out, what is never imported and the Replace choice. The file fingerprint and the per-record lines (kind, input order, key, disposition and reason) SHALL sit under a "Details" toggle that is collapsed each time a preview is read.

#### Scenario: Preview read
- **WHEN** the player reads a preview of a history file with 3 records
- **THEN** the dialog shows "3 records found" and the Replace choice, and shows no fingerprint or per-record line until Details is opened

#### Scenario: Details opened
- **WHEN** the player opens Details
- **THEN** the file fingerprint and one line per record show

#### Scenario: New preview resets Details
- **WHEN** Details is open and the player reads another preview
- **THEN** Details is collapsed

#### Scenario: Already imported
- **WHEN** the preview is of files that were already imported
- **THEN** the dialog says "These files were already imported." and Import now is disabled
