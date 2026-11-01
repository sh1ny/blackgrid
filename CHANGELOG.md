# Blackgrid Changelog

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
