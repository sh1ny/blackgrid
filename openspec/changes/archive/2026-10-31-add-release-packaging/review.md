# Review

## Metadata

- **Round:** 1 (re-check of the Required Changes)
- **Prior round:** Round 1 returned APPROVE_WITH_CHANGES with 5 Moderate findings (installer file version flags, contents of `build/release/` after a refused run, a denylist check of delete paths, machine registration of the compiler, the unrecorded ADR-0024 amendment) and 3 Suggestions.
- **Reviewer:** fresh-context subagent (Claude Code specwright-reviewer)
- **Reviewed:** openspec/changes/add-release-packaging/{proposal.md, design.md, specs/release-packaging/spec.md, specs/continuous-integration/spec.md}. This re-check covers only the 5 Required Changes, plus whether the edits introduced a defect. Round 1 also read openspec/specs/continuous-integration/spec.md, openspec/architecture.md, docs/adr/0009, docs/adr/0024, tool/release/{release.dart, src/build_step.dart, src/git.dart}, tool/vision/{fetch_runtime.dart, check_bundle.dart, bundle_inventory.json}, tool/ci/qualification.dart, .github/workflows/ci.yml, test/tool/ci/workflow_test.dart and mise.toml. Skills loaded: dart-add-unit-test, dart-use-pattern-matching, dart-write-documentation, dart-run-static-analysis.

## Findings

### Critical (blocking)

None.

### Moderate

1. **D4 `[Files]` has no version-comparison flags, so upgrades and downgrades can produce a mixed install.** By default Inno Setup keeps an installed file that has a version resource with the same or a newer version, but always replaces unversioned files (`app.so`, the `.sha256` sidecars, `runtime.manifest.json`). A downgrade, or a same-version rebuild of a pinned DLL, would leave mismatched binaries and broken hash bindings. **Status: fixed.**
2. **The contents of `build/release/` after a refused run were contradictory, and a stale set was left behind.** One scenario said "unchanged", another said "holds no package". D5 cleared the folder only after admission, so a refused run left an earlier complete set in place. **Status: fixed.**
3. **The planned script check for user data was a denylist that did not prove the spec's THEN.** It missed `{%LOCALAPPDATA}`, other path constants, `[UninstallRun]` and `[Code]`. **Status: fixed.**
4. **Installing the compiler with its full installer left per-user machine state that collided across worktrees and went stale.** Each worktree overwrote one shared HKCU uninstall entry, the entry was orphaned after `flutter clean`, and the setup's default tasks ran silently. **Status: fixed.**
5. **The change amended ADR-0024 without saying so.** ADR-0024 and the architecture.md CI row list the steps ending at `ci:qualification`. **Status: fixed.**

### Suggestions

