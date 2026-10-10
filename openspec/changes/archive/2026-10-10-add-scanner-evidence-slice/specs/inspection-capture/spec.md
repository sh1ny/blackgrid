# Spec Delta

## MODIFIED Requirements

### Requirement: Frames carry their provenance
A returned frame SHALL also expose the requested and captured client rectangles, the clipped flag, the DPI, the physical client width and height of the snapshot the request was validated against, and the target identity (window handle, process id, thread id, executable name). It SHALL expose monotonic timestamps from before and after acquisition, on the same clock as trigger timestamps, plus the UTC capture time and the caller's request id.

#### Scenario: Frame provenance
- **WHEN** a targeted capture with request id 42 succeeds unclipped for a trigger stamped at monotonic time T
- **THEN** the frame reports request id 42, clipped false, the trigger's window handle and process id, a pre-acquisition timestamp not earlier than T, and a post-acquisition timestamp not earlier than the pre-acquisition one

#### Scenario: Clipped provenance
- **WHEN** a targeted capture is clipped at the right client edge
- **THEN** the frame reports differing requested and captured rectangles and clipped true

#### Scenario: Client size of a targeted frame
- **WHEN** a targeted capture succeeds for a 2560×1440 client
- **THEN** the frame reports client width 2560 and height 1440, independent of its captured region's size

#### Scenario: Client size of a clipped fallback frame
- **WHEN** a fallback capture of a 1920×1080 client is clipped by the virtual desktop to 1800×1080
- **THEN** the frame reports captured width 1800 and client width 1920
