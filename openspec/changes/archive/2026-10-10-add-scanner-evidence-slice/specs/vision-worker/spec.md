# Spec Delta

## MODIFIED Requirements

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
