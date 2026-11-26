# Tasks

## Test map

There are no delta-spec scenarios. These checks cover the affected existing contracts.

| Requirement | Scenario | Test file or command | Test name or proof | State |
|---|---|---|---|---|
| `app-icon` | Reject invalid normal and small sources before writing outputs | `test/tool/app_icon/build_test.dart` | `a source the compiler rejects exits non-zero naming it and leaves the ico, vec and record unchanged`; `a rejected small source names it and compiles before rendering` | green |
| `app-icon` | Reject a bad vector candidate without replacing the sheet | `test/tool/app_icon/sheet_test.dart` | `a vector that fails to compile exits non-zero naming it and leaves the earlier sheet` | green |
| `app-icon` | Keep the committed vector in step | `test/tool/app_icon/committed_icon_test.dart` | `the committed vec matches its recorded hash and the compiled source` | green |
| `prepared-map-packs` | Preserve namespace wildcard and exact URI lookups | `test/maps/map_preparation_test.dart`; `test/maps/map_preparation_qualification_test.dart` | `use with a missing local target renders nothing, like a browser`; hosted qualification's existing xlink assertion on `ramp` | wildcard green; exact URI waits for hosted qualification |
| `prepared-map-packs` | The supported codec can read the emitted format | `test/maps/vector_format_test.dart` | `resolved codec writes and decodes the supported format` | green |
| `prepared-map-packs` | Keep a generation if it reproduces | `mise run maps:check` | Exact reproduction line, or the per-map diff and conditional rebuild result | awaiting upgraded pair |

## 1. Upgrade the compiler and XML

- [x] 1.1 Use the three existing failures from #125 as the red evidence. Keep the assertions and verify A1 with the upgraded pair after replacing the shared `<filter>` fixture with `<foreignObject>`. Preserve C1 and C3 in their existing requirements; do not add an app-icon filter policy or change marker admission.
- [x] 1.2 Resolve only `vector_graphics_compiler` 1.3.6 and `xml` 7.0.1. Update their shipped notices using the published licenses. To verify A2, migrate both namespace assertions to `namespaceUri:` without changing either expected result. Run the fast wildcard check and retain the exact URI assertion for the hosted qualification gate below.

## 2. Prove reproduction

- [ ] 2.1 Run `mise run analyze` and `mise run test`, or obtain those results from hosted CI if the gaming check prevents the local run. The codec test must pass before any `maps:rebuild`.
- [ ] 2.2 [evidence] Record the resolved versions and map check output → evidence/map-reproduction.md. Keep C2 in ADR-0033 and retain the current generation on success. If the comparison reports differences, follow C4 and C5: use one serialized rebuild with the original report, commit the new generation, pointer, generated asset block and old-generation deletion together, and require the owner's review of the named maps before readiness and merge. Stop on operational error; it is not evidence of drift.

## Workflow follow-up

- Watch the PR for every hosted offline gate, including the exact-URI qualification assertion, and record the archived head's green CI before reporting readiness. If artwork changes, add the required owner check before final archive.
- Archive on the PR branch. Do not merge.
