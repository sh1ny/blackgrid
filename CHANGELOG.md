# Blackgrid Changelog

## v0.8.0 - 2026-11-08

The map now names its places and extracts, opens a bubble at each marker, and refreshes its marker data from tarkov.dev without a new release; missing Kollontay and Glukhar locations are restored.

Added:
- Extract and transit names on the map, coloured for PMC, Scav, shared and transit exits. (#86)
- A `?` help button on the map: your position comes from screenshots taken with the game's own screenshot key. (#86)
- Marker bubbles follow pan and zoom, stay inside the map view and support pointer and keyboard dismissal. (#88)
- Marker summaries resolve key and required-item names from already loaded item data; unavailable names are stated rather than shown as IDs. (#88)
- Stage fresh artwork with source and calibration checks and a per-map change report; publish the exact staged candidate separately with interrupted-publication recovery diagnostics. (#91)
- Design context for the coming interface redesign (M8.5): the Ember brand kit, a product record, a before-redesign record of the current interface, and a DESIGN.md that applies Ember to Blackgrid in the "Answer strip" layout. (#93)
- Mode-specific map-data refresh at startup and from Settings, with conditional downloads, a local last-good cache and a labelled bundled fallback. (#94)
- Place names on every map that has them in tarkov.dev's data: drawn behind markers, sized by importance, rotated along roads, shown for the floors you pick and thinned when they would overlap. (#95)

Changed:
- Blackgrid loads a map pack when it can decode the pack's vector format, instead of requiring one exact vector_graphics version, so routine library updates (#83) keep maps working. The bundled maps are rebuilt with the current tools and look the same.
- Zone outlines use their category's colour instead of red. Extract and transit outlines show only while you hover over or select the extract. (#86)
- Keep offline map checks, rebuilds and metadata-only renewal tied to the active generation's frozen calibration, source locks and notices while newer artwork configuration is pending. (#91)
- Successful map-data updates replace marker facts immediately while retaining map navigation, floors, filters and saved pins; marker selection closes when content changes. (#94)
- Shared runtime and offline normalization accepts valid upstream additions, removals, edits and empty collections. Historical floor overrides apply only while reviewed identity and placement assumptions match; artwork, calibration and frozen-source integrity remain separately protected. (#94)
- Markers that refer to the same task, objective or location share its facts instead of copying them. (#94)
- Extreme offscreen geometry no longer interrupts rendering. (#94)
- Map-data availability reflects prepared-pack load failures, and malformed exit aliases are rejected before activation. (#94)

Fixed:
- Equally close overlapping map badges select the topmost visible marker, so boss badges open the boss information rather than an underlying generic spawn. (#88)
- Map navigation shortcuts no longer pan or zoom the map while a marker bubble control has keyboard focus. (#88)
- Removing the current session's application log resets raid input even when the folder is deleted afterward. (#88)
- Long marker names remain readable by scrolling, and untranslated spawn-zone identifiers use readable category labels. (#88)
- Selecting a different marker starts its summary at the top, while updates to the current marker retain its scroll position. (#88)
- Refresh boss and non-boss metadata across all 13 supported maps, restoring the reported Kollontay locations on Streets and Glukhar locations on Reserve with independently audited source-to-pack coverage. (#90)
- Reject malformed boss source facts and missing or ambiguous supported-map identities with source and map diagnostics, while preserving repeated positions and explicit empty coverage. (#90)
- Prevent metadata-only renewal from changing prepared artwork, calibration or reviewed marker floor ownership; keep normal rebuilds offline. (#90)

## v0.7.0 - 2026-11-02

Blackgrid now follows your raid from the game's logs: the Map shows the raid phase, a timer strip shows time in raid, the run-through countdown and the scav cooldown, and a new Stats dialog counts your flea sales and raids per map, kept only on your PC.

Added:
- Each change's proposal carries a `## Release Notes` section, and `release:prepare` builds the release's changelog section from them with a summary you give it (#75)
- `mise run release-notes` prints the draft notes for the next release, and `-- --check <proposal.md>` validates one proposal's section (#75)
- The Map's saved-file inputs show the raid phase (in menus, in queue, match found, raid starting, in raid or raid ended), read from the game's application, backend and push-notification logs. (#76)
- A "Raid logs:" line on the Map reports problems with the backend and push-notification logs, such as a notifications log the game has not written yet, without changing the "Logs:" line. (#76)
- A timer strip under the header, on both Map and Scanner, shows time in raid, the run-through countdown (7:10 by default) and the scav cooldown, counted from the game's log times so a restart of Blackgrid mid-raid keeps them right. (#77)
- The scav cooldown starts when a scav raid ends and uses tarkov.dev's base time, your Fence reputation and the hideout bonuses from your Tracker progress. It is kept per game mode and survives a restart. (#77)
- A "Raid timers" section in Settings turns the timers on or off, chooses which show, and sets the run-through length and your Fence reputation. (#77)
- A Stats dialog, opened from the header, shows the current mode's flea sales (sales, items sold, roubles earned) and raids per map, counted from the game's logs and kept across restarts. Nothing leaves your PC. (#79)
- Clear stats empties every mode's stats after a confirmation; a restart of Blackgrid does not bring the cleared raids and sales back. (#79)

Changed:
- The changelog of every earlier release is rewritten in the new format (#75)

Fixed:
- Factory and The Lab are detected from the game logs during event raids (the `factory_event_preset` and `laboratory_event_preset` scenes). (#76)

Removed:
- git-cliff and `cliff.toml`; `CHANGELOG.md` is no longer regenerated from Git history (#75)

## v0.6.0 - 2026-11-01

Blackgrid is now built, packaged and published without a developer's machine: hosted Windows CI runs every offline gate, a release produces a zip and an installer, and a pushed tag publishes the GitHub Release. The app has its own icon and logo, the source is MIT-licensed, and failures now say what failed while keeping your data.

Added:
- Every pull request and push to main runs analyze, tests, a Release build, the bundle check and the qualification tests on hosted Windows CI (#63)
- A release builds a zip and a per-user installer (unsigned, no admin prompt) with a SHA256SUMS file (#67)
- Pushing a `v` tag builds the Release on CI and publishes a GitHub Release with the zip, installer, checksums and that version's changelog section as notes; `-beta.N` tags are prereleases (#68)
- Blackgrid has its own icon on `blackgrid.exe`, the installer and the uninstall entry, replacing the Flutter default (#69)
- The app header and the startup screen show the Blackgrid hex logo (#70)
- The README opens with a plain-language guide for players
- The source is released under the MIT License

Changed:
- Catalog failures say what failed (no connection, download refused, invalid data or local save failed) and whether earlier item data is still in use, and the Data sources panel shows the message too (#73)
- A preference import with "Replace" no longer changes the live scan switch or the scan hotkey, and "already imported" has its own message (#73)

Fixed:
- Unreadable stored settings, pins or history rows no longer stop Blackgrid from starting; they are skipped or reset to defaults without rewriting the stored data, and a database written by a newer version gets its own message (#73)
- A Tracker response that cannot be parsed keeps your last good progress as out of date, and one bad history row no longer hides all history (#73)

## v0.5.0 - 2026-10-30

Blackgrid now talks to players in plain words, with technical details behind a Details section. Items show their pictures, the map draws its own marker icons, and requirement rows say which craft, trade, task or station they mean.

Added:
- The decision card and recent activity show each item's icon, downloaded from tarkov.dev once and kept in a local cache (#51)
- Every map marker category draws its own Blackgrid-authored icon, with a provenance record for each icon file (#53, #54)
- Requirements and uses rows name their source: a craft shows its product, count, station and level, a barter its offered item and trader level, and optional crafts and barters group after the obligations (#57)
- A collapsed Details section holds scores, margins, timings and other technical information (#58)

Changed:
- The Map rail puts the decision card and Marker preferences first and folds the saved-file inputs into a collapsed section at the bottom (#50)
- Marker preferences is a uniform grid of labelled icon tiles instead of chips with raw category keys (#56)
- Status, reason and error text, times and the import dialog use plain language instead of enum names and UTC timestamps (#58)

Fixed:
- Marker preference tile badges and labels are centred whatever the label length (#59)

## v0.4.0 - 2026-10-20

Blackgrid can now read an item from the game. With live scan on, a click on the inspect window or the scan hotkey reads the item name and drives the decision card, with one-click correction for scans it could not accept. Releases also gained version numbers, tags and a changelog.

Added:
- Releases have SemVer versions with `v` tags, the version is shown in Settings, and local tasks prepare, tag and build a release (#15)
- A Windows capture layer reacts to a mouse release while the game window is in front and copies only the screen region it needs (#18)
- A warm background vision worker keeps text recognition ready, answers the newest request and drops stale results (#22)
- Inspection recognition finds the inspect window's magnifier marker, reads the item title with OCR and matches it to a catalog item (#26)
- A Live scan switch and a Scanner evidence panel show the scan phase, OCR text, candidates and timings, with a full-client fallback pass when the targeted pass is not accepted (#27)
- An opt-in "Record scan frames" switch saves scan images for building a test corpus; it is off at every start (#32)
- An accepted scan becomes the current selection, drives the decision card and is recorded in activity history (#39)
- An unaccepted scan offers its best candidates and a search as one-click corrections (#42)
- A global scan hotkey, F9 by default, can be rebound to F1-F24 or turned off (#45)
- The decision card offers "Back to latest scan" (#46)
- A scan latency report reads the timing log and checks it against the latency targets (#47)

Changed:
- The catalog and Tracker progress refresh on launch and on every mode selection (#44)
- The Map rail shows the shared decision card in place of the "Latest accepted scan" stub, and scanning keeps working with Map open (#46)
- A scan whose best match shares its display name with another item is shown as ambiguous and offers a correction, and correction rows tell same-name variants apart (#47)

Fixed:
- A scan waits for the inspect window to open before capturing, the newest click supersedes an older scan, the last accepted item stays shown, and the footer shows the live scan state (#31)
- Title reading trims the blank margin after the item name, so more titles are read (#35)
- The targeted capture covers the area where the inspect window opens and lists every marker in it (#37)
- Catalog freshness is measured from download time, not from source timestamps (#40)

## v0.1.0 - 2026-10-07

The first baseline: a native Windows app for looking up an item and getting a keep-or-sell recommendation, an offline native map workspace, and the bundled image and text recognition runtime that later scanning builds on.

Added:
- Find real items by name or ID and get a keep-or-sell recommendation with its uncertainty; preferences and item activity survive a restart (#3)
- A native, offline Map with real multilevel artwork for Interchange, Labs and Icebreaker, map markers and your saved pins (#4)
- The Map works on its own for every supported map, with marker search, quest filters, saved log and screenshot inputs, player position and raid exits (#7)
- A native vision runtime bundles OpenCV and Tesseract for reading item names (#9)
- Reproducible, rights-gated qualification tooling and evidence for comparing Blackgrid with the reference companion (#1, #2)
- Automated review is configured for the repository (#5)

Changed:
- Development moved from Compound Engineering to OpenSpec and Specwright (#8, #11)
- The README is rewritten from the current code, and the reference companion is named neutrally with its upstream credited (#12, #13)
- Development and map qualification tests run faster (#6)
