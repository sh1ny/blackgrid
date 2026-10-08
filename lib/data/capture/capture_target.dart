/// The window title the game's main window carries (exact match).
const String captureTargetTitle = 'EscapeFromTarkov';

/// Executable names accepted for the target window, lower-cased for the
/// case-insensitive comparison.
const List<String> captureTargetExecutables = [
  'escapefromtarkov.exe',
  'escapefromtarkov_be.exe',
];

bool isCaptureTargetTitle(String title) => title == captureTargetTitle;

bool isCaptureTargetExecutable(String name) =>
    captureTargetExecutables.contains(name.toLowerCase());
