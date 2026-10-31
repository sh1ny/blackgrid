# Spec Delta

## ADDED Requirements

### Requirement: The bundle carries the committed in-app logo
The integrity check's `app-icon` step SHALL also compare the bundle's `data/flutter_assets/assets/app_icon/app_icon.vec` with the committed `assets/app_icon/app_icon.vec`, byte for byte. A missing bundled file, an unreadable committed file or unequal bytes SHALL fail the step, naming the file and the reason. The comparison reads both files only; it neither compiles nor renders them.

#### Scenario: Logo matches
- **WHEN** the bundle was built from a checkout whose committed `.vec` is in step
- **THEN** the `app-icon` step passes and its details name `app_icon.vec` beside the ten icon sizes

#### Scenario: Logo missing from the bundle
- **WHEN** the bundle has no `data/flutter_assets/assets/app_icon/app_icon.vec`, for example because the asset entry was dropped from `pubspec.yaml`
- **THEN** the `app-icon` step fails, naming the bundled path as missing, and the check exits non-zero

#### Scenario: Stale bundled logo
- **WHEN** the bundled `.vec` differs from the committed one, for example because the bundle was built before a rebuild of the icon
- **THEN** the `app-icon` step fails, saying `app_icon.vec` differs between the bundle and the checkout, and the check exits non-zero
