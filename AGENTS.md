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
- This boundary overrides general smoke-test, UI-test, and runtime-verification requirements. Attribute user-performed results to the user; record skipped checks as unverified, never passed.
