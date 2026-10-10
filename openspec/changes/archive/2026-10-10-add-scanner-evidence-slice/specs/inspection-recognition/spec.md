# Spec Delta

## MODIFIED Requirements

### Requirement: Recognition runs only as a vision-worker job
Recognition SHALL run only inside the vision worker as a job: no native recognition step SHALL run on the UI isolate. The application SHALL start recognition only through the scan pipeline while live scanning is on; with live scanning off, normal launch SHALL NOT start recognition.

#### Scenario: Job runs against a fake runtime
- **WHEN** the recognition job runs in a test against a fake job context
- **THEN** it completes without loading any native library

#### Scenario: Normal launch
- **WHEN** the application starts normally with live scanning off
- **THEN** no recognition job is constructed, and the offline source audit finds the job referenced only by the scan pipeline's source
