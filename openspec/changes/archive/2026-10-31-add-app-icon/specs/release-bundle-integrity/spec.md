# Spec Delta

## ADDED Requirements

### Requirement: The executable carries the committed application icon
The integrity check SHALL compare the icon group of the bundle's `blackgrid.exe` with `windows/runner/resources/app_icon.ico`, matching images by (width, height, bit depth), a stored 0 read as 256. Each size SHALL appear once per side, whatever its bit depth, and each embedded image SHALL equal the `.ico` image with the same key, byte for byte. A size repeated on one side, a key on one side only, unequal bytes or no readable icon group SHALL fail the step, naming the size, key or reason.

#### Scenario: Icon matches
- **WHEN** the bundle was built from a checkout whose `.ico` holds the ten required sizes
- **THEN** the `app-icon` step passes, listing the ten sizes

#### Scenario: Stale executable icon
- **WHEN** the executable still embeds the Flutter default icon: ten images, 256 px plus 16, 32 and 48 px at 4, 8 and 32 bpp each
- **THEN** the `app-icon` step fails, naming the duplicate sizes 16, 32 and 48 and the sizes missing from the executable (20, 24, 40, 64, 96, 128), and the check exits non-zero

#### Scenario: No icon resource
- **WHEN** the executable has no icon group resource, or its resource directory is malformed
- **THEN** the `app-icon` step fails with an unreadable result, and the check neither throws nor reads out of range
