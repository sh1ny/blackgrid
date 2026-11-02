# prepared-map-packs Specification

## Purpose
Defines how Blackgrid's offline-prepared map packs are built, proven and accepted. Each pack records the toolchain that built it and binds every compiled vector to its source by reproduction, not by pinned versions. The committed pack can be checked and rebuilt with one command whenever the preparation libraries change, and the app accepts any pack whose vector format it can decode.

## Requirements

### Requirement: A pack records the toolchain that built it

A pack build SHALL record in its manifest the resolved versions of `xml`, `image`, `vector_graphics_compiler`, `vector_graphics` and `vector_graphics_codec`, as resolved for the project when the build runs. A recorded version SHALL NOT be written from a fixed value in the tool. No validation or load SHALL require a recorded version to equal any particular value.

#### Scenario: Build records the installed versions
- **WHEN** a pack is built while the project resolves `vector_graphics_compiler` 1.3.4 and `image` 4.12.0
- **THEN** the manifest's toolchain record lists `vector_graphics_compiler` 1.3.4 and `image` 4.12.0, plus the resolved versions of the other three packages

#### Scenario: A package is not resolved
- **WHEN** a pack build starts and the project's resolved packages do not include `vector_graphics_codec`
- **THEN** the build fails before writing a candidate, with an error that names `vector_graphics_codec`

#### Scenario: An older recorded version still validates
- **WHEN** a pack whose `toolchain` record lists `vector_graphics_compiler` 1.3.0 and which records vector format 1 is validated with compiler 1.3.4 installed, and every vector recompiles to the committed bytes
- **THEN** validation passes

#### Scenario: Separate compile step records the compiling toolchain
- **WHEN** a candidate is normalized while the project resolves compiler 1.3.0, the project is then resolved to compiler 1.3.4, and the separate compile step runs
- **THEN** the compiled candidate's `toolchain` record lists compiler 1.3.4

### Requirement: Compiled vectors are deterministic

A pack build SHALL compile each vector component twice from the same compiler input. It SHALL fail if the two outputs differ in any byte, naming the component. A failed build SHALL leave no promotable candidate.

#### Scenario: Stable compiler
- **WHEN** a build compiles a component and both compilations give the same bytes
- **THEN** that payload is written and the build continues

#### Scenario: Unstable compiler output
- **WHEN** the two compilations of `artwork/customs/Ground_Level.vec` differ
- **THEN** the build fails with an error naming `artwork/customs/Ground_Level.vec`, and the candidate has no manifest, so it cannot be validated or promoted

### Requirement: Every compiled vector is bound to its source by recompilation

Validation SHALL recompile each vector component's compiler input, which is derived from the source SVG the pack carries as evidence, with the installed compiler. It SHALL reject the pack unless the committed payload is byte-identical to that output. No hash table of expected payloads SHALL be kept in the tool.

#### Scenario: Unmodified pack
- **WHEN** a pack built with the installed compiler is validated
- **THEN** validation passes

#### Scenario: Substituted payload
- **WHEN** another component's valid `.vec` is copied over `artwork/interchange/Ground_Level.vec` and the manifest's output hashes are updated to match
- **THEN** validation fails with an error naming `artwork/interchange/Ground_Level.vec`

### Requirement: A pack records and is checked against its vector format

Whichever step compiles the vectors SHALL record in the manifest the vector codec format number written in the header of the compiled payloads. Validation of a compiled pack SHALL reject a missing record, and any payload whose header does not carry the vector magic number and the recorded format. It SHALL check headers before comparing payload bytes. An uncompiled candidate carries no format record.

#### Scenario: Consistent format
- **WHEN** every compiled payload's header carries format 1 and the manifest records format 1
- **THEN** validation passes this check

#### Scenario: Mismatched payload header
- **WHEN** the manifest records format 1, one payload's header carries format 2, and the manifest's output hash for that payload is updated to match
- **THEN** validation fails with an error naming that payload and both formats

#### Scenario: Missing format record
- **WHEN** a compiled pack's manifest has no vector format record
- **THEN** validation fails with an error saying the vector format is not recorded

#### Scenario: Uncompiled candidate
- **WHEN** a normalized, uncompiled candidate with no format record is validated as uncompiled
- **THEN** validation passes, and promoting it fails because its vectors are not compiled

### Requirement: The app accepts packs in the vector format it decodes

The app SHALL load a pack whose manifest says its vectors are compiled and records the vector format that the app's bundled vector runtime decodes, whatever toolchain versions the manifest records. It SHALL refuse any other pack with an error that names the recorded format and the supported format. The map area SHALL show that error as a load failure.

#### Scenario: Supported format with other recorded versions
- **WHEN** the active manifest records format 1, the app decodes format 1, and the toolchain record lists compiler 9.9.9
- **THEN** the pack loads

#### Scenario: Unsupported format
- **WHEN** the active manifest records format 2 and the app decodes format 1
- **THEN** loading fails with a message naming format 2 and format 1, and the map area shows the load failure

#### Scenario: No format record
- **WHEN** the active manifest has no vector format record
- **THEN** loading fails with a message saying the vector format is not recorded

### Requirement: The app's supported vector format matches its vector runtime

The project SHALL keep the app's supported vector format equal to the format that the resolved `vector_graphics_codec` writes and decodes. A dependency update that changes the codec's format SHALL fail the fast test suite until the supported format and the pack are updated together.

