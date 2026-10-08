import 'dart:io';

/// Must be `1` for a run that calls the real capture library. Software cannot
/// tell whether *any* game is running, so whoever starts the run confirms it
/// (AGENTS.md: no interaction with Escape from Tarkov or any other game).
const noGamesRunningVariable = 'BLACKGRID_NO_GAMES_RUNNING';

const _knownGames = ['escapefromtarkov.exe', 'escapefromtarkov_be.exe'];

/// Null when a test may call native capture code; otherwise the recorded skip
/// reason. The explicit confirmation is checked first, then the process
/// listing still refuses the known game executables.
String? nativeCaptureSkipReason({
  required bool isWindows,
  required Map<String, String> environment,
  required ProcessResult Function() listProcesses,
}) {
  if (!isWindows) return 'the capture boundary is Windows-only';
  if (environment[noGamesRunningVariable] != '1') {
    return 'set $noGamesRunningVariable=1 to confirm no game is running '
        '(it installs a system-wide mouse hook and captures screen pixels)';
  }
  final listing = listProcesses();
  if (listing.exitCode != 0) {
    return 'cannot confirm the game is not running (tasklist failed)';
  }
  final text = (listing.stdout as String).toLowerCase();
  for (final game in _knownGames) {
    if (text.contains('"$game"')) {
      return 'refused: $game is running (AGENTS.md)';
    }
  }
  return null;
}
