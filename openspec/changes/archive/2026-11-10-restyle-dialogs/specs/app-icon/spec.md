# Spec Delta

## MODIFIED Requirements

### Requirement: The app header and the startup screen show the application icon
The app header SHALL draw the committed in-app vector at 32 by 32 logical pixels, and the startup screen at 54 by 54, where the generic hub icon was, beside or above the `BLACKGRID` name. The startup screen SHALL show the full brand lockup: the logo, `BLACKGRID` and the tagline `TRACK. PLAN. SURVIVE.` below it. The logo SHALL be decorative: it SHALL add no semantics node, so the accessible name stays the `BLACKGRID` text. If the vector cannot load, an empty space of the same size SHALL stand in, with the rest of the layout unchanged and no error widget shown.

#### Scenario: Header shows the logo
- **WHEN** the app shell is shown
- **THEN** the header holds the logo drawn from `assets/app_icon/app_icon.vec` at 32 by 32 beside `BLACKGRID`, and no `Icons.hub_outlined`

#### Scenario: Startup screen shows the logo
- **WHEN** the app is opening local storage, or showing the storage error
- **THEN** the screen shows the logo from `assets/app_icon/app_icon.vec` at 54 by 54 above `BLACKGRID`, the tagline `TRACK. PLAN. SURVIVE.` below `BLACKGRID`, and no `Icons.hub_outlined`

#### Scenario: Logo is not announced
- **WHEN** a screen reader reads the header
- **THEN** it reads `BLACKGRID` and `TRACK. PLAN. SURVIVE.`, and nothing for the logo

#### Scenario: Vector fails to load
- **WHEN** loading the `.vec` fails
- **THEN** the header shows an empty 32 by 32 box where the logo goes, the `BLACKGRID` text stays in the same place, no error widget is shown, and `FlutterError.onError` is not called
