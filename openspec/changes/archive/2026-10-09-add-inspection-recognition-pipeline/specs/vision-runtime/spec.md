# Spec Delta

## ADDED Requirements

### Requirement: Template match lists every location at or above a threshold
The runtime SHALL list every template-match location whose normalised cross-correlation score is at or above a caller-given threshold, in raster order, with its score, up to a caller-given cap. It SHALL report overflow, not a truncated list, when more locations qualify than the cap allows. NaN scores SHALL never qualify. Malformed images SHALL be rejected as for the other primitives.

#### Scenario: Two template copies
- **WHEN** a template is listed at threshold 0.99 against an image holding exact copies of it at (10, 5) and (60, 30)
- **THEN** the list holds (10, 5) and (60, 30) in that order, each with score at least 0.99

#### Scenario: Nothing reaches the threshold
- **WHEN** no location reaches the threshold
- **THEN** the list is empty and no failure is reported

#### Scenario: More locations than the cap
- **WHEN** more locations qualify than the cap allows
- **THEN** the operation returns failure `nativeFailure` with status -6 (`BGV_ERR_OVERFLOW`, distinct from every other status), and no partial list

#### Scenario: Template larger than image
- **WHEN** the template is wider or taller than the image
- **THEN** the operation returns failure `invalidImage`, and no native call is made
