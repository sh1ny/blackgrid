# Proposal

## Why

The native map shows markers and extract names, but not the names of the places themselves (Dorms, Big Red, the mall shops, the Labs rooms), so a player has to know the map to read it. tarkov.dev's interactive metadata already names 303 places on 10 maps, and that file is frozen in the active pack's evidence (`evidence/metadata/maps.json`). The owner decided on 2026-10-30 to use tarkov.dev's data with a rights note.

This is the last change of milestone **M8 - map labels and popups**. It serves the agent-verified exit criterion "The new pack version carries tarkov.dev's place labels with a rights note, drawn behind markers at a fixed screen size, hidden on other floors and thinned when zoomed out, proved by pack and painter tests". It also completes what the user-verified criterion "On real maps the labels, extract names and bubbles read correctly" needs. That criterion is judged by the user at the M8 close, not by a task here: it covers extract names and bubbles from earlier M8 changes as well as these labels, and it needs the game, which agents never run.

## What Changes

- The pack build reads the place labels from the frozen interactive metadata and writes them into each supported map of a new pack generation: text, position, rotation, relative size and the Blackgrid floors the label belongs to. Labs maps from source key `the-lab` to `thelab`. Maps without labels (Terminal, Icebreaker, Labyrinth) get an empty list. The prepared pack version goes up, and the app loads only the new version.
- A label's floors come from its height band: a reviewed per-map table in the builder gives each Blackgrid floor a height band, taken from tarkov.dev's layer heights and checked against them by a test, and a label belongs to every floor its band overlaps. A label without a band belongs to the base floor. A label whose band touches no floor fails the build; it is never dropped silently.
- `THIRD_PARTY_NOTICES.md` gets a rights note for the labels: their source (`the-hideout/tarkov-dev`, `src/data/maps.json`), its MIT licence and copyright line, where that licence text sits in the pack, and that Blackgrid claims no ownership of the place names. The pack's `NOTICE.txt` stays as it is.
- The map draws place labels on the canvas behind zone outlines, extract names and badges: at a fixed screen size that keeps tarkov.dev's relative sizes, rotated as the source says, with a dark halo. A label shows while one of its floors is visible, so ground labels stay when an upper-floor overlay is on, and the overlay adds its own.
- When labels would overlap, a label of the selected floor wins, then the larger one, and the other is not drawn, so zooming out thins them and zooming in brings names back.
- `maps:rebuild` produces the new generation and `maps:check` proves it reproduces. A metadata-only renewal keeps the labels unchanged, like the rest of the pack-owned metadata.

## Capabilities

### New Capabilities

- `map-place-labels`: how the native map draws place names: which labels show on which floor, their size, rotation and halo, their draw order, and how they thin when they would overlap.

### Modified Capabilities

- `prepared-map-packs`: a pack carries each map's place labels with their floors; the build fails on a malformed label or one with no floor; the app loads only the new pack version; the third-party notices credit the labels; a metadata-only renewal preserves labels with the other pack-owned rendering metadata.

## Impact

- `tool/maps/pack.dart` and a new label module in `tool/maps/`: label extraction, the per-floor band table, floor assignment, label validation and the prepared version bump. `THIRD_PARTY_NOTICES.md`: the label credit. `assets/maps/` gets a new generation (`maps:rebuild`) and `pubspec.yaml`'s asset block is rewritten with it.
- `lib/maps/prepared_map.dart` and `prepared_map_loader.dart`: parse and validate labels; accept only the new prepared version.
- `lib/application/map_controller.dart`: project visible labels for the current floor selection and viewport. `lib/ui/map_workspace.dart`: draw them before outlines.
- Tests: pack and loader tests for extraction, floors, validation and the notice; controller tests for floor visibility; painter tests for size, rotation, order and thinning.
- CI: the qualification tests that run a full map staging or rebuild get a 10-minute per-test timeout instead of the 2-minute `qualification` tag default. "staging and frozen reproduction omit stale marker overrides" (`test/maps/artwork_refresh_test.dart`) timed out at 2 minutes on three of the last four CI runs (42395244727, 42410087351, 42410085044, on normal ~40-minute runs). This change adds label work to every rebuild, so it fixes that here rather than leaving it to fail on this PR. Other qualification tests keep the 2-minute default.
- Labels are not markers: they are not hit-tested, searched, filtered or exposed as accessibility targets, and the runtime map data (`runtime-map-data`) does not touch them. No new dependency and no new setting. ADR-0033 governs the rebuild and check; ADR-0023's colours are unchanged.

## Decision Making

DECISION_MAKING: important
- **Source:** setting

### S1: Ground labels stay when an upper floor is on

- **Choice:** A label shows while any floor it belongs to is visible. On maps where overlays stack over the base, ground labels stay and the overlay adds its own labels, as markers already do.
- **Rejected:** Show only the selected floor's labels. It hides outdoor names whenever a floor is on and makes labels behave differently from markers.
- **Reversal cost:** low
- **Important:** yes, it changes what users see
- **Chosen by:** user

### S2: Thin by skipping overlapping labels

- **Choice:** Place labels of a selected overlay floor first, then the rest; within each group largest first, then in source order. Skip a label whose box overlaps one already placed. No zoom thresholds. The selected-floor-first order was added on 2026-11-07 after the design review showed that ground names (all Labs labels are size 90 and come first; Interchange's Garage A–D are larger than the mall shop names) would otherwise hide the names of the floor the user picked.
- **Rejected:** A zoom threshold that shows only large labels when zoomed out (names still collide at mid zoom); both rules together (more rules to tune and test).
- **Reversal cost:** low
- **Important:** yes, it changes what users see
- **Chosen by:** user

### S3: No switch to hide labels

- **Choice:** Labels are always on; thinning keeps clutter down.
- **Rejected:** A saved "Place labels" switch beside the marker switches. It adds a preference key, and M8.5 redesigns where settings live.
- **Reversal cost:** low
- **Important:** yes, it changes behaviour and settings users see
- **Chosen by:** user

### S4: Keep tarkov.dev's relative sizes at a fixed screen size

- **Choice:** Size 80 is about 13 px, scaled in proportion and clamped to about 10–16 px; a label without a size counts as 80. The size does not change with zoom.
- **Rejected:** One size for every label. It loses the difference between district names and small rooms.
- **Reversal cost:** low
- **Important:** yes, it changes what users see
- **Chosen by:** user

### S5: Labels belong to the pack, not to the runtime map data

- **Choice:** Labels come from the frozen interactive metadata through the pack build, as `add-live-map-data` already decided ("Artwork, calibration and location labels stay in the prepared pack").
- **Rejected:** Downloading labels at runtime. `maps.json` comes from tarkov.dev's site repository, not from the json.tarkov.dev endpoints, and label floors depend on the pack's calibration.
- **Reversal cost:** medium
- **Important:** yes, it binds the pack format
- **Chosen by:** agent (recorded by the user in the roadmap and in `add-live-map-data`)

## Release Notes

The map now names its places, such as Dorms, Big Red, the Interchange shops and the Labs rooms, using tarkov.dev's place labels. Names keep a fixed size as you zoom, follow the floor you pick and thin out when zoomed far out so they do not pile up.

### Added

- Place names on every map that has them in tarkov.dev's data: drawn behind markers, sized by importance, rotated along roads, shown for the floors you pick and thinned when they would overlap.