1. **No timeout seam, and the `setup.exe` loader leaves its child running when killed.** Taken up: D6b adds an optional timeout to `CommandRunner` that kills the process tree with `taskkill /T /F`. The Resource Bounds rows cite it, and the proposal's Impact lists `git.dart`.
2. **Exit code collision with ISCC's 2.** Taken up: D5 and the spec now exit 1 and name the failed stage and the child's own code.
3. **The Mechanism Ledger overstated what the `bundle:check` re-run covers.** Taken up: the ledger row is reworded, and the stray non-native files are an accepted Risk.
4. **(New, introduced by the Suggestion 2 edit; non-blocking.)** The Failure & Visibility table still says exit codes are "passed through". The `bundle:check` re-run row says "Its own report and exit code are passed through". The ZIP write / ISCC row says "the exit code passed through". D5 and the spec now say that packaging exits 1 and names the child's code. Those two cells should say "exit 1, naming the child's exit code", so the table does not contradict D5. A smaller point: the T1 diagram still labels the compiler edge "unattended install", while D2 now unpacks it in portable form. Both are wording only, and neither affects a Required Change.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. (Moderate 1) Specify `ignoreversion` (with `recursesubdirs createallsubdirs`) on the `[Files]` entries, assert it in the script test, and correct the Downgrade gap and the ledger row.
2. (Moderate 2) Clear `build/release/` before admission, and make D1, D5, the T2 diagram and both spec scenarios agree.
3. (Moderate 3) Replace the denylist with a structural rule: no `[InstallDelete]`, `[UninstallDelete]`, `[UninstallRun]` or `[Code]` section, and `{app}\`-only paths if a delete entry is ever needed. The spec scenario must assert exactly that.
4. (Moderate 4) Make the compiler install leave no machine registration: portable mode, then `innoextract`, with the full install as last resort using `/TASKS=""` and its effects recorded. Update the proposal and the State & Ownership row.
5. (Moderate 5) Record that ADR-0025 amends 0024 with an `Amends:` header, and list the architecture.md CI row and both index rows in Impact.

Re-check results:
1. Applied. Evidence:
   - D4 now specifies `Flags: ignoreversion recursesubdirs createallsubdirs` on the bundle entry and `ignoreversion` on the notices entry.
   - The script check asserts "`ignoreversion` on every `[Files]` entry".
   - The new spec scenario "Upgrade or downgrade replaces every file" asserts the flag.
   - The Flow & State Gaps "Downgrade" bullet and the Mechanism Ledger downgrade row now describe every file being replaced.
2. Applied. Evidence:
   - D1 now says "`package` first deletes `build/release/` (D5), then refuses unless…".
   - D5 deletes the folder "as its first action, before admission".
   - The T2 diagram has `Cleared --> Removed: admission refused` before `Recreated`.
   - The spec requirement says "SHALL first clear `build/release/`".
   - "Bundle built from another commit" now says it "holds no package, including any from an earlier run", which agrees with "Bundle changed after the build".
   - The State & Ownership and Failure & Visibility rows match.
3. Applied. Evidence:
   - The D4 script check forbids the `[InstallDelete]`, `[UninstallDelete]`, `[UninstallRun]` and `[Code]` sections and is stated to be structural.
   - A future delete entry must relax the test to `{app}\`-prefixed paths with no `..`.
   - The spec scenario "User data on uninstall" asserts the absence of those four sections.
4. Applied. Evidence:
   - D2 orders the methods: portable mode (`/PORTABLE=1`, with no uninstall entry, shortcuts or associations), then a pinned `innoextract`, then a last-resort full install with `/TASKS=""`. The last resort's shared-HKCU and stale-entry effects are stated, and must be recorded in the proposal if it is used.
   - The proposal's "Machine side effects" and the "Pinned installer compiler" bullet say the compiler is unpacked in portable form.
   - The State & Ownership row "Machine registration of the compiler" is updated.
   - The Risks bullet covers the case where neither method works.
5. Applied. Evidence:
   - The design's ADR section states that ADR-0025 carries an `Amends: 0024` header for the CI step list, and that ADR-0024 itself is not edited.
   - The same task updates the architecture.md CI workflow row, the 0024 index row ("amended by 0025") and a new 0025 index row.
   - The proposal's Impact lists the amendment next to `ci.yml` and lists all three architecture.md rows.

All five Required Changes are correctly applied. The only defect the edits introduced is the stale "passed through" wording in the Failure & Visibility table (Suggestion 4), and it does not block.

CHANGES_APPLIED: yes

## Rebuttals

- Moderate 1: fixed (design.md D4 `[Files]` flags and the script-check bullet "`ignoreversion` on every `[Files]` entry"; Flow & State Gaps "Downgrade with the installer"; Mechanism Ledger downgrade row; spec scenario "Upgrade or downgrade replaces every file").
- Moderate 2: fixed (design.md D1 "Packaging admission"; D5 "deletes `build/release/` as its first action, before admission"; T2 state diagram; State & Ownership `build/release/*` row; spec requirement "SHALL first clear `build/release/`"; scenario "Bundle built from another commit").
- Moderate 3: fixed (design.md D4 "Script check", a structural rule with an `{app}\`-only relaxation; spec scenario "User data on uninstall").
- Moderate 4: fixed (design.md D2 "Install, leaving no machine registration", options 1-3; State & Ownership "Machine registration of the compiler" row; Risks first bullet; proposal "Pinned installer compiler" and "Machine side effects").
- Moderate 5: fixed (design.md ADRs section, the `Amends: 0024` header and the architecture.md rows; proposal Impact, the `ci.yml` bullet and the `openspec/architecture.md` bullet).
- Suggestion 1: fixed (design.md D6b; Resource Bounds compiler-install and ISCC rows; proposal Impact `tool/release/src/git.dart`).
- Suggestion 2: fixed (design.md D5 exit 1 with the child's code in the message; spec requirement "Packaging publishes checksums…" and scenario "Installer compile fails").
- Suggestion 3: fixed (design.md Mechanism Ledger `bundle:check` row; Risks bullet on stray non-DLL files, accepted).