#### Scenario: Codec unchanged
- **WHEN** the fast test suite encodes a small SVG with the resolved compiler and reads the header format
- **THEN** it equals the app's supported format, and the resolved runtime decodes the payload without error

#### Scenario: Codec format changes
- **WHEN** a dependency update resolves a codec that writes format 2 while the app supports format 1
- **THEN** the fast test suite fails with a message naming both formats and `mise run maps:rebuild`

### Requirement: The committed pack is checked for reproducibility

A check SHALL first verify that the active generation's id is the hash of its manifest and that its files are exactly the manifest's outputs. It SHALL then rebuild the generation offline from its own files with the installed toolchain and compare, ignoring only the toolchain record. It SHALL pass only when everything else is byte-identical. It SHALL run in CI and SHALL NOT modify the repository.

#### Scenario: Toolchain update with identical output
- **WHEN** the compiler moves to a new version that compiles every component to the committed bytes, and the check runs
- **THEN** the check passes and prints `Map pack <generation id> reproduced byte-identically with` followed by the five resolved package versions it used, and the repository is unchanged

#### Scenario: Toolchain update that changes output
- **WHEN** a new compiler version changes the bytes of `artwork/woods/Ground_Level.vec` and the check runs
- **THEN** the check fails, prints the per-map change summary as `woods Ground_Level: 1 changed file(s)`, lists `artwork/woods/Ground_Level.vec`, names `mise run maps:rebuild`, and leaves the repository and `assets/maps/active.json` unchanged

#### Scenario: A needed input is not carried
- **WHEN** the rebuild needs a source file that the committed generation does not carry
- **THEN** the check fails with an error naming that source path, without network access

#### Scenario: Committed evidence was edited
- **WHEN** a committed evidence file no longer matches the hash in the generation's source index
- **THEN** the check fails with an error naming that file

#### Scenario: Committed output was edited
- **WHEN** `artwork/customs/Ground_Level.svg` in the active generation is edited in place, or an extra file is added to the generation's folder
- **THEN** the check fails before rebuilding, with an error naming that file

#### Scenario: Manifest no longer matches its generation id
- **WHEN** the active generation's `manifest.json` is rewritten in place, so its hash differs from the generation id in `assets/maps/active.json`
- **THEN** the check fails before rebuilding, with an error naming the generation id

### Requirement: One command rebuilds and promotes the committed pack

A rebuild command SHALL refuse interrupted-promotion leftovers, verify the committed generation and asset markers, and rebuild offline. Only a validated result SHALL be promoted, after which it SHALL update the asset declarations and delete every other generation. It SHALL report changed files and manifest values per map and floor, and SHALL require the owner's check when anything but the toolchain record changed.

#### Scenario: Only provenance changes
- **WHEN** the rebuilt manifest is identical to the active generation's apart from the toolchain record
- **THEN** a new generation is promoted, `assets/maps/active.json` names it, the map asset declarations list its directories, the previous generation folder is deleted, and the report says nothing but provenance changed and does not ask for the owner's check

#### Scenario: Manifest values change without a file change
- **WHEN** the rebuild changes the display crop of `thelab` and no output file
- **THEN** the new generation is promoted, the report prints `thelab: manifest values changed`, and it says the owner must check the maps listed in the app before merge

#### Scenario: Artwork bytes change
- **WHEN** the rebuild changes `artwork/woods/Ground_Level.vec` and two tiles of `thelab` `First_Level`
- **THEN** the new generation is promoted, and the report prints `woods Ground_Level: 1 changed file(s)` and `thelab First_Level: 2 changed file(s)`, lists those paths, and says the owner must check those maps in the app before merge

#### Scenario: Validation fails
- **WHEN** the rebuilt candidate fails validation
- **THEN** nothing is promoted or deleted, the active generation and `assets/maps/active.json` and the map asset declarations are unchanged, the command exits non-zero with the validation error, and the candidate folder is kept and named for inspection

#### Scenario: Asset declaration markers missing
- **WHEN** `pubspec.yaml` lacks the begin or end marker of the generated map asset block, or has either twice
- **THEN** the command fails before rebuilding, with an error naming the marker, and nothing under `assets/maps/` changes

#### Scenario: Interrupted earlier promotion
- **WHEN** `assets/maps/active.next.json` or a `versions/.<id>.staging` folder for any id is left from an interrupted promotion
- **THEN** the command fails before rebuilding, names the leftover path, and nothing under `assets/maps/` changes, the leftover included

### Requirement: Only the active generation is ever used

The app SHALL load only the generation that `assets/maps/active.json` names. It SHALL NOT fall back to any other generation. A pack that fails to load SHALL show its error in the map area. Packs SHALL use preparation version 3, with the complete supported map set, and the app and the validator SHALL refuse any other preparation version. A rollback is a commit that restores an earlier generation from git history.

#### Scenario: Active generation loads
- **WHEN** `assets/maps/active.json` names a valid preparation version 3 generation
- **THEN** the app loads that generation, and no other generation is read

#### Scenario: Active generation is broken
- **WHEN** the active generation's manifest cannot be loaded
- **THEN** the map area shows the load error, and the app reads no other generation

#### Scenario: Older preparation version
- **WHEN** a manifest declares preparation version 2
- **THEN** the app refuses it with an error naming preparation version 2, and validation refuses it as an unsupported preparation version
