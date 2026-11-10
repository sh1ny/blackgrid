# interface-theme Specification

## Purpose
Defines Blackgrid's visual system: the Ember dark and light rooms built from the design tokens, the saved theme choice, the bundled fonts and their notices, and the rule that screens take their colours only from the theme.

## Requirements

### Requirement: Two rooms built from the design tokens
The app SHALL provide a dark room and a light room. Each SHALL take every colour role, type role, corner radius and control size from the Ember token values recorded in DESIGN.md, under the same role names in both rooms. Blackgrid's own roles (the verdict greens and the map ground) SHALL have a dark and a light value too.

#### Scenario: Dark room carries the dark token values
- **WHEN** the app builds its dark room
- **THEN** the canvas, panel, raised, ink, accent and hairline roles equal the dark values in DESIGN.md (canvas `#0c0c0e`, panel `#121215`, raised `#18181c`, ink `#e8e6e1`, accent `#e9a14b`, hairline white at 7% alpha, `0x12FFFFFF`)

#### Scenario: Light room carries the light token values
- **WHEN** the app builds its light room
- **THEN** the same roles equal the light values in DESIGN.md (canvas `#f7f6f3`, panel `#efede9`, raised `#ffffff`, ink `#1d1b18`, accent `#d98a2b`, hairline `#1e1810` at 9% alpha, `0x171E1810`), and the accent-text role is `#8a4c05`

#### Scenario: The map ground does not follow the room
- **WHEN** either room is built
- **THEN** the map ground role is `#0c0c0e` in both rooms

### Requirement: Screens take colours only from the theme
Outside the theme and token sources, code under `lib/ui` SHALL NOT construct colour literals or use Material's named colour constants, except fully transparent. The offline test suite SHALL check this and name the file and line of each hit. The map's own palette lives under `lib/maps` and `lib/domain`, outside this rule; map painting code in `lib/ui` reads it from there.

#### Scenario: A screen reads its colours from the theme
- **WHEN** the offline test suite runs the colour check over `lib/ui` on the finished change
- **THEN** it reports no hits

#### Scenario: A hard-coded colour is reported
- **WHEN** a file under `lib/ui` other than the theme and token sources contains `Color(0xff123456)` or `Colors.amber`
- **THEN** the check fails and names that file and line

### Requirement: Saved theme choice
Settings SHALL hold a theme choice of System, Dark or Light, with System as the default. System SHALL follow the Windows light or dark setting, including a change made while the app runs. The choice SHALL be saved with the other settings and restored at the next launch.

#### Scenario: Default follows Windows
- **GIVEN** no theme choice has been saved
- **WHEN** the app starts while Windows is in light mode
- **THEN** the app shows the light room, and Settings shows System selected

#### Scenario: A chosen room survives a restart
- **WHEN** the player selects Dark and the app is restarted
- **THEN** the app starts in the dark room, and Settings shows Dark selected, whatever the Windows setting is

#### Scenario: Windows changes while System is chosen
- **GIVEN** System is selected and the app shows the dark room
- **WHEN** Windows switches to light mode
- **THEN** the app shows the light room without a restart

#### Scenario: An unreadable theme value
- **GIVEN** saved settings whose theme value is missing, not a string or not one of the three choices
- **WHEN** settings are loaded
- **THEN** the theme choice is System, and every other saved setting keeps its saved value

#### Scenario: Saving the choice fails
- **WHEN** saving a new theme choice fails
- **THEN** the save error is shown as for any other setting ("Your previous settings are kept"), and the app shows the room of the previous choice, with that choice selected in Settings

### Requirement: Theme switch in Settings
Settings SHALL show the theme choice as one control with three options in the order System, Dark, Light, with the current choice selected. Selecting an option SHALL change the room at once, with no transition animation, and save the choice.

#### Scenario: Switching rooms
- **GIVEN** the app shows the dark room
- **WHEN** the player selects Light in Settings
- **THEN** the next frame shows the light room and Light is selected

#### Scenario: Selecting the current option
- **WHEN** the player selects the option that is already selected
- **THEN** the room does not change and no save is attempted

### Requirement: Bundled fonts with notices
The app SHALL bundle Geist and Literata as font assets and use them as the interface and title families, so they do not depend on fonts installed on the player's machine. `THIRD_PARTY_NOTICES.md` SHALL name each bundled font file with its family, version or source revision, source URL and SHA-256, followed by the full SIL Open Font License 1.1 text with the family's copyright line.

#### Scenario: Interface text uses the bundled family
- **WHEN** a widget test renders body text in either room
- **THEN** its font family is Geist, and an item name in a title role uses Literata

#### Scenario: Every font file has a notice entry
- **WHEN** the offline test suite checks the font assets
- **THEN** every font file declared in `pubspec.yaml` exists, its SHA-256 matches the one named in `THIRD_PARTY_NOTICES.md`, and the OFL text for its family is present

#### Scenario: A font file changes without its notice
- **WHEN** a bundled font file's bytes differ from the SHA-256 recorded in `THIRD_PARTY_NOTICES.md`
- **THEN** the check fails and names that file

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

### Requirement: Dialogs, sheets and the startup screen in Ember
Every dialog the app opens SHALL use the Ember raised surface and every bottom sheet the Ember panel surface, a dialog with 12px corners and a sheet with 12px top corners, its title in the Literata Title role, Ember button variants with at most one primary action, and the theme's colours in both rooms. The startup screen SHALL use the Canvas surface of the room Windows asks for. Each dialog SHALL keep its wording, actions and keyboard behaviour.

#### Scenario: Stats dialog
- **WHEN** Stats opens in the light room
- **THEN** its surface is the light raised colour with 12px corners, "Close" is the only primary action and "Clear stats" is a quiet action

#### Scenario: Confirm dialog
- **WHEN** the player asks to remove a pin
- **THEN** the confirm dialog shows "Remove" as its one primary action and "Cancel" as a quiet action, and Escape cancels

#### Scenario: Marker list sheet
- **WHEN** the marker list sheet opens on the Map
- **THEN** its surface is the panel colour with 12px top corners, and its title is in the Literata Title role

#### Scenario: Map help closes
- **WHEN** Map help is open and the player presses Escape
- **THEN** it closes and keyboard focus is back on the map

#### Scenario: Startup error
- **WHEN** local storage cannot be opened
- **THEN** the startup screen shows the storage message word for word and "Retry opening local storage" in Ember styling
