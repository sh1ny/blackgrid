# Spec Delta

## Purpose

Defines how the native map draws the names of places from the prepared pack: which labels show on which floor, their size, rotation, colour and halo, their place in the draw order, and how they thin out when they would overlap.

## ADDED Requirements

### Requirement: Place labels show for the floors they belong to
The native map SHALL draw a place label of the selected map only while at least one floor the pack assigns it is visible under the current floor selection. Selecting an overlay SHALL NOT hide a label that belongs to a still-visible floor. A map whose pack entry has no labels SHALL draw none.

#### Scenario: Ground label stays under an overlay
- **WHEN** Interchange shows its base floor with the 2nd Floor overlay selected, and "Power Station" belongs to the base floor only
- **THEN** "Power Station" is drawn

#### Scenario: Overlay adds its labels
- **WHEN** Interchange's 2nd Floor overlay is selected and "IDEA" belongs to that overlay only
- **THEN** "IDEA" is drawn, and it is not drawn after the overlay is cleared

#### Scenario: Label of a hidden exclusive floor
- **WHEN** an exclusive-floor map shows one floor and a label belongs only to another floor
- **THEN** that label is not drawn

#### Scenario: Map without labels
- **WHEN** Terminal is selected and its pack entry has an empty label list
- **THEN** no place label is drawn and the map draws as before

### Requirement: Place labels keep a fixed screen size
A place label SHALL be drawn at a font size that does not change with zoom. The size SHALL follow the label's relative size from the pack: size 80 SHALL draw at 13 logical pixels, other sizes in proportion, clamped to 10–16 logical pixels.

#### Scenario: Zooming keeps the size
- **WHEN** the user zooms from fit to four times the scale
- **THEN** each drawn place label has the same font size as before, at its anchor's new position

#### Scenario: Relative sizes
- **WHEN** labels with sizes 65, 80 and 100 are drawn
- **THEN** they are drawn at about 10.6, 13 and 16 logical pixels

#### Scenario: Out-of-range size is clamped
- **WHEN** a label's relative size would give less than 10 or more than 16 logical pixels
- **THEN** it is drawn at 10 or 16 logical pixels

### Requirement: Place labels are centred, rotated and haloed
A place label SHALL be drawn as one line of text centred on its projected anchor, rotated clockwise by its rotation in degrees about that anchor, in one neutral label colour at 85% opacity over a halo in the marker background colour. The label colour SHALL differ from every faction name colour, and blended at 85% over `#090F0D` it SHALL reach a contrast of at least 3:1 against `#090F0D`.

#### Scenario: Rotated label
- **WHEN** a Streets label with rotation −90 is drawn
- **THEN** its text runs bottom to top, centred on its anchor

#### Scenario: Unrotated label
- **WHEN** a label with rotation 0 is drawn
- **THEN** its text is horizontal and centred on its anchor

#### Scenario: Colour rule rejects a bad label colour
- **WHEN** the place label colour equals a faction name colour, or blended at 85% over `#090F0D` has a contrast below 3:1 against `#090F0D`
- **THEN** the palette test fails and names the broken rule

### Requirement: Place labels sit behind every marker drawing
Place labels SHALL be drawn after the map artwork and before zone outlines, extract names, badges, the player and pins. Search, quest filters, hover and selection SHALL NOT change how a place label is drawn.

#### Scenario: Badge over a label
- **WHEN** a marker badge lies on a place label
- **THEN** the badge is drawn over the label

#### Scenario: Search does not dim labels
- **WHEN** a search dims every marker
- **THEN** place labels are drawn at their normal opacity, the same as with no search

### Requirement: Overlapping place labels thin out
Among the labels eligible to draw, the map SHALL place labels that belong to a selected overlay floor first, then the rest; within each group largest relative size first, then in pack order. It SHALL skip a label whose drawn bounds, with a 2 logical-pixel margin, overlap a label already placed. Only labels whose bounds intersect the viewport SHALL be placed. The result SHALL depend only on the labels, the floor selection, the viewport and the view transform.

#### Scenario: Zoomed out
- **WHEN** two labels of sizes 100 and 65 would overlap at the current zoom
- **THEN** only the size-100 label is drawn

#### Scenario: Zooming in restores the name
- **WHEN** the user zooms in until those two labels no longer overlap
- **THEN** both are drawn

#### Scenario: Equal sizes
- **WHEN** two labels of the same size overlap
- **THEN** the one earlier in the pack is drawn and the other is not

#### Scenario: Selected floor wins
- **WHEN** Labs Second Level is selected and a First Level label and a Second Level label of equal size overlap
- **THEN** the Second Level label is drawn and the First Level label is not

#### Scenario: Off-screen label takes no room
- **WHEN** a large label lies wholly outside the viewport next to a small visible label
- **THEN** the small label is drawn

### Requirement: Place labels are not interactive
Place labels SHALL NOT be hit-tested, selected, searched, filtered, counted in marker summaries or exposed as accessibility targets. A click on a place label SHALL behave as a click on the map at that point.

#### Scenario: Click on a label
- **WHEN** the user clicks on a place label away from any marker
- **THEN** no marker is selected and no bubble opens

#### Scenario: Click on a label over a badge
- **WHEN** the user clicks where a place label overlaps a marker badge
- **THEN** that marker is selected

#### Scenario: Accessibility targets
- **WHEN** the map builds its accessibility targets
- **THEN** no target is created for a place label
