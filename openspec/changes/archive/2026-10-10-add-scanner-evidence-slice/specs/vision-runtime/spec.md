# Spec Delta

## MODIFIED Requirements

### Requirement: Normal app launch does not load the vision runtime
Starting the application with live scanning off SHALL NOT open any vision library or read the OCR model. The runtime SHALL be loaded only by the vision self-check mode, by tests, and by the scan pipeline's vision worker while live scanning is on.

#### Scenario: Normal launch
- **WHEN** the application starts without the self-check argument and with live scanning off
- **THEN** the UI starts, and no vision library is loaded in the process

#### Scenario: Unknown argument
- **WHEN** the application starts with an unrecognised argument and with live scanning off
- **THEN** the UI starts normally, and no vision library is loaded

#### Scenario: Live scanning on at launch
- **WHEN** the application starts with live scanning saved on
- **THEN** the vision runtime is loaded only inside the scan pipeline's vision worker, never on the UI isolate
