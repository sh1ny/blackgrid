# Tasks

Milestone M4.5, change 3 of 7. Design: FULL, review round 1 `APPROVE_WITH_CHANGES` with `CHANGES_APPLIED: yes`.

**Skills.** Every Dart task group loads these skills, or reads their `SKILL.md` files:
- `dart-use-pattern-matching`: the sealed `IconSetResult` and failures.
- `dart-write-documentation`.
- `dart-add-unit-test`.
- `dart-run-static-analysis`.

Each group also follows the "Dart and Flutter code" section of `AGENTS.md`.

**Fixtures.** Tests build small synthetic SVG and manifest fixtures in temporary directories. There are no sleeps and no mocking package.

**Implementation notes from review suggestions S7 and S8.** Both are compatible with D2 and D4:
- The effective-paint walk starts at the root `svg`, so paint set on the root is inherited.
- `promptRecord` paths must resolve inside the manifest's own directory tree, with no `..` escape. This keeps the check independent of the repository root and lets it run in temp-dir tests.

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Every marker category has exactly one icon | Complete set passes | test/tool/markers/icon_set_test.dart | `coverage: release set with all 19 keys is valid` | green |
| Every marker category has exactly one icon | Missing category fails | test/tool/markers/icon_set_test.dart | `coverage: missing BtrStops is named` | green |
| Every marker category has exactly one icon | Candidate subset passes coverage | test/tool/markers/icon_set_test.dart | `coverage: candidate set with 6 keys passes coverage, other rules still apply` | green |
| Every marker category has exactly one icon | Unknown or duplicate icon fails | test/tool/markers/icon_set_test.dart | `coverage: Labels and duplicate PmcExtracts are named` | green |
| Every marker category has exactly one icon | (key list tied to the app) | test/tool/markers/icon_set_test.dart | `coverage: key list equals markerCategories minus Labels` | green |
| Icon files use the restricted single-tint vector form | Valid glyph passes and compiles | test/tool/markers/icon_set_test.dart | `form: path and circle glyph in tint passes and compiles non-empty` | green |
| Icon files use the restricted single-tint vector form | Forbidden content fails | test/tool/markers/icon_set_test.dart | `form: image, text and href are named` | green |
| Icon files use the restricted single-tint vector form | Unlisted attribute fails | test/tool/markers/icon_set_test.dart | `form: onload and unlisted attributes are named` | green |
| Icon files use the restricted single-tint vector form | Default or inherited paint fails | test/tool/markers/icon_set_test.dart | `form: default black fill fails, root and g inherited tint passes` | green |
| Icon files use the restricted single-tint vector form | Second colour or wrong view box fails | test/tool/markers/icon_set_test.dart | `form: second colour and wrong viewBox are named` | green |
| Icon files use the restricted single-tint vector form | Oversized file fails | test/tool/markers/icon_set_test.dart | `form: file over 8 KiB is named with its size` | green |
| Icon files use the restricted single-tint vector form | File that does not compile fails | test/tool/markers/icon_set_test.dart | `form: malformed XML and compiler warning fail` | green |
| Category colours keep their meaning and contrast | Valid palette passes | test/tool/markers/icon_set_test.dart | `palette: starting D7 palette passes` | red |
| Category colours keep their meaning and contrast | Required role broken fails | test/tool/markers/icon_set_test.dart | `palette: ScavExtracts outside exit role is named` | red |
| Category colours keep their meaning and contrast | Reserved hue or low contrast fails | test/tool/markers/icon_set_test.dart | `palette: hue 185 and contrast 2.4 are named; grey below 10% saturation passes` | red |
| Every icon file carries a complete provenance record | Complete matching record passes | test/tool/markers/icon_set_test.dart | `provenance: ai-assisted record with tool and matching hash passes` | red |
| Every icon file carries a complete provenance record | Missing or stale record fails | test/tool/markers/icon_set_test.dart | `provenance: missing and stale records are named` | red |
| Every icon file carries a complete provenance record | Incomplete record fails | test/tool/markers/icon_set_test.dart | `provenance: ai-assisted without tools and concept without prompt record are named` | red |
| No third-party marker art enters the set | Project-authored record passes | test/tool/markers/icon_set_test.dart | `origin: hand-authored and ai-assisted project records pass` | red |
| No third-party marker art enters the set | Third-party or unknown origin fails | test/tool/markers/icon_set_test.dart | `origin: tarkov.dev origin and traced method are named` | red |
| Preview sheet shows every icon in every state | Sheet covers every category and state | test/tool/markers/preview_test.dart | `sheet has every key x state x background and no external URL` | red |
| Preview sheet shows every icon in every state | Candidate sets compared side by side | test/tool/markers/preview_test.dart | `two candidate sets render side by side under their names` | red |
| Preview sheet shows every icon in every state | Too many candidate sets writes no sheet | test/tool/markers/preview_test.dart | `five sets exit non-zero and write nothing` | red |
| Preview sheet shows every icon in every state | Invalid set writes no sheet | test/tool/markers/preview_test.dart | `invalid set prints failures and leaves the previous sheet untouched` | red |
| (all, on the committed set) | Release set is valid | test/tool/markers/release_set_test.dart | `assets/map_markers manifest is a valid release set` | red |

