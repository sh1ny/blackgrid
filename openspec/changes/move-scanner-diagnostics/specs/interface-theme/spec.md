# Spec Delta

## MODIFIED Requirements

### Requirement: Ember surfaces and labels
Docked panels SHALL be separated by surface tone and a 1px hairline, with no shadow. Pressable controls SHALL be pill-shaped and containers SHALL have soft corners. Section labels SHALL be sentence case. The brand lockup (the wordmark and its tagline) is exempt and keeps its capitals.

#### Scenario: A docked panel has no shadow
- **WHEN** the Scanner is rendered in either room
- **THEN** each docked panel has the panel surface colour, a 1px hairline border and no elevation or shadow

#### Scenario: Section labels are sentence case
- **WHEN** the Scanner's scan evidence panel, Settings' Live scan section, the recent scans part of Diagnostics, and the Map's map picker are rendered
- **THEN** their labels read "Scan evidence", "Live scan", "Recent scans" and the map's display name (for example "Customs"), none of them in uppercase, and the Scanner shows no "Manual inspection" or "Recent scans" label

#### Scenario: The brand lockup keeps its capitals
- **WHEN** the header is rendered
- **THEN** the wordmark still reads "BLACKGRID" and the tagline "TRACK. PLAN. SURVIVE."
