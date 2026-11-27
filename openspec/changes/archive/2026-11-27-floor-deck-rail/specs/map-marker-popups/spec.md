## MODIFIED Requirements

### Requirement: Marker selection is cleared consistently
Closing the bubble, pressing Escape with focus on the canvas or in the bubble, clicking empty map space or selecting a saved pin SHALL clear marker selection and its selection-linked highlights. Escape in the floor rail SHALL return focus to the canvas without clearing selection. An Escape repeat SHALL NOT clear selection after that handoff; a fresh press SHALL. Saved-pin details and editing SHALL remain available.

#### Scenario: Close marker bubble
- **WHEN** a marker and its linked switches are highlighted and the player activates the bubble's Close control
- **THEN** the bubble, marker selection and selection-linked switch highlights disappear

#### Scenario: Pin selection
- **WHEN** a marker is selected and the player selects a saved pin
- **THEN** marker selection and its bubble clear and the pin's details remain available

#### Scenario: Empty map and Escape
- **WHEN** a marker is selected and the player clicks empty map space or presses Escape with focus on the canvas or in the bubble
- **THEN** marker selection and its bubble clear

#### Scenario: Escape leaves the floor rail without clearing selection
- **WHEN** a marker is selected and the player presses and holds Escape with a floor rail control focused
- **THEN** focus returns to the canvas, but the marker and bubble stay selected through repeats
- **AND** releasing Escape and pressing it again on the canvas clears them