## 1. ADR, byte-exact paths and architecture index

- [x] 1.1 Write `docs/adr/0023-project-authored-map-marker-icons.md` in MADR-short form: Status accepted, today's date, Source this change. It records D2 (form, tinting), D3 (manifest, provenance, `-text`), D4 and D7 (palette rules), the no-third-party-art rule, the rejected alternatives, and the change-4 fallback-glyph note from the design's ADRs section. Add its row to the in-force index in `openspec/architecture.md`. Verify that the file exists and that the index row links to it.
- [x] 1.2 Add `assets/map_markers/** -text` and `docs/design/map-marker-icons/candidates/** -text` to `.gitattributes` under the existing hash-bound block. Verify with `git check-attr text -- assets/map_markers/x.svg docs/design/map-marker-icons/candidates/a/x.svg`, which must report `unset` for both.

## 2. Set checker: manifest model and coverage

- [x] 2.1 Write failing tests for the coverage rows, including the key-list row, in `test/tool/markers/icon_set_test.dart`, with temp-dir fixtures. Run `flutter test test/tool/markers/icon_set_test.dart` and confirm they fail because the library is missing.
- [x] 2.2 Implement `tool/markers/icon_set.dart`:
  - the key constant (D1);
  - manifest parsing with unknown-field rejection, the scope, and the file-name rules (lower snake case, beside the manifest, no subpaths);
  - the sealed `IconSetResult` (`valid`/`invalid`) and `IconSetFailure` (rule, key or file, value);
  - the coverage rule.

  Verify that the coverage rows pass and flip them green.

## 3. Set checker: icon form and compile

- [x] 3.1 Write failing tests for the form rows (valid glyph, forbidden content, unlisted attribute, default/inherited paint, second colour or view box, oversized, compile). Confirm they fail for the right reason.
- [x] 3.2 Implement the form rule:
  - the D2 closed per-element allow-list, with `on*`, `style`, `id` and foreign namespaces rejected;
  - the effective-paint walk from the root `svg` through `g` (note S7);
  - the 8 KiB cap and the `0 0 24 24` view box;
  - `encodeSvg` with `warningsAsErrors: true` and the masking, clipping and overdraw optimizers off, as in `tool/maps/pack.dart:75-81`. A warning, an exception or empty output is a failure.

  Verify that the form rows pass and flip them green.

## 4. Set checker: palette, provenance, origin and CLI

- [ ] 4.1 Write failing tests for the palette, provenance and origin rows. Confirm they fail for the right reason.
- [ ] 4.2 Implement:
  - the palette rule: WCAG contrast ≥ 3:1 against `background`; the reserved hue [170°, 190°] applies only at saturation ≥ 10%; the required roles for extract keys, `Hazards`/`HazardZones` and `CustomPins`;
  - the provenance rule: SHA-256 over raw bytes, required fields, `tools` required for `ai-assisted`, and a `promptRecord` that must exist inside the manifest's directory tree (note S8);
  - the origin rule: origin `project`, method `hand-authored` or `ai-assisted`.

  Verify that the rows pass and flip them green.
- [ ] 4.3 Add the CLI `tool/markers/check.dart <manifest>`. It prints one failure per line, prints the expected hash for stale records, and exits 1 on failure and 0 when valid. Add a test that runs `main` on a valid and an invalid fixture and asserts the exit code and output. Document the command in the tool's library doc comment.

