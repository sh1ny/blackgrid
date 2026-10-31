# Spec Delta

## ADDED Requirements

### Requirement: The executable carries the committed application icon
The integrity check SHALL read the application icon group from the bundle's `blackgrid.exe` and compare it with `windows/runner/resources/app_icon.ico`. Images SHALL be matched by (width, height, bit depth), with a stored 0 read as 256. Each key SHALL appear once on each side, and each embedded image's bytes SHALL equal the `.ico` image with the same key. A duplicate key, a key on one side only, unequal bytes, or no readable icon group SHALL fail this step and name the key or the reason.

#### Scenario: Icon matches
- **WHEN** the bundle was built from a checkout whose `.ico` holds the ten required sizes
- **THEN** the `app-icon` step passes, listing the ten sizes

#### Scenario: Stale executable icon
- **WHEN** the executable still embeds the Flutter default icon: ten images, 256 px plus 16, 32 and 48 px at 4, 8 and 32 bpp each
- **THEN** the `app-icon` step fails, naming the duplicate sizes 16, 32 and 48 and the sizes missing from the executable (20, 24, 40, 64, 96, 128), and the check exits non-zero

#### Scenario: No icon resource
- **WHEN** the executable has no icon group resource, or its resource directory is malformed
- **THEN** the `app-icon` step fails with an unreadable result, and the check neither throws nor reads out of range
