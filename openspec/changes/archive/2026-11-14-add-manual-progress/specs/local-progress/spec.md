# Spec Delta

## ADDED Requirements

### Requirement: One event can be read by its ID
The store SHALL return the event with a given ID from a named mode and cycle, decoded and validated as history reads are. An ID absent from that scope SHALL return not found, without reading another scope. Damaged or unsupported event data SHALL make the cycle unavailable, as for history reads. The read SHALL NOT change any event, winner or revision.

#### Scenario: Read an undo's target
- **WHEN** event E set level 34 in PvE cycle C and E is read by its ID in C
- **THEN** the store returns E with all its fields, and C's revision is unchanged

#### Scenario: ID from another cycle
- **WHEN** an event ID stored in cycle D is read in cycle C
- **THEN** the read returns not found

#### Scenario: Damaged event
- **WHEN** the requested event's stored data is malformed
- **THEN** the read reports the cycle unavailable and the stored bytes are unchanged
