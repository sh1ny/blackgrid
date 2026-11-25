# Spec Delta

## Purpose

Turns the exfil panel in a saved raid screenshot into extract and transit rows, and matches those rows to the current map's exits, so the Map can highlight the exits this raid offers.

## ADDED Requirements

### Requirement: Panel rows split at every row label
Reading a saved exfil panel SHALL start a new extract or transit row at every `EXFIL`, `EXIT` or `TRANSIT` label followed by a row number. A row number SHALL be recognised when OCR reads its zero as `Ø`, `O` or `o`, or its one as `I`, `l` or `|`. No row's name SHALL contain another row's label.

#### Scenario: Slashed-zero labels on one line
- **WHEN** OCR reads Shoreline's panel as one line, `EXFILØ1 Road to North V-Ex EXFILØ2 Road to Customs EXFILØ3 Railway Bridge … TRANSITØI Transit to Lighthouse TRANSITØ4 Transit to Icebreaker`
- **THEN** `Road to Customs` and `Railway Bridge` are separate extract rows, `Transit to Lighthouse` and `Transit to Icebreaker` are separate transit rows, and no row contains `EXFIL` or `TRANSIT`

#### Scenario: Plain-digit labels keep working
- **WHEN** OCR reads the same panel with plain zeros, `EXFIL02 Road to Customs EXFIL03 Railway Bridge`
- **THEN** the rows are the same as with slashed zeros

#### Scenario: Label word without a row number
- **WHEN** a name contains `Exfil` without a number after it, as in `Saferoom Exfil`
- **THEN** the row keeps its whole name, `Saferoom Exfil`

### Requirement: Short rows match only by exact name
An OCR row whose letters and digits number fewer than four SHALL match an exit only when they equal that exit's normalised name. Such a row SHALL NOT match by containment or by fuzzy similarity.

#### Scenario: Short exit name
- **WHEN** a Reserve panel row reads `D-2`
- **THEN** it matches the D-2 extract

#### Scenario: Stray fragment
- **WHEN** a Shoreline panel leaves a row that reads only `I`
- **THEN** that row matches no exit, and Transit to Terminal is not highlighted unless the panel names it

### Requirement: Saved Shoreline panels resolve
A saved Shoreline exfil panel that lists its exits SHALL match those exits rather than being rejected as ambiguous. An exit missing from the panel SHALL NOT be matched.

#### Scenario: Night-vision panel
- **WHEN** the owner's 2026-11-25 night-vision screenshot (raid time 12.10) is read on Shoreline
- **THEN** the result is recognised and matches Road to North V-Ex, Road to Customs, Railway Bridge, Path to Lighthouse, Smugglers' Path (Co-op), Pier Boat, Climber's Trail, Transit to Lighthouse and Transit to Icebreaker

#### Scenario: Exit not on the panel
- **WHEN** any of the owner's four 2026-11-25 Shoreline panels is read
- **THEN** Transit to Terminal is not matched

#### Scenario: Row that truly fits two exits
- **WHEN** a single row still fits two exits with equal strength
- **THEN** the panel is reported ambiguous and nothing is highlighted, as before
