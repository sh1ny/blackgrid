# Spec Delta

## MODIFIED Requirements

### Requirement: Targeted region is planned in physical client pixels
The targeted region SHALL be a fixed band around the client centre, independent of the trigger point. The trigger point SHALL still lie inside the client. With physical client size `w×h`, `cx = w div 2`, `cy = h div 2` and `s = min(w/1920, h/1080)` as an exact rational, `f(k) = floor(k·s)`, the region SHALL be `(cx - f(440), 0, f(440) + f(700), cy + f(400))`. OS DPI SHALL NOT change the region.

#### Scenario: Sixteen resolution and scaling cells
- **WHEN** the region is planned for a click at client point (900, 500) on clients of 1920×1080, 2560×1440, 3440×1440 and 3840×2160, each at DPI 96, 120, 144 and 192
- **THEN** the planned regions are (520, 0, 1140, 940), (694, 0, 1519, 1253), (1134, 0, 1519, 1253) and (1040, 0, 2280, 1880) respectively, identical across the four DPIs of each resolution

#### Scenario: Region does not follow the cursor
- **WHEN** the region is planned on a 1920×1080 client for client points (10, 10), (900, 500) and (1900, 1070)
- **THEN** all three planned regions are (520, 0, 1140, 940)

#### Scenario: Client taller than 16:9
- **WHEN** the region is planned on a 1920×1200 client
- **THEN** the planned region is (520, 0, 1140, 1000)

#### Scenario: Non-integral scale
- **WHEN** the region is planned on a 1366×768 client
- **THEN** the planned region is (371, 0, 809, 668)

#### Scenario: Click on a negative-origin monitor
- **WHEN** the client is 2560×1440 at desktop origin (-2560, -360), the virtual desktop contains it, and the trigger point is (-1200, 340)
- **THEN** the planned region is client (694, 0, 1519, 1253), which is desktop origin (-1866, -360)

#### Scenario: Trigger point outside the client
- **WHEN** the trigger point lies outside the target's client rectangle
- **THEN** the result is `roiOutsideClient`, and no pixels are acquired

### Requirement: Clipping is explicit, never padded
A planned region SHALL be intersected with the client rectangle and the virtual desktop. A non-empty intersection SHALL be captured at its real size, with both the requested and captured rectangles reported. The frame SHALL be marked clipped exactly when the captured rectangle differs from the requested one. An empty intersection SHALL fail with `roiOutsideClient`. Missing area SHALL NOT be filled with padding.

#### Scenario: Region inside a fully visible client
- **WHEN** a targeted region is planned on a 1920×1080 client fully inside the virtual desktop
- **THEN** the requested and captured rectangles are both (520, 0, 1140, 940), and the frame is not marked clipped

#### Scenario: Region crosses the right edge
- **WHEN** a 1920×1080 client is at desktop origin (0, 0), the virtual desktop ends at x = 1200, and the trigger point is desktop (600, 500)
- **THEN** the requested rectangle is (520, 0, 1140, 940), the captured rectangle is (520, 0, 680, 940), the frame is 680×940 and marked clipped

#### Scenario: Region crosses the top-left corner
- **WHEN** a 1920×1080 client is at desktop origin (-1000, -200), the virtual desktop starts at (0, 0), and the trigger point is desktop (500, 300)
- **THEN** the requested rectangle is (520, 0, 1140, 940), the captured rectangle is (1000, 200, 660, 740), the frame is 660×740 and marked clipped

#### Scenario: Region entirely off-screen
- **WHEN** a 1920×1080 client is at desktop origin (-1700, 0), the virtual desktop starts at x = 0, and the trigger point is desktop (100, 500)
- **THEN** the result is `roiOutsideClient`, and no frame is produced

### Requirement: Frames have an immutable pixel layout
A returned frame SHALL expose its width, height, row stride in bytes, pixel format, row order and signed desktop origin, unchanged for its lifetime. The pixel format SHALL be 32-bit BGRX, top-down, with the fourth byte undefined.

#### Scenario: Frame layout
- **WHEN** a targeted capture succeeds on a 1920×1080 client at desktop origin (0, 0) for client point (900, 500)
- **THEN** the frame reports 1140×940, stride ≥ 4560, format BGRX top-down, and desktop origin (520, 0)

#### Scenario: Pixel access after release
- **WHEN** a frame's pixels are read after it was released
- **THEN** the read fails with a typed `frameReleased` error, and no native memory is accessed