## 5. Preview generator

- [ ] 5.1 Write failing tests for the preview rows in `test/tool/markers/preview_test.dart`. Confirm they fail because the generator is missing.
- [ ] 5.2 Implement `tool/markers/preview.dart <manifest>... [--out <path>]`, default `build/marker-previews/index.html`:
  - validate every set first; refuse invalid input or more than 4 sets, writing nothing;
  - inline each glyph once as a `<symbol>`;
  - tint by alpha with `feFlood` and `feComposite operator="in"`;
  - show the badge from the manifest geometry at 24 px and ×3, on `#070D0B` and on mid and light map tones (pick these and note them in the generator);
  - show the normal, selected, dimmed (alpha 0.22) and highlighted (`#18FFFF` ring) states, plus a deuteranopia `feColorMatrix` row;
  - write to `<out>.tmp`, then rename.

  Verify that the rows pass and flip them green.

## 6. Round 1: style directions (candidate sets)

- [ ] 6.1 Draw 3 style directions for `PmcExtracts`, `Transits`, `Hazards`, `BossSpawns`, `lootContainers` and `QuestItems`. Examples: solid silhouette, 2 px outline, and outline with solid accent. Each direction is a `scope: candidate` set in `docs/design/map-marker-icons/candidates/<direction>/` with the D7 roles. Hand-code the SVG path data, never opening, tracing or describing any third-party marker set. Record provenance `origin: project`, `method: ai-assisted`, with the agent's tool named and `concept: none`. Verify that `dart run tool/markers/check.dart` passes on each candidate manifest.
- [ ] 6.2 Generate the side-by-side sheet: `dart run tool/markers/preview.dart docs/design/map-marker-icons/candidates/*/manifest.json`. Start `docs/design/map-marker-icons/README.md` with the round-1 directions, the no-third-party-reference rule, and how to regenerate the sheet. Verify that the sheet file exists.
- [ ] 6.3 **(user)** The user opens the sheet in a browser and picks a direction, or asks for changes, or supplies their own drawings or ChatGPT concepts. A ChatGPT concept's prompt goes in `docs/design/map-marker-icons/prompts/`, and the concept image is not committed. Record the user's pick and their words in the README. The agent does not mark this task done until the user has answered.

## 7. Round 2: the release set

- [ ] 7.1 Draw all 19 icons in the picked direction in `assets/map_markers/` with `manifest.json` (`scope: release`, D3 badge geometry, D7 palette and roles). Provenance must be honest per file: `ai-assisted` with the tool named, `hand-authored` for the user's own drawings, and the concept source and prompt record where a ChatGPT concept was used. Do not add the folder to `pubspec.yaml` (change 4 does). Verify that `dart run tool/markers/check.dart assets/map_markers/manifest.json` exits 0.
- [ ] 7.2 Add `test/tool/markers/release_set_test.dart`, which validates the committed `assets/map_markers/manifest.json`. Verify that it passes in `mise run test` and flip its row green.
- [ ] 7.3 Generate the release sheet and add round 2 to the README. The README lists the palette for the user to decide, explicitly including `stationaryWeapons` moving from gold to the danger red. It names the PMC/Scav/shared extract and spawn glyph distinctions for the user to judge.
- [ ] 7.4 **(user)** The user reviews the release sheet: 24 px readability on dark, mid and light tones, glyph distinctness, the palette and the `stationaryWeapons` move, and the states. They approve or ask for edits. Each edit refreshes the file's hash only after its provenance is re-attested, and is re-checked with 7.1's command. Record the user's approval and words in the README. The agent does not mark this task done until the user approves.

## 8. Integration checks

- [ ] 8.1 Run `dart format` on the new files, then `mise run analyze` and `mise run test`. Both must pass with every test-map row green.
- [ ] 8.2 Run `openspec validate design-map-marker-icons --strict`. Confirm that `git status` shows no file under `build/` staged, and that `pubspec.yaml` is unchanged.

## Workflow follow-up

- Archive, ship and merge follow `specwright-commit`, `specwright-finish` and `specwright-pr` (finish: pr).
- Next on the roadmap is `add-map-marker-icons`, which needs this change.
