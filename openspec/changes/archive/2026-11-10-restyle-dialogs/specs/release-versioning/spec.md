# Spec Delta

## MODIFIED Requirements

### Requirement: The running app reports its version
The application SHALL show its app version in the General section of the Settings page. A build made without a release version SHALL report `dev`.

#### Scenario: Release build shows its version
- **WHEN** the Settings page opens in a build made with app version `0.2.0+120`
- **THEN** the General section shows `0.2.0+120`

#### Scenario: Development build
- **WHEN** the Settings page opens in a build made without an app version
- **THEN** the General section shows `dev`
