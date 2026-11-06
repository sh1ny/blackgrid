# Tasks

## Test map

The change has no specs (`skip_specs: true`): it adds design documents and changes no behaviour. The rows below are mechanical checks, not scenarios.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| n/a (no specs) | DESIGN.md, its sidecar and PRODUCT.md are readable by impeccable | `.claude/skills/impeccable/scripts/impeccable doctor --json` | only `platform-native-evidence` reported (accepted, design D9) | n/a: mechanical check, no code |
| n/a (no specs) | The proposal's release notes parse | `mise run release-notes -- --check openspec/changes/document-ember-design-context/proposal.md` | exit 0 | n/a: mechanical check, no code |
| n/a (no specs) | The app is unchanged and the analyzer ignores `brand/` | `mise run analyze` | passes on the branch; `mise run test` is not run locally (owner decision 2026-11-06: no file under `lib/` or `test/` changes) and runs in the PR's CI | n/a: mechanical check, no code |

## 1. Brand kit

- [x] 1.1 Copy `F:\Dev\Orca\Workspace\mythspine-html\brand` into `brand/` as real files, with the OFL licence texts beside the fonts `brand/flutter/` not wired into `lib/`, and `brand/**` excluded in `analysis_options.yaml`; verify with a recursive file comparison against the source

## 2. Product record

- [x] 2.1 Write `PRODUCT.md` (impeccable product schema 1) from STRATEGY.md, the README, the code and the owner's answers, including the brand lockup exemption and the theme switch

## 3. Before-redesign record

- [x] 3.1 Capture the reachable screens of the Release build of `2343fb2` into `.impeccable/review/current/` read-only, with Escape from Tarkov confirmed not running, and redact local paths
- [x] 3.2 Write `PROVENANCE.md` (file, screen and state, window size, date, method, states not captured) and `DESIGN.before.md`

## 4. DESIGN.md

- [x] 4.1 Start `DESIGN.md` from `brand/BRAND.md`, rename it for Blackgrid, keep the shared system, and add the Blackgrid extensions X1–X14 and the "Owner decisions (2026-11-06)" table
- [x] 4.2 Build the static mock-up `.impeccable/preview/ember-directions.html` (Directions A, B and C on the kit's CSS and the project's marker glyphs), revise B from the owner's review into round 2, and record the round 2 decisions in DESIGN.md (X11–X14, R1–R7, C1–C4)
- [x] 4.3 Write the sidecar `.impeccable/design.json` from DESIGN.md, run `impeccable doctor --json`, and confirm only the accepted `platform-native-evidence` mention remains

## 5. Plan edits

- [x] 5.1 Add M8.5 "Ember interface" to `openspec/roadmap.md` as Next, with exit criteria and a proposed split, and move M9 to the head of Later with its agreed split unchanged
- [x] 5.2 Replace STRATEGY.md's brand line with Ember

## 6. Verification

- [ ] 6.1 Run `openspec validate document-ember-design-context`, the release-notes check and `mise run analyze` (the owner waived the local `mise run test` for this documents-only change; CI runs it on the PR), and confirm no file under `lib/`, `test/`, `assets/`, `windows/` or `tool/` changed
