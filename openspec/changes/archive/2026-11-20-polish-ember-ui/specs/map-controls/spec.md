# Spec Delta

## ADDED Requirements

### Requirement: The map credit names the map's creator
The artwork attribution at the bottom left of the Map SHALL read `Map creator: <author>`, where `<author>` is the shown map's author from its map pack, in the theme's primary ink. When the pack gives no author for the map, it SHALL show the map's name alone, without the prefix. It SHALL stay one line and shorten with an ellipsis when it does not fit.

#### Scenario: Map with an author
- **WHEN** Map shows a loaded map whose pack names the author `Shebuka`
- **THEN** the attribution reads `Map creator: Shebuka` in the theme's primary ink

#### Scenario: Map without an author
- **WHEN** Map shows a loaded map whose pack gives no author and whose name is `Customs`
- **THEN** the attribution reads `Customs`, and no text on the Map begins `Map creator:`

#### Scenario: Long credit on a narrow map
- **WHEN** the author's name is longer than the space left beside the map controls
- **THEN** the attribution stays on one line, ends in an ellipsis and does not overlap the controls
