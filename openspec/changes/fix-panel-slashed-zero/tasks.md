# Tasks

## Test map

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| raid-panel-reading → Panel rows split at every row label | Slashed-zero labels on one line | test/domain/raid_panel_text_parser_test.dart | slashed-zero row labels split rows like plain zeros | red |
| raid-panel-reading → Panel rows split at every row label | Plain-digit labels keep working | test/domain/raid_panel_text_parser_test.dart | slashed-zero row labels split rows like plain zeros | green |
| raid-panel-reading → Panel rows split at every row label | Label word without a row number | test/domain/raid_panel_text_parser_test.dart | an Exfil word without a row number stays in the name | green |
| raid-panel-reading → Short rows match only by exact name | Short exit name | test/domain/raid_exfil_matcher_test.dart | a short row matches only an exit with that exact name | green |
| raid-panel-reading → Short rows match only by exact name | Stray fragment | test/domain/raid_exfil_matcher_test.dart | a short row matches only an exit with that exact name | red |
| raid-panel-reading → Saved Shoreline panels resolve | Night-vision panel | test/domain/raid_exfil_matcher_test.dart | recorded Shoreline panels match their listed exits | red |
| raid-panel-reading → Saved Shoreline panels resolve | Exit not on the panel | test/domain/raid_exfil_matcher_test.dart | recorded Shoreline panels match their listed exits | red |
| raid-panel-reading → Saved Shoreline panels resolve | Row that truly fits two exits | test/domain/raid_exfil_matcher_test.dart | a row that names two exits equally still rejects the panel | green |

## 1. Split rows at slashed-zero labels

- [ ] 1.1 Record the fixture `test/fixtures/raid_panel/shoreline_2026-11-25.json`. Run `tool/ocr/read_saved_panel.dart` on the owner's four Shoreline panel screenshots (raid times 12.03, 12.06, 12.10 and 12.37) and on one 2026-11-21 Shoreline panel. Keep each one's `raw_text` and the exits its panel lists. Verify: the file holds five entries, and at least one `raw_text` shows each of `EXFILØ3`, `TRANSITØI` and the column layout (`EXFILØI EXFILØ2 …` before the names).
- [ ] 1.2 Verify A1: in the fixture texts and the existing parser tests, every row number starts with `0`, `Ø`, `O` or `o`. Ten-plus numbers keep the existing digit path. Record the result in the task note. If a panel numbers rows from `1x`, stop: that is design drift.
- [ ] 1.3 Write the failing parser tests in `test/domain/raid_panel_text_parser_test.dart`. "slashed-zero row labels split rows like plain zeros" parses the 12.10 text and its `Ø`→`0` copy. Both must give separate `Road to Customs`, `Railway Bridge`, `Transit to Lighthouse` and `Transit to Icebreaker` rows, with no row containing `EXFIL` or `TRANSIT`. "an Exfil word without a row number stays in the name" parses `EXFIL02 Saferoom Exfil EXFIL03 Railway Exfil` and must give `Saferoom Exfil` and `Railway Exfil`. Run `mise exec -- flutter test test/domain/raid_panel_text_parser_test.dart`. The slashed-zero case must fail on a joined row, the plain-zero and Exfil-word cases must pass.
- [ ] 1.4 Implement D1 in `RaidPanelTextParser._normalize`. After `EXFIL`/`EXIT`/`TRANSIT` and at most one space, a two-character number starting with `0`, `Ø`, `O` or `o` becomes digits: `Ø`, `O` and `o` become `0`, and `I`, `l` and `|` become `1`. Verify: the 1.3 tests pass, every existing parser test still passes, and the two rows turn green.
- [ ] 1.5 Carry C1. The doc comment on `RaidPanelTextParser._normalize` must say that a row number's zero can arrive as `Ø`/`O`/`o` and its one as `I`/`l`/`|`, and that the label patterns rely on this repair. Verify by reading the comment.

## 2. Short rows match only by exact name

- [ ] 2.1 Write the failing matcher tests in `test/domain/raid_exfil_matcher_test.dart`. "a short row matches only an exit with that exact name": a `D-2` row matches the D-2 extract, and an `I` row matches neither `Transit to Terminal` nor `Transit to Lighthouse`. "recorded Shoreline panels match their listed exits": for each fixture entry, parse its text, match against Shoreline's bundled exits, and expect `recognized` with exactly the listed exits. That means no Transit to Terminal, and the 12.10 entry gives the nine exits in the spec. "a row that names two exits equally still rejects the panel": two exits and one row naming both give `ambiguous` with no ids. Run `mise exec -- flutter test test/domain/raid_exfil_matcher_test.dart`. The `I` case and the recorded-panel test must fail; `D-2` and the ambiguity case must pass.
- [ ] 2.2 Implement D2 in `RaidExfilMatcher.namesMatch`: a row under four normalised characters matches only an equal name. Verify: the 2.1 tests pass, every existing matcher test still passes, and the remaining rows turn green.
- [ ] 2.3 Carry C2. The doc comment on `RaidExfilMatcher.namesMatch` must state the short-row rule and why containment is refused (label fragments such as `I`). Verify by reading the comment. The spec requirement for C2 already lands in this change's delta.
- [ ] 2.4 Re-run the offline end-to-end check with the Release OCR DLL. Run `tool/ocr/read_saved_panel.dart` on the four Shoreline panels and the 10:01 Interchange panel, then match each against its map's bundled exits in a scratch test that is not committed. Every panel must be `recognized`, Shoreline must give the listed exits without Terminal, and Interchange must still give its 8. Delete the scratch file. Verify by the printed results, recorded in the task note.
- [ ] 2.5 Run `mise run analyze`, `mise run test` and `dart format` on the changed files. All must pass with no new analyzer findings.

## 3. Owner check

- [ ] 3.1 [user] In a Shoreline raid with marker categories on, save a screenshot with the exfil panel open (one against a bright sky or with night vision if convenient). Check that This raid lists the panel's exits and Diagnostics shows no "matches more than one current-map exit" message. Agents never launch or check against the game (AGENTS.md).

## Workflow follow-up

- Climber's Trail sits on Shoreline's 2nd floor from #135's position classification while it is outdoors; a separate small change, not this one.
