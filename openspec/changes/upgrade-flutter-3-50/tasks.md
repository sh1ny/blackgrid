# Tasks

## Test map

Not applicable. This toolchain change has no delta requirements or changed Blackgrid behaviour. Existing tests and the full hosted gates check compatibility under the new SDK. If a regression needs a behaviour change outside S1, stop for the owner's scope decision first. For an in-scope behaviour fix, capture a failing focused test before fixing it; preserve coverage and follow the Windows CI test rules.

## 1. Upgrade and verify the Windows toolchain

- [ ] 1.1 [evidence] Set Flutter 3.50.1 as the single local and CI pin (C2). Set `test` 1.32.0 in the root and progress member and `build_runner` 2.17.1 in the root. Verify A1 with a targeted workspace Pub dry run before accepting new hosted packages. Use the existing root lockfile (C1); check that unrelated versions remain unchanged, `test_api` is 0.7.14, and `analyzer` is in `>=14.3.0 <15.0.0`. Vet every selected new version before materializing the graph, verify the pin with `mise exec -- flutter --version` and verify the recorded lockfile with `mise exec -- flutter pub get --enforce-lockfile`. Record the resolved delta, release dates and advisory checks in evidence/1.1.md.
- [ ] 1.2 Update the README badge and toolchain instructions, the installed release/development package rows and applicable verbatim license texts in `THIRD_PARTY_NOTICES.md`, and `openspec/config.yaml`. Verify the active pins and notice rows against the resolved workspace and run `mise run release-notes -- --check openspec/changes/upgrade-flutter-3-50/proposal.md`. Do not edit historical version references or add another CI Flutter pin (C2).
- [ ] 1.3 [evidence] Verify A2 before shipping with the upgraded generator, analyzer and existing tests. Run the gaming check before heavy local work; if the owner is gaming, send heavy gates to hosted CI. Run the separate root `mise exec -- dart run build_runner build` and compare tracked generated Dart to the baseline. Preserve the schema and its historical snapshots (C9), and explain any generated-source differences. Use `mise run analyze` and `mise run test` locally when permitted, and record any resulting analyzer, code, test or layout changes. Confirm the committed CI/ADR destinations still establish the existing same-run qualification, skip audit, hosted-only confirmation, job limit, packaging and map reproduction contracts (C3-C8); no rewrites of those specs or ADRs are needed. Record the checks, results and anything left to hosted CI in evidence/1.3.md.

## Workflow follow-up

- Run pre-ship review, open the PR and watch the hosted Gates job on Windows. Verify map reproduction, Release build, bundle check, qualification and packaging under Flutter 3.50.1 without weakening any check. Inspect the qualification log for the applicable accepted skips and successful native capture cases.
- After reviews and checks settle, archive on the PR branch. Watch the archive head and record the final PR head and hosted checkout SHA and the final log evidence. Do not merge.
- Owner-only install check, unverified until reported. With the game closed, verify the installer checksum, install per user and open Blackgrid. Confirm the main window and expected version open, then report the source commit, build number, installer SHA-256 and outcome. A local rebuild is a separate candidate, not the hosted artifact. No agent runs this check.
