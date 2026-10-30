# blackgrid Changelog

## v0.5.0 - 2026-10-30

### Features

- *(map)* collapse saved-file inputs at the bottom of the Map rail (#50)

- *(item-icons)* show item icons on the decision card and history (#51)

- *(map)* add Blackgrid-authored map marker icon set (#53)

- *(map)* draw Blackgrid-authored icons for map markers (#54)

- *(map)* show marker preferences as a grid of labelled icon tiles (#56)

- *(requirements)* name requirement and use rows in plain words (#57)

- *(plain-language)* speak to players in plain words, details behind Details (#58)

### Fixes

- *(map)* centre marker preference tile badges and labels (#59)

- *(release)* clarify changelog entries and skip local merges (#60)

### Build, CI, and tooling

- *(specwright)* update Specwright to 0.10.0

## v0.4.0 - 2026-10-20

### Features

- *(release)* add release versioning (#15)

- *(capture)* add the Windows capture boundary (#18)

- *(vision)* add the warm vision worker (#22)

- *(vision)* add the inspection recognition pipeline (#26)

- *(scanner)* add live scan pipeline and Scanner evidence (#27)

- *(scan)* add opt-in scan frame recording (#32)

- *(scan-decisions)* drive the decision card from accepted scans (#39)

- *(scan-correction)* offer one-click correction for unaccepted scans (#42)

- *(catalog)* refresh catalog and progress on mode selection (#44)

- *(scanner)* add a global scan hotkey trigger (#45)

- *(map)* return to the latest accepted scan from the decision card (#46)

- *(scanner)* add latency qualification and same-name ambiguity (#47)

### Fixes

- *(scanner)* wait for the inspect window before capturing (#31)

- *(vision)* bound the blank title margin before OCR (#35)

- *(capture)* place the targeted region where the inspect window opens (#37)

- *(catalog)* measure catalog freshness from download time (#40)

### Documentation

- *(roadmap)* plan release versioning and defer installers to M6 (#14)

- *(roadmap)* mark release versioning as landed

- *(roadmap)* plan fix-title-crop as M2 change 8 and record the targeted-pass issue for M4

- *(close-m2)* close M2 and promote M4 to Now (#36)

- *(plan)* place catalog startup refresh in M4 and requirement rows in M4.5

### Build, CI, and tooling

- *(specwright)* update Specwright to 0.1.6 and configure PR reviewers

- *(specwright)* update Specwright to 0.1.8

- *(tooling)* upgrade Specwright to 0.4.0

- *(tooling)* upgrade Specwright to 0.6.0

## v0.1.0 - 2026-10-07

### Features

- *(m1)* enable safe manual inspection and durable local activity (#3)

- *(m3)* navigate real native maps offline (#4)

- *(map)* deliver complete independent M5 map workspace (#7)

### Fixes

- *(test)* speed up development and map qualification tests (#6)

### Documentation

- add product strategy and M0 qualification plan

- *(qualification)* bound U2 evidence and unblock M1 authoring (#2)

- rewrite README from the current code (#12)

- name the reference companion neutrally and credit its upstream (#13)

### Build, CI, and tooling

- initialize private repository

- add Windows Flutter baseline and development tooling

- *(ai)* share skills and Dart MCP config between Claude Code and OMP

### Other

- Merge pull request #1: reproducible rights-gated M0 qualification

Preserve the reviewed qualification history and its author attribution.

Co-authored-by: KintsugiBot <296966193+KintsugiBot@users.noreply.github.com>

- Add .mira.yml for Blackgrid review configuration (#5)

- Adopt OpenSpec + Specwright in place of Compound Engineering (#8)

- Add native item vision runtime (OpenCV + Tesseract) (#9)

- Update Specwright to 0.1.4 and re-request review after fixes (#11)
