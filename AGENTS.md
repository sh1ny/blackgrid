# Blackgrid Agent Instructions

## Game Interaction Safety

- Never inspect, control, focus, capture, automate, attach to, or otherwise interact with Escape from Tarkov or any other game.
- When debugging requires an in-game state or item, ask the user to load or position it. Inspect only Blackgrid, repository files, logs produced for the application, or screenshots the user explicitly supplies.
- Never read, scan, attach to, or inspect a game's process memory. Anti-cheat systems can treat this as prohibited behavior and ban the user.

## Escape from Tarkov testing boundary

- AI agents MUST NOT launch, restart, drive, or verify Blackgrid or the reference companion while Escape from Tarkov is running. This prohibits automated and agent-driven manual checks.
- Testing any feature that requires the game to be running belongs 100% to the user. Agents MUST NOT launch the game or create/run automated live-game tests.
- Written tests and fixture/mocked/offline checks are allowed. Agents may launch and test the app only after confirming Escape from Tarkov is not running; if that cannot be confirmed, do not launch it.
- When verification requires the game, stop before that verification and ask the user to perform the test or explicitly approve skipping that confirmation. Approval to skip is not permission for an agent to perform live-game testing.
- The CI workflow's `BLACKGRID_NO_GAMES_RUNNING=1` applies only to GitHub-hosted runners. Agents never set it on a developer machine, including to make a local `ci:qualification` run pass.
- This boundary overrides general smoke-test, UI-test, and runtime-verification requirements. Attribute user-performed results to the user; record skipped checks as unverified, never passed.

## Dart and Flutter code

These rules apply to every agent that writes or changes Dart, including subagents that cannot load skills. An agent with a Skill tool loads the skills named here; an agent without one reads the skill's `SKILL.md` file directly.

- Before writing Dart, read the skills that match the work, in `.claude/skills/<name>/SKILL.md`:
  - `dart-use-pattern-matching`: sealed result and failure types, state switches, destructuring.
  - `dart-write-documentation`: `///` doc comments on public APIs.
  - `dart-add-unit-test`: test layout and structure.
  - `dart-run-static-analysis`: analyzer and `dart fix`.
  - `flutter-add-widget-test`: only when a widget test is needed.
- Prove each invariant at the cheapest test layer that can prove it completely:
  - Permutations of state machines and admission rules belong in service or model tests, not in widget or full-app tests.
  - Add a regression test at the lowest layer that reproduces the bug.
- Never wait with arbitrary sleeps (`Future.delayed`, or `sleep` to "let it finish"). Instead use:
  - completers and explicit signals;
  - short durations injected through constructor parameters;
  - fake clocks;
  - a bounded `eventually`-style condition poll, and only for state that crosses an isolate.
- Keep fixtures only as large as the invariant needs. Use small synthetic images and buffers, not production-sized ones, unless size is what the test proves.
- Use hand-written fakes injected through constructor or factory parameters. The repo has no mocking package.
- Build fakes that must block inside another isolate from top-level factories over shared native control memory, following `test/data/capture/support/holdable_capture_platform.dart`.
- Tag tests that need a built bundle, native DLLs or long runtimes `@Tags(['qualification'])`, so that `mise run test` stays a fast offline loop. A tag protects the loop; it does not excuse a slow test.
- Never weaken an integrity, ownership or safety check to make a test faster.
- Verify with `mise run analyze` and `mise run test`, which use the Flutter version pinned in `mise.toml`, not a bare `dart`/`flutter` from `PATH`. Format with `dart format`.
