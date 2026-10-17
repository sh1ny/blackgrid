# Spec Delta

## MODIFIED Requirements

### Requirement: Every published scan writes one case line and its frames
While recording is on, each scan that ends accepted, rejected or failed SHALL get exactly one line in the session's `frames.jsonl`. Superseded scans SHALL get none. The recorder SHALL write the scan's full-client frame, when it has one, as an opaque RGB PNG `<id>-full.png` at its captured size. It SHALL write the scan's targeted strip, when it has one, as `<id>-targeted.png`. The line SHALL name these files, with `image: null` or `strip: null` for a missing frame.

#### Scenario: Scan accepted by the fallback pass
- **WHEN** Scanner's scan #7 of session `20261010-140307` is accepted by its fallback pass on a 1920x1080 client
- **THEN** the folder holds `20261010-140307-0007-full.png` (1920x1080) and `20261010-140307-0007-targeted.png` (1140x600), and `frames.jsonl` has one line with id `20261010-140307-0007`

#### Scenario: Superseded scan
- **WHEN** a scan is superseded before it ends
- **THEN** nothing is written for it

#### Scenario: Accepted scan whose extra capture fails
- **WHEN** a scan is accepted by its targeted pass and its extra full-client capture fails with `targetChanged`
- **THEN** its strip PNG is written, and its line has `outcome: "accepted"`, `image: null` and `fullFailure: "targetChanged"`

#### Scenario: Ended on the targeted pass without a fallback
- **WHEN** a scan is rejected `catalogUnavailable` after its targeted pass
- **THEN** its strip PNG is written and its line has `image: null`, `outcome: "rejected"` and `rejectReason: "catalogUnavailable"`

#### Scenario: No frame at all
- **WHEN** a scan fails because its targeted capture answers `captureBusy`
- **THEN** no PNG is written and its line has `image: null`, `strip: null`, `outcome: "failed"` and `failure: "captureBusy"`

